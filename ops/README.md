# Nova ground station - operations

How the Nova ground station starts, stops, is checked and is updated.

## 1. Operator quick start

**The stack starts by itself.** Power on the ops PC and the Pi, wait ~40 s.
Nothing needs to be typed.

To confirm it is healthy, open the **Nova Console** (desktop icon, or it opens
automatically at logon):

> http://localhost:8080 - on the ops PC

> http://192.168.137.1:8080 - from the operator laptop

Every row should be green.

| What you see | What it means | What to do |
|---|---|---|
| All rows green | Everything is up | Open the novaOps UI and start ops |
| A row is **amber** | Process is running but not answering yet | Wait 15 s; if it stays amber, hit **Restart** on that row |
| A row is **red** | Process is stopped or crashed | Hit **Start**. If it goes red again, expand **logs** on that row |
| **novaGround** red under Remote hosts | The Pi is off, unplugged, or still booting | Check power and the ethernet cable |
| Everything red including the broker | The stack never started | See section 5 |

The operator UI itself is at **http://192.168.137.1:3000**.

---

## 2. Build Overview

Each machine supervises its own processes; nothing is launched by hand.

| Component | Machine | Supervised by | Starts on boot |
|---|---|---|---|
| Mosquitto broker | Ops PC | Windows service | yes |
| novaOps backend | Ops PC | WinSW service `nova-prod-backend` | yes (delayed) |
| novaOps frontend | Ops PC | WinSW service `nova-prod-frontend` | yes (delayed) |
| FAS bridge | Ops PC | WinSW service `nova-prod-fas` | yes (delayed) |
| Nova Console | Ops PC | WinSW service `nova-prod-console` | yes (delayed) |
| novaGround | Pi | systemd `novaGround.service` | yes |

**Prod is Automatic, dev is Manual.** 

---

## 3. Command reference

Windows commands run from `C:\Nova` (the Nova repo) in an **elevated**
PowerShell. Pi commands run from the novaGround checkout on the Pi.

### Updating the ground station

Every new version goes through dev, a hardware test and a pin before it can
reach prod. Each step is one command, and only `publish` needs internet.

**1. Get the code you want to test into dev**

```powershell
.\ops\Nova.ps1 get-changes
```

This pulls the branch each dev folder is on, then reinstalls and rebuilds dev.
A normal test day tests the `dev` branch, which holds every merged feature
waiting for hardware:

```powershell
.\ops\Nova.ps1 get-changes -Ref dev
```

To try one open PR's branch on the bench before it's merged, use `-Ref` with
that branch, and `-Only` if only one repo is involved:

```powershell
.\ops\Nova.ps1 get-changes -Ref fix/fas-port-reconnect -Only backend
```

On the Pi, update its dev checkout with git, then `./nova-pi.sh build --env dev`.

**2. Switch to dev and test with hardware**

```powershell
.\ops\Nova.ps1 use dev
```

This stops prod and starts dev (the prod console stays up). The dev operator
UI is on port 3001. Run the Integration Test. On the Pi, stop the prod
service and run `./run.sh` from the dev checkout. Afterwards:

```powershell
.\ops\Nova.ps1 use prod
```

**3. Pin what you tested**

```powershell
.\ops\Nova.ps1 pin -Test "integration test" -Notes "All valves cycled; PGSO drift noted"
```

This records the commits the dev stack and the Pi's dev checkout are running,
plus the dev config, as a new release such as `v2026.10.04`. It also lists the
test's recordings and bundles them into `C:\Nova\archive`.

`pin` refuses if any tested checkout has uncommitted changes, because that code
could never be checked out again. It records which branch each repo was on.
That's normally `dev`, but any branch can be pinned. It warns when the branch
isn't `dev`, `main`, `hotfix/*` or `release/*`, and the release notes show it.

It reads the Pi over SSH. If the Pi is unreachable, pass
`-GroundCommit <full hash> -GroundBranch dev`, or `-SkipPi` to keep the
current novaGround pin. `-Firmware <commit>` updates the firmware reference.

**4. Approve it for prod** (once it has earned it; a pinned release can still
be an intermediate version)

```powershell
.\ops\Nova.ps1 promote v2026.10.04
```

