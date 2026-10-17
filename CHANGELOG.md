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

## Before releases

- This repo used to pin `daqhats` and ran the stack with `update.sh`, Docker
  and tmux. daqhats is now installed by novaGround's `install.sh`, and the
  stack runs as Windows services (`ops/Nova.ps1`) on the ops PC and systemd
  (`nova-pi.sh`) on the Pi.
- The backend and frontend submodules moved from `prod/novaOps-back` and
  `prod/novaOPS-front` to `prod/backend` and `prod/frontend`.

