<#
.SYNOPSIS
    Nova ground station control script - install, start, stop, restart, update
    and inspect every Nova program on the Windows PC.

.DESCRIPTION
    Wraps the backend, frontend and FAS bridge as WinSW-managed Windows
    services, plus the standalone Nova Console status page. Each action is
    independently runnable by hand; nothing here depends on the console app.

    Prod services are Automatic (delayed) start, so a power cycle brings the
    whole stack back with no operator input. Dev services are Manual.

.PARAMETER Action
    install    Create/refresh the Windows services (and install dependencies).
    uninstall  Stop and remove the Windows services. Leaves code and logs.
    start      Start services.
    stop       Stop services.
    restart    Stop then start services.
    status     Print a status table for every Nova service.
    update     git pull, reinstall dependencies, rebuild frontend, restart.
    logs       Tail a service log.
    doctor     Check prerequisites and diagnose a stack that will not come up.

.PARAMETER Env
    prod (default) or dev.

.PARAMETER Only
    Limit the action to specific components: backend, frontend, fas, console.
    Default is all four.

.PARAMETER Offline
    Skip every network-dependent dependency step (pip install, npm ci, WinSW
    download). Use in the field where there is no internet.

.EXAMPLE
    .\ops\Nova.ps1 install -Env prod
.EXAMPLE
    .\ops\Nova.ps1 restart -Env prod -Only backend,fas
.EXAMPLE
    .\ops\Nova.ps1 status
.EXAMPLE
    .\ops\Nova.ps1 update -Env prod
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('install', 'uninstall', 'start', 'stop', 'restart', 'status', 'update', 'logs', 'doctor')]
    [string]$Action,

    [ValidateSet('prod', 'dev')]
    [string]$Env = 'prod',

    [ValidateSet('backend', 'frontend', 'fas', 'console')]
    [string[]]$Only,

    [switch]$Offline,

    # install only: kill any stray node/npm processes that are holding files in
    # the target directory, instead of stopping with an explanation.
    [switch]$Force,

    # logs only: how many trailing lines to show, and whether to follow.
    [int]$Lines = 60,
    [switch]$Follow
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

# Everything ops-related is located relative to THIS script, never relative to
# a repo. That is what lets the ops directory live inside novaOps-back today and
# at C:\Nova\ops (or its own repo) tomorrow with no code change.
$OpsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$configPath = Join-Path $OpsDir 'nova.config.ps1'
if (-not (Test-Path $configPath)) {
    throw "Missing config file: $configPath"
}
. $configPath

$cfg = $NovaConfig
$envCfg = $cfg.Environments[$Env]
if ($null -eq $envCfg) { throw "Unknown environment '$Env'" }

$AllComponents = @('backend', 'frontend', 'fas', 'console')
if ($null -eq $Only -or $Only.Count -eq 0) { $Only = $AllComponents }

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

function Write-Step { param([string]$Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Message) Write-Host "    $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "    $Message" -ForegroundColor Yellow }
function Write-Err  { param([string]$Message) Write-Host "    $Message" -ForegroundColor Red }

function Assert-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw "This action creates or controls Windows services and must be run from an elevated PowerShell (Run as Administrator)."
    }
}

# ---------------------------------------------------------------------------
# Service definitions
#
# One definition per component. Everything downstream (XML generation, status,
# start/stop) is driven from this, so adding a component means adding one entry.
# ---------------------------------------------------------------------------

function Get-PythonExe {
    param([string]$RepoPath)
    return (Join-Path $RepoPath '.venv\Scripts\python.exe')
}

function Get-NodeExe {
    $node = Get-Command node.exe -ErrorAction SilentlyContinue
    if ($null -ne $node) { return $node.Source }
    $fallback = 'C:\Program Files\nodejs\node.exe'
    if (Test-Path $fallback) { return $fallback }
    return $null
}

function Get-ConsolePython {
    param([string]$RepoPath)
    # The console is stdlib-only, so it deliberately does NOT depend on the
    # backend's virtualenv: that venv is deleted and rebuilt by updates, and the
    # console has to keep running (and keep reporting) across exactly those
    # moments. Preference order: explicit config, system Python, backend venv.
    if (-not [string]::IsNullOrWhiteSpace($cfg.ConsolePython) -and (Test-Path $cfg.ConsolePython)) {
        return $cfg.ConsolePython
    }
    $sysPy = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($null -ne $sysPy) { return $sysPy.Source }
    return (Get-PythonExe $RepoPath)
}