This marks the release stable. The next `publish` creates a
`release/v2026.10.04` branch in each code repo at the tested commit and opens
its PR into `main`. Merge each with **Create a merge commit**
([CONTRIBUTING.md §5](../CONTRIBUTING.md#5-getting-code-to-prod-leads)).

**5. Deploy to prod**

```powershell
.\ops\Nova.ps1 deploy
```

This deploys the newest stable release. It checks out the pinned commits in
`prod\`, reinstalls, restarts and deploys the Pi over SSH. It always prints the
novaGround commit, so you can do the Pi step by hand if needed. It compares
prod's live config with the tested config; add `-WithConfig` to switch prod to
the tested config (the old one is kept in history).

To roll back, or to deploy a pre-release on purpose:

```powershell
.\ops\Nova.ps1 deploy v2026.09.12
```

```powershell
.\ops\Nova.ps1 deploy v2026.10.04 -AllowPrerelease
```

**6. Publish when online**

```powershell
.\ops\Nova.ps1 publish
```

This pushes the pins and tags and creates or updates the GitHub releases:
pinned = pre-release, stable = release, newest stable = **Latest**. It also
pushes the `release/*` branches made by `promote` and opens their PRs into
`main`. It refuses
if a pinned commit is not on GitHub yet, and prints the `git push` that fixes
it. `-DryRun` shows what it would do.

### Every verb

| Verb | Environment | What it does |
|---|---|---|
| `get-changes` | dev only | Fetch, check out (`-Ref`), fast-forward, reinstall and rebuild dev |
| `use dev` / `use prod` | either | Stop one stack, start the other (the prod console always stays up) |
| `pin` | reads dev | Record dev's commits, the Pi's commit and dev config as a release tag |
| `promote <tag>` | - | Mark a pinned release stable and create its `release/<tag>` branches |
| `deploy [<tag>]` | prod only | Put a release into prod and the Pi (default: newest stable) |
| `publish` | - | Push releases and tags; create/update GitHub releases |
| `archive` | - | Bundle finished recordings into `C:\Nova\archive` |
| `hotfix -Name <what> -Test "..."` | prod only | Turn emergency edits in the prod checkouts (PC and Pi), just tested on prod, into `hotfix/<what>` branches, and pin them as a new release. `publish` opens their PRs |
| `install` | `-Env` | Create/refresh services, install deps, build the frontend, set up station folders |
| `uninstall` | `-Env` | Stop and remove services. Leaves code, config, data and logs alone |
| `start` / `stop` / `restart` | `-Env` | Control services (broker started first, stopped last) |
| `status` | both | Services, health, Pi reachability, which stack is live, what each is running |
| `logs` | `-Env` | Tail a service's stdout and stderr |
| `doctor` | both | Check every prerequisite and print what is missing |

The workflow verbs work on one environment each and refuse the other; only
the service verbs take `-Env prod|dev` (default `prod`).

Useful flags:

- `-Only backend,fas` - limit to specific components
- `-Offline` - skip pip/npm/WinSW downloads, for a field machine with no internet
- `-Follow` - with `logs`, tail continuously

```powershell
.\ops\Nova.ps1 restart -Env prod -Only fas
```

```powershell
.\ops\Nova.ps1 logs -Env dev -Only backend -Follow
```

### Raspberry Pi - `./nova-pi.sh`

```bash
sudo ./nova-pi.sh status
```

Same verbs: `install`, `uninstall`, `build`, `start`, `stop`, `restart`,
`status`, `logs`, `update`, `doctor`. Add `--env dev` to act on
`/home/admin/dev/novaGround`.

`deploy` is the Pi half of `Nova.ps1 deploy`. It always targets prod:

```bash
sudo ./nova-pi.sh deploy v2026.10.04
```

With a tag, it asks the Nova Console on the ops PC which novaGround commit that
release pins. With no argument, it uses the newest stable release. If the
console is unreachable, pass the commit that `Nova.ps1 deploy` printed:

```bash
sudo ./nova-pi.sh deploy 9042566e66e4ad78857af3ec144289aaca480842
```

The commit comes from GitHub, or, offline, from the Pi's dev checkout.

### Running in the foreground (debugging)

When a service will not start or stay up, run the same programs in a visible window.
The Windows launchers are in the backend repo (`prod\backend\scripts\`)
```powershell
.\scripts\prod_windows.ps1
```

```powershell
.\scripts\dev_windows.ps1 -WithMock
```

#### For novaGround:

```bash
./run.sh --target novaMock
```

`run.sh` warns if the systemd service is already running - the two cannot share
the serial port or the broker client ID.

---

## 4. First-time setup

### Nova Server (new machine)

1. Install **Python 3.11+** (tick "Add to PATH"), **Node.js 20+**, **Git**, and
   **Mosquitto** (as a Windows service). For `publish`, also install the
   GitHub CLI (`winget install GitHub.cli`) and run `gh auth login`.
2. Clone this repo (Nova-Collected on GitHub) **as** `C:\Nova`, with the
   prod submodules:

   ```powershell
   git clone https://github.com/UTATRocketry/Nova-Collected.git C:\Nova
   ```

   ```powershell
   git -C C:\Nova submodule update --init prod/backend prod/frontend firmware
   ```

3. Clone the dev checkouts. The dev stack runs from these, normally on the
   `dev` branch:

   ```powershell
   git clone -b dev https://github.com/UTATRocketry/novaOps-back.git C:\Nova\dev\backend
   ```

   ```powershell
   git clone -b dev https://github.com/UTATRocketry/novaOPS-front.git C:\Nova\dev\frontend
   ```

4. Create this PC's settings file from the tracked example, and set at least
   the real admin password and `FasPort` in it:

   ```powershell
   Copy-Item C:\Nova\ops\nova.settings.example.ps1 C:\Nova\ops\nova.settings.ps1
   notepad C:\Nova\ops\nova.settings.ps1
   ```

   `nova.settings.ps1` is the only settings file `Nova.ps1` reads, and it's
   never committed, like the frontend's `.env` (made from `.env.example`). If
   you skip this step, the first `Nova.ps1` command copies the example for
   you.
5. Set up key-based SSH to the Pi so `pin` and `deploy` don't prompt for a
   password each time:

   ```powershell
   ssh-keygen -t ed25519
   ```

   ```powershell
   type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh admin@192.168.137.10 "cat >> ~/.ssh/authorized_keys"
   ```

6. From an elevated PowerShell in `C:\Nova`:

   ```powershell
   .\ops\Nova.ps1 install -Env prod
   ```

   ```powershell
   .\ops\Nova.ps1 install -Env dev
   ```

7. Verify:

   ```powershell
   .\ops\Nova.ps1 doctor
   ```

### Raspberry Pi

```bash
cd /home/admin/prod/novaGround && sudo ./install.sh
```

Then confirm with `sudo ./nova-pi.sh doctor`. Keep a second clone at
`/home/admin/dev/novaGround` for testing. `pin` reads it and `deploy` falls back
to it when offline.

### Changing settings later

Never edit a service definition directly. Change the source of truth and
reinstall:

- **Windows:** edit `ops\nova.settings.ps1` (this PC's own, untracked copy),
  then `.\ops\Nova.ps1 install -Env prod`.
- **A new default or a new setting for every station:** change
  `ops/nova.settings.example.ps1` through a PR. Stations whose `nova.settings.ps1`
  lacks a new setting use the example's value, with a warning (and a `doctor`
  line) until it's copied across.
- **Pi:** edit `/etc/nova/novaGround.env`, then `sudo systemctl restart novaGround`
- **Sensor/actuator config:** edit it in the web interface. It is saved to
  `C:\Nova\config\<env>\` and every version is kept in `C:\Nova\config\history\`.

---

## 5. Troubleshooting

**Start here:** `.\ops\Nova.ps1 doctor` on the PC, `sudo ./nova-pi.sh doctor` on
the Pi. Most problems are one FAIL line.

| Symptom | Likely cause |
|---|---|
| Everything red, console reachable | Mosquitto is not running. `Start-Service mosquitto` |
| Console itself unreachable | The console service is stopped. `.\ops\Nova.ps1 start -Only console` |
| Backend amber forever | It is running but `/health` does not answer - check its logs for a config or port error |
| Frontend red right after a deploy | `next build` failed or `.next` is missing. Re-run `install` and read the build output |
| FAS bridge red | The COM port in `ops\nova.settings.ps1` does not exist. `doctor` prints the ports that do |
| novaGround red under Remote hosts | Pi off, cable out, or its IP changed. See section 6 |
| Telemetry flickers between two sources | Two things are publishing - a bench `run.sh` session and the systemd service are both up, or both stacks are running (`use prod`) |
| `get-changes`: "cannot fast-forward" | Someone committed in the dev folder. Push or reset it by hand |
| `pin`: "has uncommitted changes" | Commit (and ideally push) the tested code, then pin again |
| `pin` warns "not on dev, main, hotfix/* or release/*" | Dev was running a feature branch. Fine for a one-off test; say why in `-Notes` |
| `pin`: "local 'dev' has commits that are not on origin/dev" | Someone committed on the ops PC. Move the commit to a branch and PR it |
| `pin`: "Could not read the Pi's dev commit" | SSH to the Pi failed. Fix it, or pass `-GroundCommit` / `-SkipPi` |
| `deploy`: "has local changes to tracked files" | Something was edited inside `prod\`. If it was a tested emergency fix, capture it with `Nova.ps1 hotfix`. Otherwise stash or discard it. Config belongs in `C:\Nova\config\prod` |
| `publish`: "not on GitHub yet" | Push the listed commits (the command to run is printed), then publish again |
| `git status` shows `prod/*` modified | Normal when prod is not on the newest pin. `Nova.ps1 status` says what prod runs |

Logs:

- **Windows:** `C:\Nova\logs\<service>.out.log` and `.err.log`, or the **logs**
  expander on each console row
- **Pi:** `journalctl -u novaGround -f`

---

## 6. IP addresses (Ethernet Only)

| Host | Address |
|---|---|
| Nova-Server (ops PC) | 192.168.137.1 |
| novaGround (Pi) | 192.168.137.10 |
| novaThermo (Pi) | 192.168.137.20 |

---

## 7. Operator laptop setup

The laptop needs **no software and no repos** - it only speaks HTTP to the ops
PC. Two ways to get the shortcut on the desktop.

### Option A: run the setup script (not yet in the repo)

> `Setup-OperatorLaptop.ps1` has not been added to the repo yet. Use Option B
> until it is.

Copy `ops\operator\Setup-OperatorLaptop.ps1` to the laptop and run it. No admin
rights needed for the shortcuts:

```powershell
.\Setup-OperatorLaptop.ps1
```

It creates **Nova Console** and **novaOps UI** desktop shortcuts, then verifies
it can actually reach the ops PC and reports which ports answer.

To also set the laptop's static IP in the same pass (needs an elevated
PowerShell):

```powershell
.\Setup-OperatorLaptop.ps1 -StaticIp 192.168.137.50
```

### Option B: copy the .url files

`ops\operator\Nova Console.url` and `ops\operator\novaOps UI.url` are plain text
files. Copy them to the laptop's
desktop and they work - no scripts, no execution policy, nothing to install. To
point it somewhere else, open it in Notepad and edit the URL line.

A `.url` file is used rather than a `.lnk` precisely because it is copyable
between machines and editable in a text editor.

### If the shortcut opens but the page does not load

Work through it in this order:

1. Can the laptop ping `192.168.137.1`? If not, it is a cable or an IP problem
   on the laptop, not a Nova problem.
2. Is the laptop's own IP on the `192.168.137.x` subnet? Check with `ipconfig`.
   An address starting `169.254.` means it asked for DHCP and nothing answered
3. Is the console service running on the ops PC? `.\ops\Nova.ps1 status`
4. Windows Firewall on the ops PC may be blocking inbound 8080/3000. Allow them from an elevated PowerShell on the ops PC:
   `New-NetFirewallRule -DisplayName "Nova UI" -Direction Inbound -Protocol TCP -LocalPort 3000,8080 -Action Allow`

---

## 8. Files

| Path | What it is |
|---|---|
| `ops\nova.settings.ps1` | **The** settings file: paths, ports, IPs, COM port, admin password. This PC's own copy; never committed |
| `ops/nova.settings.example.ps1` | Tracked reference that `nova.settings.ps1` is created from. New settings and defaults go here, by PR |
| `ops/Nova.ps1` | Every command in section 3 |
| `ops/console/nova_console.py` | The standalone status page (stdlib only), and `/api/releases` for the Pi |
| `releases/<tag>/` | What a release pinned (`release.json`) and the config it was tested with |
| `prod\backend\scripts\prod_windows.ps1` | Foreground prod launcher, for debugging |
| `prod\backend\scripts\dev_windows.ps1` | Foreground dev launcher, hot reload |
| `C:\Nova\config\<env>\` | Live station config, edited from the web interface |
| `C:\Nova\config\history\` | Every config ever used (`snapshots\<hash>.yaml`) and `history.jsonl` |
| `C:\Nova\data\<env>\` | Raw recordings and their `.meta.json` |
| `C:\Nova\archive\<env>\<recording>\` | Self-contained recording bundles (data + config + meta) |
| `C:\Nova\state\prod.json` | Which release prod is running |
| `C:\Nova\releases.json` | Generated release index served by the console - do not hand-edit |
| `C:\Nova\console.json` | Generated console config - do not hand-edit |
| `C:\Nova\logs\` | All Windows service logs |
| `C:\Nova\bin\` | WinSW plus the per-service shims |

On the Pi:

| Path | What it is |
|---|---|
| `/etc/nova/novaGround.env` | **Single source of truth** for the Pi |
| `/etc/nova/deployed` | Which release prod is running, written by `nova-pi.sh deploy` |
| `nova-pi.sh` | Install/build/start/stop/restart/update/deploy/status/logs/doctor |
| `start.sh` | Service entry point (systemd calls this) |
| `run.sh` | Interactive tmux session, for bench work |
| `novaGround.service` | The systemd unit, installed by `nova-pi.sh install` |
