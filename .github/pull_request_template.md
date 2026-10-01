<!--
Title: type(scope): what changed   e.g.  fix(ops): keep the prod console up during deploy
Rules: CONTRIBUTING.md
-->

## What and why

<!-- One or two sentences. Link the issue if there is one: "Closes #12". -->

## How was this tested?

<!-- ops/ scripts run the ground station. Say where you ran the change:
     a throwaway copy, `-DryRun`, or the ops PC with a lead present. -->

## System impact

- [ ] Docs only
- [ ] Changes how `Nova.ps1` installs, starts, stops or deploys services
- [ ] Changes the release workflow (pin / promote / deploy / publish)
- [ ] Changes `ops/nova.settings.example.ps1` (a default, or a new setting) - each station copies it into its own `nova.settings.ps1`, then runs `install`

## Checklist

- [ ] Does **not** change `prod/`, `pi/`, `firmware`, `.gitmodules` or `releases/` (only `Nova.ps1` does; CI checks)
- [ ] Works in Windows PowerShell 5.1 (no `??`, ternaries, or PowerShell 7-only cmdlets)
- [ ] `ops/README.md` updated if a command or step changed