function Get-NovaServiceDefs {
    param([string]$EnvName)

    $e = $cfg.Environments[$EnvName]
    $backendPy = Get-PythonExe $e.BackendPath
    $nodeExe = Get-NodeExe
    $brokerHostPort = "$($cfg.Broker.Host):$($cfg.Broker.Port)"
    $serverIp = $cfg.Hosts.Server

    # Environment shared by the Python services.
    $pyEnv = @{
        NOVA_MQTT_BROKER = $cfg.Broker.Host
        NOVA_MQTT_PORT   = "$($cfg.Broker.Port)"
    }

    $defs = @()

    $defs += [pscustomobject]@{
        Component   = 'backend'
        ServiceName = "nova-$EnvName-backend"
        DisplayName = "Nova $EnvName backend (novaOps API)"
        Description = 'FastAPI backend: MQTT bridge, command translation, websocket streaming.'
        Executable  = $backendPy
        Arguments   = "-m uvicorn app.main:app --host 0.0.0.0 --port $($e.BackendPort)"
        WorkingDir  = $e.BackendPath
        Env         = $pyEnv + @{
            NOVA_ADMIN_PASSWORD   = $e.AdminPassword
            NOVA_PUBLIC_BASE_URL  = "http://${serverIp}:$($e.BackendPort)"
            PYTHONUNBUFFERED      = '1'
        }
        DependsOn   = @($cfg.Broker.ServiceName)
        HealthUrl   = "http://127.0.0.1:$($e.BackendPort)/health"
    }

    $defs += [pscustomobject]@{
        Component   = 'frontend'
        ServiceName = "nova-$EnvName-frontend"
        DisplayName = "Nova $EnvName frontend (novaOps UI)"
        Description = 'Next.js production server for the novaOps operator UI.'
        Executable  = $nodeExe
        # Invoke Next's bin directly rather than through npm.cmd: a cmd wrapper
        # gets killed on stop while the node child survives as an orphan.
        Arguments   = "node_modules\next\dist\bin\next start -p $($e.FrontendPort) -H 0.0.0.0"
        WorkingDir  = $e.FrontendPath
        Env         = @{
            NODE_ENV = 'production'
            NEXT_PUBLIC_NOVA_API_BASE_URL = "http://${serverIp}:$($e.BackendPort)"
            NEXT_PUBLIC_NOVA_WS_BASE_URL  = "ws://${serverIp}:$($e.BackendPort)"
        }
        DependsOn   = @()
        HealthUrl   = "http://127.0.0.1:$($e.FrontendPort)/"
    }

    $fasArgs = "tools\fas_bridge.py --broker $brokerHostPort --ops-url http://127.0.0.1:$($e.BackendPort) --data-dir data --baud $($e.FasBaud)"
    if (-not [string]::IsNullOrWhiteSpace($e.FasPort)) {
        $fasArgs = "$fasArgs --port $($e.FasPort)"
    }
    $defs += [pscustomobject]@{
        Component   = 'fas'
        ServiceName = "nova-$EnvName-fas"
        DisplayName = "Nova $EnvName FAS bridge"
        Description = 'RS-422 to MQTT bridge for the FAS FMC. Requires a physical COM port.'
        Executable  = $backendPy
        Arguments   = $fasArgs
        WorkingDir  = $e.BackendPath
        Env         = $pyEnv + @{
            NOVA_FAS_PORT    = $e.FasPort
            NOVA_OPS_URL     = "http://127.0.0.1:$($e.BackendPort)"
            PYTHONUNBUFFERED = '1'
        }
        DependsOn   = @($cfg.Broker.ServiceName)
        HealthUrl   = $null
    }

    $defs += [pscustomobject]@{
        Component   = 'console'
        ServiceName = "nova-$EnvName-console"
        DisplayName = "Nova $EnvName console (status page)"
        Description = 'Standalone status and control page for the Nova ground station.'
        Executable  = (Get-ConsolePython $e.BackendPath)
        # Absolute path to the console script, resolved from where Nova.ps1
        # itself lives, so moving the ops directory needs no edit here.
        Arguments   = "`"$(Join-Path $OpsDir 'console\nova_console.py')`" --config `"$($cfg.ConsoleCfg)`" --port $($e.ConsolePort)"
        WorkingDir  = $OpsDir
        Env         = @{ PYTHONUNBUFFERED = '1' }
        # The console must start even when nothing else can, so it depends on
        # nothing - reporting "broker is down" is its entire job.
        DependsOn   = @()
        HealthUrl   = "http://127.0.0.1:$($e.ConsolePort)/api/health"
    }

    return $defs | Where-Object { $Only -contains $_.Component }
}

# ---------------------------------------------------------------------------
# WinSW plumbing
# ---------------------------------------------------------------------------

