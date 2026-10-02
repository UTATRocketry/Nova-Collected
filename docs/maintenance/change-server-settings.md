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
   | Admin password | `Environments.<env>.AdminPassword` |
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

1. Edit the Pi's settings:

   ```bash
   sudo nano /etc/nova/novaGround.env
   ```

2. Restart the service:

   ```bash
   sudo systemctl restart novaGround
   ```

3. Check: `sudo ./nova-pi.sh doctor`.

> [!CAUTION]
> Leave `NOVA_FAS_PORT` empty on the Pi. See
> [SUPPORT.md: Known issues](../../SUPPORT.md#known-issues).

## Sensor and actuator config

Not a setting: edit it on the **Config** page of the web interface. See
[configs.md](../architecture/configs.md).
