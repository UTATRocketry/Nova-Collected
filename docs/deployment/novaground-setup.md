# Set up the Raspberry Pi

Install novaGround on the GSS Raspberry Pi (`192.168.137.10`) so it runs as a
service and starts on boot.

> [!IMPORTANT]
> Use **Raspberry Pi OS (Legacy, 64-bit)**. The MCC daqhats library doesn't
> work on Debian Trixie.

## 1. Clone the prod and dev checkouts

```bash
git clone https://github.com/UTATRocketry/novaGround.git /home/admin/prod/novaGround
git clone -b dev https://github.com/UTATRocketry/novaGround.git /home/admin/dev/novaGround
```

The service runs `prod`. `dev` is for tests: `Nova.ps1 pin` reads its commit,
and `deploy` fetches from it when the Pi is offline.

## 2. Install

```bash
cd /home/admin/prod/novaGround && sudo ./install.sh
```

This installs the toolchain and libraries (including daqhats), then has
`nova-pi.sh` build novaGround and register the `novaGround` systemd service. Its
settings are written to `/etc/nova/novaGround.env`.

## 3. Check its settings

The service reads `/etc/nova/novaGround.env`. The defaults point at the ops PC:

| Variable | Default |
|---|---|
| `NOVA_TARGET` | `novaGround` (use `novaThermo` on the thermocouple Pi) |
| `NOVA_BROKER` | `192.168.137.1` |
| `NOVA_BACKEND` | `192.168.137.1:8000` |

After editing it:

```bash
sudo systemctl restart novaGround
```

## 4. Verify

```bash
sudo ./nova-pi.sh doctor
sudo ./nova-pi.sh status
```

On the ops PC, novaGround should be green under **Remote hosts** in the Nova
Console.

> [!TIP]
> Stacking more than one DAQ HAT? Set each board's address jumpers so addresses
> count up from 0 (there must always be a board at 0), then run
> `sudo daqhats_read_eeproms`.
