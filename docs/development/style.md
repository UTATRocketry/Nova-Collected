# Style guide

How Nova code and docs are formatted and named. Where a tool enforces a rule,
the tool wins: run it instead of formatting by hand.

> [!NOTE]
> Don't reformat code you aren't changing. It hides your real change in review
> and causes merge conflicts ([CONTRIBUTING.md §8](../../CONTRIBUTING.md#8-avoiding-merge-conflicts)).

## Python (backend, FAS bridge, Nova Console)

- **Python 3.11+**, with `from __future__ import annotations` at the top of
  each module.
- **PEP 8**: 4-space indents, `snake_case` functions and variables,
  `PascalCase` classes, `UPPER_CASE` constants.
- **Type hints** on every function signature. Use `X | None`, not `Optional[X]`.
- **Pydantic models** for anything that crosses an API or config boundary.
- **Logging** through `logging.getLogger(__name__)`, never `print`, except in
  command-line tools.
- **Docstrings** say *why*, not what the next line does.
- Lint: `pylint app` (configured in `pyproject.toml`). Tests: `python -m pytest -q`.

## TypeScript and React (frontend)

- **`strict` TypeScript**; no `any` without a comment saying why. CI runs
  `npm run typecheck` and `npm run build`.
- **Components** in `PascalCase.tsx`, one exported component per file. Hooks
  are `useSomething.ts`; other modules are `camelCase.ts`.
- **Chakra UI** for styling, with tokens from `lib/theme/`. No hard-coded
  colors.
- **Icons** through `Icon.tsx` (Material Symbols); it owns weight and fill.

UI rules for a control surface:

> [!IMPORTANT]
> **Never show a value you don't have.** "No data" renders as "—", never a
> made-up `0`. An operator must always be able to tell stale from zero.

- Dark mode is the default (night and bunker operations). The nav rail and top
  bar (`chrome.*` colors) stay dark in light mode too.
- Commands that can move hardware need a clear label and state, and must not
  fire on a single accidental click.

## C++ (novaGround)

- **C++17**, built with meson and clang.
- **Format with clang-format** using the repo's `.clang-format` (LLVM base,
  4-space indents, `int* p` pointer style):

  ```bash
  clang-format -i src/path/to/file.cpp
  ```

- `snake_case` functions and variables, `PascalCase` types, `kConstant`
  constants, `member_` for private members.
- RAII for every resource (files, I2C handles, threads); no raw `new`/`delete`.

## PowerShell (`ops/`)

Must run on **Windows PowerShell 5.1** under `Set-StrictMode -Version 2`. The
full rules are in [AGENTS.md](../../AGENTS.md#coding-conventions-opsps1).
Before a PR, check it parses:

```powershell
$e = $null; [void][System.Management.Automation.Language.Parser]::ParseFile("$PWD\ops\Nova.ps1", [ref]$null, [ref]$e); $e
```

- `Verb-Noun` function names with approved verbs.
- No `??`, ternary `? :`, `&&`/`||`, or `ConvertFrom-Json -AsHashtable`
  (PowerShell 7 only).

## Shell scripts (Pi)

- `#!/usr/bin/env bash` and `set -uo pipefail`. Add `-e` only where every
  failure should abort the script (as `start.sh` does); the others check
  errors themselves so they can print what to do.
- **LF line endings** for `*.sh` and `*.service` (enforced by
  `.gitattributes`); a CRLF shebang fails on the Pi.
- Check with `bash -n script.sh`.

## Names shared across repos

| Thing | Style | Example |
|---|---|---|
| MQTT topics | lowercase, `/`-separated, `nova/` prefix | `nova/telemetry/engine` |
| JSON fields on the wire | `snake_case` | `hat_id`, `board_type` |
| Config sections | as the schema defines them | `Sensors`, `safetyRules` |
| Sensor and actuator names | uppercase, no spaces | `PGSO`, `MAIN_VALVE` |
| Branches and PR titles | [CONTRIBUTING.md §3, §6](../../CONTRIBUTING.md#3-branches) | `feature/valve-timeout`, `fix(fas): ...` |

## Documentation

- **Write for someone in a hurry**, often mid-test. Lead with what to do.
- **Headings** in sentence case that name their content. Not "Notes".
- **Procedures** are numbered steps, each with a copy-pasteable command.
- **One home per fact.** Link to it instead of repeating it.
- **Callouts** draw attention to what matters, using GitHub's alert syntax.
  Keep them rare; if everything is a callout, nothing is.

  | Callout | Use for |
  |---|---|
  | `> [!NOTE]` | Useful context the reader might skip |
  | `> [!TIP]` | A faster or better way |
  | `> [!IMPORTANT]` | Something the reader must know to succeed |
  | `> [!WARNING]` | Something that can break the station or lose data |
  | `> [!CAUTION]` | Something that can move hardware or hurt someone |

- **Diagrams** are draw.io files in `docs/assets/diagrams/`, rendered to PNG by
  `build_diagrams.py --png`. Commit the source and the PNG.
- Never write a number or behaviour you haven't checked in the code. Write
  "unconfirmed" instead.
