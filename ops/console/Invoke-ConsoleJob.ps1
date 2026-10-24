<#
.SYNOPSIS
    Runs the Nova.ps1 actions queued by the Nova Console's buttons.

.DESCRIPTION
    Started by the "\Nova\Console Runner" scheduled task, which
    `Nova.ps1 console-runner` registers to run as the station account,
    elevated. The console itself runs as SYSTEM, which has no SSH keys for the
    Pis or GitHub login, and deploy/install restart the console service, so
    the console only writes job files and starts this task.

    A job is <JobsDir>\<id>.json, written by the console with status "queued".
    For each queued job, oldest first, this script:
      1. marks it running;
      2. runs it in a child powershell.exe (this script with -JobId), whose
         stdout and stderr go to <id>.log and <id>.err.log, so Nova.ps1's
         output, and the git, npm and ssh it starts, stream into the log live;
      3. marks it done or failed with the exit code;
      4. starts the prod console again if the job stopped it.

    Only Nova.ps1 actions and parameters from the lists below can run; the
    console validates every value before it writes a job.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$JobsDir,
    [string]$ConsoleService = 'nova-prod-console',
    # Internal: run this one job in this process (the child of step 2).
    [string]$JobId
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$NovaPs1 = Join-Path (Split-Path -Parent $PSScriptRoot) 'Nova.ps1'
$JobIdPattern = '^[0-9]{8}-[0-9]{6}-[a-z0-9]{4}$'
$AllowedActions = @('status', 'doctor', 'use', 'get-changes', 'pin', 'promote', 'deploy', 'publish',
                    'archive', 'hotfix', 'install')
$AllowedParams = @('Target', 'Env', 'Only', 'Offline', 'Ref', 'PiRef', 'Test', 'Notes', 'Firmware',
                   'SkipPi', 'Name', 'WithConfig', 'AllowPrerelease', 'AlsoDeploy', 'DryRun')

function Read-Job {
    param([string]$Path)
    return (Get-Content -Raw -LiteralPath $Path -Encoding UTF8 | ConvertFrom-Json)
}

function Set-JobField {
    param($Job, [string]$Name, $Value)
    $Job | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
}

function Save-Job {
    # UTF-8 without a BOM, replaced in one move so the console never reads half a file.
    param($Job, [string]$Path)
    $tmp = "$Path.tmp"
    [IO.File]::WriteAllText($tmp, ($Job | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding $false))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

# ---------------------------------------------------------------------------
# Child: run one job's Nova.ps1 action in this process.
# ---------------------------------------------------------------------------
if ($JobId) {
    if ($JobId -notmatch $JobIdPattern) { throw "Not a job id: $JobId" }
    $job = Read-Job (Join-Path $JobsDir "$JobId.json")
    $action = [string]$job.action
    if ($AllowedActions -notcontains $action) { throw "The console may not run '$action'." }

    # Splatting passes every value straight to Nova.ps1's parameters: no
    # command line, so quotes in a test description can't break anything.
    $splat = @{ Action = $action }
    if ($null -ne $job.params) {
        foreach ($p in @($job.params.PSObject.Properties)) {
            if ($AllowedParams -notcontains $p.Name) { throw "The console may not pass -$($p.Name)." }
            $v = $p.Value
            if ($v -is [bool]) { if ($v) { $splat[$p.Name] = $true } }
            elseif ($v -is [array]) { if (@($v).Count -gt 0) { $splat[$p.Name] = [string[]]@($v) } }
            elseif ($null -ne $v -and "$v" -ne '') { $splat[$p.Name] = [string]$v }
        }
    }

    $env:NOVA_NONINTERACTIVE = '1'
    Write-Host "==> $($job.display)"
    Write-Host "    started $((Get-Date).ToString('s')) as $env:USERDOMAIN\$env:USERNAME, from the Nova Console ($($job.from))"
    Write-Host ""
    try {
        & $NovaPs1 @splat
        exit 0
    } catch {
        Write-Host ""
        Write-Host "FAILED: $($_.Exception.Message)"
        exit 1
    }
}

# ---------------------------------------------------------------------------
# Parent: work through the queue.
# ---------------------------------------------------------------------------
New-Item -ItemType Directory -Force -Path $JobsDir | Out-Null

# Task Scheduler runs one instance at a time; this lock also covers a run
# started by hand while the task is busy.
$lockStream = $null
try {
    $lockStream = [IO.File]::Open((Join-Path $JobsDir 'runner.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
} catch {
    Write-Host 'Another runner is working through the queue.'
    exit 0
}

try {
    while ($true) {
        $queued = @(Get-ChildItem -LiteralPath $JobsDir -Filter '*.json' -File |
                    Where-Object { $_.BaseName -match $JobIdPattern } |
                    Sort-Object Name |
                    Where-Object { [string](Read-Job $_.FullName).status -eq 'queued' })
        if ($queued.Count -eq 0) { break }

        $file = $queued[0].FullName
        $job = Read-Job $file
        $id = [string]$job.id
        Set-JobField $job 'status' 'running'
        Set-JobField $job 'started' ((Get-Date).ToString('o'))
        Set-JobField $job 'runAs' "$env:USERDOMAIN\$env:USERNAME"
        Save-Job $job $file

        $out = Join-Path $JobsDir "$id.log"
        $err = Join-Path $JobsDir "$id.err.log"
        $argLine = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -JobsDir `"$JobsDir`" -JobId $id"
        $code = 1
        try {
            $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $argLine -RedirectStandardOutput $out `
                        -RedirectStandardError $err -WindowStyle Hidden -Wait -PassThru
            $code = $proc.ExitCode
        } catch {
            [IO.File]::AppendAllText($err, "The runner could not start this job: $($_.Exception.Message)`n")
        }

        $job = Read-Job $file
        $status = 'failed'
        if ($code -eq 0) { $status = 'done' }
        Set-JobField $job 'status' $status
        Set-JobField $job 'exitCode' $code
        Set-JobField $job 'finished' ((Get-Date).ToString('o'))
        Save-Job $job $file

        # deploy and install stop the console service; install doesn't start it again.
        $svc = Get-Service -Name $ConsoleService -ErrorAction SilentlyContinue
        if ($null -ne $svc -and $svc.Status -ne 'Running') {
            try { Start-Service -Name $ConsoleService } catch { [IO.File]::AppendAllText($err, "Could not restart ${ConsoleService}: $($_.Exception.Message)`n") }
        }
    }
} finally {
    $lockStream.Dispose()
}
