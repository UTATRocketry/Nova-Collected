# Deployment

Putting Nova onto the ground station's machines, and the reference for the
commands that run it. To release or deploy a new version, see
[RELEASING.md](../../RELEASING.md).

## Setting up a machine

Do these in order for a new station.

| Step | Guide                                                                               |
| ---- | ----------------------------------------------------------------------------------- |
| 1    | [server-setup.md](server-setup.md): Windows server, services, settings              |
| 2    | [novaground-setup.md](novaground-setup.md): novaGround on the GSS Pi                |
| 3    | [operator-laptop-setup.md](operator-laptop-setup.md): shortcuts, nothing to install |
|      |                                                                                     |

## Reference

| Document                             | Look here for                                   |
| ------------------------------------ | ----------------------------------------------- |
| [commands.md](commands.md)           | Every `Nova.ps1` and `nova-pi.sh` verb and flag |
| [network.md](network.md)             | IP addresses and ports                          |
| [server-layout.md](server-layout.md) | Where config, data, logs and services live      |

> [!WARNING]
> Before the stack leaves the bench, check that `AdminPassword` in the ops PC's
> `ops\nova.settings.ps1` isn't the example's placeholder. `doctor` warns if it
> is.
