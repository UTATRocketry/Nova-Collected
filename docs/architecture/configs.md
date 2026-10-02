# Backend config

The station config: what it contains, where it lives, how every version is kept,
and how recordings point back to the config they were taken with.

**What this document answers**

- Which sections and fields a config file has, and which are required
- What the backend rejects when a config is saved
- Where the live config, its history and the published defaults live
- How to find the exact config behind any recording

Source of truth: the backend's `app/models.py` (schema),
`app/services/config_service.py` (loading and validation),
`app/services/config_history.py` (history) and
`app/services/recording_service.py` (recordings).

> [!TIP]
> To restore an older config, follow
> [maintenance/restore-an-old-config.md](../maintenance/restore-an-old-config.md).

## Where config lives

| What | Where | Changed by |
|---|---|---|
| Live config | `C:\Nova\config\<env>\*.yaml` (`NOVA_CONFIG_DIR`) | the web interface (Config page) |
| History | `C:\Nova\config\history\` (`NOVA_CONFIG_HISTORY_DIR`) | the backend, automatically |
| Published defaults | backend repo, `config/system.yaml` and `config/launch.yaml` | a PR, rarely and deliberately |
| Tested config of a release | this repo, `releases/<tag>/config/` | `Nova.ps1 pin` / `hotfix` |

`Nova.ps1` sets `NOVA_CONFIG_DIR` and `NOVA_CONFIG_HISTORY_DIR` for each stack.
Unset (on a laptop), the backend uses its own `config/` folder and
`config/history/`.

On first start, an **empty** config folder is seeded from the published
defaults. A folder that already has a `.yaml` is never overwritten, so a code
update can't replace a station's calibrations.

> [!WARNING]
> Don't change `config/*.yaml` in the backend repo to change a calibration.
> Calibrations are edited in the web interface on the station. Change the repo
> files only to change the defaults a new station starts from, in their own PR.

The active file is `system.yaml`. Other files in the folder (for example
`launch.yaml`) can be switched to with **Config → Load**
(`POST /api/config/load`).

## The model

A config file is YAML with these top-level sections. All are optional and
default to empty.

| Section | Type | Holds |
|---|---|---|
| `Sensors` | list | Every sensor: what it measures, where its samples come from, how to calibrate it |
| `Actuators` | list | Every valve, servo, relay, motor and GPIO device, and how to reach it |
| `Commands` | map (or list with `name`) | System commands sent with `POST /api/system-commands` |
| `safetyRules` | `critical` / `hazardous` lists | Which commands a `pad` user may send, and which the novaLock blocks |
| `Procedures` | list | Checklists shown on the Engine page |
| `Devices` | list | FAS boards (`EPB:0`, `FMC:0`) and the normal ranges of their readings |
| `Packets` | list | Packet templates for the Console page's transmit form |
| `BuzzerMelodies` | map | Named melodies: lists of `[freq_hz, dur_ms]` notes (optional third value: volume; `freq_hz` 0 is a rest) |

### Sensors

```yaml
Sensors:
  - name: PGS                  # unique; shown in the UI
    type: PT                   # PT, LC or TC
    unit: psi
    range: [0.0, 1000.0]       # expected range, for display
    binding:                   # where samples come from
      source: GCS              # GCS or TCS: a DAQ HAT channel on a Pi
      hat_id: 0
      channel_id: 0
    convert:
      method: linear           # none, zero_offset, linear, polynomial (default linear)
      calibration:             # [raw volts, value] points
        - [1.99, 0.0]
        - [9.3034, 900.0]
```

A FAS sensor uses `source: FAS` with `board_type` (for example `EPB`),
`board_id` and `channel`. The legacy form `node: "EPB_0"` is still accepted.

> [!NOTE]
> With calibration on (`POST /api/flags/calibration`), **every method except
> `none` applies piecewise-linear interpolation** between the `calibration`
> points. `zero_offset` and `polynomial` are accepted but not implemented
> separately yet ([known issue](../../SUPPORT.md#known-issues)). With calibration off, values
> are shown raw, in volts.

### Actuators

```yaml
Actuators:
  - name: MAIN_VALVE           # unique
    type: solenoid             # servo, solenoid, powered_device, powered_gpio_device, gpio_device, motor
    binding:
      target: FAS              # GCS (Pi), FAS (flight boards), TCS or OPS
      board_type: EPB
      board_id: 0
      relay_channel: 2
    actions:
      solenoid_type: nominally_open
```

| Binding field | Use |
|---|---|
| `relay_channel` | Relay or load switch driven for this actuator |
| `servo_channel` | PWM channel (servos) |
| `gpio_channel` | GPIO line (e.g. IMC arm) |
| `reverse_relay_channel` | Second relay of a reversible motor |
| `board_type`, `board_id` | FAS board; required for `target: FAS` (or legacy `node`) |

| Action field | Use |
|---|---|
| `position_aliases` + `positions` | Servo positions by name, in pulse-width µs; the two lists must be the same length |
| `default_position` | Servo position to start in |
| `solenoid_type` | `nominally_closed` or `nominally_open` |
| `relay_type` | `nominally_off` or `nominally_on` |
| `gpio_commands` | Allowed GPIO commands, e.g. `[ARM, DISARM]` |
| `reversible`, `state_labels`, `invert_relays` | Motors: two-way wiring, custom state names, inverted relay logic |

### safetyRules

```yaml
safetyRules:
  critical:            # the only commands a pad user may send
    - SVOTV: ALL
  hazardous:           # refused while the novaLock is locked
    - MOV: ALL
    - MFV: [open]
```

Each rule maps an actuator name to `ALL` or a list of states. Names and states
are matched case-insensitively. See
[system-overview.md](system-overview.md#safety-model) for how roles and the
novaLock use them.

## What the backend rejects

A save, upload or load fails with an error, and the live file stays unchanged,
when:

- a field has the wrong type, or `type` / `method` / `source` isn't one of the
  values above;
- two sensors read the same address (`source`, `hat_id`, `channel_id`, or the
  FAS board and channel);
- two actuators have the same name;
- a FAS actuator sets neither `board_type` nor `node`;
- a servo's `position_aliases` and `positions` differ in length;
- a motor has no `relay_channel`, a reversible motor has no
  `reverse_relay_channel`, or its `state_labels` are the wrong count or
  duplicated.

A successful save is written back without defaults or empty fields, so files
stay short.

## History

Every config the backend runs with is kept, automatically:

```
C:\Nova\config\history\
├── snapshots\<hash>.yaml   every distinct content, stored once
└── history.jsonl           one line per event
```

```json
{"time": "2026-10-04T14:02:11+00:00", "env": "prod", "file": "system.yaml",
 "hash": "3f9a1c0e7b2d4a61", "source": "edit", "client": "c1a2b3 (operator)"}
```

| `source` | When |
|---|---|
| `startup` | The backend started |
| `edit` | A save from the web interface (repeats of identical content aren't logged again) |
| `load` | A different file was activated |
| `reload` | The file was re-read from disk |

`Nova.ps1` also snapshots a live file into the same history before it
overwrites it (for example `deploy -WithConfig`).

> [!IMPORTANT]
> The hash is the first 16 hex characters of the file's SHA-256, computed
> identically by the backend (`config_history.py`) and `Nova.ps1`
> (`Get-ContentHash`). Change both or neither. `.gitattributes` keeps git from
> changing the bytes of `releases/*/config/`.

## Recordings

Starting data saving (`POST /api/flags/data-saving`) makes the backend:

1. pick a name not already used in the data folder (`YYYY-MM-DD-HH_data_N`);
2. write `<name>.meta.json` with the environment, release, backend commit,
   start time and the hash of the active config;
3. tell the loggers to start.

A config change during the recording is appended to the same file; stopping
adds the stop time. The loggers write raw values into the same folder:

| Logger | Files |
|---|---|
| FAS bridge | `<name>.csv` |
| novaGround | `<build ID>_<name>_sensors.csv`, `<build ID>_<name>_actuators.csv`, e.g. `novaGround_<name>_sensors.csv` (uploaded to the backend on stop) |

`Nova.ps1 archive` (also run by `pin`) turns each finished recording into a
self-contained bundle that can be understood without the station:

> [!WARNING]
> **Known issue:** `archive` collects files whose names *start with* the
> recording name, so it misses novaGround's `novaGround_<name>_*.csv` files.
> Until that's fixed, copy them into the bundle's `data\` folder by hand
> ([SUPPORT.md](../../SUPPORT.md#known-issues)).

```
C:\Nova\archive\<env>\<recording>\
├── data\          every CSV for the recording
├── config\        <hash>_<file> for each config it used
├── meta.json      the backend's metadata
└── bundle.json    file list with sizes and SHA-256, written last
```

## Requirements

- Calibrations are edited on the station, never committed.
- Nothing is lost: every saved version is recoverable by hash.
- Any recording identifies the exact config it was taken with.
- A code update or a release never overwrites a station's live config.
- A mistyped config fails to save instead of silently mis-routing a sensor or
  actuator.
