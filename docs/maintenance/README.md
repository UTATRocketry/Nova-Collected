# Maintenance

Step-by-step procedures for keeping the ground station running. Each file is
one procedure: follow it top to bottom.

> [!TIP]
> Something broken and you don't know why? Start with
> [SUPPORT.md](../../SUPPORT.md#troubleshooting), which points to the right
> procedure for each symptom.

## Routine

| Procedure                                     | When |
| --------------------------------------------- | --------------------------------------------- |
| [Check server health](check-server-health.md) | Before every test, after power-up or a deploy |
| [Archive recordings](archive-recordings.md)   | After a session that wasn't pinned |

## Fixing problems

| Procedure | When |
|---|---|
| [Run a service in the foreground](run-a-service-in-the-foreground.md) | A service won't start or stay up |
| [Restore an old config](restore-an-old-config.md) | A calibration was changed or lost |

## Changes

| Procedure                                                         | When                                               |
| ----------------------------------------------------------------- | -------------------------------------------------- |
| [Change server settings](change-server-settings.md)               | A port, IP, COM port or the admin password changes |
| [Update the firmware reference](update-the-firmware-reference.md) | The new firmware is released                 |

## Releases

Releasing, hotfixes and rollbacks have their own guide,
[RELEASING.md](../../RELEASING.md):

- [Release a version](../../RELEASING.md#releasing-a-version)
- [Capture an on-site hotfix](../../RELEASING.md#on-site-hotfix)
- [Roll back](../../RELEASING.md#rolling-back)
