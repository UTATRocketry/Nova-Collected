# Set up a new NovaOps server

Turn a fresh Windows 11 PC into the Nova server ("Nova-Server",
`192.168.137.1`).

> [!IMPORTANT]
> Run every PowerShell step in an **elevated** PowerShell (Run as
> administrator). `Nova.ps1` creates Windows services and refuses without it.

## 1. Install the prerequisites

- **Python 3.11+**: tick "Add python.exe to PATH" in the installer.
- **Node.js 20+**
- **Git**
- **Mosquitto**, installed as a Windows service.
- For `publish` only: the GitHub CLI, then sign in.

  ```powershell
  winget install GitHub.cli
  gh auth login
  ```

## 2. Clone this repo as `C:\Nova`

```powershell
git clone https://github.com/UTATRocketry/Nova-Collected.git C:\Nova
git -C C:\Nova submodule update --init prod/backend prod/frontend firmware
```

> [!NOTE]
> The folder must be `C:\Nova`. `pi/novaGround` stays empty on the PC; the Pi
> has its own clones.

## 3. Clone the dev checkouts

The dev stack runs from these, normally on the `dev` branch:

```powershell
git clone -b dev https://github.com/UTATRocketry/novaOps-back.git C:\Nova\dev\backend
git clone -b dev https://github.com/UTATRocketry/novaOPS-front.git C:\Nova\dev\frontend
```

## 4. Create this PC's settings file

```powershell
Copy-Item C:\Nova\ops\nova.settings.example.ps1 C:\Nova\ops\nova.settings.ps1
notepad C:\Nova\ops\nova.settings.ps1
```

Set at least:

| Setting | Set it to |
|---|---|
| `AdminPassword` (prod and dev) | A real password, not the example's placeholder |
| `FasPort` (prod) | The COM port of the RS-422 adapter, e.g. `COM3`. `Nova.ps1 doctor` lists the ports that exist |

> [!CAUTION]
> `nova.settings.ps1` holds the real admin password and is never committed.
> If you skip this step, the first `Nova.ps1` command copies the example,
> placeholder password included.

## 5. Set up SSH to the Pi

So `pin` and `deploy` don't prompt for a password each time:

```powershell
ssh-keygen -t ed25519
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh admin@192.168.137.10 "cat >> ~/.ssh/authorized_keys"
```

## 6. Install both stacks

```powershell
cd C:\Nova
.\ops\Nova.ps1 install -Env prod
.\ops\Nova.ps1 install -Env dev
```

This creates the services, installs Python and npm dependencies, builds the
frontend and creates the station folders. Add `-Offline` on a machine with no
internet to skip downloads (WinSW must then already be in `C:\Nova\bin`).

## 7. Verify

```powershell
.\ops\Nova.ps1 doctor
```

Every line should be OK. Then open `http://localhost:8080`: every row of the
Nova Console should be green.

## Next

- [Set up the Raspberry Pi](novaground-setup.md)
- [Set up an operator laptop](operator-laptop-setup.md)
- [Deploy a release](../../RELEASING.md#5-deploy-it-to-prod)
