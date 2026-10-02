<#
.SYNOPSIS
    NovaOps server control script - test, pin, deploy and operate every
    Nova program on the Windows PC.

.DESCRIPTION
    Wraps the backend, frontend and FAS bridge as WinSW-managed Windows
    services, plus the standalone Nova Console status page. Each action is
    independently runnable by hand; nothing here depends on the console app.

    Prod services are Automatic (delayed) start, so a power cycle brings the
    whole stack back with no operator input. Dev services are Manual.

    Release workflow (each step works offline except publish):

        get-changes   put a branch (normally dev) on the dev stack   (dev only)
        use dev       stop prod, start dev - then hardware test
        pin           record what dev ran as a release, e.g. v2026.10.04
        promote       mark a pinned release stable
        deploy        put a stable release into prod                 (prod only)
        publish       when online: push, create GitHub releases, open
                      the PRs that bring the release into each repo's main

    An emergency fix made and tested on prod during a test:

        hotfix -Name <what> -Test "..."   capture it as hotfix/<what> and a
                                          stable release           (prod only)

    See CONTRIBUTING.md for the branches (dev, main, hotfix/*, release/*).

.PARAMETER Action
    get-changes  Fetch and check out new code in the dev folders, then
                 reinstall/rebuild dev. Always dev.
    use          `use dev` / `use prod`: stop one stack and start the other.
    pin          Pin the commits dev is running (plus the Pi's) and the dev
                 config as a new release tag. Always reads dev.
    promote      `promote <tag>`: mark a pinned release as stable.
    deploy       `deploy [<tag>]`: check out a release in prod (default: the
                 newest stable), reinstall, restart, and deploy the Pi.
                 Always prod.
    publish      Push releases and tags, create/update GitHub releases.
    archive      Bundle finished recordings (data + meta + config) into
                 ArchiveDir. Also run automatically by pin.
    hotfix       `hotfix -Name <what> -Test "..."`: commit the edits in the
                 prod checkouts (PC and Pi) to hotfix/<what>, and record them
                 as a new release that is stable at once. Always prod.
    install      Create/refresh the Windows services (and install dependencies).
    uninstall    Stop and remove the Windows services. Leaves code and logs.
    start / stop / restart
                 Control services.
    status       Services, which stack is live, and what each is running.
    logs         Tail a service log.
    doctor       Check prerequisites and diagnose a stack that will not come up.

.PARAMETER Target
    use: dev or prod. promote/deploy: a release tag such as v2026.10.04.

.PARAMETER Env
    prod (default) or dev, for install/uninstall/start/stop/restart/logs.
    The workflow actions ignore it: each only works on its own environment.

.PARAMETER Only
    Limit the action to specific components: backend, frontend, fas, console.
    Default is all four.

.PARAMETER Offline
    Skip every network-dependent dependency step (pip install, npm ci, WinSW
    download). Use in the field where there is no internet.

.EXAMPLE
    .\ops\Nova.ps1 get-changes -Ref main
.EXAMPLE
    .\ops\Nova.ps1 use dev
.EXAMPLE
    .\ops\Nova.ps1 pin -Test "integration test" -Notes "All valves cycled, PT drift on PGSO"
.EXAMPLE
    .\ops\Nova.ps1 promote v2026.10.04
.EXAMPLE
    .\ops\Nova.ps1 deploy
.EXAMPLE
    .\ops\Nova.ps1 publish -DryRun
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet('get-changes', 'use', 'pin', 'promote', 'deploy', 'publish', 'archive', 'hotfix',
                 'install', 'uninstall', 'start', 'stop', 'restart', 'status', 'update', 'logs', 'doctor')]
    [string]$Action,

    # use: dev|prod. promote/deploy: a release tag.
    [Parameter(Position = 1)]
    [string]$Target,

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
    [switch]$Follow,

    # get-changes: branch, tag or commit to check out (default: pull the
    # branch each dev folder is already on).
    [string]$Ref,

    # pin: what the test was, free-text notes, and optional overrides for the
    # firmware reference and the Pi commit (when the Pi cannot be reached).
    [string]$Test,
    [string]$Notes = '',
    [string]$Firmware,
    [string]$GroundCommit,
    # With -GroundCommit: the Pi branch it came from, so branch policy can be
    # checked (otherwise the release is marked unverified).
    [string]$GroundBranch,

    # hotfix: the new branch's name, e.g. igniter-delay -> hotfix/igniter-delay
    [string]$Name,

    # deploy: also replace prod's live config with the release's config, and
    # allow deploying a release that has not been promoted to stable.
    [switch]$WithConfig,
    [switch]$AllowPrerelease,

    # pin/deploy: leave the Pi alone (pin keeps novaGround's current pin).
    [switch]$SkipPi,

    # publish: print what would be pushed/created without doing it.
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

# Everything ops-related is located relative to THIS script, never relative to
# a code repo, so C:\Nova\ops works the same whichever release prod is running.
$OpsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
# Settings: ops\nova.settings.ps1 is this machine's own copy and the only file
# read. It is never committed; the tracked ops\nova.settings.example.ps1 is the
# reference it is created from (like .env.example and .env).
$settingsPath = Join-Path $OpsDir 'nova.settings.ps1'
$exampleSettingsPath = Join-Path $OpsDir 'nova.settings.example.ps1'
$legacySettingsPath = Join-Path $OpsDir 'nova.config.ps1'
if (-not (Test-Path $settingsPath)) {
    if (Test-Path $legacySettingsPath) {
        # The settings file used to be called nova.config.ps1. Carry this
        # machine's values over rather than starting again from the example.
        Copy-Item -LiteralPath $legacySettingsPath -Destination $settingsPath
        Write-Host "Copied $legacySettingsPath to $settingsPath (the settings file's new name)." -ForegroundColor Yellow
        Write-Host "Check it, then delete nova.config.ps1." -ForegroundColor Yellow
    } elseif (Test-Path $exampleSettingsPath) {
        Copy-Item -LiteralPath $exampleSettingsPath -Destination $settingsPath
        Write-Host "Created $settingsPath from nova.settings.example.ps1." -ForegroundColor Yellow
        Write-Host "Review it for this machine - at least AdminPassword and FasPort - then run: .\ops\Nova.ps1 install -Env prod" -ForegroundColor Yellow
    } else {
        throw "Missing $settingsPath, and no $exampleSettingsPath to create it from."
    }
}
try { . $settingsPath }
catch { throw "Error in ${settingsPath}: $($_.Exception.Message)" }
# Older copies of the file define $NovaConfig instead of $NovaSettings.
if (-not (Get-Variable -Name NovaSettings -Scope Script -ErrorAction SilentlyContinue)) {
    if (-not (Get-Variable -Name NovaConfig -Scope Script -ErrorAction SilentlyContinue)) {
        throw "$settingsPath does not define `$NovaSettings."
    }
    $NovaSettings = $NovaConfig
}
$cfg = $NovaSettings

function Add-MissingSettings {
    # Settings added to the example after this machine's copy was made would
    # otherwise be $null here. Take the example's value and say so.
    param([hashtable]$Mine, [hashtable]$Reference, [string]$Prefix)
    $added = @()
    foreach ($key in $Reference.Keys) {
        if (-not $Mine.ContainsKey($key)) {
            $Mine[$key] = $Reference[$key]
            $added += "$Prefix$key"
        } elseif ($Mine[$key] -is [hashtable] -and $Reference[$key] -is [hashtable]) {
            $added += Add-MissingSettings $Mine[$key] $Reference[$key] "$Prefix$key."
        }
    }
    return $added
}
$referenceCfg = $null
$newSettings = @()
if (Test-Path $exampleSettingsPath) {
    $referenceCfg = & { . $exampleSettingsPath; $NovaSettings }
    $newSettings = @(Add-MissingSettings $cfg $referenceCfg '')
    if ($newSettings.Count -gt 0) {
        Write-Host ("nova.settings.ps1 is missing setting(s) added to nova.settings.example.ps1: $($newSettings -join ', '). " +
                    "Using the example's values for now; copy them into $settingsPath to keep or change them.") -ForegroundColor Yellow
    }
}

# The release workflow actions each work on exactly one environment, so they
# never need -Env - and passing the other one is a mistake worth stopping.
$FixedEnv = @{ 'get-changes' = 'dev'; 'pin' = 'dev'; 'hotfix' = 'prod'; 'deploy' = 'prod' }
if ($FixedEnv.ContainsKey($Action)) {
    if ($PSBoundParameters.ContainsKey('Env') -and $Env -ne $FixedEnv[$Action]) {
        throw "'$Action' always works on $($FixedEnv[$Action]); drop -Env $Env."
    }
    $Env = $FixedEnv[$Action]
}

$envCfg = $cfg.Environments[$Env]
if ($null -eq $envCfg) { throw "Unknown environment '$Env'" }

# The Nova repo is the folder that contains ops\ (C:\Nova on the ops PC).
$RepoRoot = Split-Path -Parent $OpsDir

# Git and ssh print UTF-8; without this, Windows PowerShell mangles any
# non-ASCII text in release notes.
[Console]::OutputEncoding = [Text.Encoding]::UTF8

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
            # Server state outside the checkout (see nova.settings.ps1), and
            # what this stack is running, stamped into every recording.
            NOVA_ENV                = $EnvName
            NOVA_CONFIG_DIR         = (Get-EnvConfigDir $EnvName)
            NOVA_CONFIG_HISTORY_DIR = (Get-HistoryDir)
            NOVA_DATA_DIR           = (Get-EnvDataDir $EnvName)
            NOVA_RELEASE            = (Get-EnvState $EnvName).release
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

    # Same data folder as the backend, so every file of a recording (the
    # bridge's <name>.csv, novaGround's uploads, the backend's .meta.json)
    # ends up side by side for `archive`.
    $fasArgs = "tools\fas_bridge.py --broker $brokerHostPort --ops-url http://127.0.0.1:$($e.BackendPort) --data-dir `"$(Get-EnvDataDir $EnvName)`" --baud $($e.FasBaud)"
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
        Description = 'Standalone status and control page for the NovaOps server.'
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

    $holders = @(Get-ProcessesUsingPath $Path)
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
    $lines = @('# Generated by ops/Nova.ps1 - edit ops/nova.settings.ps1 instead.')
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
        releaseIndex = $cfg.ReleaseIndex
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
    Initialize-ServerState $Env
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
    Update-ReleaseIndex
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
    Write-Host "NovaOps server - service status" -ForegroundColor White
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
    Write-Host "  [versions]" -ForegroundColor White
    $live = Get-LiveStack
    if ($live) { Write-Host "    live stack               $live" -ForegroundColor Green }
    else { Write-Host "    live stack               none" -ForegroundColor Red }
    $novaBranch = (Invoke-Git $RepoRoot @('rev-parse', '--abbrev-ref', 'HEAD') -AllowFail).Text
    if ($novaBranch -eq $cfg.Branches.Prod) { Write-Host "    Nova scripts             $novaBranch" }
    else { Write-Host "    Nova scripts             $novaBranch  (trying a branch - switch back: git -C $RepoRoot switch $($cfg.Branches.Prod))" -ForegroundColor Yellow }
    try {
        $prodRelease = (Get-EnvState 'prod').release
        if ($prodRelease) { Write-Host "    prod release             $prodRelease" }
        else { Write-Host "    prod release             unknown (not deployed with Nova.ps1 yet)" -ForegroundColor Yellow }
        foreach ($envName in @('prod', 'dev')) {
            $e = $cfg.Environments[$envName]
            foreach ($pair in @(@('backend', $e.BackendPath), @('frontend', $e.FrontendPath))) {
                if (-not (Test-Path $pair[1])) { continue }
                $c = Get-LocalCheckout $pair[1]
                $flag = if ($c.Dirty.Count -gt 0) { '  +local changes' } else { '' }
                Write-Host ("    {0,-24} {1}  {2}{3}" -f "$envName $($pair[0])", $c.Commit.Substring(0, 7), $c.Branch, $flag)
            }
        }
        $tags = @(Get-ReleaseTags)
        $stable = @(Get-StableTags)
        if ($tags.Count -gt 0) { Write-Host "    newest pinned            $($tags[0])" }
        if ($stable.Count -gt 0) {
            Write-Host "    newest stable            $($stable[0])"
            if ($prodRelease -and $prodRelease -ne $stable[0]) {
                Write-Host "    prod is not on the newest stable release: .\ops\Nova.ps1 deploy" -ForegroundColor Yellow
            }
        }
    } catch {
        Write-Warn "Could not read versions: $($_.Exception.Message)"
    }

    Write-Host ""
    Write-Host "  Console:  http://localhost:$($cfg.Environments.prod.ConsolePort)"
    Write-Host "  Operator: http://$($cfg.Hosts.Server):$($cfg.Environments.prod.FrontendPort)"
    Write-Host ""
}

function Invoke-Logs {
    $defs = @(Get-NovaServiceDefs $Env)
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

    Check 'settings file' (Test-Path $settingsPath) $settingsPath
    if ($newSettings.Count -gt 0) {
        Check 'settings up to date' $false "missing from nova.settings.ps1 (using the example's values): $($newSettings -join ', ')"
    }
    $placeholder = $null
    if ($null -ne $referenceCfg) { $placeholder = $referenceCfg.Environments.prod.AdminPassword }
    Check 'prod admin password' ($cfg.Environments.prod.AdminPassword -ne $placeholder) $(if ($cfg.Environments.prod.AdminPassword -eq $placeholder) { "still the example's placeholder - set it in $settingsPath" } else { 'set' })

    $isRepo = ($null -ne $git) -and ((Invoke-Git $RepoRoot @('rev-parse', '--show-toplevel') -AllowFail).Code -eq 0)
    Check 'Nova repo' $isRepo $(if ($isRepo) { $RepoRoot } else { "$RepoRoot is not a git checkout - see ops/README.md" })

    $ssh = Get-Command ssh.exe -ErrorAction SilentlyContinue
    Check 'ssh (pin/deploy the Pi)' ($null -ne $ssh) $(if ($null -ne $ssh) { '' } else { 'enable the Windows OpenSSH Client feature' })

    $gh = Get-Command gh.exe -ErrorAction SilentlyContinue
    Check 'gh (publish only)' ($null -ne $gh) $(if ($null -ne $gh) { '' } else { 'winget install GitHub.cli, then gh auth login' })

    foreach ($envName in @('prod', 'dev')) {
        $cd = Get-EnvConfigDir $envName
        $n = @(Get-ChildItem -Path $cd -Filter '*.yaml' -File -ErrorAction SilentlyContinue).Count
        Check "$envName live config" ($n -gt 0) $(if ($n -gt 0) { "$cd ($n files)" } else { "none in $cd - run: Nova.ps1 install -Env $envName" })
    }

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
# Server state
#
# Live config, recordings and history live outside every checkout (see
# nova.settings.ps1). These helpers are the only place that knows the layout.
# ---------------------------------------------------------------------------

function Get-EnvConfigDir { param([string]$EnvName) return (Join-Path $cfg.ConfigRoot $EnvName) }
function Get-HistoryDir   { return (Join-Path $cfg.ConfigRoot 'history') }
function Get-EnvDataDir   { param([string]$EnvName) return (Join-Path $cfg.DataRoot $EnvName) }

function Get-Prop {
    # Read a property off parsed JSON that may not have it. StrictMode turns a
    # missing property into an error, and old files will lack new fields.
    # Missing or null returns NOTHING (not $null), so @(Get-Prop ...) is empty
    # rather than a one-element array holding $null.
    param($Object, [string]$Name)
    if ($null -eq $Object) { return }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p -or $null -eq $p.Value) { return }
    return $p.Value
}

function Write-TextFile {
    # UTF-8 without a BOM: these files are also read by Python, bash and git,
    # and Windows PowerShell's -Encoding utf8 would prepend a BOM.
    param([string]$Path, [string]$Text)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding $false))
}

function ConvertTo-NiceJson {
    # Windows PowerShell 5.1 indents JSON erratically; release.json is read on
    # GitHub, so normalise to two-space indentation.
    param($InputObject, [int]$Depth = 8)
    $raw = $InputObject | ConvertTo-Json -Depth $Depth
    $indent = 0
    $lines = foreach ($line in ($raw -split "`r?`n")) {
        $t = $line.Trim()
        if (-not $t) { continue }
        if ($t -match '^[\}\]]') { $indent-- }
        ('  ' * [Math]::Max($indent, 0)) + ($t -replace '^("(?:[^"\\]|\\.)*"):\s+', '$1: ')
        if ($t -match '[\{\[]$') { $indent++ }
    }
    $text = ($lines -join "`n") -replace '\[\n\s*\]', '[]' -replace '\{\n\s*\}', '{}'
    return $text + "`n"
}

function Get-ContentHash {
    # Same scheme as the backend's config history: first 16 hex of SHA-256.
    param([string]$Path)
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLower().Substring(0, 16)
}

function Get-EnvState {
    # What an environment is running, written by deploy.
    param([string]$EnvName)
    $path = Join-Path $cfg.StateDir "$EnvName.json"
    $state = $null
    if (Test-Path $path) {
        try { $state = Get-Content -Raw -Path $path | ConvertFrom-Json } catch { $state = $null }
    }
    return [pscustomobject]@{
        release  = [string](Get-Prop $state 'release')
        deployed = [string](Get-Prop $state 'deployed')
    }
}

function Set-EnvState {
    param([string]$EnvName, [hashtable]$State)
    Write-TextFile (Join-Path $cfg.StateDir "$EnvName.json") (ConvertTo-NiceJson $State 5)
}

function Save-ConfigToHistory {
    # Mirror of the backend's ConfigHistory.snapshot, for files this script is
    # about to overwrite, so nothing the server ran with is ever lost.
    param([string]$Path, [string]$EnvName, [string]$Source)
    $hash = Get-ContentHash $Path
    $snap = Join-Path (Get-HistoryDir) "snapshots\$hash.yaml"
    if (-not (Test-Path $snap)) {
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $snap) | Out-Null
        Copy-Item -LiteralPath $Path -Destination $snap
    }
    $entry = [ordered]@{
        time   = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss+00:00')
        env    = $EnvName
        file   = (Split-Path -Leaf $Path)
        hash   = $hash
        source = $Source
        client = "Nova.ps1 ($env:USERNAME)"
    }
    [IO.File]::AppendAllText((Join-Path (Get-HistoryDir) 'history.jsonl'),
        (($entry | ConvertTo-Json -Compress) + "`n"), (New-Object Text.UTF8Encoding $false))
    return $hash
}

function Initialize-ServerState {
    param([string]$EnvName)
    $e = $cfg.Environments[$EnvName]
    $configDir = Get-EnvConfigDir $EnvName
    $dataDir = Get-EnvDataDir $EnvName
    foreach ($d in @($configDir, (Get-HistoryDir), $dataDir, $cfg.ArchiveDir, $cfg.StateDir)) {
        New-Item -ItemType Directory -Force -Path $d | Out-Null
    }

    # The first install with server state carries over the config and data
    # this environment was already running with - INCLUDING uncommitted local
    # edits - so moving them out of the checkout loses nothing. Copies only;
    # the originals stay where they were.
    $repoConfig = Join-Path $e.BackendPath 'config'
    $haveConfig = @(Get-ChildItem -Path $configDir -Filter '*.yaml' -File -ErrorAction SilentlyContinue).Count -gt 0
    if (-not $haveConfig -and (Test-Path $repoConfig)) {
        $yaml = @(Get-ChildItem -Path $repoConfig -Filter '*.yaml' -File)
        foreach ($f in $yaml) { Copy-Item -LiteralPath $f.FullName -Destination $configDir }
        Write-Ok "Live config for $EnvName now lives in $configDir (copied $($yaml.Count) file(s) from $repoConfig)"
    }
    $repoData = Join-Path $e.BackendPath 'data'
    $haveData = @(Get-ChildItem -Path $dataDir -File -ErrorAction SilentlyContinue).Count -gt 0
    if (-not $haveData -and (Test-Path $repoData)) {
        $old = @(Get-ChildItem -Path $repoData -File | Where-Object { $_.Name -ne '.gitkeep' })
        foreach ($f in $old) { Copy-Item -LiteralPath $f.FullName -Destination $dataDir }
        if ($old.Count -gt 0) { Write-Ok "Copied $($old.Count) existing data file(s) from $repoData to $dataDir" }
    }
}

function Set-StackRunning {
    # Start or stop one environment's services. The prod console is never
    # stopped here: it is the operator's status page, and must stay up while
    # dev is live.
    param([string]$EnvName, [bool]$Running)
    $saveOnly = $Only
    $script:Only = $AllComponents
    try { $defs = @(Get-NovaServiceDefs $EnvName) } finally { $script:Only = $saveOnly }

    if ($Running) {
        $broker = Get-Service -Name $cfg.Broker.ServiceName -ErrorAction SilentlyContinue
        if ($null -ne $broker -and $broker.Status -ne 'Running') {
            Write-Step "Starting broker $($cfg.Broker.ServiceName)"
            Start-Service -Name $cfg.Broker.ServiceName
        }
    } else {
        $defs = @($defs | Where-Object { -not ($EnvName -eq 'prod' -and $_.Component -eq 'console') } |
                  Sort-Object { $_.Component } -Descending)
    }

    foreach ($def in $defs) {
        $svc = Get-Service -Name $def.ServiceName -ErrorAction SilentlyContinue
        if ($null -eq $svc) {
            if ($Running) { Write-Warn "$($def.ServiceName) is not installed - run: .\ops\Nova.ps1 install -Env $EnvName" }
            continue
        }
        try {
            if ($Running -and $svc.Status -ne 'Running') {
                Start-Service -Name $def.ServiceName
                Write-Ok "started $($def.ServiceName)"
            } elseif (-not $Running -and $svc.Status -ne 'Stopped') {
                Stop-Service -Name $def.ServiceName -Force
                Write-Ok "stopped $($def.ServiceName)"
            }
        } catch {
            Write-Err "Could not change $($def.ServiceName): $($_.Exception.Message)"
        }
    }
}

function Get-LiveStack {
    # Whichever environment's backend is running.
    foreach ($envName in @('prod', 'dev')) {
        $svc = Get-Service -Name "nova-$envName-backend" -ErrorAction SilentlyContinue
        if ($null -ne $svc -and $svc.Status -eq 'Running') { return $envName }
    }
    return $null
}

# ---------------------------------------------------------------------------
# Git, SSH and GitHub helpers
# ---------------------------------------------------------------------------

function Invoke-Native {
    # Run a native program, keeping stdout and stderr apart so a warning can
    # never end up inside a commit hash. Throws on failure unless -AllowFail.
    param([string]$Exe, [string[]]$ArgList, [switch]$AllowFail)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $all = & $Exe @ArgList 2>&1
        $code = $LASTEXITCODE
    } catch {
        $all = @($_)
        $code = 127
    } finally { $ErrorActionPreference = $prev }
    $out = @($all | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$_" })
    $err = @($all | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$_" })
    if ($code -ne 0 -and -not $AllowFail) {
        throw "$Exe $($ArgList -join ' ') failed:`n$(($err + $out) -join "`n")"
    }
    return [pscustomobject]@{ Code = $code; Out = $out; Err = $err; Text = (($out -join "`n").Trim()) }
}

function Invoke-Git {
    param([string]$Dir, [string[]]$GitArgs, [switch]$AllowFail)
    return (Invoke-Native 'git.exe' (@('-C', $Dir) + $GitArgs) -AllowFail:$AllowFail)
}

function Test-GitCommit {
    param([string]$Dir, [string]$Sha)
    return ((Invoke-Git $Dir @('cat-file', '-e', "$Sha^{commit}") -AllowFail).Code -eq 0)
}

function Export-GitBlob {
    # Byte-exact copy of a file as stored at a tag. Captured PowerShell output
    # is re-encoded, and config hashes have to match to the byte.
    param([string]$Rev, [string]$RepoPath, [string]$OutFile)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $OutFile) | Out-Null
    $psi = New-Object Diagnostics.ProcessStartInfo 'git.exe'
    $psi.Arguments = "-C `"$RepoRoot`" show `"${Rev}:$RepoPath`""
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $proc = [Diagnostics.Process]::Start($psi)
    $fs = [IO.File]::Create($OutFile)
    try { $proc.StandardOutput.BaseStream.CopyTo($fs) } finally { $fs.Close() }
    $errText = $proc.StandardError.ReadToEnd()
    $proc.WaitForExit()
    if ($proc.ExitCode -ne 0) { throw "Could not read ${Rev}:$RepoPath from git: $errText" }
}

function Assert-NovaRepo {
    if ((Invoke-Git $RepoRoot @('rev-parse', '--show-toplevel') -AllowFail).Code -ne 0) {
        throw "$RepoRoot is not a git checkout of the Nova repo. See ops/README.md, 'First-time setup'."
    }
}

function Get-PinParts {
    # Everything a release pins. Dev/Prod are this PC's checkouts; novaGround
    # lives on the Pi and firmware is a reference only
    return @(
        [pscustomobject]@{ Path = 'prod/backend';       Label = 'novaOps backend';      Dev = $cfg.Environments.dev.BackendPath;  Prod = $cfg.Environments.prod.BackendPath }
        [pscustomobject]@{ Path = 'prod/frontend';      Label = 'novaOps frontend';     Dev = $cfg.Environments.dev.FrontendPath; Prod = $cfg.Environments.prod.FrontendPath }
        [pscustomobject]@{ Path = 'pi/novaGround';      Label = 'novaGround (Pi)';      Dev = $null; Prod = $null }
        [pscustomobject]@{ Path = 'firmware';           Label = 'firmware (reference)'; Dev = $null; Prod = $null }
    )
}

function Get-Pins {
    # submodule path -> pinned commit, as recorded at $Rev.
    param([string]$Rev = 'HEAD')
    $pins = @{}
    $r = Invoke-Git $RepoRoot (@('ls-tree', $Rev, '--') + @(Get-PinParts | ForEach-Object { $_.Path })) -AllowFail
    foreach ($line in $r.Out) {
        if ($line -match '^160000 commit ([0-9a-f]{40})\t(.+)$') { $pins[$Matches[2]] = $Matches[1] }
    }
    return $pins
}

function Get-LocalCheckout {
    param([string]$Path)
    if (-not (Test-Path $Path)) { throw "Missing checkout: $Path" }
    $sha = (Invoke-Git $Path @('rev-parse', 'HEAD')).Text
    $branch = (Invoke-Git $Path @('rev-parse', '--abbrev-ref', 'HEAD')).Text
    if ($branch -eq 'HEAD') { $branch = '(detached)' }
    $dirty = @((Invoke-Git $Path @('status', '--porcelain', '--untracked-files=no')).Out | Where-Object { $_ })
    $onRemote = @((Invoke-Git $Path @('branch', '-r', '--contains', $sha) -AllowFail).Out).Count -gt 0
    # dev and main only change through merged PRs, so on those branches the
    # commit must already be on origin's copy (as of the last fetch).
    $onUpstream = $true
    if ($branch -eq $cfg.Branches.Dev -or $branch -eq $cfg.Branches.Prod) {
        $onUpstream = (Invoke-Git $Path @('merge-base', '--is-ancestor', $sha, "origin/$branch") -AllowFail).Code -eq 0
    }
    return [pscustomobject]@{ Commit = $sha; Branch = $branch; Dirty = $dirty; OnRemote = $onRemote; OnUpstream = $onUpstream }
}

function Test-UsualBranch {
    # The branches a release normally comes from (CONTRIBUTING.md). Others are
    # allowed - pin and promote only say so. '(unchanged)' carries a pin over
    # from the previous release.
    param([string]$Branch)
    return ($Branch -eq $cfg.Branches.Dev -or $Branch -eq $cfg.Branches.Prod -or $Branch -eq '(unchanged)' -or
            $Branch.StartsWith($cfg.Branches.HotfixPrefix) -or $Branch.StartsWith($cfg.Branches.ReleasePrefix))
}

function Get-UsualBranchText {
    return "'$($cfg.Branches.Dev)', '$($cfg.Branches.Prod)', '$($cfg.Branches.HotfixPrefix)*' or '$($cfg.Branches.ReleasePrefix)*'"
}

function Get-NovaBranch {
    return (Invoke-Git $RepoRoot @('rev-parse', '--abbrev-ref', 'HEAD')).Text
}

function Assert-NovaOnMain {
    # The Nova repo uses GitHub Flow: release history lives on its main. While
    # C:\Nova is switched to a branch to try script changes, commands that
    # write release history refuse, so no record lands on a feature branch.
    param([string]$What)
    $b = Get-NovaBranch
    if ($b -ne $cfg.Branches.Prod) {
        throw ("'$What' records release history, which lives on the Nova repo's $($cfg.Branches.Prod), but $RepoRoot is on '$b'. " +
               "Switch back first:  git -C $RepoRoot switch $($cfg.Branches.Prod)")
    }
}

function Import-Commit {
    # Make $Sha available in checkout $Path: already there, fetched from
    # origin, or - offline - fetched from the dev checkout it was tested in.
    param([string]$Path, [string]$Sha, [string]$DevPath)
    if (Test-GitCommit $Path $Sha) { return }
    Write-Step "Fetching $($Sha.Substring(0, 7)) into $Path"
    [void](Invoke-Git $Path @('fetch', 'origin') -AllowFail)
    if (Test-GitCommit $Path $Sha) { return }
    if ($DevPath -and (Test-Path $DevPath)) {
        [void](Invoke-Git $Path @('fetch', $DevPath, '+refs/heads/*:refs/remotes/nova-dev/*', '+HEAD:refs/remotes/nova-dev/HEAD') -AllowFail)
        if (Test-GitCommit $Path $Sha) { return }
    }
    throw "Commit $Sha is not in $Path, and neither origin nor $DevPath could supply it."
}

function Invoke-PiSsh {
    # -Tty: interactive (sudo prompts, live build output); output not captured.
    param([string]$Command, [switch]$Tty)
    $sshArgs = @('-o', 'ConnectTimeout=8')
    if ($Tty) { $sshArgs += '-t' }
    $sshArgs += @("$($cfg.Pi.User)@$($cfg.Hosts.NovaGround)", $Command)
    if ($Tty) {
        try { & ssh.exe @sshArgs; $code = $LASTEXITCODE } catch { $code = 127 }
        return [pscustomobject]@{ Code = $code; Out = @() }
    }
    return (Invoke-Native 'ssh.exe' $sshArgs -AllowFail)
}

function Get-PiDevCommit {
    $d = $cfg.Pi.DevDir
    $r = Invoke-PiSsh "git -C $d rev-parse HEAD && git -C $d rev-parse --abbrev-ref HEAD && git -C $d status --porcelain --untracked-files=no | head -n 20"
    if ($r.Code -ne 0 -or $r.Out.Count -lt 2 -or $r.Out[0] -notmatch '^[0-9a-f]{40}$') { return $null }
    $branch = $r.Out[1]
    if ($branch -eq 'HEAD') { $branch = '(detached)' }
    return [pscustomobject]@{ Commit = $r.Out[0]; Branch = $branch; Dirty = @($r.Out | Select-Object -Skip 2 | Where-Object { $_ }) }
}

function Get-GitHubBase {
    # https://github.com/<owner>/<repo> for a submodule path, or for the Nova
    # repo itself when $Path is empty.
    param([string]$Path)
    if ($Path) {
        $url = (Invoke-Git $RepoRoot @('config', '-f', '.gitmodules', '--get', "submodule.$Path.url") -AllowFail).Text
    } else {
        $url = (Invoke-Git $RepoRoot @('remote', 'get-url', 'origin') -AllowFail).Text
    }
    if ($url -match 'github\.com[:/]([^/]+)/([^/]+?)(\.git)?/?$') { return "https://github.com/$($Matches[1])/$($Matches[2])" }
    return $null
}

function Invoke-Gh {
    param([string[]]$GhArgs, [switch]$AllowFail)
    Push-Location $RepoRoot
    try { return (Invoke-Native 'gh.exe' $GhArgs -AllowFail:$AllowFail) } finally { Pop-Location }
}

# ---------------------------------------------------------------------------
# Releases
#
#   v2026.10.04          annotated tag on the commit that pins a tested set
#   stable/v2026.10.04   added by `promote`; `deploy` defaults to the newest
#   releases/<tag>/      release.json (pins, test, notes, recordings) and
#                        config/ (the exact config files that were tested)
# ---------------------------------------------------------------------------

$ReleaseTagPattern = '^v\d{4}\.\d{2}\.\d{2}(\.\d+)?$'

function Get-ReleaseTags {
    # Newest first.
    $r = Invoke-Git $RepoRoot @('for-each-ref', '--sort=-v:refname', '--format=%(refname:short)', 'refs/tags/') -AllowFail
    return @($r.Out | Where-Object { $_ -match $ReleaseTagPattern })
}

function Get-StableTags {
    # Newest release first (not most recently promoted).
    $r = Invoke-Git $RepoRoot @('for-each-ref', '--sort=-v:refname', '--format=%(refname:short)', 'refs/tags/stable/') -AllowFail
    return @($r.Out | ForEach-Object { $_ -replace '^stable/', '' } | Where-Object { $_ -match $ReleaseTagPattern })
}

function Get-ReleaseManifest {
    param([string]$Tag)
    $r = Invoke-Git $RepoRoot @('show', "${Tag}:releases/$Tag/release.json") -AllowFail
    if ($r.Code -ne 0) { return $null }
    return ($r.Out -join "`n" | ConvertFrom-Json)
}

function Get-PinCommit {
    param($Manifest, [string]$Path)
    return (Get-Prop (Get-Prop (Get-Prop $Manifest 'pins') $Path) 'commit')
}

function New-ReleaseTagName {
    $base = 'v' + (Get-Date -Format 'yyyy.MM.dd')
    $existing = @((Invoke-Git $RepoRoot @('tag', '-l', "$base*")).Out)
    if ($existing -notcontains $base) { return $base }
    $n = 2
    while ($existing -contains "$base.$n") { $n++ }
    return "$base.$n"
}

function Update-ReleaseIndex {
    # C:\Nova\releases.json - served by the console at /api/releases, which is
    # how `nova-pi.sh deploy <tag>` finds the commit to check out.
    if ((Invoke-Git $RepoRoot @('rev-parse', '--git-dir') -AllowFail).Code -ne 0) { return }
    $stable = @(Get-StableTags)
    $releases = @()
    foreach ($tag in (Get-ReleaseTags)) {
        $m = Get-ReleaseManifest $tag
        if ($null -eq $m) { continue }
        $releases += [ordered]@{
            tag     = $tag
            created = (Get-Prop $m 'created')
            test    = (Get-Prop $m 'test')
            kind    = (Get-Prop $m 'kind')
            stable  = ($stable -contains $tag)
            pins    = (Get-Prop $m 'pins')
        }
    }
    $latest = $null
    if ($stable.Count -gt 0) { $latest = $stable[0] }
    $index = [ordered]@{
        generated    = (Get-Date).ToString('s')
        latestStable = $latest
        deployed     = [ordered]@{ prod = (Get-EnvState 'prod').release }
        releases     = $releases
    }
    Write-TextFile $cfg.ReleaseIndex (ConvertTo-NiceJson $index 8)
}

function New-ReleaseNotes {
    # Markdown body for the GitHub release, regenerated on every publish so the
    # status line follows promotion.
    param([string]$Tag, [bool]$IsStable)
    $m = Get-ReleaseManifest $Tag
    $prevTag = Get-Prop $m 'previous'
    $prev = $null
    if ($prevTag) { $prev = Get-ReleaseManifest $prevTag }
    $nova = Get-GitHubBase ''

    $L = New-Object 'System.Collections.Generic.List[string]'
    if ((Get-Prop $m 'kind') -eq 'hotfix') { $L.Add('**Status: stable hotfix** - fixed and tested on prod during a test.') }
    elseif ($IsStable) { $L.Add('**Status: stable** - promoted for prod use.') }
    else { $L.Add('**Status: pre-release** - passed its hardware test, not yet promoted to stable.') }
    $unusual = @()
    foreach ($p in @((Get-Prop $m 'pins').PSObject.Properties)) {
        if ($p.Name -eq 'firmware') { continue }
        $b = [string](Get-Prop $p.Value 'branch')
        if ($b -and $b -ne '(given by hand)' -and -not (Test-UsualBranch $b)) { $unusual += "``$($p.Name)`` from ``$b``" }
    }
    if ($unusual.Count -gt 0) { $L.Add(''); $L.Add("**Outside the usual branches:** $($unusual -join ', ') - see the notes for why.") }
    $L.Add('')
    $L.Add("**Test:** $(Get-Prop $m 'test')  ")
    $L.Add("**Pinned:** $(Get-Prop $m 'created') by $(Get-Prop $m 'operator')")
    $notesText = Get-Prop $m 'notes'
    if ($notesText) { $L.Add(''); $L.Add($notesText) }

    $L.Add('')
    $L.Add('| Component | Commit | Branch | Since ' + $(if ($prevTag) { $prevTag } else { 'previous' }) + ' |')
    $L.Add('|---|---|---|---|')
    foreach ($part in (Get-PinParts)) {
        $pin = Get-Prop (Get-Prop $m 'pins') $part.Path
        $sha = Get-Prop $pin 'commit'
        if (-not $sha) { continue }
        $base = Get-GitHubBase $part.Path
        $old = Get-PinCommit $prev $part.Path
        $shaCell = if ($base) { "[``$($sha.Substring(0, 7))``]($base/commit/$sha)" } else { "``$($sha.Substring(0, 7))``" }
        $change = if (-not $old) { '-' } elseif ($old -eq $sha) { 'unchanged' } elseif ($base) { "[changes]($base/compare/$old...$sha)" } else { 'changed' }
        $L.Add("| $($part.Label) | $shaCell | $(Get-Prop $pin 'branch') | $change |")
    }

    $configs = @(Get-Prop $m 'config')
    if ($configs.Count -gt 0) {
        $L.Add('')
        $where = if ($nova) { "[releases/$Tag/config]($nova/tree/$Tag/releases/$Tag/config)" } else { "releases/$Tag/config" }
        $L.Add("**Config tested with** ($where):")
        foreach ($c in $configs) { $L.Add("- ``$(Get-Prop $c 'file')`` (hash ``$(Get-Prop $c 'hash')``)") }
    }
    $recs = @(Get-Prop $m 'recordings')
    if ($recs.Count -gt 0) {
        $L.Add('')
        $L.Add("**Recordings from this test:** " + (($recs | ForEach-Object { "``$_``" }) -join ', '))
    }
    $L.Add('')
    $L.Add("Deploy: ``.\ops\Nova.ps1 deploy $Tag`` on the ops PC; ``sudo ./nova-pi.sh deploy $Tag`` on the Pi.")
    return ($L -join "`n")
}

# ---------------------------------------------------------------------------
# Release workflow actions
# ---------------------------------------------------------------------------

function Invoke-GetChanges {
    Assert-Admin
    $targets = @()
    if ($Only -contains 'backend' -or $Only -contains 'fas') { $targets += [pscustomobject]@{ Name = 'backend'; Path = $envCfg.BackendPath } }
    if ($Only -contains 'frontend') { $targets += [pscustomobject]@{ Name = 'frontend'; Path = $envCfg.FrontendPath } }

    foreach ($t in $targets) {
        Write-Step "dev $($t.Name): $($t.Path)"
        if (-not (Test-Path $t.Path)) { throw "Missing dev checkout $($t.Path). Clone it there first (see ops/README.md)." }

        $dirty = @((Invoke-Git $t.Path @('status', '--porcelain', '--untracked-files=no')).Out | Where-Object { $_ })
        if ($dirty.Count -gt 0) {
            Write-Warn "Uncommitted changes here (git will refuse anything that would overwrite them):"
            $dirty | ForEach-Object { Write-Warn "  $_" }
        }
        if ((Invoke-Git $t.Path @('fetch', '--all', '--prune') -AllowFail).Code -ne 0) {
            Write-Warn "fetch failed (offline?) - using what was already fetched."
        }
        if ($Ref) {
            # A remote branch name creates a local tracking branch; a tag or
            # commit leaves the checkout detached, which is fine for testing.
            $co = Invoke-Git $t.Path @('checkout', $Ref) -AllowFail
            if ($co.Code -ne 0) {
                throw "Could not check out '$Ref' in $($t.Path):`n$(($co.Err + $co.Out) -join "`n")`nIf the backend and frontend use different branches, run get-changes once per component with -Only."
            }
        }
        $branch = (Invoke-Git $t.Path @('rev-parse', '--abbrev-ref', 'HEAD')).Text
        if ($branch -eq 'HEAD') {
            Write-Warn "Detached HEAD - nothing to pull."
        } elseif ((Invoke-Git $t.Path @('rev-parse', '--abbrev-ref', '@{u}') -AllowFail).Code -ne 0) {
            Write-Warn "$branch has no upstream branch - nothing to pull."
        } else {
            $ff = Invoke-Git $t.Path @('merge', '--ff-only', '@{u}') -AllowFail
            if ($ff.Code -ne 0) { throw "$branch in $($t.Path) cannot fast-forward to its upstream (local commits?). Resolve by hand, then re-run." }
        }
        $c = Get-LocalCheckout $t.Path
        Write-Ok "now at $($c.Commit.Substring(0, 7)) ($($c.Branch))"
        if (-not (Test-UsualBranch $c.Branch)) {
            Write-Warn "'$($c.Branch)' is fine to try on the bench. A release pinned from it is flagged as outside $(Get-UsualBranchText)."
        }
    }

    Invoke-Install

    Write-Host ""
    Write-Ok "Dev is ready. Next:"
    Write-Ok "  .\ops\Nova.ps1 use dev"
    Write-Ok "Pi (if its code changed):  ssh $($cfg.Pi.User)@$($cfg.Hosts.NovaGround)"
    Write-Ok "  cd $($cfg.Pi.DevDir) && git pull && ./nova-pi.sh build --env dev"
}

function Invoke-Use {
    Assert-Admin
    if ($Target -notin @('dev', 'prod')) { throw "Usage: .\ops\Nova.ps1 use dev   or   .\ops\Nova.ps1 use prod" }
    $other = if ($Target -eq 'dev') { 'prod' } else { 'dev' }

    Write-Step "Stopping $other"
    Set-StackRunning $other $false
    # The broker client IDs and the FAS COM port are released asynchronously.
    Start-Sleep -Seconds 2
    Write-Step "Starting $Target"
    Set-StackRunning $Target $true

    Write-Host ""
    if ($Target -eq 'dev') {
        Write-Warn "Dev is live. Prod stays stopped until: .\ops\Nova.ps1 use prod  (or a reboot - prod starts on boot)."
        Write-Warn "Operator UI for dev: http://$($cfg.Hosts.Server):$($cfg.Environments.dev.FrontendPort)"
        Write-Warn "Pi: stop its prod service and run dev by hand -  sudo systemctl stop novaGround; cd $($cfg.Pi.DevDir) && ./run.sh"
    } else {
        Write-Ok "Prod is live. Pi: sudo systemctl start novaGround  (if you stopped it for dev)"
    }
}

function New-Release {
    # Record $Pins as a new release: a vYYYY.MM.DD tag on one commit of the
    # Nova repo's main, holding release.json and the exact config $EnvName ran
    # with. Shared by pin (a dev-stack test) and hotfix (a prod-stack fix).
    # Returns the tag.
    param(
        [System.Collections.Specialized.OrderedDictionary]$Pins,
        [string]$EnvName,
        [string]$Kind,
        [string[]]$Warnings = @(),
        [switch]$Stable
    )
    $current = Get-Pins 'HEAD'
    $tag = New-ReleaseTagName
    $releaseDir = Join-Path $RepoRoot "releases\$tag"
    Write-Step "Recording release $tag"

    # The config the stack ran with, byte for byte.
    $configFiles = @()
    $configDir = Get-EnvConfigDir $EnvName
    $yaml = @(Get-ChildItem -Path $configDir -Filter '*.yaml' -File -ErrorAction SilentlyContinue)
    if ($yaml.Count -eq 0) { $Warnings += "No live $EnvName config in $configDir - this release records no config." }
    New-Item -ItemType Directory -Force -Path (Join-Path $releaseDir 'config') | Out-Null
    foreach ($f in $yaml) {
        Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $releaseDir "config\$($f.Name)")
        $configFiles += [ordered]@{ file = $f.Name; hash = (Get-ContentHash $f.FullName) }
    }

    # Recordings made since the previous release: the test's data.
    $prevTag = $null
    $allTags = @(Get-ReleaseTags)
    if ($allTags.Count -gt 0) { $prevTag = $allTags[0] }
    $since = $null
    if ($prevTag) {
        $prevCreated = Get-Prop (Get-ReleaseManifest $prevTag) 'created'
        if ($prevCreated) { $since = [datetime]$prevCreated }
    }
    $recordings = @()
    foreach ($mf in @(Get-ChildItem -Path (Get-EnvDataDir $EnvName) -Filter '*.meta.json' -File -ErrorAction SilentlyContinue)) {
        try { $meta = Get-Content -Raw -LiteralPath $mf.FullName | ConvertFrom-Json } catch { continue }
        $started = Get-Prop $meta 'started'
        if ($null -eq $since -or ($started -and [datetime]$started -ge $since)) { $recordings += (Get-Prop $meta 'recording') }
    }

    $manifest = [ordered]@{
        tag        = $tag
        kind       = $Kind
        env        = $EnvName
        created    = (Get-Date).ToString('o')
        test       = $Test
        notes      = $Notes
        operator   = "$env:USERNAME@$env:COMPUTERNAME"
        previous   = $prevTag
        pins       = $Pins
        config     = $configFiles
        recordings = @($recordings | Sort-Object)
    }
    Write-TextFile (Join-Path $releaseDir 'release.json') (ConvertTo-NiceJson $manifest 6)

    # Record the gitlinks directly: the commits need not be present locally
    # (the Pi's never are), and prod's checkouts are only moved by deploy.
    foreach ($path in @($Pins.Keys)) {
        $sha = $Pins[$path].commit
        if ($sha -and $current[$path] -ne $sha) {
            [void](Invoke-Git $RepoRoot @('update-index', '--cacheinfo', "160000,$sha,$path"))
        }
    }
    [void](Invoke-Git $RepoRoot @('add', '--', "releases/$tag"))

    $label = if ($Kind -eq 'hotfix') { 'Hotfix' } else { 'Pin' }
    $msg = @("$label ${tag}: $Test", '')
    if ($Notes) { $msg += @($Notes, '') }
    foreach ($path in @($Pins.Keys)) { $msg += "$path $($Pins[$path].commit) $($Pins[$path].branch)" }
    $msgFile = [IO.Path]::GetTempFileName()
    try {
        Write-TextFile $msgFile ($msg -join "`n")
        [void](Invoke-Git $RepoRoot @('commit', '-q', '-F', $msgFile))
        [void](Invoke-Git $RepoRoot @('tag', '-a', $tag, '-F', $msgFile))
        if ($Stable) {
            Write-TextFile $msgFile "Stable on creation: $Kind ($env:USERNAME, $((Get-Date).ToString('s')))"
            [void](Invoke-Git $RepoRoot @('tag', '-a', "stable/$tag", "$tag^{commit}", '-F', $msgFile))
        }
    } finally { Remove-Item -LiteralPath $msgFile -ErrorAction SilentlyContinue }

    Update-ReleaseIndex | Out-Null
    Invoke-Archive | Out-Null

    Write-Host ""
    $stableText = if ($Stable) { ', stable' } else { '' }
    Write-Ok "Release $tag  ($Test$stableText)"
    foreach ($part in (Get-PinParts)) {
        $sha = $Pins[$part.Path].commit
        $was = if ($current[$part.Path] -eq $sha) { 'unchanged' } else { 'CHANGED' }
        Write-Ok ("  {0,-22} {1}  {2,-22} {3}" -f $part.Label, $sha.Substring(0, 7), $Pins[$part.Path].branch, $was)
    }
    Write-Ok "  config: $(@($configFiles | ForEach-Object { $_.file }) -join ', ')"
    Write-Ok "  recordings: $($recordings.Count)"
    $Warnings | ForEach-Object { Write-Warn $_ }
    return $tag
}

function Invoke-Pin {
    if ([string]::IsNullOrWhiteSpace($Test)) {
        throw 'Say what was tested:  .\ops\Nova.ps1 pin -Test "integration test" [-Notes "..."]'
    }
    Assert-NovaRepo
    Assert-NovaOnMain 'pin'
    if ((Invoke-Git $RepoRoot @('diff', '--cached', '--quiet') -AllowFail).Code -ne 0) {
        throw "The Nova repo has staged changes. Commit or unstage them first (git -C $RepoRoot status) - pin makes its own commit."
    }

    $current = Get-Pins 'HEAD'
    $pins = [ordered]@{}
    $problems = @()
    $warnings = @()
    # Allowed, but worth saying: pins from outside dev/main/hotfix/release.
    $unusual = @()

    # PC components: exactly what the dev checkouts are running.
    foreach ($part in @(Get-PinParts | Where-Object { $_.Dev })) {
        $c = Get-LocalCheckout $part.Dev
        if ($c.Dirty.Count -gt 0) {
            $problems += "$($part.Label) ($($part.Dev)) has uncommitted changes. Tested code must be committed to be pinned:"
            $problems += @($c.Dirty | ForEach-Object { "    $_" })
        }
        if (-not $c.OnUpstream) {
            # dev and main only ever change through merged PRs on GitHub.
            $problems += ("$($part.Label): local '$($c.Branch)' has commits that are not on origin/$($c.Branch). " +
                          "Move them to a branch (git -C $($part.Dev) switch -c bugfix/<what>), push it and open a PR, " +
                          "then reset '$($c.Branch)' (git -C $($part.Dev) switch $($c.Branch); git reset --hard origin/$($c.Branch)).")
        }
        if (-not $c.OnRemote) {
            $warnings += "$($part.Label) $($c.Commit.Substring(0, 7)) is not on any remote branch yet - push it before publish."
        }
        if (-not (Test-UsualBranch $c.Branch)) { $unusual += "$($part.Label) on '$($c.Branch)'" }
        $pins[$part.Path] = [ordered]@{ commit = $c.Commit; branch = $c.Branch }
    }

    # novaGround: the Pi's dev checkout, over SSH.
    $gp = 'pi/novaGround'
    if ($GroundCommit) {
        if ($GroundCommit -notmatch '^[0-9a-f]{40}$') { throw "-GroundCommit needs the full 40-character hash (run 'git rev-parse HEAD' on the Pi)." }
        $gb = if ($GroundBranch) { $GroundBranch } else { '(given by hand)' }
        $pins[$gp] = [ordered]@{ commit = $GroundCommit; branch = $gb }
        if ($GroundBranch -and -not (Test-UsualBranch $GroundBranch)) { $unusual += "novaGround (Pi) on '$GroundBranch'" }
    } elseif ($SkipPi) {
        if (-not $current[$gp]) { throw "-SkipPi keeps the current novaGround pin, but there is none." }
        $pins[$gp] = [ordered]@{ commit = $current[$gp]; branch = '(unchanged)' }
        $warnings += "novaGround pin kept unchanged (-SkipPi) - make sure that is what the Pi ran."
    } else {
        Write-Step "Reading the Pi's dev commit ($($cfg.Pi.User)@$($cfg.Hosts.NovaGround):$($cfg.Pi.DevDir))"
        $pi = Get-PiDevCommit
        if ($null -eq $pi) {
            throw ("Could not read the Pi's dev commit over SSH. Fix SSH, or re-run with " +
                   "-GroundCommit <full hash from 'git rev-parse HEAD' in $($cfg.Pi.DevDir)> -GroundBranch <its branch>, " +
                   "or -SkipPi to keep the current novaGround pin.")
        }
        if ($pi.Dirty.Count -gt 0) {
            $problems += "novaGround ($($cfg.Pi.DevDir) on the Pi) has uncommitted changes. Commit them on the Pi first:"
            $problems += @($pi.Dirty | ForEach-Object { "    $_" })
        }
        if (-not (Test-UsualBranch $pi.Branch)) { $unusual += "novaGround (Pi) on '$($pi.Branch)'" }
        $pins[$gp] = [ordered]@{ commit = $pi.Commit; branch = $pi.Branch }
    }

    # Firmware: a reference, changed only when you say so.
    if ($Firmware) {
        $fwDir = Join-Path $RepoRoot 'firmware'
        $r = Invoke-Git $fwDir @('rev-parse', "$Firmware^{commit}") -AllowFail
        if ($r.Code -eq 0) { $fwSha = $r.Text }
        elseif ($Firmware -match '^[0-9a-f]{40}$') { $fwSha = $Firmware }
        else { throw "Unknown firmware ref '$Firmware'. Fetch it in $fwDir first, or give the full commit hash." }
        $pins['firmware'] = [ordered]@{ commit = $fwSha; branch = '(given by hand)' }
    } else {
        $pins['firmware'] = [ordered]@{ commit = $current['firmware']; branch = '(unchanged)' }
    }

    if ($problems.Count -gt 0) {
        $problems | ForEach-Object { Write-Err $_ }
        throw "Nothing was pinned."
    }
    if ($unusual.Count -gt 0) {
        # Not the normal path (CONTRIBUTING.md), but allowed: say so on record.
        $warnings += "Pinned from outside the usual branches ($(Get-UsualBranchText)): $($unusual -join '; '). Explain why in -Notes or the release notes."
    }

    $tag = @(New-Release -Pins $pins -EnvName 'dev' -Kind 'test' -Warnings $warnings)[-1]

    Write-Host ""
    Write-Ok "Next: .\ops\Nova.ps1 promote $tag   (once it is proven stable)"
    Write-Ok "      .\ops\Nova.ps1 publish          (when online)"
}

function Invoke-Promote {
    Assert-NovaRepo
    Assert-NovaOnMain 'promote'
    $stable = @(Get-StableTags)
    if (-not $Target) {
        $pending = @(Get-ReleaseTags | Where-Object { $stable -notcontains $_ } | Select-Object -First 5)
        throw "Name the release to promote: .\ops\Nova.ps1 promote <tag>`nNot yet stable: $($pending -join ', ')"
    }
    $m = Get-ReleaseManifest $Target
    if ($null -eq $m) { throw "$Target is not a pinned release." }
    if ($stable -contains $Target) { Write-Ok "$Target is already stable."; return }

    # The normal path is a release pinned from dev (CONTRIBUTING.md). Anything
    # else is allowed; make sure whoever promotes it has seen that.
    $pins = Get-Prop $m 'pins'
    foreach ($p in @($pins.PSObject.Properties)) {
        if ($p.Name -eq 'firmware') { continue }
        $branch = [string](Get-Prop $p.Value 'branch')
        if ($branch -eq '(given by hand)') { Write-Warn "$($p.Name): commit was given by hand; its branch is unknown." }
        elseif (-not (Test-UsualBranch $branch)) { Write-Warn "$($p.Name) was pinned from '$branch', outside $(Get-UsualBranchText)." }
    }

    $msgFile = [IO.Path]::GetTempFileName()
    try {
        Write-TextFile $msgFile "Promoted $Target to stable ($env:USERNAME, $((Get-Date).ToString('s')))"
        [void](Invoke-Git $RepoRoot @('tag', '-a', "stable/$Target", "$Target^{commit}", '-F', $msgFile))
    } finally { Remove-Item -LiteralPath $msgFile -ErrorAction SilentlyContinue }
    Update-ReleaseIndex

    Write-Ok "$Target is stable."
    Write-Ok "Next: .\ops\Nova.ps1 deploy          (deploys the newest stable release)"
    Write-Ok "      .\ops\Nova.ps1 publish         (when online: creates release/$Target and opens its PRs into $($cfg.Branches.Prod))"
}

function Invoke-Hotfix {
    # On-site hotfix: an emergency edit made in the prod checkouts and just
    # tested on the prod stack becomes hotfix/<name> in each repo it touched,
    # recorded as a new release that is stable straight away - prod is already
    # running it. `publish` opens the PRs into main, then back into dev.
    Assert-NovaRepo
    Assert-NovaOnMain 'hotfix'
    if (-not $Name -or [string]::IsNullOrWhiteSpace($Test)) {
        throw 'Usage: .\ops\Nova.ps1 hotfix -Name <what> -Test "<how it was tested>"     e.g.  hotfix -Name igniter-delay -Test "integration test, igniter re-run"'
    }
    if ($Name -notmatch '^[a-z0-9]+(-[a-z0-9]+)*$') { throw "-Name must be lower-case words joined by single hyphens, e.g. igniter-delay" }
    if ((Invoke-Git $RepoRoot @('diff', '--cached', '--quiet') -AllowFail).Code -ne 0) {
        throw "The Nova repo has staged changes. Commit or unstage them first (git -C $RepoRoot status) - hotfix makes its own commit."
    }
    $branch = "$($cfg.Branches.HotfixPrefix)$Name"

    $prodRelease = (Get-EnvState 'prod').release
    $base = $null
    if ($prodRelease) { $base = Get-ReleaseManifest $prodRelease }
    if ($null -eq $base) { Write-Warn "Prod's release is unknown (not deployed with Nova.ps1), so each hotfix branch starts from what its checkout had." }
    $current = Get-Pins 'HEAD'

    # Look at everything before changing anything.
    $plan = @()
    foreach ($part in @(Get-PinParts | Where-Object { $_.Prod })) {
        if (-not (Test-Path $part.Prod)) { throw "Missing prod checkout $($part.Prod)." }
        $edits = @((Invoke-Git $part.Prod @('status', '--porcelain')).Out | Where-Object { $_ })
        if ($edits.Count -gt 0 -and (Invoke-Git $part.Prod @('rev-parse', '--verify', '--quiet', "refs/heads/$branch") -AllowFail).Code -eq 0) {
            throw "$branch already exists in $($part.Prod). Pick another -Name."
        }
        $plan += [pscustomobject]@{ Part = $part; Edits = $edits; Head = (Invoke-Git $part.Prod @('rev-parse', 'HEAD')).Text }
    }
    $pi = $null
    if (-not $SkipPi) {
        $d = $cfg.Pi.ProdDir
        Write-Step "Checking the Pi's prod checkout ($($cfg.Pi.User)@$($cfg.Hosts.NovaGround):$d)"
        $r = Invoke-PiSsh "git -C $d rev-parse HEAD && (git -C $d rev-parse --verify --quiet refs/heads/$branch >/dev/null && echo BRANCH-EXISTS || echo BRANCH-FREE) && git -C $d status --porcelain"
        if ($r.Code -ne 0 -or $r.Out.Count -lt 2 -or $r.Out[0] -notmatch '^[0-9a-f]{40}$') {
            throw "Could not read the Pi's prod checkout over SSH. Fix SSH, or re-run with -SkipPi if the Pi was not edited."
        }
        $pi = [pscustomobject]@{ Head = $r.Out[0]; Exists = ($r.Out[1] -eq 'BRANCH-EXISTS'); Edits = @($r.Out | Select-Object -Skip 2 | Where-Object { $_ }) }
        if ($pi.Edits.Count -gt 0 -and $pi.Exists) { throw "$branch already exists on the Pi. Pick another -Name." }
    }

    $edited = @($plan | Where-Object { $_.Edits.Count -gt 0 })
    if ($edited.Count -eq 0 -and ($null -eq $pi -or $pi.Edits.Count -eq 0)) {
        throw ("No edits found in the prod checkouts, so there is nothing to capture. " +
               "(A planned hotfix is an ordinary hotfix/* branch tested on the dev stack - see CONTRIBUTING.md.)")
    }

    Write-Step "Capturing the prod edits as $branch"
    foreach ($p in $edited) {
        Write-Ok "$($p.Part.Label):"
        $p.Edits | ForEach-Object { Write-Ok "    $_" }
    }
    if ($null -ne $pi -and $pi.Edits.Count -gt 0) {
        Write-Ok "novaGround (Pi):"
        $pi.Edits | ForEach-Object { Write-Ok "    $_" }
    }

    # The server may have no git identity; commits still need one.
    $who = @()
    if (-not (Invoke-Git $RepoRoot @('config', 'user.name') -AllowFail).Text) {
        $who = @('-c', "user.name=NovaOps server ($env:USERNAME)", '-c', "user.email=nova@$($env:COMPUTERNAME.ToLower())")
    }
    $subject = "fix: $Name (on-site hotfix)"
    $msgFile = [IO.Path]::GetTempFileName()
    $pins = [ordered]@{}
    try {
        Write-TextFile $msgFile (@($subject, '', "Tested on prod: $Test", $Notes) -join "`n")
        foreach ($p in $plan) {
            $path = $p.Part.Path
            if ($p.Edits.Count -gt 0) {
                [void](Invoke-Git $p.Part.Prod @('switch', '-q', '-c', $branch))
                [void](Invoke-Git $p.Part.Prod @('add', '-A'))
                [void](Invoke-Git $p.Part.Prod ($who + @('commit', '-q', '-F', $msgFile)))
                $pins[$path] = [ordered]@{ commit = (Invoke-Git $p.Part.Prod @('rev-parse', 'HEAD')).Text; branch = $branch }
            } else {
                $was = [string](Get-Prop (Get-Prop (Get-Prop $base 'pins') $path) 'branch')
                if (-not $was) { $was = '(unchanged)' }
                $pins[$path] = [ordered]@{ commit = $p.Head; branch = $was }
            }
        }
    } finally { Remove-Item -LiteralPath $msgFile -ErrorAction SilentlyContinue }

    $gp = 'pi/novaGround'
    if ($null -eq $pi) {
        $pins[$gp] = [ordered]@{ commit = $current[$gp]; branch = '(unchanged)' }
    } elseif ($pi.Edits.Count -gt 0) {
        $d = $cfg.Pi.ProdDir
        $r = Invoke-PiSsh ("git -C $d switch -q -c $branch && git -C $d add -A && " +
                           "git -C $d -c user.name='NovaOps server' -c user.email=nova@pi commit -q -m '$subject' && git -C $d rev-parse HEAD")
        $sha = @($r.Out | Where-Object { $_ -match '^[0-9a-f]{40}$' } | Select-Object -Last 1)
        if ($r.Code -ne 0 -or $sha.Count -eq 0) {
            throw "Committing on the Pi failed (the PC checkouts are already on $branch). Commit it on the Pi by hand, then re-run pin with -GroundCommit."
        }
        $pins[$gp] = [ordered]@{ commit = $sha[0]; branch = $branch }
    } else {
        $was = [string](Get-Prop (Get-Prop (Get-Prop $base 'pins') $gp) 'branch')
        if (-not $was) { $was = '(unchanged)' }
        $pins[$gp] = [ordered]@{ commit = $pi.Head; branch = $was }
    }
    $pins['firmware'] = [ordered]@{ commit = $current['firmware']; branch = '(unchanged)' }

    $tag = @(New-Release -Pins $pins -EnvName 'prod' -Kind 'hotfix' -Stable)[-1]
    # Prod is already running exactly this.
    Set-EnvState 'prod' @{ release = $tag; deployed = (Get-Date).ToString('o') }
    Update-ReleaseIndex

    Write-Host ""
    Write-Ok "Prod is running hotfix release $tag (stable)."
    Write-Ok "Next: .\ops\Nova.ps1 publish   (when online: pushes $branch and opens its PRs into $($cfg.Branches.Prod), then $($cfg.Branches.Dev))"
    if ($null -ne $pi -and $pi.Edits.Count -gt 0) {
        Write-Warn "The Pi's commit exists only on the Pi. Push it from there when it has internet:"
        Write-Warn "  git -C $($cfg.Pi.ProdDir) push -u origin $branch"
    }
}

function Sync-ReleaseConfig {
    # Compare prod's live config with the config the release was tested with;
    # replace it only with -WithConfig.
    param([string]$Tag, $Manifest)
    $live = Get-EnvConfigDir 'prod'
    $files = @(Get-Prop $Manifest 'config')
    if ($files.Count -eq 0) { Write-Warn "$Tag recorded no config; prod's live config is unchanged."; return }

    Write-Step "Prod live config ($live) vs the config $Tag was tested with"
    $differs = @()
    foreach ($f in $files) {
        $name = Get-Prop $f 'file'
        $livePath = Join-Path $live $name
        if (-not (Test-Path $livePath)) { $state = 'missing in prod' }
        elseif ((Get-ContentHash $livePath) -eq (Get-Prop $f 'hash')) { $state = 'same' }
        else { $state = 'DIFFERENT' }
        Write-Host ("    {0,-24} {1}" -f $name, $state)
        if ($state -ne 'same') { $differs += $f }
    }
    if ($differs.Count -eq 0) { return }

    if (-not $WithConfig) {
        Write-Warn "Prod keeps its live config. To switch to the tested config, re-run with -WithConfig"
        Write-Warn "(the current files are saved to config history first, so nothing is lost)."
        return
    }
    foreach ($f in $differs) {
        $name = Get-Prop $f 'file'
        $livePath = Join-Path $live $name
        if (Test-Path $livePath) { [void](Save-ConfigToHistory $livePath 'prod' "replaced by deploy $Tag") }
        Export-GitBlob $Tag "releases/$Tag/config/$name" $livePath
        Write-Ok "prod $name <- $Tag"
    }
}

function Invoke-PiDeploy {
    param([string]$Tag, $Manifest)
    $sha = Get-PinCommit $Manifest 'pi/novaGround'
    if (-not $sha) { Write-Warn "$Tag pins no novaGround commit."; return }
    Write-Host ""
    Write-Step "Pi: novaGround for $Tag is $sha"
    $manual = @(
        "ssh $($cfg.Pi.User)@$($cfg.Hosts.NovaGround)",
        "cd $($cfg.Pi.ProdDir) && sudo ./nova-pi.sh deploy $Tag      (or: deploy $sha)"
    )
    if ($SkipPi) {
        Write-Warn "Skipped (-SkipPi). To deploy it yourself:"
        $manual | ForEach-Object { Write-Warn "  $_" }
        return
    }
    # Run the Pi's dev copy of nova-pi.sh: that is the tooling that was just
    # tested, so it knows `deploy` even when prod's copy is older.
    $r = Invoke-PiSsh "sudo $($cfg.Pi.DevDir)/nova-pi.sh deploy $sha --release $Tag" -Tty
    if ($r.Code -ne 0) {
        Write-Err "The Pi deploy did not complete (unreachable, or it failed above). To do it yourself:"
        $manual | ForEach-Object { Write-Err "  $_" }
    } else {
        Write-Ok "Pi deployed."
    }
}

function Invoke-Deploy {
    Assert-Admin
    Assert-NovaRepo
    $stable = @(Get-StableTags)
    $tag = $Target
    if (-not $tag) {
        if ($stable.Count -eq 0) {
            throw "No release has been promoted yet. Promote one first (.\ops\Nova.ps1 promote <tag>), or deploy a pre-release on purpose: .\ops\Nova.ps1 deploy <tag> -AllowPrerelease"
        }
        $tag = $stable[0]
    }
    $m = Get-ReleaseManifest $tag
    if ($null -eq $m) { throw "$tag is not a pinned release (no releases/$tag/release.json at that tag)." }
    if ($stable -notcontains $tag -and -not $AllowPrerelease) {
        throw "$tag has not been promoted to stable. Promote it first, or add -AllowPrerelease to deploy it anyway."
    }
    Write-Step "Deploying $tag to prod  ($(Get-Prop $m 'test'), pinned $(Get-Prop $m 'created'))"
    $novaBranch = Get-NovaBranch
    if ($novaBranch -ne $cfg.Branches.Prod) {
        Write-Warn "$RepoRoot is on '$novaBranch', so these scripts come from that branch, not $($cfg.Branches.Prod)."
    }

    # Get every commit and check every checkout BEFORE stopping anything, so a
    # failure here leaves prod running untouched.
    $parts = @(Get-PinParts | Where-Object { $_.Prod })
    foreach ($part in $parts) {
        $sha = Get-PinCommit $m $part.Path
        if (-not $sha) { throw "$tag has no pin for $($part.Path)." }
        if (-not (Test-Path $part.Prod)) { throw "Missing prod checkout $($part.Prod)." }
        $dirty = @((Invoke-Git $part.Prod @('status', '--porcelain', '--untracked-files=no')).Out | Where-Object { $_ })
        if ($dirty.Count -gt 0) {
            $dirty | ForEach-Object { Write-Err "  $_" }
            throw ("$($part.Prod) has local changes to tracked files. If they are a fix tested on prod, capture them first: " +
                   ".\ops\Nova.ps1 hotfix -Name <what> -Test `"...`". Otherwise stash (git -C $($part.Prod) stash) or discard them. " +
                   "Config belongs in $(Get-EnvConfigDir 'prod').")
        }
        Import-Commit $part.Prod $sha $part.Dev
    }

    Write-Step "Stopping dev and prod"
    Set-StackRunning 'dev' $false
    Set-StackRunning 'prod' $false

    foreach ($part in $parts) {
        $sha = Get-PinCommit $m $part.Path
        [void](Invoke-Git $part.Prod @('checkout', '-q', '--detach', $sha))
        Write-Ok "$($part.Label) -> $($sha.Substring(0, 7))"
    }

    Sync-ReleaseConfig $tag $m

    Set-EnvState 'prod' @{ release = $tag; deployed = (Get-Date).ToString('o') }
    Invoke-Install
    Set-StackRunning 'prod' $true
    Update-ReleaseIndex

    Invoke-PiDeploy $tag $m

    Write-Host ""
    Write-Ok "Prod is running $tag."
}

function Invoke-Publish {
    Assert-NovaRepo
    Assert-NovaOnMain 'publish'
    $tags = @(Get-ReleaseTags)
    $stable = @(Get-StableTags)
    if ($tags.Count -eq 0) { Write-Warn "Nothing has been pinned yet."; return }

    $remote = Invoke-Git $RepoRoot @('ls-remote', '--tags', 'origin') -AllowFail
    if ($remote.Code -ne 0) { throw "Cannot reach origin - still offline? Everything stays local until publish succeeds." }
    $remoteTags = @($remote.Out | ForEach-Object { (($_ -split "`t")[1] -replace '^refs/tags/', '') -replace '\^\{\}$', '' } | Select-Object -Unique)
    $newTags = @($tags | Where-Object { $remoteTags -notcontains $_ })
    $newStable = @($stable | Where-Object { $remoteTags -notcontains "stable/$_" })

    $gh = Get-Command gh.exe -ErrorAction SilentlyContinue
    if ($null -eq $gh -and -not $DryRun) {
        throw "The GitHub CLI is not installed. Install it (winget install GitHub.cli), run 'gh auth login', then publish again."
    }
    if ($null -ne $gh -and (Invoke-Gh @('auth', 'status') -AllowFail).Code -ne 0) {
        throw "gh is not logged in. Run 'gh auth login', then publish again."
    }

    # 1. Push the hotfix branches `hotfix` made in the prod checkouts. (The Pi
    #    pushes its own; step 2 says so if it has not.)
    foreach ($tag in $newTags) {
        $pins = Get-Prop (Get-ReleaseManifest $tag) 'pins'
        foreach ($part in @(Get-PinParts | Where-Object { $_.Prod })) {
            $b = [string](Get-Prop (Get-Prop $pins $part.Path) 'branch')
            if (-not $b.StartsWith($cfg.Branches.HotfixPrefix)) { continue }
            if ((Invoke-Git $part.Prod @('rev-parse', '--verify', '--quiet', "refs/heads/$b") -AllowFail).Code -ne 0) { continue }
            Write-Step "Pushing $b from $($part.Prod)"
            if ($DryRun) { Write-Ok "  (dry run) git -C $($part.Prod) push -u origin $b"; continue }
            $r = Invoke-Git $part.Prod @('push', '-u', 'origin', $b) -AllowFail
            if ($r.Code -ne 0) { Write-Warn "  push failed: $(($r.Err + $r.Out) -join ' ')" }
        }
    }

    # 2. Every commit a new release pins must be fetchable by everyone else.
    Write-Step "Checking that pinned commits are on GitHub"
    $missing = @()
    $checked = @{}
    foreach ($tag in $newTags) {
        $pins = Get-Prop (Get-ReleaseManifest $tag) 'pins'
        foreach ($p in @($pins.PSObject.Properties)) {
            $sha = Get-Prop $p.Value 'commit'
            if (-not $sha -or $checked.ContainsKey($sha)) { continue }
            $checked[$sha] = $true
            $base = Get-GitHubBase $p.Name
            if ($null -eq $gh -or -not $base) { Write-Warn "  not checked (no gh / not GitHub): $($p.Name) $($sha.Substring(0, 7))"; continue }
            $slug = $base -replace '^https://github\.com/', ''
            if ((Invoke-Gh @('api', "repos/$slug/commits/$sha", '--silent') -AllowFail).Code -ne 0) {
                $branch = Get-Prop $p.Value 'branch'
                $isHotfix = ([string]$branch).StartsWith($cfg.Branches.HotfixPrefix)
                $hint = switch ($p.Name) {
                    'pi/novaGround' {
                        $dir = if ($isHotfix) { $cfg.Pi.ProdDir } else { $cfg.Pi.DevDir }
                        "on the Pi: git -C $dir push -u origin $branch"
                    }
                    'firmware'      { 'firmware is developed separately - pin a commit that is on GitHub' }
                    default {
                        $part = Get-PinParts | Where-Object { $_.Path -eq $p.Name }
                        $dir = if ($isHotfix) { $part.Prod } else { $part.Dev }
                        "git -C $dir push -u origin $branch"
                    }
                }
                $missing += "$tag  $($p.Name) $($sha.Substring(0, 7)) ($branch)  ->  $hint"
            }
        }
    }
    if ($missing.Count -gt 0) {
        Write-Err "These pinned commits are not on GitHub yet:"
        $missing | ForEach-Object { Write-Err "  $_" }
        throw "Push them, then publish again. Nothing was published."
    }

    # 3. Bring in what was merged on GitHub meanwhile (ops/ and docs PRs).
    #    A merge, never a rebase: rebasing would move the pin commits out from
    #    under their release tags. PRs may not touch prod/, pi/, firmware or
    #    releases/ (CONTRIBUTING.md, enforced by CI), so this cannot conflict
    #    with a pin.
    $branch = (Invoke-Git $RepoRoot @('rev-parse', '--abbrev-ref', 'HEAD')).Text
    [void](Invoke-Git $RepoRoot @('fetch', '-q', 'origin', $branch))
    $behind = [int](Invoke-Git $RepoRoot @('rev-list', '--count', "HEAD..origin/$branch")).Text
    if ($behind -gt 0) {
        Write-Step "origin/$branch has $behind commit(s) this PC does not - merging them in"
        if ($DryRun) {
            Write-Ok "  (dry run) git merge origin/$branch"
        } else {
            $mg = Invoke-Git $RepoRoot @('merge', '--no-edit', "origin/$branch") -AllowFail
            if ($mg.Code -ne 0) {
                [void](Invoke-Git $RepoRoot @('merge', '--abort') -AllowFail)
                throw ("Merging origin/$branch conflicted, so nothing was pushed:`n$(($mg.Out + $mg.Err) -join "`n")`n" +
                       "This means a PR changed prod/, pi/, firmware or releases/, which only pin may do. Ask a lead to resolve it.")
            }
            Write-Ok "  merged"
        }
    }

    # 4. Push the pin commits and tags.
    $refs = @($branch) + @($newTags | ForEach-Object { "refs/tags/$_" }) + @($newStable | ForEach-Object { "refs/tags/stable/$_" })
    Write-Step "Pushing $branch, $($newTags.Count) new release tag(s), $($newStable.Count) new stable tag(s)"
    if ($DryRun) { Write-Ok "  (dry run) git push origin $($refs -join ' ')" }
    else { [void](Invoke-Git $RepoRoot (@('push', 'origin') + $refs)) }

    # 5. Tag every pinned commit in its own repo as nova/<tag>. Feature and
    #    hotfix branches are deleted after merging; without a tag, a squash-
    #    merged or deleted branch's commit could eventually vanish from GitHub,
    #    and that release could never be checked out again. Firmware is developed
    #    separately, so it is not tagged.
    Write-Step "Tagging pinned commits in the code repos (nova/<tag>)"
    foreach ($part in @(Get-PinParts | Where-Object { $_.Path -ne 'firmware' })) {
        $base = Get-GitHubBase $part.Path
        if (-not $base -or $null -eq $gh) { Write-Warn "  $($part.Label): skipped (no gh / not GitHub)"; continue }
        $slug = $base -replace '^https://github\.com/', ''
        $existing = @((Invoke-Gh @('api', "repos/$slug/git/matching-refs/tags/nova/", '--paginate', '--jq', '.[].ref') -AllowFail).Out)
        foreach ($tag in $tags) {
            $sha = Get-PinCommit (Get-ReleaseManifest $tag) $part.Path
            if (-not $sha -or $existing -contains "refs/tags/nova/$tag") { continue }
            if ($DryRun) { Write-Ok "  (dry run) $slug nova/$tag -> $($sha.Substring(0, 7))"; continue }
            $r = Invoke-Gh @('api', "repos/$slug/git/refs", '-f', "ref=refs/tags/nova/$tag", '-f', "sha=$sha", '--silent') -AllowFail
            if ($r.Code -eq 0) { Write-Ok "  $slug nova/$tag -> $($sha.Substring(0, 7))" }
            else { Write-Warn "  $slug nova/$tag not created (no write access?): $(($r.Err + $r.Out) -join ' ')" }
        }
    }

    # 6. GitHub releases: create new ones, fix pre-release flags after promotion.
    Write-Step "GitHub releases"
    $latest = $null
    if ($stable.Count -gt 0) { $latest = $stable[0] }
    foreach ($tag in $tags) {
        $isStable = $stable -contains $tag
        $existing = $null
        if ($null -ne $gh) {
            $view = Invoke-Gh @('release', 'view', $tag, '--json', 'isPrerelease') -AllowFail
            if ($view.Code -eq 0) { $existing = ($view.Text | ConvertFrom-Json) }
        }
        if ($null -ne $existing -and [bool]$existing.isPrerelease -eq (-not $isStable)) { continue }

        $notesFile = [IO.Path]::GetTempFileName()
        try {
            Write-TextFile $notesFile (New-ReleaseNotes $tag $isStable)
            $status = if ($isStable) { 'stable' } else { 'pre-release' }
            if ($null -eq $existing) {
                $title = "$tag - $(Get-Prop (Get-ReleaseManifest $tag) 'test')"
                $ghArgs = @('release', 'create', $tag, '--verify-tag', '--title', $title, '--notes-file', $notesFile, '--latest=false')
                if (-not $isStable) { $ghArgs += '--prerelease' }
                $what = "create $tag ($status)"
            } else {
                $ghArgs = @('release', 'edit', $tag, '--notes-file', $notesFile, "--prerelease=$((-not $isStable).ToString().ToLower())")
                $what = "update $tag -> $status"
            }
            if ($DryRun) { Write-Ok "  (dry run) $what" }
            else { [void](Invoke-Gh $ghArgs); Write-Ok "  $what" }
        } finally { Remove-Item -LiteralPath $notesFile -ErrorAction SilentlyContinue }
    }
    if ($latest) {
        if ($DryRun) { Write-Ok "  (dry run) mark $latest as Latest" }
        else { [void](Invoke-Gh @('release', 'edit', $latest, '--latest')); Write-Ok "  $latest marked Latest" }
    }

    # 7. Get the newest stable release into each code repo's main, then back
    #    into dev. main receives exactly the tested commit: a release/<tag>
    #    branch made at it (a hotfix release uses its hotfix branch instead).
    #    A back-merge PR from main into dev is only needed when main has
    #    content dev lacks, which in practice means a hotfix.
    if ($latest) {
        Write-Step "Pull requests for $latest"
        $m = Get-ReleaseManifest $latest
        $nova = Get-GitHubBase ''
        $prodB = $cfg.Branches.Prod
        $devB = $cfg.Branches.Dev
        foreach ($part in @(Get-PinParts | Where-Object { $_.Path -ne 'firmware' })) {
            $base = Get-GitHubBase $part.Path
            if (-not $base -or $null -eq $gh) { Write-Warn "  $($part.Label): skipped (no gh / not GitHub)"; continue }
            $slug = $base -replace '^https://github\.com/', ''
            $pin = Get-Prop (Get-Prop $m 'pins') $part.Path
            $sha = [string](Get-Prop $pin 'commit')
            $pinBranch = [string](Get-Prop $pin 'branch')
            if (-not $sha) { continue }

            $cmp = Invoke-Gh @('api', "repos/$slug/compare/$prodB...$sha", '--jq', '.status') -AllowFail
            if ($cmp.Code -eq 0 -and @('identical', 'behind') -contains $cmp.Text) {
                Write-Ok "  $slug : $prodB already has $($sha.Substring(0, 7))"
            } else {
                if ($pinBranch.StartsWith($cfg.Branches.HotfixPrefix)) {
                    $head = $pinBranch
                    $title = "fix(hotfix): $($pinBranch.Substring($cfg.Branches.HotfixPrefix.Length)) ($latest)"
                } else {
                    $head = "$($cfg.Branches.ReleasePrefix)$latest"
                    $title = "chore(release): $latest"
                    if (-not $DryRun) {
                        # 422 = the branch already exists, which is fine.
                        [void](Invoke-Gh @('api', "repos/$slug/git/refs", '-f', "ref=refs/heads/$head", '-f', "sha=$sha", '--silent') -AllowFail)
                    }
                }
                $open = Invoke-Gh @('pr', 'list', '-R', $slug, '--head', $head, '--base', $prodB, '--state', 'all', '--json', 'number', '--jq', 'length') -AllowFail
                if ($open.Code -eq 0 -and $open.Text -and [int]$open.Text -gt 0) {
                    Write-Ok "  $slug : PR $head -> $prodB already exists"
                } elseif ($DryRun) {
                    Write-Ok "  (dry run) $slug : open PR $head -> $prodB  '$title'"
                } else {
                    $body = @(
                        "Brings **$latest** into ``$prodB``: exactly the commit that was tested ($(Get-Prop $m 'test')).",
                        '',
                        "Release notes: $nova/releases/tag/$latest",
                        '',
                        '**Merge with "Create a merge commit"**, not squash, so the tested commit is kept (CONTRIBUTING.md section 5).'
                    ) -join "`n"
                    $bodyFile = [IO.Path]::GetTempFileName()
                    try {
                        Write-TextFile $bodyFile $body
                        $r = Invoke-Gh @('pr', 'create', '-R', $slug, '--base', $prodB, '--head', $head, '--title', $title, '--body-file', $bodyFile) -AllowFail
                    } finally { Remove-Item -LiteralPath $bodyFile -ErrorAction SilentlyContinue }
                    if ($r.Code -eq 0) { Write-Ok "  $slug : opened $($r.Text)" }
                    else { Write-Warn "  $slug : could not open PR $head -> $prodB : $(($r.Err + $r.Out) -join ' ')" }
                }
            }

            # Back-merge: does main hold changes dev does not?
            $diff = Invoke-Gh @('api', "repos/$slug/compare/$devB...$prodB", '--jq', '.files | length') -AllowFail
            if ($diff.Code -ne 0) { Write-Warn "  $slug : no '$devB' branch to merge $prodB back into"; continue }
            if (-not $diff.Text -or [int]$diff.Text -eq 0) { continue }
            $open = Invoke-Gh @('pr', 'list', '-R', $slug, '--head', $prodB, '--base', $devB, '--state', 'open', '--json', 'number', '--jq', 'length') -AllowFail
            if ($open.Code -eq 0 -and $open.Text -and [int]$open.Text -gt 0) { Write-Ok "  $slug : back-merge PR $prodB -> $devB already open"; continue }
            if ($DryRun) { Write-Ok "  (dry run) $slug : open back-merge PR $prodB -> $devB"; continue }
            $r = Invoke-Gh @('pr', 'create', '-R', $slug, '--base', $devB, '--head', $prodB, '--title', "chore: merge $prodB back into $devB",
                             '--body', "$prodB has changes $devB does not (usually a hotfix). Merge with **Create a merge commit** so the next release includes them.") -AllowFail
            if ($r.Code -eq 0) { Write-Ok "  $slug : opened back-merge $($r.Text)" }
            else { Write-Warn "  $slug : could not open back-merge PR: $(($r.Err + $r.Out) -join ' ')" }
        }
    }

    Write-Host ""
    Write-Ok "Published."
    Write-Warn "Recording bundles are in $($cfg.ArchiveDir); uploading them to Drive is not set up yet."
}

function Invoke-Archive {
    # One self-contained folder per finished recording:
    #   archive\<env>\<recording>\data\     the raw CSVs from every logger
    #   archive\<env>\<recording>\config\   <hash>_<file> for each config used
    #   archive\<env>\<recording>\meta.json the backend's recording metadata
    #   archive\<env>\<recording>\bundle.json   file list + checksums, written last
    $made = 0
    $waiting = 0
    foreach ($envName in @('prod', 'dev')) {
        $dataDir = Get-EnvDataDir $envName
        if (-not (Test-Path $dataDir)) { continue }
        $all = @(Get-ChildItem -Path $dataDir -File)
        foreach ($mf in @($all | Where-Object { $_.Name -like '*.meta.json' })) {
            try { $meta = Get-Content -Raw -LiteralPath $mf.FullName | ConvertFrom-Json }
            catch { Write-Warn "Unreadable $($mf.FullName)"; continue }
            $name = Get-Prop $meta 'recording'
            $stopped = Get-Prop $meta 'stopped'
            if (-not $name) { continue }
            if (-not $stopped) { $waiting++; continue }
            # novaGround uploads its CSVs just after the stop; give them a minute.
            if (([DateTime]::UtcNow - ([datetime]$stopped).ToUniversalTime()).TotalSeconds -lt 60) { $waiting++; continue }

            $pattern = '^' + [regex]::Escape($name) + '(\.|_[A-Za-z])'
            $files = @($all | Where-Object { $_.Name -match $pattern -and $_.Name -ne $mf.Name })
            $bundle = Join-Path $cfg.ArchiveDir "$envName\$name"
            if (Test-Path (Join-Path $bundle 'bundle.json')) {
                # Already bundled: redo it only if more data arrived since.
                $have = @(Get-ChildItem -Path (Join-Path $bundle 'data') -File -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
                if (@($files | Where-Object { $have -notcontains $_.Name }).Count -eq 0) { continue }
            }

            New-Item -ItemType Directory -Force -Path (Join-Path $bundle 'data'), (Join-Path $bundle 'config') | Out-Null
            $dataList = @()
            foreach ($f in $files) {
                Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $bundle 'data') -Force
                $dataList += [ordered]@{ file = $f.Name; bytes = $f.Length; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $f.FullName).Hash.ToLower() }
            }
            Copy-Item -LiteralPath $mf.FullName -Destination (Join-Path $bundle 'meta.json') -Force

            $configList = @()
            $missingConfig = @()
            foreach ($c in @(Get-Prop $meta 'config')) {
                $hash = Get-Prop $c 'hash'
                $file = Get-Prop $c 'file'
                if (-not $hash) { continue }
                $dest = "config/${hash}_$file"
                if (@($configList | Where-Object { $_.path -eq $dest }).Count -gt 0) { continue }
                $snap = Join-Path (Get-HistoryDir) "snapshots\$hash.yaml"
                if (Test-Path $snap) {
                    Copy-Item -LiteralPath $snap -Destination (Join-Path $bundle $dest) -Force
                    $configList += [ordered]@{ file = $file; hash = $hash; path = $dest }
                } else {
                    $missingConfig += "$file ($hash)"
                }
            }

            $manifest = [ordered]@{
                recording      = $name
                env            = $envName
                bundled        = (Get-Date).ToString('o')
                data           = $dataList
                config         = $configList
                missing_config = $missingConfig
                note           = $(if ($files.Count -eq 0) { 'No data files were found for this recording (was MQTT down, or the loggers not running?).' } else { $null })
            }
            Write-TextFile (Join-Path $bundle 'bundle.json') (ConvertTo-NiceJson $manifest 5)
            if ($missingConfig.Count -gt 0) { Write-Warn "$name : config snapshot(s) missing from history: $($missingConfig -join ', ')" }
            $made++
        }
    }
    Write-Ok "Archive: $made recording(s) bundled into $($cfg.ArchiveDir)$(if ($waiting) { "; $waiting still recording or just stopped" })"
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

switch ($Action) {
    'get-changes' { Invoke-GetChanges }
    'use'         { Invoke-Use }
    'pin'         { Invoke-Pin }
    'promote'     { Invoke-Promote }
    'deploy'      { Invoke-Deploy }
    'publish'     { Invoke-Publish }
    'archive'     { Invoke-Archive }
    'hotfix'      { Invoke-Hotfix }
    'install'   { Invoke-Install }
    'uninstall' { Invoke-Uninstall }
    'start'     { Invoke-StartStop -Mode start }
    'stop'      { Invoke-StartStop -Mode stop }
    'restart'   { Invoke-Restart }
    'status'    { Invoke-Status }
    'update'    { throw "'update' is now two steps: get-changes (new code into dev) and deploy (a pinned release into prod). See ops/README.md." }
    'logs'      { Invoke-Logs }
    'doctor'    { Invoke-Doctor }
}
