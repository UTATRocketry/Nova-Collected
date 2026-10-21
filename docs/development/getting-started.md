# Getting started as a developer

From a fresh laptop to your first PR. Read in this order:

1. [README.md](../../README.md) for the big picture.
2. [CONTRIBUTING.md](../../CONTRIBUTING.md): branches, commits and PRs.

   > [!IMPORTANT]
   > CONTRIBUTING.md is **required reading before your first PR**.

3. [architecture/system-overview.md](../architecture/system-overview.md).
4. [organization.md](organization.md) and [style.md](style.md) for the repo
   you'll work in.
5. [firmware/FMC-Interface-Contract.md](../../firmware/FMC-Interface-Contract.md)
   if you touch anything that talks to the flight computer.

## Get the code

Clone this repo (named Nova-Collected on GitHub; `Nova` matches the server's
`C:\Nova`), then clone the code repos you'll change into its `dev/` folder:

```bash
git clone --recursive https://github.com/UTATRocketry/Nova-Collected.git Nova
cd Nova
git clone -b dev https://github.com/UTATRocketry/novaOps-back.git dev/backend
git clone -b dev https://github.com/UTATRocketry/novaOPS-front.git dev/frontend
git clone -b dev https://github.com/UTATRocketry/novaGround.git dev/novaGround
```

> [!WARNING]
> **Make all your changes in the `dev/` clones.** The submodules in `prod/`,
> `pi/` and `firmware/` are checked out at the newest release (detached HEAD)
> and are overwritten when it changes. `dev/` is ignored by this repo, so
> nothing you do there shows up here.

In GitHub Desktop, add each `dev/` clone with **File → Add local repository**.

## Run each part without hardware

| Part | Needs | Run (from its `dev/` clone) |
|---|---|---|
| Broker | Mosquitto | `mosquitto -v` |
| Backend + simulator (Windows) | Python 3.11+ | `scripts/dev_windows.ps1 -Broker localhost -WithMock`, then open `http://localhost:8000/docs` |
| Backend (Linux/macOS) | Python 3.11+ | `scripts/dev_linux.sh --broker localhost`, then open `http://localhost:8000/docs` |
| Simulator, if not started above | paho-mqtt | `python tools/novaMock.py --broker localhost` (stands in for novaGround and the FAS bridge) |
| Frontend | Node 20+ | `npm install`, `cp .env.example .env.local`, `npm run dev`, then open `http://localhost:3000` |
| novaGround | Raspberry Pi OS (Legacy, 64-bit) | see [novaGround's setup guide](https://github.com/UTATRocketry/novaGround/blob/dev/docs/setup.md); `./build/novaMock` needs no hardware |
| FAS bench | STM32CubeIDE toolchain | `firmware/bench/bench.bat`, then open `http://127.0.0.1:8770` |

> [!TIP]
> Start the broker, then the backend with `-WithMock`, then the frontend. You
> get live simulated data on every page with no hardware at all.

## Check your change

| Repo | Run before you push |
|---|---|
| backend | `python -m pytest -q` |
| frontend | `npm run typecheck` and `npm run build` |
| novaGround | `bash -n *.sh`, and a build on a Pi if you changed C++ |

CI runs the same checks on every PR. [CONTRIBUTING.md §7](../../CONTRIBUTING.md#7-testing)
says how far beyond that a change must be tested; the hands-on part is the
[testing procedure](testing-procedure.md).

## Everyday workflows

### Work on a change

Picking up an issue from the board? Follow
[working-on-an-issue.md](working-on-an-issue.md) from start to finish.

```bash
cd dev/backend
git switch dev && git pull
git switch -c bugfix/fas-port-reconnect
# ...edit, commit...
git push -u origin bugfix/fas-port-reconnect    # then open the PR into dev
```

Once merged into `dev`, your change reaches prod when a test day tests `dev`
and a lead releases it ([RELEASING.md](../../RELEASING.md)). Nothing changes in
this repo until then.

### Get the newest release's versions

```bash
git pull
git submodule update --init --recursive
```

> [!TIP]
> `git config --global submodule.recurse true` makes a plain `git pull` update
> the submodules too.

Submodule pins move only through `Nova.ps1 pin`. Never bump them by hand.

## Diagrams

Diagrams in these docs are PNG images in
[_assets/diagrams/](../_assets/diagrams/). To change one, edit it in
[draw.io](https://www.drawio.com) and export it over the existing PNG.
