# Glossary

| Term | Meaning |
|---|---|
| COTS | Commercial off the shelf |
| DAQ | Data acquisition |
| EGSE | Electrical ground support equipment |
| EPB | Electro-Pneumatic Board: FAS actuator and sensor board |
| FAS | Flight Avionics System |
| FMC | Flight Main Computer (STM32H742); the only board the ground talks to |
| GCS | Ground Control System (Nova as a whole) |
| GPIO | General-purpose input/output |
| GSE | Ground support equipment |
| GSS | Ground Station Suitcase |
| IMC | Ignition management controller |
| LC / PT / TC | Load cell / pressure transducer / thermocouple |
| MFV / MOV | Main fuel valve / main oxidizer valve |
| MQTT | Publish/subscribe messaging protocol; Nova's backbone |
| P&ID | Piping and instrumentation diagram |
| PMB | Power Management Board |
| RAB | Recovery Arming Board |
| SRAD | Student researched and designed |
| WinSW | Windows Service Wrapper; runs Nova's processes as services |

## Names

- **Nova**: the ground software suite. It replaced the older **Carina** software.
- **Nebula**: the current Ground Station Suitcase (part of the EGSE). Nebula
  and Nova were built together for the Discovery rocket.
- **novaGround**: the Pi software. **novaThermo**: the same code built for the
  thermocouple Pi. **novaMock**: the same code with no hardware.
- **novaSim**: the backend's Python simulator (`tools/novaSim.py`), which
  stands in for novaGround and the FAS bridge over MQTT. Not to be confused
  with novaGround's **novaMock** build target above; novaSim needs no Pi.
- **novaOps**: the backend and frontend together.
- **novaLock**: the physical lockout key that gates hazardous commands.
- **Gigafloss**: the FAS avionics stack and its firmware repo.
- **prod / dev**: the two stacks on the ops PC. Also the `main` / `dev` branches.

## Contributing terms

| Word | Meaning |
|---|---|
| **branch** | a separate line of work in a repo |
| **PR** (pull request) | a request to merge your branch, where others review it |
| **merge** | bring one branch's changes into another |
| **squash and merge** | merge a PR as a single commit |
| **CI** | automatic checks GitHub runs on every PR |
| **dev stack / prod stack** | the two copies of the software on the ground station PC |
| **release** | a set of exact versions of all repos that was tested together, named by date, e.g. `v2026.10.04` |
| **pin / promote / deploy** | record a tested release / approve it for prod / put it on prod ([RELEASING.md](../../RELEASING.md)) |
| **hotfix** | a fix to prod made from `main`; `Nova.ps1 hotfix` captures one made on-site |
