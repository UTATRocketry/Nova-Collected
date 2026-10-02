# AGENTS.md

Nova-Collected (cloned as `C:\Nova` on the ground station PC) holds the Nova
ground station's operations tooling and pins the versions of its code repos:
`prod/backend` (novaOps-back, Python/FastAPI + `tools/fas_bridge.py`),
`prod/frontend` (novaOPS-front, Next.js), `pi/novaGround` (C++ on a Raspberry
Pi) and `firmware` (the FAS's STM32 firmware, reference only). The tooling
is `ops/Nova.ps1` (PowerShell) plus `ops/console/nova_console.py` (Python,
stdlib only). This software commands valves on a real engine.

## Commands

Checks to run after changing this repo (the same as CI):

```powershell
# In Windows PowerShell 5.1 (powershell.exe, the ground station's default), from the repo root.
# Prints nothing when the script parses; repeat for any other ops\*.ps1 you changed.
$e = $null; [void][System.Management.Automation.Language.Parser]::ParseFile("$PWD\ops\Nova.ps1", [ref]$null, [ref]$e); $e
python -m py_compile ops/console/nova_console.py
```

Read-only, safe anywhere: `.\ops\Nova.ps1 status`, `.\ops\Nova.ps1 doctor`,
`.\ops\Nova.ps1 publish -DryRun`, `.\ops\github\Set-RepoRules.ps1 -DryRun`.

Code repos, run inside their `dev/` clones:

| Repo | Check |
|---|---|
| `dev/backend` | `python -m pytest -q` |
| `dev/frontend` | `npm ci`, `npm run typecheck`, `npm run build` |
| `dev/novaGround` | `bash -n *.sh` (a real build needs the Pi's HAT libraries) |

## Mandatory rules

1. **Never run `Nova.ps1` actions that change state unless the user asks:**
   `install`, `uninstall`, `start`, `stop`, `restart`, `use`, `get-changes`,
   `pin`, `promote`, `hotfix`, `deploy`, `publish`. They control Windows
   services, commit and tag release history, or deploy to the Pi.
2. **Never edit or commit inside `prod/`, `pi/` or `firmware/`, and never move
   a submodule pointer or write `releases/` by hand.** Those are the released
   versions; only `Nova.ps1 pin` and `hotfix` change them, and CI rejects PRs
   that do.
3. **Change a code repo in its `dev/` clone** (`dev/backend`, `dev/frontend`,
   `dev/novaGround`), on a branch made from `dev`. `dev/` is gitignored here.
4. **Never commit to `dev` or `main` directly in any repo.** Work goes on a
   supporting branch and through a PR (CONTRIBUTING.md §3-§4).
5. **Branch names follow Conventional Branch** (`feature/`, `bugfix/`,
   `chore/`, `hotfix/`, `release/`; lowercase words joined by single hyphens).
   **PR titles follow Conventional Commits** (`type(scope): description`).
   CI enforces both.
6. **Never commit `ops/nova.settings.ps1`.** It's each machine's own copy and
   holds the real admin password. A new or changed default goes in
   `ops/nova.settings.example.ps1`.
7. **Never make changes in or commit to the firmware repo.** It is for reference only
8. **`publish` must merge `origin/main`, never rebase.** Release tags point at
   pin commits, and a rebase would orphan them.
9. **Keep the config content hash identical in both places:** the first 16
   hex characters of SHA-256, in the backend's
   `app/services/config_history.py` and in `Get-ContentHash` in `Nova.ps1`.
   Release configs under `releases/*/config/` are `-text` in `.gitattributes`
   so git never changes their bytes.
10. **Never change global git config in tests.** For a test-only setting,
    use `GIT_CONFIG_COUNT` / `GIT_CONFIG_KEY_0` / `GIT_CONFIG_VALUE_0` in the
    test process.

## Coding conventions (`ops/*.ps1`)

- **Windows PowerShell 5.1 compatible.** No `??`, ternary `? :`, `&&`/`||`,
  or `ConvertFrom-Json -AsHashtable`.
- **The script runs under `Set-StrictMode -Version 2`.**
  - A function that returns an array returns a bare value for one item and
    `$null` for none. Wrap the call site in `@(...)` before using `.Count`.
  - Read parsed JSON properties with `Get-Prop`. A missing property throws
    under strict mode, and `Get-Prop` returns nothing instead.
- **Run git and other programs through `Invoke-Git` / `Invoke-Native`.** They
  keep stderr out of captured values and only throw without `-AllowFail`.
- **Never pass text containing double quotes as a native argument.** 5.1
  mangles it. Write commit and tag messages to a temp file and use `-F`.
- **Write JSON with `Write-TextFile` (UTF-8, no BOM) and `ConvertTo-NiceJson`.**
  5.1's `-Encoding utf8` adds a BOM, which Python and bash choke on.
- **Copy a file out of git with `Export-GitBlob`.** PowerShell re-encodes
  captured output, which changes the bytes and breaks the config hashes.
- **Read settings only through `$cfg`.** It's `$NovaSettings` from
  `ops/nova.settings.ps1`, with missing keys filled from the example.
  - A new setting goes in `nova.settings.example.ps1`.
  - Never hard-code `C:\Nova` paths; they come from the settings.
- **`nova_console.py` must stay stdlib-only.** It keeps running while
  `install` rebuilds the backend's virtualenv.

## Known pitfalls

- **Submodule names must equal their paths.** `Nova.ps1` and
  `Set-RepoRules.ps1` look up `submodule.<path>.url`. After a `git mv`,
  rename the `.gitmodules` / `.git/config` sections and
  `.git/modules/<name>` to match.
- **`git commit -a` in this repo sweeps in submodule pointer changes**, as
  does GitHub Desktop's "commit all". Stage paths explicitly.
- **`.gitignore` does not allow comments after a pattern.** Put comments on
  their own line.
- **Check the file ends with a newline before appending a line.** The
  backend's `.gitignore` once lacked one, which glued
  `!data/.gitkeep` and `config/history/` into one broken rule.
- **Backslashes in Windows paths break `sed` and non-raw Python strings.** Use
  an editor tool, or Python raw strings (`r'...'`), for edits involving
  `C:\...`.
- **`*.sh` and `*.service` must be LF.** A CRLF shebang fails on the Pi with
  "bad interpreter". `.gitattributes` enforces it and novaGround's CI checks.
- **`fas_bridge.py` re-implements `firmware/gs/protocol.py`** rather than
  importing it. A protocol change needs a matching bridge change, and a `!`
  PR title.
- **The frontend has no ESLint config.** `npm run lint` waits for interactive
  input, so don't run it in CI or non-interactive shells.
- **The backend had 9 failing tests before the config-history work.** Compare
  against a baseline worktree before blaming your change.
- **The ground station can't be used to test `Nova.ps1`.** Test it in a
  scratch sandbox instead:
  - local bare repos stand in for GitHub;
  - load the script's functions via the PowerShell AST;
  - stub `Assert-Admin`, `Invoke-Install`, `Set-StackRunning`,
    `Invoke-PiSsh` and `Invoke-Gh`, so the git operations still run for real.

## Related documentation

- [CONTRIBUTING.md](CONTRIBUTING.md): branches, PR rules, testing levels,
  hotfix and release flow. The source of truth for process.
- [docs/deployment/commands.md](docs/deployment/commands.md): every
  `Nova.ps1` and `nova-pi.sh` verb and flag.
- [RELEASING.md](RELEASING.md): the release model and workflow, and why pins
  work the way they do.
- [docs/architecture/configs.md](docs/architecture/configs.md): the backend
  config schema, its history, and recordings.
- [SUPPORT.md](SUPPORT.md): troubleshooting and known issues.
- [docs/development/organization.md](docs/development/organization.md) and
  [docs/development/style.md](docs/development/style.md): where code goes and
  how it's formatted, in every repo.
- [CHANGELOG.md](CHANGELOG.md): generated by git-cliff (`cliff.toml`) in the
  `changelog` GitHub Actions workflow, here and in each code repo; never edit
  it by hand. Its sections come from Conventional Commit PR titles.
- [docs/development/getting-started.md](docs/development/getting-started.md):
  cloning, the `dev/` clones, and running each part without hardware.
- [firmware/FMC-Interface-Contract.md](firmware/FMC-Interface-Contract.md):
  what the flight computer presents to the ground station.