function Get-WinSWExe {
    if (Test-Path $cfg.WinSW.Exe) { return $cfg.WinSW.Exe }
    if ($Offline) {
        throw "WinSW.exe not found at $($cfg.WinSW.Exe) and -Offline was given. Copy WinSW-x64.exe there manually and re-run."
    }
    Write-Step "Downloading WinSW to $($cfg.WinSW.Exe)"
    New-Item -ItemType Directory -Force -Path $cfg.BinDir | Out-Null
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $cfg.WinSW.Url -OutFile $cfg.WinSW.Exe -UseBasicParsing
    } catch {
        throw "Could not download WinSW ($($_.Exception.Message)). Download $($cfg.WinSW.Url) on a connected machine, save it as $($cfg.WinSW.Exe), and re-run."
    }
    Write-Ok "WinSW ready."
    return $cfg.WinSW.Exe
}

function New-WinSWXml {
    param([psobject]$Def)

    $logDir = $cfg.LogDir
    $xml = New-Object System.Text.StringBuilder
    [void]$xml.AppendLine('<service>')
    [void]$xml.AppendLine("  <id>$($Def.ServiceName)</id>")
    [void]$xml.AppendLine("  <name>$([Security.SecurityElement]::Escape($Def.DisplayName))</name>")
    [void]$xml.AppendLine("  <description>$([Security.SecurityElement]::Escape($Def.Description))</description>")
    [void]$xml.AppendLine("  <executable>$([Security.SecurityElement]::Escape($Def.Executable))</executable>")
    [void]$xml.AppendLine("  <arguments>$([Security.SecurityElement]::Escape($Def.Arguments))</arguments>")
    [void]$xml.AppendLine("  <workingdirectory>$([Security.SecurityElement]::Escape($Def.WorkingDir))</workingdirectory>")
    [void]$xml.AppendLine("  <logpath>$([Security.SecurityElement]::Escape($logDir))</logpath>")
    [void]$xml.AppendLine('  <log mode="roll-by-size">')
    [void]$xml.AppendLine('    <sizeThreshold>10240</sizeThreshold>')
    [void]$xml.AppendLine('    <keepFiles>5</keepFiles>')
    [void]$xml.AppendLine('  </log>')
    [void]$xml.AppendLine("  <startmode>$($envCfg.StartMode)</startmode>")
    if ($envCfg.StartMode -eq 'Automatic') {
        # The network stack and Mosquitto need to be up first; delayed start is
        # the difference between a clean boot and a service that fails once and
        # sits in Stopped until someone notices.
        [void]$xml.AppendLine('  <delayedAutoStart/>')
    }
    foreach ($dep in $Def.DependsOn) {
        [void]$xml.AppendLine("  <depend>$dep</depend>")
    }
    # Restart forever on crash: an unattended ground station has nobody to click OK.
    [void]$xml.AppendLine('  <onfailure action="restart" delay="10 sec"/>')
    [void]$xml.AppendLine('  <resetfailure>1 hour</resetfailure>')
    [void]$xml.AppendLine('  <stoptimeout>15 sec</stoptimeout>')
    [void]$xml.AppendLine('  <stopparentprocessfirst>true</stopparentprocessfirst>')
    foreach ($key in ($Def.Env.Keys | Sort-Object)) {
        $val = $Def.Env[$key]
        if ($null -eq $val) { $val = '' }
        [void]$xml.AppendLine("  <env name=`"$key`" value=`"$([Security.SecurityElement]::Escape([string]$val))`"/>")
    }
    [void]$xml.AppendLine('</service>')
    return $xml.ToString()
}

function Get-ServiceShimPath {
    param([psobject]$Def)
    return (Join-Path $cfg.BinDir "$($Def.ServiceName).exe")
}

function Test-ServiceInstalled {
    param([string]$Name)
    $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
    return ($null -ne $svc)
}

# ---------------------------------------------------------------------------
# Dependency installation
# ---------------------------------------------------------------------------

function Install-BackendDeps {
    param([string]$RepoPath)

    if (-not (Test-Path $RepoPath)) { throw "Backend path not found: $RepoPath" }
    $venv = Join-Path $RepoPath '.venv'
    $py = Get-PythonExe $RepoPath

    if (-not (Test-Path $py)) {
        Write-Step "Creating virtualenv at $venv"
        $sysPy = Get-Command python.exe -ErrorAction SilentlyContinue
        if ($null -eq $sysPy) { throw "python.exe not found on PATH. Install Python 3.11+ and re-run." }
        & $sysPy.Source -m venv $venv
        if ($LASTEXITCODE -ne 0) { throw "Failed to create virtualenv at $venv" }
    }

    if ($Offline) {
        Write-Warn "Offline: skipping pip install. Using the packages already in $venv."
        return
    }

    Write-Step "Installing Python dependencies"
    & $py -m pip install --upgrade pip --quiet
    & $py -m pip install -r (Join-Path $RepoPath 'requirements.txt') --quiet
    if ($LASTEXITCODE -ne 0) { throw "pip install failed. Re-run with -Offline if the machine has no internet and the venv is already populated." }
    Write-Ok "Python dependencies installed."
}

function Get-ProcessesUsingPath {
    <#
        Find running processes launched from, or working inside, $Path.

        Next.js loads next-swc.win32-x64-msvc.node (a native module) into the
        node process, and Windows locks a loaded DLL. `npm ci` deletes
        node_modules wholesale, so any live node process makes it fail with
        EPERM/unlink - which npm then misreports as a permissions problem.
    #>
    param([string]$Path)

    $needle = $Path.TrimEnd('\')
    $found = @()
    try {
        $procs = Get-CimInstance Win32_Process -ErrorAction Stop |
                 Where-Object { $_.Name -in @('node.exe', 'npm.exe') }
        foreach ($p in $procs) {
            $cmd = "$($p.CommandLine)"
            $exe = "$($p.ExecutablePath)"
            if ($cmd -like "*$needle*" -or $exe -like "$needle*") {
                $found += [pscustomobject]@{ Id = $p.ProcessId; Name = $p.Name; CommandLine = $cmd }
            }
        }
    } catch {
        Write-Warn "Could not enumerate processes: $($_.Exception.Message)"
    }
    return $found
}

function Clear-PathLocks {
    param([string]$Path, [string]$Label)

    $holders = Get-ProcessesUsingPath $Path
    if ($holders.Count -eq 0) { return }

    Write-Warn "$($holders.Count) process(es) are running out of $Label and will lock its files:"
    foreach ($h in $holders) {
        $short = $h.CommandLine
        if ($short.Length -gt 110) { $short = $short.Substring(0, 110) + '...' }
        Write-Warn "  PID $($h.Id)  $($h.Name)  $short"
    }

    if (-not $Force) {
        throw ("Refusing to reinstall dependencies while those processes hold files in $Label. " +
               "Stop them (a stray 'npm run dev' is the usual culprit), or re-run with -Force to have them killed.")
    }

    foreach ($h in $holders) {
        Write-Step "Stopping PID $($h.Id) ($($h.Name))"
        Stop-Process -Id $h.Id -Force -ErrorAction SilentlyContinue
    }
    # Windows releases the file handle a moment after the process dies.
    Start-Sleep -Seconds 2
}

function Install-FrontendDeps {
    param([string]$RepoPath)

    if (-not (Test-Path $RepoPath)) { throw "Frontend path not found: $RepoPath" }
    $npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if ($null -eq $npm) { throw "npm not found on PATH. Install Node.js 20+ and re-run." }

    # Anything still running from this directory will make `npm ci` fail.
    Clear-PathLocks -Path $RepoPath -Label 'the frontend directory'

    if ($Offline) {
        Write-Warn "Offline: skipping npm install."
    } else {
        Write-Step "Installing Node dependencies"
        Push-Location $RepoPath
        try {
            if (Test-Path (Join-Path $RepoPath 'package-lock.json')) {
                & $npm.Source ci
            } else {
                & $npm.Source install
            }
            if ($LASTEXITCODE -ne 0) {
                throw ("npm install failed. If the error was EPERM/unlink on a .node file, something " +
                       "still had node_modules open: stop every node process, then re-run " +
                       "(add -Force to have this script kill them for you). Antivirus scanning " +
                       "C:\Nova can also cause it - consider an exclusion.")
            }
        } finally { Pop-Location }
    }

    # The production build must exist regardless - `next start` refuses to run
    # without .next, and that failure only shows up at boot time otherwise.
    Write-Step "Building frontend (next build)"
    Push-Location $RepoPath
    try {
        & $npm.Source run build
        if ($LASTEXITCODE -ne 0) { throw "next build failed. Fix the build before installing the service." }
    } finally { Pop-Location }
    Write-Ok "Frontend built."
}

function Write-FrontendEnv {
    param([string]$RepoPath, [hashtable]$EnvVars)
    # Next.js inlines NEXT_PUBLIC_* at build time, so these must be on disk
    # before `npm run build` - service-level env vars are too late.
    $lines = @('# Generated by ops/Nova.ps1 - edit ops/nova.config.ps1 instead.')
    foreach ($key in ($EnvVars.Keys | Sort-Object)) {
        if ($key -like 'NEXT_PUBLIC_*') { $lines += "$key=$($EnvVars[$key])" }
    }
    $target = Join-Path $RepoPath '.env.production'
    Set-Content -Path $target -Value $lines -Encoding utf8
    Write-Ok "Wrote $target"
}

function Write-ConsoleConfig {
    # The console reads a plain JSON file so it stays a stdlib-only program with
    # no PowerShell dependency, and so it survives a repo update untouched.
    $services = @()
    foreach ($envName in @('prod', 'dev')) {
        $saveOnly = $Only
        $script:Only = $AllComponents
        try {
            foreach ($d in (Get-NovaServiceDefs $envName)) {
                $services += [ordered]@{
                    component = $d.Component
                    env       = $envName
                    service   = $d.ServiceName
                    label     = $d.DisplayName
                    health    = $d.HealthUrl
                    log       = (Join-Path $cfg.LogDir "$($d.ServiceName).out.log")
                }
            }
        } finally { $script:Only = $saveOnly }
    }

    $payload = [ordered]@{
        generated = (Get-Date).ToString('s')
        broker    = [ordered]@{
            service = $cfg.Broker.ServiceName
            host    = $cfg.Broker.Host
            port    = $cfg.Broker.Port
        }
        hosts     = [ordered]@{
            'novaGround' = [ordered]@{ ip = $cfg.Hosts.NovaGround; mdns = $cfg.HostNames.NovaGround }
            'novaThermo' = [ordered]@{ ip = $cfg.Hosts.NovaThermo; mdns = $cfg.HostNames.NovaThermo }
        }
        server    = $cfg.Hosts.Server
        logDir    = $cfg.LogDir
        uiUrls    = [ordered]@{
            prod = "http://$($cfg.Hosts.Server):$($cfg.Environments.prod.FrontendPort)"
            dev  = "http://$($cfg.Hosts.Server):$($cfg.Environments.dev.FrontendPort)"
        }
        services  = $services
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $cfg.ConsoleCfg) | Out-Null
    $json = $payload | ConvertTo-Json -Depth 8
    Set-Content -Path $cfg.ConsoleCfg -Value $json -Encoding utf8
    Write-Ok "Wrote console config $($cfg.ConsoleCfg)"
}

# ---------------------------------------------------------------------------
# Actions
# ---------------------------------------------------------------------------

function Invoke-Install {
    Assert-Admin
    Write-Step "Installing Nova [$Env] services: $($Only -join ', ')"

    foreach ($dir in @($cfg.Root, $cfg.LogDir, $cfg.BinDir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    $winsw = Get-WinSWExe

    # Stop our own services before touching their files. A running frontend
    # holds next-swc*.node open, which makes `npm ci` fail with EPERM; a running
    # backend holds files in the venv. They are restarted by the caller (update)
    # or started explicitly afterwards.
    $running = @()
    foreach ($def in (Get-NovaServiceDefs $Env)) {
        if (-not (Test-ServiceInstalled $def.ServiceName)) { continue }
        $svc = Get-Service -Name $def.ServiceName -ErrorAction SilentlyContinue
        if ($null -ne $svc -and $svc.Status -ne 'Stopped') {
            Write-Step "Stopping $($def.ServiceName) before reinstalling"
            try {
                Stop-Service -Name $def.ServiceName -Force -ErrorAction Stop
                $running += $def.ServiceName
            } catch {
                Write-Warn "Could not stop $($def.ServiceName): $($_.Exception.Message)"
            }
        }
    }
    if ($running.Count -gt 0) { Start-Sleep -Seconds 2 }

    # The console is stdlib-only and runs on system Python, so it is not in this
    # list - installing only the console must not require the backend repo.
    if ($Only -contains 'backend' -or $Only -contains 'fas') {
        Install-BackendDeps $envCfg.BackendPath
    }
    if ($Only -contains 'frontend') {
        $defsForEnv = Get-NovaServiceDefs $Env
        $feDef = $defsForEnv | Where-Object { $_.Component -eq 'frontend' }
        Write-FrontendEnv $envCfg.FrontendPath $feDef.Env
        Install-FrontendDeps $envCfg.FrontendPath
    }

    if ((Get-Service -Name $cfg.Broker.ServiceName -ErrorAction SilentlyContinue) -eq $null) {
        Write-Warn "Mosquitto service '$($cfg.Broker.ServiceName)' is not installed. Install Mosquitto and enable it as a service, or the backend and FAS bridge will have no broker."
    }

    foreach ($def in (Get-NovaServiceDefs $Env)) {
        if ($null -eq $def.Executable -or -not (Test-Path $def.Executable)) {
            Write-Err "Skipping $($def.ServiceName): executable not found ($($def.Executable))."
            continue
        }

        $shim = Get-ServiceShimPath $def
        $xmlPath = [IO.Path]::ChangeExtension($shim, '.xml')

        if (Test-ServiceInstalled $def.ServiceName) {
            Write-Step "Reinstalling $($def.ServiceName)"
            & $shim stop 2>&1 | Out-Null
            & $shim uninstall 2>&1 | Out-Null
            Start-Sleep -Milliseconds 1500
        } else {
            Write-Step "Installing $($def.ServiceName)"
        }

        Copy-Item -Path $winsw -Destination $shim -Force
        Set-Content -Path $xmlPath -Value (New-WinSWXml $def) -Encoding utf8

        & $shim install
        if ($LASTEXITCODE -ne 0) { throw "WinSW failed to install $($def.ServiceName)." }
        Write-Ok "$($def.ServiceName) installed ($($envCfg.StartMode))."
    }

    Write-ConsoleConfig
    New-NovaShortcuts

    Write-Host ""
    Write-Ok "Done. Console: http://localhost:$($envCfg.ConsolePort)"
    if ($envCfg.StartMode -eq 'Automatic') {
        Write-Ok "Prod services will start automatically on boot. Start them now with: .\ops\Nova.ps1 start -Env $Env"
    } else {
        Write-Ok "Dev services are Manual. Start them with: .\ops\Nova.ps1 start -Env $Env"
    }
}

function Invoke-Uninstall {
    Assert-Admin
    Write-Step "Removing Nova [$Env] services: $($Only -join ', ')"
    foreach ($def in (Get-NovaServiceDefs $Env)) {
        if (-not (Test-ServiceInstalled $def.ServiceName)) {
            Write-Warn "$($def.ServiceName) is not installed."
            continue
        }
        $shim = Get-ServiceShimPath $def
        if (Test-Path $shim) {
            & $shim stop 2>&1 | Out-Null
            & $shim uninstall 2>&1 | Out-Null
        } else {
            & sc.exe stop $def.ServiceName | Out-Null
            & sc.exe delete $def.ServiceName | Out-Null
        }
        Write-Ok "$($def.ServiceName) removed."
    }
    Write-Ok "Code and logs were left in place."
}

function Invoke-StartStop {
    param([ValidateSet('start', 'stop')][string]$Mode)
    Assert-Admin

    $defs = Get-NovaServiceDefs $Env
    # Start broker-first / stop broker-last so nothing spends its first seconds
    # retrying a connection that was never going to succeed yet.
    if ($Mode -eq 'stop') { $defs = @($defs | Sort-Object { $_.Component } -Descending) }

    if ($Mode -eq 'start') {
        $broker = Get-Service -Name $cfg.Broker.ServiceName -ErrorAction SilentlyContinue
        if ($null -ne $broker -and $broker.Status -ne 'Running') {
            Write-Step "Starting broker $($cfg.Broker.ServiceName)"
            Start-Service -Name $cfg.Broker.ServiceName
        }
    }

    foreach ($def in $defs) {
        if (-not (Test-ServiceInstalled $def.ServiceName)) {
            Write-Warn "$($def.ServiceName) is not installed - run: .\ops\Nova.ps1 install -Env $Env"
            continue
        }
        try {
            if ($Mode -eq 'start') {
                Start-Service -Name $def.ServiceName
                Write-Ok "started $($def.ServiceName)"
            } else {
                Stop-Service -Name $def.ServiceName -Force
                Write-Ok "stopped $($def.ServiceName)"
            }
        } catch {
            Write-Err "$Mode failed for $($def.ServiceName): $($_.Exception.Message)"
        }
    }
}

function Invoke-Restart {
    Invoke-StartStop -Mode stop
    Start-Sleep -Seconds 2
    Invoke-StartStop -Mode start
}

function Test-HttpHealth {
    param([string]$Url)
    if ([string]::IsNullOrWhiteSpace($Url)) { return 'n/a' }
    try {
        $resp = Invoke-WebRequest -Uri $Url -TimeoutSec 3 -UseBasicParsing
        if ($resp.StatusCode -ge 200 -and $resp.StatusCode -lt 400) { return 'OK' }
        return "HTTP $($resp.StatusCode)"
    } catch {
        return 'no answer'
    }
}

function Invoke-Status {
    Write-Host ""
    Write-Host "Nova ground station - service status" -ForegroundColor White
    Write-Host ("-" * 78)

    $broker = Get-Service -Name $cfg.Broker.ServiceName -ErrorAction SilentlyContinue
    if ($null -eq $broker) {
        Write-Err ("{0,-26} {1}" -f $cfg.Broker.ServiceName, 'NOT INSTALLED')
    } else {
        $line = "{0,-26} {1}" -f $broker.Name, $broker.Status
        if ($broker.Status -eq 'Running') { Write-Ok $line } else { Write-Err $line }
    }

    foreach ($envName in @('prod', 'dev')) {
        Write-Host ""
        Write-Host "  [$envName]" -ForegroundColor White
        $saveOnly = $Only
        $script:Only = $AllComponents
        try { $defs = Get-NovaServiceDefs $envName } finally { $script:Only = $saveOnly }

        foreach ($def in $defs) {
            $svc = Get-Service -Name $def.ServiceName -ErrorAction SilentlyContinue
            if ($null -eq $svc) {
                Write-Host ("    {0,-24} {1,-10} {2}" -f $def.Component, 'not inst.', '') -ForegroundColor DarkGray
                continue
            }
            $health = ''
            if ($svc.Status -eq 'Running') { $health = Test-HttpHealth $def.HealthUrl }
            $line = "    {0,-24} {1,-10} {2}" -f $def.Component, $svc.Status, $health
            if ($svc.Status -eq 'Running' -and $health -ne 'no answer') {
                Write-Host $line -ForegroundColor Green
            } elseif ($svc.Status -eq 'Running') {
                Write-Host $line -ForegroundColor Yellow
            } else {
                Write-Host $line -ForegroundColor Red
            }
        }
    }

    Write-Host ""
    Write-Host "  [remote hosts]" -ForegroundColor White
    foreach ($name in @('NovaGround', 'NovaThermo')) {
        $ip = $cfg.Hosts[$name]
        $reachable = Test-Connection -ComputerName $ip -Count 1 -Quiet -ErrorAction SilentlyContinue
        if ($reachable) {
            Write-Host ("    {0,-24} {1,-10} {2}" -f $name, 'reachable', $ip) -ForegroundColor Green
        } else {
            Write-Host ("    {0,-24} {1,-10} {2}" -f $name, 'NO REPLY', $ip) -ForegroundColor Red
        }
    }
    Write-Host ""
    Write-Host "  Console:  http://localhost:$($cfg.Environments.prod.ConsolePort)"
    Write-Host "  Operator: http://$($cfg.Hosts.Server):$($cfg.Environments.prod.FrontendPort)"
    Write-Host ""
}

function Invoke-Update {
    Assert-Admin
    Write-Step "Updating Nova [$Env] (branch $($envCfg.GitBranch))"

    $git = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($null -eq $git) { throw "git not found on PATH." }

    $repos = @()
    if ($Only -contains 'backend' -or $Only -contains 'fas' -or $Only -contains 'console') { $repos += $envCfg.BackendPath }
    if ($Only -contains 'frontend') { $repos += $envCfg.FrontendPath }

    Invoke-StartStop -Mode stop

    foreach ($repo in ($repos | Select-Object -Unique)) {
        if (-not (Test-Path $repo)) { Write-Err "Missing repo: $repo"; continue }
        Write-Step "git pull in $repo"
        Push-Location $repo
        try {
            $dirty = & $git.Source status --porcelain
            if (-not [string]::IsNullOrWhiteSpace(($dirty | Out-String).Trim())) {
                Write-Warn "Working tree is dirty - pulling anyway may conflict. Uncommitted files:"
                $dirty | ForEach-Object { Write-Warn "  $_" }
            }
            & $git.Source fetch --all --prune
            & $git.Source checkout $envCfg.GitBranch
            & $git.Source pull --ff-only
            if ($LASTEXITCODE -ne 0) { throw "git pull failed in $repo (not a fast-forward?). Resolve by hand and re-run." }
        } finally { Pop-Location }
    }

    # Reinstall so a new dependency or a changed service definition is picked up.
    Invoke-Install
    Invoke-StartStop -Mode start
    Write-Ok "Update complete."
}

function Invoke-Logs {
    $defs = Get-NovaServiceDefs $Env
    if ($defs.Count -eq 0) { throw "No components selected." }
    if ($defs.Count -gt 1) {
        Write-Warn "Multiple components selected; showing the first. Use -Only <component> to pick one."
    }
    $def = $defs[0]
    $log = Join-Path $cfg.LogDir "$($def.ServiceName).out.log"
    $errLog = Join-Path $cfg.LogDir "$($def.ServiceName).err.log"

    foreach ($path in @($log, $errLog)) {
        if (-not (Test-Path $path)) {
            Write-Warn "No log yet at $path"
            continue
        }
        Write-Host ""
        Write-Host "--- $path ---" -ForegroundColor Cyan
        if ($Follow) {
            Get-Content -Path $path -Tail $Lines -Wait
        } else {
            Get-Content -Path $path -Tail $Lines
        }
    }
}

function Invoke-Doctor {
    Write-Host ""
    Write-Step "Nova prerequisites"

    function Check {
        param([string]$Label, [bool]$Pass, [string]$Detail)
        if ($Pass) { Write-Ok ("{0,-28} OK    {1}" -f $Label, $Detail) }
        else { Write-Err ("{0,-28} FAIL  {1}" -f $Label, $Detail) }
    }

    $py = Get-Command python.exe -ErrorAction SilentlyContinue
    Check 'python on PATH' ($null -ne $py) $(if ($null -ne $py) { $py.Source } else { 'install Python 3.11+' })

    $node = Get-NodeExe
    Check 'node' ($null -ne $node) $(if ($null -ne $node) { $node } else { 'install Node.js 20+' })

    $git = Get-Command git.exe -ErrorAction SilentlyContinue
    Check 'git on PATH' ($null -ne $git) ''

    Check 'WinSW cached' (Test-Path $cfg.WinSW.Exe) $cfg.WinSW.Exe

    $broker = Get-Service -Name $cfg.Broker.ServiceName -ErrorAction SilentlyContinue
    Check 'mosquitto service' ($null -ne $broker) $(if ($null -ne $broker) { "$($broker.Status)" } else { 'install Mosquitto' })

    $brokerPort = Test-NetConnection -ComputerName $cfg.Broker.Host -Port $cfg.Broker.Port -WarningAction SilentlyContinue
    Check 'broker port 1883' ($brokerPort.TcpTestSucceeded) "$($cfg.Broker.Host):$($cfg.Broker.Port)"

    foreach ($envName in @('prod', 'dev')) {
        $e = $cfg.Environments[$envName]
        Check "$envName backend path" (Test-Path $e.BackendPath) $e.BackendPath
        Check "$envName frontend path" (Test-Path $e.FrontendPath) $e.FrontendPath
        Check "$envName venv" (Test-Path (Get-PythonExe $e.BackendPath)) ''
        Check "$envName frontend build" (Test-Path (Join-Path $e.FrontendPath '.next')) 'run: Nova.ps1 install'
    }

    $serverIp = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -eq $cfg.Hosts.Server }
    Check 'server IP configured' ($null -ne $serverIp) "$($cfg.Hosts.Server) expected on this PC"

    foreach ($name in @('NovaGround', 'NovaThermo')) {
        $ip = $cfg.Hosts[$name]
        $up = Test-Connection -ComputerName $ip -Count 1 -Quiet -ErrorAction SilentlyContinue
        Check "$name reachable" $up $ip
    }

    if (-not [string]::IsNullOrWhiteSpace($envCfg.FasPort)) {
        $ports = [System.IO.Ports.SerialPort]::GetPortNames()
        Check "FAS serial $($envCfg.FasPort)" ($ports -contains $envCfg.FasPort) ("present: " + ($ports -join ', '))
    }
    Write-Host ""
}

function New-NovaShortcuts {
    # One double-click for the operator. The console is the entry point to
    # everything else, so this is the only icon they need to know about.
    #
    # The console SERVICE already starts at boot; the Startup shortcut is only
    # the visible half, so the page is already on screen when someone logs in
    # rather than being something they have to remember to open.
    $url = "http://localhost:$($cfg.Environments.prod.ConsolePort)"

    try {
        $shell = New-Object -ComObject WScript.Shell

        $desktop = [Environment]::GetFolderPath('CommonDesktopDirectory')
        $lnk = $shell.CreateShortcut((Join-Path $desktop 'Nova Console.lnk'))
        $lnk.TargetPath = $url
        $lnk.Save()
        Write-Ok "Desktop shortcut 'Nova Console' -> $url"
    } catch {
        Write-Warn "Could not create the desktop shortcut: $($_.Exception.Message)"
    }

    try {
        $shell = New-Object -ComObject WScript.Shell
        # CommonStartup = every user on this PC, which is what a shared
        # ground-station login wants.
        $startup = [Environment]::GetFolderPath('CommonStartup')
        $startLnk = $shell.CreateShortcut((Join-Path $startup 'Nova Console.lnk'))
        $startLnk.TargetPath = $url
        $startLnk.Save()
        Write-Ok "Startup shortcut added - the console opens automatically at logon."
        Write-Ok "  (delete '$startup\Nova Console.lnk' to disable that)"
    } catch {
        Write-Warn "Could not create the startup shortcut: $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

switch ($Action) {
    'install'   { Invoke-Install }
    'uninstall' { Invoke-Uninstall }
    'start'     { Invoke-StartStop -Mode start }
    'stop'      { Invoke-StartStop -Mode stop }
    'restart'   { Invoke-Restart }
    'status'    { Invoke-Status }
    'update'    { Invoke-Update }
    'logs'      { Invoke-Logs }
    'doctor'    { Invoke-Doctor }
}
