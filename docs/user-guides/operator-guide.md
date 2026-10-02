# Operator guide

For the person running a test from the operator laptop: checking the station,
taking control, and recording. Setting up the laptop is in
[operator-laptop-setup.md](../deployment/operator-laptop-setup.md).

> [!CAUTION]
> The novaOps UI commands valves on a real engine. Follow the test procedure
> and the test lead's calls. If anything that can move hardware behaves
> unexpectedly, stop and tell the test lead.

## 1. Check the station is healthy

**The stack starts by itself.** Once the ops PC and the Pi have been on for
about 40 seconds, nothing needs to be typed.

Open **Nova Console** (desktop shortcut, or `http://192.168.137.1:8080`).
Every row should be green.

| You see | Do this |
|---|---|
| All rows green | Go to step 2 |
| A row is **amber** (running, not answering yet) | Wait 15 s. If it stays amber, press **Restart** on that row |
| A row is **red** (stopped) | Press **Start**. If it goes red again, call the software lead |
| **novaGround** red under Remote hosts | Check the Pi's power and ethernet cable |

More symptoms: [SUPPORT.md](../../SUPPORT.md#the-nova-console). Before a test,
the software lead runs the full
[health check](../maintenance/check-server-health.md).

## 2. Open the UI and take a role

Open **novaOps UI** (`http://192.168.137.1:3000`). Everyone starts as a
**viewer** and can only watch.

| Role | Can do | How many |
|---|---|---|
| viewer | Watch everything | Any |
| pad | Only the safety-critical commands listed in config (for the pad crew) | One |
| operator | Send any command, subject to the novaLock | One |
| admin | Everything, plus assign roles to others; needs the admin password | One |

> [!NOTE]
> Taking an exclusive role (pad, operator, admin) demotes whoever held it. If
> the operator's browser disconnects, the longest-connected viewer becomes
> operator, so close stray browser tabs on other machines.

While the **novaLock** key is locked, hazardous commands (the main valves) and
recovery arming are refused, whatever your role.

## 3. The pages

| Page | Use it for |
|---|---|
| **Engine** | The P&ID with live sensor values and clickable valves, gauges, plots and procedures |
| **Flight** | FMC health, IMU/baro/GPS, SD logger, recovery arming (RAB), camera/aux rails |
| **Devices** | FAS board fleet, EPB and PMB power, charger, diagnostics |
| **Console** | Serial link to the FMC: pick the COM port, see raw frames, send packets, logs |
| **Config** | Sensors, actuators, calibrations, procedures, safety rules. Saved automatically with full history |
| **Tools** | Analysis of recordings, direct relay/servo control, radio config, soundboard |
| **Settings** | Your session and role |

> [!IMPORTANT]
> "—" always means **no data**: nothing fresh has arrived for 10 seconds. The
> UI never shows a made-up `0`.

## 4. Record the test

1. Start **data saving** before the test.
2. Stop it after the test.

The backend names the recording and notes the config in use, and the loggers
write their files next to it. `Nova.ps1 pin` later bundles everything into
`C:\Nova\archive` ([configs.md](../architecture/configs.md#recordings)).

> [!WARNING]
> Nova writes data files only while data saving is on. Check it's on before
> anything you need to keep.

## 5. When something looks wrong

See [SUPPORT.md: In the operator UI](../../SUPPORT.md#in-the-operator-ui) for
stale values, rejected commands and values that flicker between two sources.
