# Nova ground station - operations

How the Nova ground station starts, stops, and is checked. 

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

Windows commands run from the root of your **Nova-Collected** clone. Pi commands
run from the novaGround checkout on the Pi. Anything that touches a service needs
an **elevated** PowerShell.

### Windows (Nova Server) - `ops\Nova.ps1`

```powershell
.\ops\Nova.ps1 status
```

```powershell
.\ops\Nova.ps1 doctor
```

```powershell
.\ops\Nova.ps1 restart -Env prod
```

Every verb, all independently runnable:

| Verb | What it does |
|---|---|
| `install` | Create/refresh services, install deps, build the frontend, write the console config, create shortcuts |
| `uninstall` | Stop and remove services. Leaves code and logs alone |
| `start` / `stop` / `restart` | Control services (broker started first, stopped last) |
| `status` | Service table + health probes + Pi reachability |
| `update` | `git pull`, reinstall deps, rebuild frontend, reinstall services, restart |
| `logs` | Tail a service's stdout and stderr |
| `doctor` | Check every prerequisite and print what is missing |

Useful flags:

- `-Env prod|dev` - which stack (default `prod`)
- `-Only backend,fas` - limit to specific components
- `-Offline` - skip pip/npm/WinSW downloads, for a field machine with no internet
- `-Follow` - with `logs`, tail continuously

Examples:

```powershell
.\ops\Nova.ps1 restart -Env prod -Only fas
```

```powershell
.\ops\Nova.ps1 logs -Env prod -Only backend -Follow
```

```powershell
.\ops\Nova.ps1 update -Env prod -Offline
```

### Raspberry Pi - `./nova-pi.sh`

```bash
sudo ./nova-pi.sh status
```

Same verbs: `install`, `uninstall`, `build`, `start`, `stop`, `restart`,
`status`, `logs`, `update`, `doctor`. Add `--env dev` to act on
`/home/admin/dev/novaGround`.

```bash
sudo ./nova-pi.sh update
```

### Running in the foreground (debugging)

When a service will not stay up, run the same programs in a visible window.
The Windows launchers are in the backend repo (`novaOps/backend/scripts/`);
`run.sh` is in novaGround on the Pi:

```powershell
.\scripts\prod_windows.ps1
```

```powershell
.\scripts\dev_windows.ps1 -WithDummy
```

```bash
./run.sh --target novaMock
```

`run.sh` warns if the systemd service is already running - the two cannot share
the serial port or the broker client ID.

---

## 4. First-time setup

### Nova Server

1. Install **Python 3.11+** (tick "Add to PATH"), **Node.js 20+**, **Git**, and
   **Mosquitto** (as a Windows service).
2. Clone Nova-Collected, for example to `C:\Nova\Nova-Collected`. The console
   service runs from this clone, so don't delete or move it afterwards.
3. Clone the backend and frontend to the layout in `ops/nova.config.ps1`:
   - `C:\Nova\prod\novaOps-back`, `C:\Nova\prod\novaOPS-front`
   - `C:\Nova\dev\novaOps-back`, `C:\Nova\dev\novaOPS-front`

   Check out the commits pinned in Nova-Collected (`git submodule status`).
4. Review `ops\nova.config.ps1` - especially `FasPort` and `AdminPassword`.
5. From an elevated PowerShell in `C:\Nova\Nova-Collected`:

```powershell
.\ops\Nova.ps1 install -Env prod
```

6. Verify:

```powershell
.\ops\Nova.ps1 doctor
```

Repeat step 5 with `-Env dev` if you want the dev services registered (they
will not auto-start).

### Raspberry Pi

```bash
cd /home/admin/prod/novaGround && sudo ./install.sh
```

Then confirm with `sudo ./nova-pi.sh doctor`.

### Changing settings later

Never edit a service definition directly. Change the source of truth and
reinstall:

- **Windows:** edit `ops\nova.config.ps1`, then `.\ops\Nova.ps1 install -Env prod`
- **Pi:** edit `/etc/nova/novaGround.env`, then `sudo systemctl restart novaGround`

---

## 5. Troubleshooting

**Start here:** `.\ops\Nova.ps1 doctor` on the PC, `sudo ./nova-pi.sh doctor` on
the Pi. Most problems are one FAIL line.

| Symptom | Likely cause |
|---|---|
| Everything red, console reachable | Mosquitto is not running. `Start-Service mosquitto` |
| Console itself unreachable | The console service is stopped. `.\ops\Nova.ps1 start -Only console` |
| Backend amber forever | It is running but `/health` does not answer - check its logs for a config or port error |
| Frontend red right after an update | `next build` failed or `.next` is missing. Re-run `install` and read the build output |
| FAS bridge red | The COM port in `nova.config.ps1` does not exist. `doctor` prints the ports that do |
| novaGround red under Remote hosts | Pi off, cable out, or its IP changed. See section 6 |
| Telemetry flickers between two sources | Two things are publishing - a bench `run.sh` session and the systemd service are both up |
| Update fails with "not a fast-forward" | Someone committed on the ground-station machine. Resolve by hand |

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
| `ops/nova.config.ps1` | **Single source of truth** for Windows: paths, ports, IPs |
| `ops/Nova.ps1` | Install/start/stop/restart/update/status/logs/doctor |
| `ops/console/nova_console.py` | The standalone status page (stdlib only) |
| `novaOps/backend/scripts/prod_windows.ps1` | Foreground prod launcher, for debugging |
| `novaOps/backend/scripts/dev_windows.ps1` | Foreground dev launcher, hot reload |
| `novaOps/backend/scripts/dev_linux.sh` | Same, for Linux/macOS bench work |
| `C:\Nova\console.json` | Generated console config - do not hand-edit |
| `C:\Nova\logs\` | All Windows service logs |
| `C:\Nova\bin\` | WinSW plus the per-service shims |

On the Pi:

| Path | What it is |
|---|---|
| `/etc/nova/novaGround.env` | **Single source of truth** for the Pi |
| `nova-pi.sh` | Install/build/start/stop/restart/update/status/logs/doctor |
| `start.sh` | Service entry point (systemd calls this) |
| `run.sh` | Interactive tmux session, for bench work |
| `novaGround.service` | The systemd unit, installed by `nova-pi.sh install` |

