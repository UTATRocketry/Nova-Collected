# Command reference

Every `Nova.ps1` verb (ops PC) and `nova-pi.sh` verb (Raspberry Pi). For the
release workflow in order, see [RELEASING.md](../../RELEASING.md).

> [!IMPORTANT]
> Run `Nova.ps1` from `C:\Nova` in an **elevated** PowerShell. Run
> `nova-pi.sh` from a novaGround checkout on the Pi.

> [!TIP]
> The everyday verbs (status, doctor, use, get-changes, pin, promote, deploy,
> publish, archive, hotfix, install) are also buttons under **Quick actions** and **Actions** in the
> Nova Console, once `console-runner` has been run. The buttons show the same
> command before they run it.

## Nova.ps1

| Verb | Environment | What it does | Changes the station? |
|---|---|---|---|
| `status` | both | Services, health, which stack is live, what each runs, and each Pi's instance, commits and backend, with anything that disagrees | no |
| `doctor` | both | Checks every prerequisite, including SSH to each Pi and its settings, and prints what's missing | no |
| `logs` | `-Env` | Tails a service's stdout and stderr | no |
| `start` / `stop` / `restart` | `-Env` | Controls services (broker started first, stopped last) | yes |
| `install` | `-Env` | Creates or refreshes services, installs dependencies, builds the frontend, sets up station folders | yes |
| `uninstall` | `-Env` | Stops and removes services; leaves code, config, data and logs | yes |
| `use dev` / `use prod` | either | Stops one stack and starts the other, on the PC and every Pi, rewriting each Pi's settings (the prod console stays up) | yes |
| `get-changes` | dev only | Fetches, checks out `-Ref` (`-PiRef` on the Pis), fast-forwards, reinstalls and rebuilds dev, on the PC and every Pi | yes |
| `pin` | reads dev | Records dev's commits, novaGround's commit and dev config as a release; other Pis are recorded as "ran with", not pinned | yes |
| `promote <tag>` | - | Marks a pinned release stable | yes |
| `deploy [<tag>]` | prod only | Puts a release into prod and onto novaGround, then every Pi on prod (default: newest stable) | yes |
| `hotfix -Name <what> -Test "..."` | prod only | Turns tested emergency edits in prod into `hotfix/<what>` branches and a stable release | yes |
| `publish` | - | Pushes releases and tags; creates or updates GitHub releases and PRs | yes (GitHub) |
| `archive` | - | Bundles finished recordings into `C:\Nova\archive` | yes (files only) |
| `console-runner` | - | Registers the scheduled task that runs the console's buttons as this account; asks for its password | yes (a scheduled task) |

The workflow verbs act on one environment and refuse the other. Only the
service verbs take `-Env prod|dev` (default `prod`).

### Flags

| Flag | Used with | Effect |
|---|---|---|
| `-Env prod\|dev` | service verbs | Which stack (default `prod`) |
| `-Only backend,frontend,fas,console` | service verbs, `get-changes` | Limit to these components |
| `-Ref <branch\|tag\|commit>` | `get-changes` | What to check out in the PC's dev folders |
| `-PiRef <branch\|tag\|commit>` | `get-changes` | What to check out in each Pi's dev checkout (default: pull its branch) |
| `-Follow` | `logs` | Keep tailing |
| `-Lines <n>` | `logs` | How many trailing lines to show (default 60) |
| `-Force` | `install` | Kill stray node/npm processes holding files in the frontend folder, instead of stopping to explain |
| `-Offline` | `install`, `get-changes` | Skip pip/npm/WinSW downloads |
| `-Test "..."`, `-Notes "..."` | `pin`, `hotfix` | Recorded in the release |
| `-GroundCommit <hash> -GroundBranch <b>` | `pin` | novaGround's commit, when its Pi is unreachable |
| `-SkipPi` | `get-changes`, `use`, `pin`, `deploy`, `hotfix` | Leave every Pi alone (`pin` keeps the current novaGround pin) |
| `-AlsoDeploy <Pi>` | `deploy` | Also put this Pi (e.g. `NovaThermo`) on the commit the release recorded it running with |
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
./nova-pi.sh status
```

Verbs: `install`, `uninstall`, `use`, `configure`, `build`, `start`, `stop`,
`restart`, `status`, `logs`, `update`, `doctor`, `deploy`, `report`. Add
`--env dev` to act on the dev instance (`novaGround@dev`) and
`/home/admin/dev/novaGround`.

Each Pi runs `novaGround@prod` (starts on boot) or `novaGround@dev`, never both.
`Nova.ps1` switches them and writes their settings, so on the Pi you mostly
need these:

| Command | What it does |
|---|---|
| `sudo ./nova-pi.sh install --name <Pi> --target <binary>` | Sets up the units and the report timer; moves a Pi off the old single `novaGround.service` |
| `sudo ./nova-pi.sh use prod\|dev` | Switches this Pi only |
| `sudo ./nova-pi.sh configure --env <env> --broker <host:port> --backend <host:port>` | Writes one environment's settings by hand, when the ops PC can't reach the Pi |
| `./nova-pi.sh status [--json]` | What runs, both checkouts, each backend and whether it answers, the last upload |

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

Why it works this way: [design/pi-orchestration.md](../design/pi-orchestration.md).
