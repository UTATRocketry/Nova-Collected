# Code organization

Where code goes in each Nova repo, and the rules that keep it there. Read the
section for the repo you're changing before adding a file.

**What this document answers**

- Which folder a new file belongs in, in each repo
- Which layer may call which
- The cross-repo rules every change must keep

## Rules for every repo

1. **One source of truth per fact.** A setting, topic name or protocol constant
   is defined once and read from there. Don't copy a value to a second place.
2. **Only the backend publishes commands.** novaGround and the FAS bridge
   execute commands; the frontend asks the backend. Nothing else writes to
   `nova/command`.
3. **Hardware is touched in one place per machine:** novaGround's
   `src/interfaces/` on the Pi, and `tools/fas_bridge.py` for the flight
   computer.
4. **Station state lives outside code.** Live config, recordings and logs never
   go in a repo ([configs.md](../architecture/configs.md)).
5. **A contract change touches every side in the same release.** A renamed
   topic, payload field or protocol message needs matching PRs in every repo
   that uses it, and a `!` PR title ([CONTRIBUTING.md §6](../../CONTRIBUTING.md#6-pr-titles-and-commit-messages)).
   Contracts are documented in [api/](../api/).

## novaOps-back (backend)

```
app/
├── main.py            app factory: logging, config seeding, routers
├── context.py         AppContext: owns every service; MQTT → WebSocket glue
├── deps.py            FastAPI dependencies: get_context, require_role
├── models.py          Pydantic models: config schema and request bodies
├── state.py           RuntimeState: latest values, flags, lockout
├── websocket_manager.py
├── routers/           one file per API area (config, flags, commands, ...)
└── services/          the logic: parsing, commands, MQTT, roles, recordings, history
config/                published default configs
tools/                 fas_bridge.py and the simulators
scripts/               foreground launchers (Windows, Linux)
tests/                 pytest, one test file per service or concern
```

- **Routers stay thin.** A router validates the request with a model from
  `models.py`, calls a service through the `AppContext` (`Depends(get_context)`)
  and returns. Logic goes in `services/`.
- **Services don't import routers or FastAPI.** They take plain values and are
  tested directly.
- **New config fields go in `models.py`**, with a default, so existing station
  configs still load. Validation that spans several entries goes in
  `ConfigService._check_duplicates` or a `model_validator`.
- **New endpoints get a role check** (`require_role`) if they can move hardware.
- **Tests:** add `tests/test_<service>.py` next to the existing ones.
- `app/static/` and `app/templates/` are the backend's own debug pages
  (`/view-json`, `/view-mqtt`); the operator UI is the frontend repo.

## novaOPS-front (frontend)

```
src/
├── app/               Next.js routes: one folder per page (engine, flight, devices, ...)
│   └── tools/<name>/  a tool page: page.tsx + tool.ts (registers it)
├── components/
│   ├── primitives/    shared building blocks: Card, Chip, Gauge, Plot, Tabs, ...
│   ├── shell/         app frame: nav rail, top bar
│   └── <area>/        components used by one page (engine, flight, config, ...)
├── hooks/             React Query and store hooks (useConfig, useCommands, ...)
└── lib/
    ├── api/           every REST call, through novaFetch
    ├── ws/            the WebSocket connection (NovaSocket)
    ├── store/         zustand store for live telemetry
    ├── theme/         Chakra system and color mode
    └── <area>/        logic with no React: analysis, pid, console, alerts, ...
```

- **Pages compose; components render; `lib/` computes.** Put logic that doesn't
  need React in `lib/`, so it's testable and reusable.
- **REST calls go through `lib/api/`** and are used through a hook in `hooks/`.
  A few components still call `fetch` directly; move them when you touch them.
- **Live data comes from the store**, filled by `lib/ws/`. Components subscribe
  through selectors, not by opening their own socket.
- **A component used by two areas moves to `primitives/`.**
- **A new tool** is a folder in `src/app/tools/` with `page.tsx` and a `tool.ts`
  that calls `registerTool`.
- Import with the `@/` alias (`@/lib/api`), not long relative paths.

## novaGround

```
src/
├── main.cpp           argument parsing, wiring, thread start-up
├── interfaces/        hardware drivers: DAQ HATs, GPIO, TCA9535, PCA9685
├── controllers/       device logic on top of the drivers; loops.cpp holds the thread loops
├── core/              CommandRouter, TelemetryStore, data logging
└── utils/             JSON helpers
```

- **Only `interfaces/` talks to hardware.** Controllers use interfaces; core
  uses controllers.
- **A missing device must not stop the program.** Check at start-up, log it,
  and keep running without it (see how `main.cpp` handles each device).
- **New source files** must be added to that folder's `meson.build`.
- Build targets (`novaGround`, `novaThermo`, `novaMock`) differ only by compile
  definitions in the top-level `meson.build`. Hardware-only code must compile
  out under `NOVA_MOCK_MODE`.

## Nova-Collected (this repo)

- `ops/Nova.ps1` is one script, organised in commented sections (settings,
  services, release workflow, ...). Put a new function in the matching
  section. Its conventions are in [AGENTS.md](../../AGENTS.md#coding-conventions-opsps1).
- `ops/console/nova_console.py` must stay stdlib-only.
- Documentation goes in `docs/`; see [docs/README.md](../README.md) for which
  folder.
