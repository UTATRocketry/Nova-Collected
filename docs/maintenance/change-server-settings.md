# Change server settings

Change a port, an IP address, the FAS COM port or the admin password.

> [!WARNING]
> Never edit a service definition directly. Change the settings file and
> reinstall, so the services are regenerated from it.

## Ops PC

1. Open this PC's settings:

   ```powershell
   notepad C:\Nova\ops\nova.settings.ps1
   ```

2. Change the value. Common ones:

   | Setting | Where in the file |
   |---|---|
   | FAS COM port | `Environments.prod.FasPort` |
   | Admin password | `Environments.<env>.AdminPassword`. Prod's is also the Nova Console's password for actions; reinstalling prod updates both |
   | Ports | `Environments.<env>.BackendPort`, `FrontendPort`, `ConsolePort` |
   | Pi addresses | `Hosts` |

3. Reinstall the stack you changed (elevated PowerShell):

   ```powershell
   .\ops\Nova.ps1 install -Env prod
   ```

4. Check:

   ```powershell
   .\ops\Nova.ps1 doctor
   ```

> [!NOTE]
> `nova.settings.ps1` is this PC's own copy and is never committed. To change a
> **default** or add a **new setting** for every station, edit
> `ops/nova.settings.example.ps1` through a PR. Stations missing a new setting
> use the example's value and `doctor` warns until it's copied across.

## Raspberry Pi

The Pis get the server's address, the broker port and each environment's
backend port from `nova.settings.ps1`. After changing those, push them to every
Pi by switching to the live stack again:

```powershell
.\ops\Nova.ps1 use prod
```

That rewrites each Pi's `/etc/nova/novaGround-prod.env` and `-dev.env`, and
restarts novaGround if its settings changed. Don't edit those files on the Pi:
the next `use`, `deploy` or `get-changes` overwrites them.

What's set on the Pi itself is which Pi it is and which binary it runs:

```bash
sudo ./nova-pi.sh install --name NovaThermo --target novaThermo
```

Everything else a Pi's environment file holds is set in `ops/nova.settings.ps1`
under `Pi.Env.prod` and `Pi.Env.dev`, for every Pi, with `Pi.Overrides.<Pi>.<env>`
for one Pi: `Verbosity`, `SampleMs`, `PublishMs`, `Stats`, `StatsMs`,
`BenchFlags`, `SimScenario`, `StateDir` and `ExtraArgs`. `Nova.ps1 use`, `deploy`
and `get-changes` write them, and novaGround restarts if they changed.
`BenchFlags` is `off` in prod: with it off, `--stop-actuate` (which stops the Pi
driving any output) is refused and the instance does not start.
Flags for both environments on one Pi (`NOVA_GLOBAL_ARGS`) stay in
`/etc/nova/pi.env`: `sudo ./nova-pi.sh configure --env dev --global-args "--verbosity 2"`.

## Sensor and actuator config

Not a setting: edit it on the **Config** page of the web interface. See
[configs.md](../architecture/configs.md).
