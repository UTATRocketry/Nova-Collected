# Backend API (REST and WebSocket)

The novaOps backend serves on port 8000 (prod) or 8001 (dev). This page is
the map.

> [!TIP]
> The live, generated reference is always at **`http://<host>:8000/docs`**
> (Swagger) and `/redoc`. Use it for exact request bodies, and to try requests
> from the browser.

Source: `novaOps-back/app/routers/`.

## REST

| Method | Path | What |
|---|---|---|
| GET | `/health` | Liveness (used by the Nova Console) |
| GET | `/api/config/` | Active config as JSON |
| GET | `/api/config/actuators` · `/sensors` · `/procedures` | Parts of the config |
| GET | `/api/config/list` | YAML files in the config directory |
| POST | `/api/config/load` | Activate a YAML file from disk |
| GET | `/api/config/download/{file_name}` | Download a config file |
| POST | `/api/config/upload` | Upload and activate a config file |
| PUT / PATCH | `/api/config/update` | Replace / shallow-merge the active config |
| POST | `/api/config/reload` | Reload from disk |
| GET / POST | `/api/flags/calibration` | Calibrated vs raw sensor output |
| GET / POST | `/api/flags/data-saving` | Start / stop a recording (returns its name) |
| GET / POST | `/api/flags/lockout` | Read / override the novaLock lockout (testing) |
| GET | `/api/data-files` | List recordings |
| GET | `/api/data-files/{file_name}` | Download a CSV |
| POST | `/api/data-files/upload` | novaGround uploads its CSVs here on stop |
| GET | `/api/roles` | Connected clients and their roles |
| POST | `/api/roles` | Assign a role |
| POST | `/api/commands` | Send an actuator command (same checks as WebSocket) |
| POST | `/api/system-commands` | System-level commands |
| POST | `/api/console` · `/api/console/command` | Raw console payload / FAS console command |
| POST | `/api/direct/relay` · `/api/direct/servo` | Direct channel control (tools pages) |
| POST | `/api/fas/buzzer` · `sd` · `rab` · `aux` · `runcam_record` · `radio_config` · `sound` · `charger` | FAS board controls |
| POST / GET | `/api/fas/sound/upload` · `/api/fas/sound/clip/{token}` | Soundboard clip staging (the bridge downloads the clip over HTTP) |
| GET / PUT | `/api/diagram` | P&ID layout used by the Engine page |

Every config change is snapshotted to the config history automatically, and
broadcast to clients as `config_update`.

## WebSocket `/ws`

Clients connect to `ws://<host>:8000/ws` and start as `viewer`.

**Server → client**

| `type` | When |
|---|---|
| `session` | On connect, and whenever your role changes (`role`, `client_id`) |
| `snapshot` | On connect: current actuator states |
| `engine_data` | Parsed sensor readings |
| `parsed_data` | Same data, kept for older clients |
| `flight_data` · `flight_events` | FAS state and events |
| `lockout` | novaLock state changes |
| `config_update` · `diagram_update` | Someone changed the config or P&ID |
| `mqtt_message` | Every raw MQTT message (for the console / debug views) |
| `error` | A rejected command or request (`detail`) |

**Client → server**

| Message | Needs |
|---|---|
| `{"type":"solenoid","name":"SVOTV","state":"open"}` | pad (critical only), operator or admin |
| `{"type":"role_request","role":"operator"}` | admin to set another client's role; admin role needs `password` |
| `{"type":"console_command","command":{"action":"list_ports"}}` | operator or admin |
| `{"type":"console","payload":{...}}` | any |
