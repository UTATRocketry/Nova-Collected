# Restore an old config

Bring back a calibration or config the station used before: the one from a
particular day, a particular recording, or a particular release.

## 1. Find the hash you want

Pick the source you know:

- **A date or time:** search the history log on the ops PC.

  ```powershell
  Get-Content C:\Nova\config\history\history.jsonl | Select-String '2026-10-04'
  ```

  Each line has a `hash`.
- **A recording:** open `C:\Nova\data\<env>\<recording>.meta.json`. The
  `config` list has the hash of every config used during it.
- **A release:** the config it was tested with is in
  `C:\Nova\releases\<tag>\config\`. Skip to step 3 and use that file.

## 2. Find the snapshot

```powershell
Get-Item C:\Nova\config\history\snapshots\<hash>.yaml
```

## 3. Load it

Pick one:

- **From the web interface (recommended):** on the **Config** page, upload the
  snapshot file. It's validated, made the active config, and recorded in the
  history.
- **By hand, with the backend stopped:** copy it over the live file, then
  restart.

  ```powershell
  .\ops\Nova.ps1 stop -Env prod -Only backend
  Copy-Item C:\Nova\config\history\snapshots\<hash>.yaml C:\Nova\config\prod\system.yaml
  .\ops\Nova.ps1 start -Env prod -Only backend
  ```

> [!NOTE]
> Nothing is lost either way. The config you replaced is already in the history
> under its own hash.

## 4. Check

Open the **Config** page and confirm the sensors and calibrations are the ones
you expected.
