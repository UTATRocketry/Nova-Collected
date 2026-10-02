# Station network

Every Nova machine is on one wired ethernet network with static addresses. The
addresses are set in `ops\nova.settings.ps1` on the ops PC and
`/etc/nova/novaGround.env` on the Pi.

| Host | Address | Runs |
|---|---|---|
| Ops PC ("Nova-Server") | `192.168.137.1` | backend, frontend, broker, FAS bridge, Nova Console |
| novaGround Pi | `192.168.137.10` | novaGround |
| novaThermo Pi | `192.168.137.20` | novaThermo |
| Operator laptop | any free `192.168.137.x` (e.g. `.50`) | a browser |

| Port (ops PC) | prod | dev |
|---|---|---|
| Operator UI (frontend) | 3000 | 3001 |
| Backend API + WebSocket | 8000 | 8001 |
| Nova Console | 8080 | 8081 |
| MQTT broker (shared) | 1883 | 1883 |

> [!NOTE]
> Windows Firewall on the ops PC must allow inbound 3000 and 8080 for the
> operator laptop to connect. The command is in
> [SUPPORT.md](../../SUPPORT.md#the-operator-laptop-cant-reach-the-station).

The console falls back to the mDNS names `novaground.local` and
`novathermo.local` when a Pi's static address doesn't answer (needs
`avahi-daemon` on the Pi).
