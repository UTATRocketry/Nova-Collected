# Nova-Collected
## Project Overview
Nova-Collected is a collection of scripts and programs designed to manage and operate the Nova ground control software. It includes:
- **Submodules**: External dependencies and reusable components.
- **Configuration Scripts**: Scripts for initial setup and running the combined applications.

## Directory Structure
```
Nova-Collected/
├── daqhats/                # DAQ HAT library and examples
├── novaGround/             # Hardware control software
├── novaOPS-back/           # Backend services for Nova Ops
├── novaOPS-front/          # Frontend services for Nova Ops
├── initial_config.sh       # Initial setup script
├── post_reboot_config.sh   # Post-reboot configuration script
├── tmux.sh                 # Tmux workspace setup script
├── update.sh               # Submodule update script
└── README.md               # Documentation
```

## Installation
```
git clone  --recursive https://github.com/UTATRocketry/Nova-Collected.git
cd Nova-Collected/
chmod +x initial_config.sh, post_reboot_config.sh, tmux.sh, update.sh
```

## Contributing
To add new submodules:
```
git submodule add <submodule url>
git submodule update --init --recursive
```

To fetch updates for all submodules use `git pull --recursive` or `git submodule update --remote <submodule-path>` for a single submodule.

To push changes to a submodule, first commit/push your submodule's changes like normal. Ex:
```
cd path/to/submodule_x
git diff
git add <stuff>
git commit -m "comment"
git push
```

Then, update the parent repo to track the updated version of the submodule:
```
cd ..
git add path/to/submodule_x
git commit -m "Update Submodule X"
git push
git submodule status --recursive
```
If you have committed a bunch of changes in various submodules you can push all changes in submodules from the parent repo with `git push --recurse-submodules=check`

Make sure all submodule commits used by the revisions to be pushed are available on a remote tracking branch.
- If `check` is used, it will be checked that all submodule commits that changed in the revisions to be pushed are available on a remote.
Otherwise the push will be aborted and exit with non-zero status.
- If `on-demand` is used, all submodules that changed in the revisions to be pushed will be pushed. If on-demand was not able to push all necessary revisions it will also be aborted and exit with non-zero status.

To remove a submodule, deinitialize the submodule and remove the submodule directory:
```
git submodule deinit -f -- path/to/submodule
rm -rf path/to/submodule
```
Then remove the submodule references by editing the `.gitmodules` and `.git/config` files to remove the submodule entry, then commit the changes:
```
git add .gitmodules
git rm --cached path/to/submodule
git commit -m "Remove submodule path/to/submodule"
git push
```