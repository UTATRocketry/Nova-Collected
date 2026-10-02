# MQTT topics

The broker is Mosquitto on the ops PC, port 1883. All payloads are JSON.
Taken from the code: `novaOps-back/app/context.py`,
`novaOps-back/tools/fas_bridge.py` and `novaGround/src/`.

| Topic | Published by | Subscribed by | Contents |
|---|---|---|---|
| `nova/telemetry/engine` | novaGround, fas_bridge | backend | Sensor samples (below) |
| `nova/telemetry/flight` | fas_bridge | backend | FAS state snapshot under `data`, events under `events` |
| `nova/command` | backend | novaGround, fas_bridge | Every command, wrapped in an envelope |
| `nova/console` | backend, fas_bridge | backend, fas_bridge | Raw console traffic: decoded frames, port lists, upload progress |
| `nova/control` | novaLock, backend | backend | Lockout state; the backend also mirrors data-saving start/stop here |

> [!WARNING]
> Only the backend publishes on `nova/command`. A topic or payload change must
> land in every repo that uses it in the same release, with a `!` PR title.

> [!NOTE]
> Older docs use `nova/telemetry`, `novaground/telemetry` and
> `novaground/command`. Those topics no longer exist.

## `nova/telemetry/engine`

```json
{
  "source": "GCS",
  "sensors": [{"hat_id": 0, "channel_id": 0, "value": 1.234, "timestamp": 12345}]
}
```

The backend maps `(source, hat_id, channel_id)` to a sensor via each sensor's
`binding` in `system.yaml`. Identical consecutive payloads from one source are
ignored. The FAS bridge sends its sensors keyed `"<node>:<channel>"`
(for example `"EPB_0:0"`).

## `nova/telemetry/flight`

```json
{"source": "FAS", "data": {"fas_boards": {}, "fas_fmc": {}, "fas_pmb": {}, "fas_imc": {}}}
```

`data` keys: `fas_boards`, `fas_actuators`, `fas_sensors`, `fas_board_status`,
`fas_fmc`, `fas_pmb`, `fas_imc`, `fas_rab`, `fas_aux`, `fas_radio_cfg`,
`fas_sound`, `fas_link`. The backend stores and forwards it without parsing.

## `nova/command`

Every command uses the envelope:

```json
{"source": "novaOps", "command": {"type": "<type>", "...": "..."}}
```

| `type` | Handled by | Example |
|---|---|---|
| relay / gpio / servo | novaGround | built from the actuator's `binding` in config |
| `fas` | fas_bridge | `{"type":"fas","board_type":"EPB","board_id":0,"port":"relay","channel":2,"action":"on"}` |
| `console` | fas_bridge | `{"type":"console","action":"list_ports"}`; actions: start, stop, list_ports, configure, disconnect, status, tx |
| `data_file` | novaGround, fas_bridge | `{"type":"data_file","action":"start_data_saving","filename":"..."}` |

Servo `value` is always a pulse width in microseconds. Unknown types are
dropped silently by each consumer.

## `nova/control`

```json
{"source": "novaLock", "state": "locked"}
```

While locked, the backend rejects commands listed under `safetyRules.hazardous`
and RAB arming. See [architecture/system-overview.md](../architecture/system-overview.md#safety-model).
