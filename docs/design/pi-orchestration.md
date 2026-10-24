# Pi orchestration

Status: in progress, fixes [#29](https://github.com/UTATRocketry/Nova-Collected/issues/29).
The code is in two PRs, `bugfix/backend-port-fix` in novaGround and
`feature/pi-orchestration` in this repo.

This covers how the ops PC drives the two Raspberry Pis: how a Pi knows which
backend to upload to, what happens to novaThermo when we pin and deploy, how
the Pis report to the Nova Console, and how the console runs `Nova.ps1` so we
don't have to remote desktop into the ops PC for routine work.

## Where we started

There are two Pis, both running the novaGround repo. They only differ in which
binary they run (`NOVA_TARGET`):

| Pi | Address | Binary |
|---|---|---|
| novaGround | `192.168.137.10` | `novaGround` |
| novaThermo | `192.168.137.20` | `novaThermo` |

Each one has a prod checkout and a dev checkout under `/home/admin`. A single
`novaGround.service` ran the prod checkout and read its settings, including
the backend address, from `/etc/nova/novaGround.env`. To run dev you SSHed in,
stopped the service and started `run.sh` in tmux, which read the same file.

On the PC side, `Nova.ps1` only ever talked to novaGround, and only for some
verbs. `pin` read novaGround's dev commit over SSH, `deploy` ran `nova-pi.sh
deploy` on it, and `hotfix` captured edits from its prod checkout. `get-changes`
and `use` printed SSH instructions for you to follow by hand. novaThermo was
never touched at all; `status`, `doctor` and the console just pinged it.

That caused a few problems.

The backend port lived in a file nothing managed. That's #29. Prod's backend is
on 8000 and dev's is on 8001, but both the service and `run.sh` read
`NOVA_BACKEND` from the one env file. If you forgot to change it for a dev
test, novaGround uploaded to a port nobody was listening on and the CSVs never
showed up. If you changed it and forgot to change it back, the next prod test
uploaded to dev. Nothing on the Pi noticed either way.

novaThermo wasn't recorded anywhere. A release said which novaGround commit it
pinned and said nothing about the thermocouple Pi, which could have been on any
branch with uncommitted changes. If a thermocouple reading looked off in a
recording, we had no way to find out what code produced it.

The Pi half of `get-changes` and `use` was manual, so it was easy to skip,
especially in the middle of a test.

The server address and port were hard-coded in six places (`nova-pi.sh`,
`run.sh`, `start.sh`, `install.sh`, the unit file and `main.cpp`) on top of
`nova.settings.ps1`.

Failed uploads were quiet. `upload_file()` didn't set `CURLOPT_FAILONERROR`,
so a 404 or 500 counted as success, and the result was ignored anyway. The
backend URL was only logged at `--verbosity 2`.

And the console couldn't see the Pis. It runs as a Windows service with no SSH
keys, so all it could do was ping.

## The rules we went with

- The PC owns which stack is live and where the server is. The Pi owns which
  Pi it is and which binary it runs. Each of those is written down in one place.
- novaGround is the only Pi a release pins. Any other Pi gets recorded as
  "ran with".
- A difference between the Pis is reported, not blocked.
- A Pi never switches stacks by itself. An operator does that with `use`.
- The console only runs `Nova.ps1` actions from a fixed list. It never runs
  a command on a Pi directly.

## On the Pi

`novaGround.service` is now a template, `novaGround@.service`, with two
instances:

| Unit | Runs | On boot |
|---|---|---|
| `novaGround@prod` | `/home/admin/prod/novaGround` | yes |
| `novaGround@dev` | `/home/admin/dev/novaGround` | no |

That matches the PC, where prod services start automatically and dev ones
don't. After a reboot everything is back on prod.

The settings are split between three files:

| File | Holds | Written by |
|---|---|---|
| `/etc/nova/pi.env` | `NOVA_PI_NAME`, `NOVA_TARGET`, `NOVA_EXTRA_ARGS` | `nova-pi.sh install`, once per Pi |
| `/etc/nova/novaGround-prod.env` | `NOVA_BROKER`, `NOVA_BACKEND`, `NOVA_CONSOLE` for prod | `Nova.ps1` |
| `/etc/nova/novaGround-dev.env` | the same for dev | `Nova.ps1` |

`Nova.ps1` rewrites both env files on every `use`, `deploy` and `get-changes`,
using `Hosts.Server`, `Broker.Port` and each environment's `BackendPort` and
`ConsolePort` from `nova.settings.ps1`. Prod always gets prod's port and dev
always gets dev's, and nobody edits the files by hand. That's what fixes #29.
`Nova.ps1` writes the files itself (base64 over SSH) rather than calling
`nova-pi.sh`, so it works whichever version of `nova-pi.sh` the Pi has checked
out.

Some smaller changes on the Pi:

- `start.sh` won't start without `NOVA_BROKER` and `NOVA_BACKEND`, and the
  unit's `EnvironmentFile=` lines are required. A missing setting stops the
  service instead of falling back to `:8000`.
- Only one instance runs at a time. `start.sh` exits with code 78 if the other
  instance or a `run.sh` session is running, and the unit doesn't restart on
  78. Two copies would fight over the MQTT client ID and the DAQ HATs.
- `run.sh` takes `--env` (default `dev`) and reads that environment's file. Its
  tmux session is called `NovaGround-<env>`.
- `nova-pi.sh use prod|dev` switches one Pi by hand, and `nova-pi.sh configure`
  writes an env file by hand for when the PC can't reach the Pi.
- `nova-pi.sh install` handles the migration. It removes the old unit, moves
  `NOVA_TARGET` and `NOVA_EXTRA_ARGS` into `pi.env`, turns the old broker and
  backend into the prod env file, and keeps the old file as
  `novaGround.env.old`.

## On the PC

The settings now list the Pis. Their addresses still come from `Hosts` and
`HostNames`:

```powershell
Pi = @{
    User    = 'admin'
    ProdDir = '/home/admin/prod/novaGround'
    DevDir  = '/home/admin/dev/novaGround'
    Pinned  = 'NovaGround'
    Targets = @{ NovaGround = 'novaGround'; NovaThermo = 'novaThermo' }
}
```

What each verb now does with the Pis:

| Verb | Pis |
|---|---|
| `get-changes` | Fetches, fast-forwards (or checks out `-PiRef`) and builds every Pi's dev checkout, rewrites the dev env files, and restarts `novaGround@dev` if it's running |
| `use` | Rewrites the env files on every Pi, then stops one instance and starts the other |
| `pin` | Pins novaGround's dev commit like before, and records the other Pis as `ranWith`. Warns if novaGround's dev instance wasn't the one running |
| `deploy` | Rewrites the env files, deploys the pinned commit to novaGround, leaves novaThermo's code alone unless you pass `-AlsoDeploy NovaThermo`, then puts every Pi on prod |
| `hotfix` | Captures novaGround's prod edits like before, and records the other Pis as `ranWith` |
| `status`, `doctor` | Show each Pi's running instance, commits, release and backends, and flag anything that doesn't match |

`-SkipPi` now leaves every Pi alone. If a Pi can't be reached, the PC side
still finishes and prints the commands to run on the Pi.

`deploy` still runs the dev checkout's copy of `nova-pi.sh` to deploy prod.
That's on purpose. The dev copy is the tooling we just tested, and it knows
about the new units. The pinned commit's own copy might be from before this
change.

## novaThermo in a release

`pin` and `hotfix` ask every Pi except novaGround what it's running and put it
in `release.json`:

```json
"ranWith": {
  "NovaThermo": {
    "target": "novaThermo",
    "checked": true,
    "running": "dev",
    "checkout": "dev",
    "commit": "4f1c2e0...",
    "branch": "dev",
    "dirty": 0,
    "matchesPin": false
  }
}
```

`running` is what was active (`prod`, `dev`, `dev (run.sh)` or `nothing`), and
`checkout` is where the commit was read from. If nothing was running we read
the dev checkout. `dirty` counts uncommitted files, which `pin` warns about
because that code can't be rebuilt later. If a Pi couldn't be reached, or you
passed `-SkipPi`, the entry has `checked: false` and a note, and the pin goes
ahead anyway.

None of this becomes a submodule pointer; `pi/novaGround` is still the only Pi
commit a release pins. The release notes get a "ran with, not pinned" row for
each Pi, marked when it differs from novaGround.

`deploy` doesn't change novaThermo's code by default, since novaThermo isn't
part of the release. It does switch it to prod. To put it on the commit it ran
with during the test:

```powershell
.\ops\Nova.ps1 deploy v2026.10.21 -AlsoDeploy NovaThermo
```

If the release has no `ranWith` entry for it, `deploy` stops before changing
anything.

## Pi reports

The console can't SSH into the Pis, and giving it keys would let anyone on the
LAN run commands on them. So the Pis push their state to it instead.

`nova-pi-report.timer` runs `nova-pi.sh report` every 15 seconds, which POSTs a
JSON snapshot to `/api/pi-report` on the prod console (the prod console stays
up while dev is live). The snapshot has the active instance and any `run.sh`
session, each environment's unit state, backend and checkout, whether that
backend answers from the Pi, the deployed release, and the last upload.

The console keeps the latest report from each Pi in memory and in
`C:\Nova\state\pis.json`, and only accepts names from its config. Report age
comes from the console's clock because the Pis have no RTC.

Anyone on the LAN could post a fake report, but all that changes is what the
page shows.

## The console

The page lives in `ops/console/web/` (`console.html`, `console.css`,
`console.js`) and `nova_console.py` serves it. From the top it has quick links,
quick actions, broker, services, remote hosts, releases, next steps, activity,
actions, and commands to copy.

The banner shows the live stack: prod with its release, or dev with the
backend, frontend and novaGround commits it's running.

Remote hosts shows each Pi's report: ping, report age, active instance,
commit, release, backend and last upload. These are flagged red:

- the Pi is on a different stack than the PC
- its backend isn't the right one for its stack
- that backend doesn't answer from the Pi (only checked for the live stack)
- its last upload failed

These are flagged amber:

- no report for 45 seconds
- novaGround's prod commit isn't what prod's release pins
- novaThermo is on a different commit from novaGround (just a note)

Next steps lists what's wrong, each with a button that runs the fix. Fixes that
have to run on a Pi show a command to copy instead.

## Running Nova.ps1 from the console

At first the console was only going to show commands to copy. But that still
meant remote desktop into the ops PC for every routine action, so the everyday
verbs are buttons now:

| Section | Buttons |
|---|---|
| Quick actions | Prod / Dev, Status, Doctor, Archive |
| Actions | Get Changes, Pin, Promote, Deploy, Publish |
| Actions > Advanced | Hotfix, Install |

The form fields use the `Nova.ps1` flag names and don't explain them. That's
what [commands.md](../deployment/commands.md) is for.

The console can't run `Nova.ps1` itself. Its service runs as SYSTEM, which has
no SSH key for the Pis or GitHub login for `publish`, and git won't trust
`C:\Nova` from it. Also, `deploy` and `install` restart the console, so
anything the console started as a child process would die partway through.

Instead, `Nova.ps1 console-runner` registers a scheduled task,
`\Nova\Console Runner`, that runs `ops\console\Invoke-ConsoleJob.ps1` as the
station account with admin rights. It asks for that account's password once,
since Windows needs it to run the task when nobody is logged in.

When you press a button, the console checks the action against its list and
sends back the exact command. If the action changes anything, you confirm it.
Then the console writes a job file to `C:\Nova\state\console-jobs\` and starts
the task. The task checks the job against its own list, runs it in a child
PowerShell with `NOVA_NONINTERACTIVE=1`, and sends the output to the job's log,
which the Activity panel shows as it runs. The values are passed by splatting,
so quotes in a test description can't break the command. If the job stopped
the console, the task starts it again at the end.

Only one job runs at a time. During a `deploy` the page loses the console for
about a minute and then picks the same log back up.

With `NOVA_NONINTERACTIVE` set, `Nova.ps1` runs ssh with `BatchMode` and no
`-t`, because there's no one to type a password. So the station account needs
key-based SSH to each Pi, and `admin` needs passwordless sudo on the Pis, which
is the Raspberry Pi OS default. Running Doctor from the console checks the SSH
part.

### Safety

Anything that changes state shows a confirmation with the command and a short
warning, and asks for the admin password every time. Status, Doctor and a
Publish dry run don't ask for either.

The password is prod's `AdminPassword`, the same one used for the admin role in
novaOps, so there isn't a second password to keep track of. `console.json`
only stores a salted PBKDF2 hash of it, since any local account can read that
file. Five wrong tries from one computer locks that computer out for two
minutes. If there's no hash in `console.json`, which happens with an older
one, every change is refused.

The service Start/Stop/Restart buttons don't ask for a password. A stuck
service needs to be restartable quickly in the middle of a test.

There's no free-form command box. Branches, tags and names have to match a
pattern, and text fields can't contain control characters. Running the console
with `--read-only`, or without the runner set up, makes the buttons copy the
command instead.

The console is plain HTTP, so the password goes over the LAN unencrypted. That's
only okay because the station network is isolated. Keep it that way, and change
`AdminPassword` from the example's placeholder (`doctor` warns about it).

## Upload failures

`upload_file()` now sets `CURLOPT_FAILONERROR`, so an HTTP error counts as a
failure. Every upload is logged with its URL as `UPLOAD OK` or `UPLOAD FAILED`,
and the result is saved to `/var/lib/nova/<env>/last_upload.json` for the report
to pick up. At startup novaGround logs its environment and backend at normal
verbosity and checks the backend's `/health` once. If that fails it logs a
warning and keeps going, since the backend often comes up after the Pi.

## Things we didn't do

Adding an `--env` flag to the scripts would still depend on someone passing it,
and the service has no one to pass it.

Having only `deploy` write the env file would fix prod but leave dev tests
needing a hand edit.

We could have made novaThermo always match novaGround, but the two Pis don't
always need the same changes, and a novaGround fix shouldn't have to wait on a
novaThermo build. Recording what it ran is enough to trace a recording back to
its code.

Pinning novaThermo as a second submodule would make it part of every release,
which is the opposite of what we want.

The Pis could have switched stacks on their own by reading the console's
reply. But novaGround drives relays and servos, so a background timer must
never restart it in the middle of a test.

Running `Nova.ps1` from the console service directly runs into the account and
restart problems above. Running the console service as the station account
fixes the account but not the restart, and it would put the account's password
in a WinSW XML file in plain text.

## Later

- novaGround could publish the same snapshot over MQTT, so the operator UI can
  show upload problems directly.
- Adding a third Pi should just mean adding it to `Pi.Targets` and `Hosts`.
