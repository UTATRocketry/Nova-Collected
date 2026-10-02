# ops

The ground station's operations tooling. `Nova.ps1` installs, starts, checks,
updates and releases the Nova stack on the ops PC. The Nova Console is the
status page operators use to see that everything is up.

## Structure

```
ops\
├── Nova.ps1                    every command: install, status, doctor, deploy, pin, ...
├── nova.settings.example.ps1   tracked default settings (paths, ports, IPs, COM port)
├── nova.settings.ps1           this machine's settings: never committed
├── console\nova_console.py     Nova Console status page (Python, stdlib only)
├── github\Set-RepoRules.ps1    sets branch protection on the GitHub repos
└── operator\*.url              desktop shortcuts for the operator laptop
```

> [!IMPORTANT]
> `nova.settings.ps1` is the only settings file `Nova.ps1` reads, and it holds
> the real admin password. Never commit it. New settings and defaults go in
> `nova.settings.example.ps1`, through a PR.

## Getting started

### Set up

Follow [docs/deployment/server-setup.md](../docs/deployment/server-setup.md).
In short, from an **elevated** PowerShell in `C:\Nova`:

```powershell
.\ops\Nova.ps1 install -Env prod
.\ops\Nova.ps1 install -Env dev
.\ops\Nova.ps1 doctor
```

### Run

The prod stack starts on boot. Open the Nova Console at
`http://localhost:8080`; every row should be green.

```powershell
.\ops\Nova.ps1 status                          # what's running, and which release
.\ops\Nova.ps1 restart -Env prod -Only fas     # restart one component
.\ops\Nova.ps1 logs -Env prod -Only backend -Follow
```

> [!WARNING]
> `install`, `start`, `stop`, `restart`, `use`, `get-changes`, `pin`,
> `promote`, `hotfix`, `deploy` and `publish` change the running station.
> `status`, `doctor` and `publish -DryRun` are read-only.

### Troubleshoot

```powershell
.\ops\Nova.ps1 doctor
```

Most problems show up as one FAIL line. Symptoms and fixes are in
[SUPPORT.md](../SUPPORT.md#troubleshooting).

## More information

| To...                                              | Read                                                                                                                     |
| -------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| Look up any command or flag                        | [docs/deployment/commands.md](../docs/deployment/commands.md)                                                            |
| Release, deploy or roll back                       | [RELEASING.md](../RELEASING.md)                                                                                          |
| Follow a maintenance procedure                     | [docs/maintenance/](../docs/maintenance/README.md)                                                                       |
| Find where the station keeps config, data and logs | [docs/deployment/server-layout.md](../docs/deployment/server-layout.md)                                                                     |
| Change `Nova.ps1` itself                           | [AGENTS.md](../AGENTS.md) (coding conventions) and [CONTRIBUTING.md §10](../CONTRIBUTING.md#10-this-repo-nova-collected) |
