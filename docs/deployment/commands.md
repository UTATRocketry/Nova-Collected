# Command reference

Every `Nova.ps1` verb (ops PC) and `nova-pi.sh` verb (Raspberry Pi). For the
release workflow in order, see [RELEASING.md](../../RELEASING.md).

> [!IMPORTANT]
> Run `Nova.ps1` from `C:\Nova` in an **elevated** PowerShell. Run
> `nova-pi.sh` from a novaGround checkout on the Pi.

## Nova.ps1

| Verb | Environment | What it does | Changes the station? |
|---|---|---|---|
| `status` | both | Services, health, Pi reachability, which stack is live, what each runs | no |
| `doctor` | both | Checks every prerequisite and prints what's missing | no |
| `logs` | `-Env` | Tails a service's stdout and stderr | no |
| `start` / `stop` / `restart` | `-Env` | Controls services (broker started first, stopped last) | yes |
| `install` | `-Env` | Creates or refreshes services, installs dependencies, builds the frontend, sets up station folders | yes |
| `uninstall` | `-Env` | Stops and removes services; leaves code, config, data and logs | yes |
| `use dev` / `use prod` | either | Stops one stack and starts the other (the prod console stays up) | yes |
| `get-changes` | dev only | Fetches, checks out `-Ref`, fast-forwards, reinstalls and rebuilds dev | yes |
| `pin` | reads dev | Records dev's commits, the Pi's commit and dev config as a release | yes |
| `promote <tag>` | - | Marks a pinned release stable | yes |
| `deploy [<tag>]` | prod only | Puts a release into prod and onto the Pi (default: newest stable) | yes |
| `hotfix -Name <what> -Test "..."` | prod only | Turns tested emergency edits in prod into `hotfix/<what>` branches and a stable release | yes |
| `publish` | - | Pushes releases and tags; creates or updates GitHub releases and PRs | yes (GitHub) |
| `archive` | - | Bundles finished recordings into `C:\Nova\archive` | yes (files only) |

The workflow verbs act on one environment and refuse the other. Only the
service verbs take `-Env prod|dev` (default `prod`).

### Flags

| Flag | Used with | Effect |
|---|---|---|
| `-Env prod\|dev` | service verbs | Which stack (default `prod`) |
| `-Only backend,frontend,fas,console` | service verbs, `get-changes` | Limit to these components |
| `-Ref <branch\|tag\|commit>` | `get-changes` | What to check out in dev |
| `-Follow` | `logs` | Keep tailing |
| `-Lines <n>` | `logs` | How many trailing lines to show (default 60) |
| `-Force` | `install` | Kill stray node/npm processes holding files in the frontend folder, instead of stopping to explain |
| `-Offline` | `install`, `get-changes` | Skip pip/npm/WinSW downloads |
| `-Test "..."`, `-Notes "..."` | `pin`, `hotfix` | Recorded in the release |
| `-GroundCommit <hash> -GroundBranch <b>` | `pin` | The Pi's commit, when the Pi is unreachable |
| `-SkipPi` | `pin` | Keep the current novaGround pin |
| `-Firmware <commit\|tag>` | `pin` | Update the firmware reference |
| `-WithConfig` | `deploy` | Switch prod to the release's tested config |
| `-AllowPrerelease` | `deploy` | Allow deploying a release that isn't stable |
| `-DryRun` | `publish` | Show what would happen, change nothing |

```powershell
.\ops\Nova.ps1 restart -Env prod -Only fas
.\ops\Nova.ps1 logs -Env dev -Only backend -Follow
```

## nova-pi.sh

```bash
sudo ./nova-pi.sh status
```

Verbs: `install`, `uninstall`, `build`, `start`, `stop`, `restart`, `status`,
`logs`, `update`, `doctor`, `deploy`. Add `--env dev` to act on
`/home/admin/dev/novaGround`.

`deploy` is the Pi half of `Nova.ps1 deploy` and always targets prod:

```bash
sudo ./nova-pi.sh deploy v2026.10.04
```

With a tag, it asks the Nova Console which novaGround commit that release pins;
with no argument, it uses the newest stable release. If the console is
unreachable, pass the commit `Nova.ps1 deploy` printed:

```bash
sudo ./nova-pi.sh deploy 9042566e66e4ad78857af3ec144289aaca480842
```
