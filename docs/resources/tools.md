# Tools and helpful resources

## Simulators and debug tools (in the repos)

| Tool | Where | What it's for |
|---|---|---|
| `novaSim.py` | novaOps-back `tools/` | **The main simulator.** Stands in for novaGround and the FAS bridge together, following the current MQTT contract. `--ui` adds a control page. Started by `dev_windows.ps1 -WithMock` |
| `nova_dummy.py` | novaOps-back `tools/` | Lighter novaGround simulator: sine-wave DAQ channels, FAS EPB samples, IMC state that follows commands |
| `novaMock` | novaGround build target | The real novaGround code with hardware init disabled |
| `fas_bridge.py` | novaOps-back `tools/` | The production FAS link; also runs on a laptop for bench work |
| `serial_probe.py` | novaOps-back `tools/` | Check what is on a serial port |
| `sim_control.html` | novaOps-back `tools/` | The control panel `novaSim.py --ui` serves |
| `/view-json`, `/view-mqtt` | backend | Raw WebSocket JSON and MQTT traffic in the browser |
| `/docs` | backend | Live Swagger API reference; try requests from the browser |
| Nova Console | ops PC :8080 | Service status, start/stop/restart, logs |
| Bench console | `firmware/bench/` | Build, flash and check FAS boards offline |
| Gigafloss EGSE Controller | `firmware/gs/` | The FAS's own stand-alone ground station, with a `MOCK` port |

## External documentation

| Topic | Link |
|---|---|
| FastAPI | https://fastapi.tiangolo.com |
| Next.js (App Router) | https://nextjs.org/docs |
| Chakra UI v3 | https://www.chakra-ui.com/docs |
| TanStack Query | https://tanstack.com/query/latest |
| Zustand | https://zustand.docs.pmnd.rs |
| JointJS (P&ID canvas) | https://docs.jointjs.com |
| uPlot | https://github.com/leeoniya/uPlot |
| MQTT essentials | https://www.hivemq.com/mqtt/ |
| Mosquitto | https://mosquitto.org/documentation/ |
| Eclipse Paho C++ | https://github.com/eclipse-paho/paho.mqtt.cpp |
| MCC DAQ HATs | https://mccdaq.github.io/daqhats/ |
| meson | https://mesonbuild.com |
| libgpiod | https://libgpiod.readthedocs.io |
| WinSW | https://github.com/winsw/winsw |
| draw.io | https://www.drawio.com/doc/ |

## Recommended dev tools

VS Code with the Remote - SSH extension (for the Pi), Python and ESLint
extensions; MQTT Explorer to watch topics live; a serial monitor; Git and the
GitHub CLI (`gh`).
