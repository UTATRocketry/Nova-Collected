<#
.SYNOPSIS
    Apply the GitHub settings CONTRIBUTING.md relies on to every Nova repo.

.DESCRIPTION
    For the Nova repo and each code repo (not firmware - that is the FAS
    team's):

      - Merge buttons: "Squash and merge" (work into dev; the squash commit
        takes the PR title) and "Create a merge commit" (releases, hotfixes
        and back-merges). Rebase merging off.
      - Branches are deleted after merging; the "Update branch" button is on.
      - Protected branches - changes only through PRs, required CI checks,
        1 approval, code-owner review for CODEOWNERS paths, stale approvals
        dismissed, conversations resolved, no force-pushes or deletion:
          code repos:  dev and main. dev is the default branch, so new PRs
                       target it without anyone having to choose.
          Nova repo:   main (GitHub Flow). Admins are not enforced, so the
                       ground station (signed in as an admin) can still push
                       the release records Nova.ps1 commits to main.
      - The labels the PR template refers to.

    Needs the GitHub CLI signed in as an admin of the repos (gh auth login).
    Safe to re-run: every step sets rather than adds. Creating the dev branch
    in each code repo is left to you (CONTRIBUTING.md, "Setting up").

.PARAMETER DryRun
    Print what would change without changing anything.

.EXAMPLE
    .\ops\github\Set-RepoRules.ps1 -DryRun
.EXAMPLE
    .\ops\github\Set-RepoRules.ps1
#>
[CmdletBinding()]
param([switch]$DryRun)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
$RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path))

function Invoke-Tool {
    param([string]$Exe, [string[]]$ArgList)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $all = & $Exe @ArgList 2>&1; $code = $LASTEXITCODE } finally { $ErrorActionPreference = $prev }
    return [pscustomobject]@{ Code = $code; Text = (($all | ForEach-Object { "$_" }) -join "`n").Trim() }
}

function Get-Slug {
    param([string]$Url)
    if ($Url -match 'github\.com[:/]([^/]+)/([^/]+?)(\.git)?/?$') { return "$($Matches[1])/$($Matches[2])" }
    return $null
}

if ($null -eq (Get-Command gh.exe -ErrorAction SilentlyContinue)) {
    throw "The GitHub CLI is not installed: winget install GitHub.cli, then gh auth login."
}
if ((Invoke-Tool 'gh.exe' @('auth', 'status')).Code -ne 0) { throw "gh is not signed in: gh auth login" }

# Required checks = the job names in each repo's .github/workflows/pr-checks.yml.
$targets = @(
    [pscustomobject]@{
        Slug     = (Get-Slug (Invoke-Tool 'git.exe' @('-C', $RepoRoot, 'remote', 'get-url', 'origin')).Text)
        Checks   = @('rules', 'nova')
        Protect  = @('main')
        Default  = 'main'
    }
)
foreach ($pair in @(@('prod/backend', 'tests'), @('prod/frontend', 'build'), @('pi/novaGround', 'scripts'))) {
    $url = (Invoke-Tool 'git.exe' @('-C', $RepoRoot, 'config', '-f', '.gitmodules', '--get', "submodule.$($pair[0]).url")).Text
    $targets += [pscustomobject]@{ Slug = (Get-Slug $url); Checks = @('rules', $pair[1]); Protect = @('dev', 'main'); Default = 'dev' }
}

$labels = @(
    @{ Name = 'hardware-risk';        Color = 'd73a4a'; Description = 'Can move hardware: actuators, safety rules, interlocks, timeouts, sequencing' }
    @{ Name = 'breaking';             Color = 'b60205'; Description = 'Changes a message format, topic or protocol other repos depend on' }
    @{ Name = 'needs-hardware-test';  Color = 'fbca04'; Description = 'Waiting for a Bench (3) or Integration (4) test' }
    @{ Name = 'hotfix';               Color = 'e99695'; Description = 'Fix to prod - merge with a merge commit, then back into dev' }
    @{ Name = 'release';              Color = '0e8a16'; Description = 'A tested release on its way into main - merge with a merge commit' }
)

