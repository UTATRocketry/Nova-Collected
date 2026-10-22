# Set up a Raspberry Pi

Install novaGround on a station Pi so it runs as a service and starts on boot.
There are two: the GSS Pi, **NovaGround** (`192.168.137.10`), and the
thermocouple Pi, **NovaThermo** (`192.168.137.20`). Both run the novaGround
repo; they differ only in which binary they run.

> [!IMPORTANT]
> Use **Raspberry Pi OS (Legacy, 64-bit)**. The MCC daqhats library doesn't
> work on Debian Trixie.

## 1. Clone the prod and dev checkouts

```bash
git clone https://github.com/UTATRocketry/novaGround.git /home/admin/prod/novaGround
git clone -b dev https://github.com/UTATRocketry/novaGround.git /home/admin/dev/novaGround
```

`novaGround@prod` runs the prod checkout and `novaGround@dev` runs the dev one.
`Nova.ps1 pin` reads novaGround's dev commit, and `deploy` fetches from it when
the Pi is offline.

## 2. Let the ops PC in without a password

`Nova.ps1` drives the Pis over SSH. On the ops PC:

```powershell
ssh-keygen -t ed25519
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh admin@192.168.137.10 "cat >> ~/.ssh/authorized_keys"
```

Repeat the second line for `192.168.137.20`.

## 3. Install

```bash
cd /home/admin/prod/novaGround && sudo ./install.sh
```

This installs the toolchain and libraries (including daqhats), asks which Pi
this is, builds novaGround, and sets up `novaGround@prod`, `novaGround@dev` and
the report timer. To set the Pi up again later without the installer:

```bash
sudo ./nova-pi.sh install --name NovaGround --target novaGround   # NovaThermo / novaThermo on the other Pi
```

The name must match the Pi's name under `Pi.Targets` in
`ops/nova.settings.ps1`; the console only accepts reports from those names.

## 4. Write its settings from the ops PC

The broker and backend addresses for each environment come from
`nova.settings.ps1`, never from a file you edit on the Pi. Writing them is part
of switching stacks, so on the ops PC run:

```powershell
.\ops\Nova.ps1 use prod
```

That writes `/etc/nova/novaGround-prod.env` and `-dev.env` on every Pi and starts
`novaGround@prod`. [The design doc](../design/pi-orchestration.md) explains why
the settings are split this way.

## 5. Verify

```bash
./nova-pi.sh doctor
./nova-pi.sh status
```

On the ops PC, `.\ops\Nova.ps1 doctor` checks SSH and each Pi's settings, and
the Nova Console's **Remote hosts** section should show the Pi reporting, with
no red flags.

> [!TIP]
> Stacking more than one DAQ HAT? Set each board's address jumpers so addresses
> count up from 0 (there must always be a board at 0), then run
> `sudo daqhats_read_eeproms`.
