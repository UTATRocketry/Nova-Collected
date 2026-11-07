# Changelog

Every Nova release, newest first. A release is a set of commits of all the code
repos that passed a hardware test together (see [RELEASING.md](RELEASING.md)).

> [!NOTE]
> This file is **generated** by [git-cliff](https://git-cliff.org) from this
> repo's commit history, by the `changelog` GitHub Actions workflow, which opens
> a PR after each release. Don't edit it by hand: change `cliff.toml` instead.

Each release lists the changes to this repo (ops tooling and docs). What
changed in the code itself is in each code repo's own `CHANGELOG.md`, and the
release page links to the exact commits that were tested.

## [v2026.10.24](https://github.com/UTATRocketry/Nova-Collected/releases/tag/v2026.10.24) - 2026-10-24

### Release

- Pin v2026.10.24: Bench Test

### Features

- **ops:** switch, pin and report every Pi with the stack (#36)

## [v2026.10.22](https://github.com/UTATRocketry/Nova-Collected/releases/tag/v2026.10.22) - 2026-10-22

### Release

- Pin v2026.10.22: Bench Test

### Documentation

- add guide for working on issues and update contributing guidelines
- add guide for working on issues and update contributing guidelines (#32)

### Chores

- **github:** add issue forms
- add changelog generation workflow and initial changelog file
- add changelog generation workflow and initial changelog file (#26)
- update branch naming conventions to include 'tests/' prefix
- update branch naming conventions to include 'tests/' prefix (#31)
- **github:** make Software Elevated Privileges the default code owner
- **github:** make Software Elevated Privileges the default code owner (#33)
- update archive handling for novaGround files and improve documentation
- update archive handling for novaGround files and improve docum… (#34)

## [v2026.10.11](https://github.com/UTATRocketry/Nova-Collected/releases/tag/v2026.10.11) - 2026-10-12

### Release

- Pin v2026.10.11: cold flow test

### Fixes

- **scripts:** array handling in Clear-PathLocks and Invoke-Logs functions
- **docs:** correct image path for system overview in README
- **docs:** update documentation links and asset paths in various files

### Documentation

- Add extensive system documentation

## Before releases

- This repo used to pin `daqhats` and ran the stack with `update.sh`, Docker
  and tmux. daqhats is now installed by novaGround's `install.sh`, and the
  stack runs as Windows services (`ops/Nova.ps1`) on the ops PC and systemd
  (`nova-pi.sh`) on the Pi.
- The backend and frontend submodules moved from `prod/novaOps-back` and
  `prod/novaOPS-front` to `prod/backend` and `prod/frontend`.

