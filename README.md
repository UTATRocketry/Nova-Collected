# Nova GCS

Nova is UTAT Rocketry's Ground Control System: the software that shows live
engine and flight-computer data and commands valves on a real engine. This
repo (**Nova-Collected** on GitHub, cloned as `C:\Nova` on the ops PC) holds
the operations tooling and pins which version of each code repo belongs
together.

> [!IMPORTANT]
> This software commands valves on a real engine. Read
> [CONTRIBUTING.md](CONTRIBUTING.md) before your first change.

![System overview](docs/assets/diagrams/png/system-overview.png)

## Repo structure

```
Nova\                      this repo
├── ops\                   Nova.ps1 (runs, updates and releases the stack) + Nova Console
├── prod\backend\          submodule: novaOps-back - FastAPI backend + FAS bridge
├── prod\frontend\         submodule: novaOPS-front - Next.js operator UI
├── pi\novaGround\         submodule: novaGround - C++ on the Raspberry Pi
├── firmware\              submodule: FAS's firmware (reference only)
├── releases\<tag>\        what each release pinned, and the config it was tested with
├── docs\                  documentation
└── dev\                   your own clones of the code repos (gitignored)
```

> [!NOTE]
> The submodules show the **released** versions and are overwritten whenever a
> release changes. Make changes in the `dev\` clones, never in `prod\`, `pi\`
> or `firmware\`.

## Getting started

### Set up

```bash
git clone --recursive https://github.com/UTATRocketry/Nova-Collected.git Nova
cd Nova
git clone -b dev https://github.com/UTATRocketry/novaOps-back.git dev/backend
git clone -b dev https://github.com/UTATRocketry/novaOPS-front.git dev/frontend
git clone -b dev https://github.com/UTATRocketry/novaGround.git dev/novaGround
```

Setting up the ops PC, the Pi or an operator laptop instead:
[docs/deployment/](docs/deployment/README.md).

### Run

- **On your laptop, without hardware:**
  [docs/development/getting-started.md](docs/development/getting-started.md#run-each-part-without-hardware).
- **On the ground station:** the stack starts on boot. Check it in the Nova
  Console at `http://192.168.137.1:8080`. Commands are in
  [ops/README.md](ops/README.md).

### Troubleshoot

```powershell
.\ops\Nova.ps1 doctor
```

`doctor` checks every prerequisite on the ops PC and prints what's missing. For
symptoms and fixes, see [SUPPORT.md](SUPPORT.md).

## More information

| To... | Read |
|---|---|
| Contribute code | [CONTRIBUTING.md](CONTRIBUTING.md) |
| Find any document | [docs/README.md](docs/README.md) |
| Release a version or roll back | [RELEASING.md](RELEASING.md) |
| See what changed | [CHANGELOG.md](CHANGELOG.md) |
| Get help or fix a problem | [SUPPORT.md](SUPPORT.md) |
| See this year's plans | [ROADMAP.md](ROADMAP.md) |
| Understand the system | [docs/architecture/system-overview.md](docs/architecture/system-overview.md) |
