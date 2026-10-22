# Support

Where to get help with Nova, and how to fix the problems people hit most.

## Getting help

1. **Search this page** for your symptom.
2. **Ask in the software channel.** Say what you were doing, what you expected,
   what happened, and paste the error or the `doctor` output.
3. **Open an issue** in the repo the problem is in, if it's a bug.

> [!CAUTION]
> During a test, if anything that can move hardware behaves unexpectedly, stop
> and tell the test lead before troubleshooting. Don't retry commands to see
> what happens.

## Resources

| For | Read |
|---|---|
| Operators running a test | [Operator guide](docs/user-guides/operator-guide.md) |
| New members | [Getting started](docs/development/getting-started.md), [training workshops](docs/resources/training-workshops.md) |
| How the system works | [System overview](docs/architecture/system-overview.md) |
| Station commands | [Command reference](docs/deployment/commands.md) |
| Step-by-step fixes and routine tasks | [Maintenance procedures](docs/maintenance/README.md) |
| Words and acronyms | [Glossary](docs/misc/glossary.md) |
| Everything else | [docs/README.md](docs/README.md) |

## Troubleshooting

> [!TIP]
> **Start with `doctor`.** Run `.\ops\Nova.ps1 doctor` on the ops PC and
> `sudo ./nova-pi.sh doctor` on the Pi. Most problems are one FAIL line.

### The Nova Console

| You see | It means | Do this |
|---|---|---|
| All rows green | Everything is up | Open the novaOps UI |
| A row is **amber** | Running but not answering yet | Wait 15 s. If it stays amber, press **Restart** on that row |
| A row is **red** | Stopped or crashed | Press **Start**. If it goes red again, expand **logs** on that row |
| **novaGround** red under Remote hosts | The Pi is off, unplugged or still booting | Check its power and ethernet cable |
| Everything red, including the broker | Mosquitto isn't running, so the stack never started | `Start-Service mosquitto` |
| The console page itself doesn't load | The console service is stopped | `.\ops\Nova.ps1 start -Only console` |

### Services

| Symptom | Likely cause and fix |
|---|---|
| Backend amber forever | It runs but `/health` doesn't answer. Check its log for a config or port error |
| Frontend red right after a deploy | `next build` failed or `.next` is missing. Re-run `install` and read the build output |
| FAS bridge red | The COM port in `ops\nova.settings.ps1` doesn't exist. `doctor` prints the ports that do |
| novaGround red, Pi powered | Its IP changed or SSH/ethernet is down. See [network.md](docs/deployment/network.md) |
| A service won't stay up | Run it in the foreground to see the error: [procedure](docs/maintenance/run-a-service-in-the-foreground.md) |

Logs are in `C:\Nova\logs\<service>.out.log` and `.err.log` (or the **logs**
expander in the console). On the Pi: `journalctl -u novaGround -f`.

### In the operator UI

| Symptom | Likely cause and fix |
|---|---|
| A value shows "—" | No fresh data for 10 s. Check that source's row in the Nova Console |
| Values flicker between two sources | Two things are publishing: a bench `run.sh` and the service, or both stacks. Stop one (`use prod`) |
| A command is rejected | Read the error. Usually your role (viewers can't command) or the novaLock is engaged |
| Calibrated values look wrong | Check the sensor's `calibration` points on the Config page, and whether calibration is switched on |

### Releases and updates

| Message | Fix |
|---|---|
| `get-changes`: "cannot fast-forward" | Someone committed in the dev folder. Push or reset it by hand |
| `pin`: "has uncommitted changes" | Commit (and push) the tested code, then pin again |
| `pin`: "not on dev, main, hotfix/* or release/*" | A feature branch was tested. Fine for a one-off; say why in `-Notes` |
| `pin`: "local 'dev' has commits that are not on origin/dev" | Someone committed on the ops PC. Move the commit to a branch and PR it |
| `pin`: "Could not read the Pi's dev commit" | SSH to the Pi failed. Fix it, or pass `-GroundCommit` / `-SkipPi` |
| `deploy`: "has local changes to tracked files" | Something was edited in `prod\`. A tested emergency fix: capture it with `hotfix` ([RELEASING.md](RELEASING.md#on-site-hotfix)). Otherwise stash or discard it |
| `publish`: "not on GitHub yet" | Run the printed `git push`, then publish again |
| `git status` shows `prod/*` modified | Normal when prod isn't on the newest pin. `Nova.ps1 status` shows what prod runs |

### The operator laptop can't reach the station

Work through these in order:

1. Can the laptop ping `192.168.137.1`? If not, it's a cable or address
   problem on the laptop.
2. Is the laptop's own address on `192.168.137.x`? Check with `ipconfig`. An
   address starting `169.254.` means it asked for DHCP and nothing answered:
   set a static address ([operator-laptop-setup.md](docs/deployment/operator-laptop-setup.md)).
3. Is the console service running on the ops PC? `.\ops\Nova.ps1 status`
4. Windows Firewall on the ops PC may be blocking 3000 and 8080. Allow them
   from an elevated PowerShell on the ops PC:

   ```powershell
   New-NetFirewallRule -DisplayName "Nova UI" -Direction Inbound -Protocol TCP -LocalPort 3000,8080 -Action Allow
   ```

## Known issues

Found by checking the docs against the code. Each one should have an issue in
the repo it belongs to; link the issue here when you open it.

| Where | Issue |
|---|---|
| Backend `convert.method` | `zero_offset` and `polynomial` are accepted but behave as `linear` ([configs.md](docs/architecture/configs.md#sensors)) |
| Backend `app/routers/lock.py` | Defines `/api/lock/lock` but isn't registered in `main.py`. Use `/api/flags/lockout` |
| novaGround `start.sh` | If `NOVA_FAS_PORT` is set in `/etc/nova/novaGround.env` and that device exists, `start.sh` passes `--fas-port`, which `main.cpp` rejects ("Unknown option"), so the service exits and systemd restarts it in a loop. **Leave `NOVA_FAS_PORT` empty.** The FAS link runs in the backend's FAS bridge, not novaGround |
| Backend `Dockerfile`, `docker-compose.yml`, `initial_config.sh` | Left from the old Docker/Pi setup; prod runs as Windows services |
| `ops/operator/Setup-OperatorLaptop.ps1` | Referenced by earlier docs, not in the repo yet |
| [testing-procedure.md](docs/development/testing-procedure.md) | Not written yet |
| Frontend | No ESLint config; `npm run lint` waits for interactive input |