$failures = @()
foreach ($t in $targets) {
    if (-not $t.Slug) { Write-Host "Skipping a repo whose remote is not on GitHub." -ForegroundColor Yellow; continue }
    Write-Host ""
    Write-Host "==> $($t.Slug)" -ForegroundColor Cyan

    $branches = Invoke-Tool 'gh.exe' @('api', "repos/$($t.Slug)/branches", '--paginate', '--jq', '.[].name')
    if ($branches.Code -ne 0) { $failures += "$($t.Slug): cannot read the repo ($($branches.Text))"; continue }
    $have = @($branches.Text -split "`n")
    $missing = @($t.Protect | Where-Object { $have -notcontains $_ })
    if ($missing.Count -gt 0) {
        Write-Host "    missing branch(es): $($missing -join ', ') - create them first (CONTRIBUTING.md, 'Setting up'); they will be skipped." -ForegroundColor Yellow
        $failures += "$($t.Slug): missing $($missing -join ', ')"
    }

    # 1. Merge buttons, branch clean-up and the default branch.
    $settings = @('-F', 'allow_squash_merge=true', '-F', 'allow_merge_commit=true', '-F', 'allow_rebase_merge=false',
                  '-F', 'delete_branch_on_merge=true', '-F', 'allow_update_branch=true',
                  '-f', 'squash_merge_commit_title=PR_TITLE', '-f', 'squash_merge_commit_message=PR_BODY',
                  '-f', 'merge_commit_title=PR_TITLE', '-f', 'merge_commit_message=PR_BODY')
    if ($have -contains $t.Default) { $settings += @('-f', "default_branch=$($t.Default)") }
    if ($DryRun) { Write-Host "    (dry run) squash + merge commit, no rebase, delete merged branches, default branch $($t.Default)" }
    else {
        $r = Invoke-Tool 'gh.exe' (@('api', '-X', 'PATCH', "repos/$($t.Slug)", '--silent') + $settings)
        if ($r.Code -eq 0) { Write-Host "    merge settings applied; default branch $($t.Default)" -ForegroundColor Green }
        else { $failures += "$($t.Slug) settings: $($r.Text)" }
    }

    # 2. Labels.
    foreach ($l in $labels) {
        if ($DryRun) { Write-Host "    (dry run) label $($l.Name)"; continue }
        $r = Invoke-Tool 'gh.exe' @('label', 'create', $l.Name, '--color', $l.Color, '--description', $l.Description, '--force', '-R', $t.Slug)
        if ($r.Code -ne 0) { $failures += "$($t.Slug) label $($l.Name): $($r.Text)" }
    }
    if (-not $DryRun) { Write-Host "    labels applied" -ForegroundColor Green }

    # 3. Protect the permanent branches.
    foreach ($b in @($t.Protect | Where-Object { $have -contains $_ })) {
        $protection = @{
            required_status_checks        = @{ strict = $false; contexts = @($t.Checks) }
            enforce_admins                = $false
            required_pull_request_reviews = @{
                required_approving_review_count = 1
                dismiss_stale_reviews           = $true
                require_code_owner_reviews      = $true
            }
            restrictions                     = $null
            required_conversation_resolution = $true
            allow_force_pushes               = $false
            allow_deletions                  = $false
        }
        if ($DryRun) { Write-Host "    (dry run) protect $b; required checks: $($t.Checks -join ', ')"; continue }
        $tmp = [IO.Path]::GetTempFileName()
        try {
            [IO.File]::WriteAllText($tmp, ($protection | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false))
            $r = Invoke-Tool 'gh.exe' @('api', '-X', 'PUT', "repos/$($t.Slug)/branches/$b/protection", '--input', $tmp, '--silent')
        } finally { Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue }
        if ($r.Code -eq 0) { Write-Host "    $b protected; required checks: $($t.Checks -join ', ')" -ForegroundColor Green }
        elseif ($r.Text -match 'Upgrade to GitHub Pro|make this repository public') {
            $failures += "$($t.Slug): branch protection on a private repo needs a paid or GitHub Education plan for the org"
        } else { $failures += "$($t.Slug) protect ${b}: $($r.Text)" }
    }
}

Write-Host ""
if ($failures.Count -gt 0) {
    Write-Host "Not everything was applied:" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    exit 1
}
Write-Host "All repos match CONTRIBUTING.md." -ForegroundColor Green
