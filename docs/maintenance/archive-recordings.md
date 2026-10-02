# Archive recordings

Turn finished recordings into self-contained bundles (data, config and
metadata together) that can be understood without the station.

> [!NOTE]
> `Nova.ps1 pin` does this automatically. Run it by hand to archive recordings
> from a session that wasn't pinned, for example a calibration run.

## Steps

1. Make sure data saving is **stopped** in the UI, and wait a minute.
   `archive` skips recordings that are still running or stopped less than
   60 seconds ago, so novaGround has time to upload its files.
2. On the ops PC:

   ```powershell
   .\ops\Nova.ps1 archive
   ```

3. Check the bundles in `C:\Nova\archive\<env>\<recording>\`. Each has `data\`,
   `config\`, `meta.json` and, written last, `bundle.json`.

   > [!WARNING]
   > `archive` currently misses novaGround's files. Copy
   > `C:\Nova\data\<env>\novaGround_<recording>_*.csv` into the bundle's
   > `data\` folder by hand ([known issue](../../SUPPORT.md#known-issues)).

> [!IMPORTANT]
> A bundle without `bundle.json` is incomplete (the archive was interrupted).
> Run `archive` again.

4. Copy the bundles you need to the team's shared Drive by hand. Automatic
   upload is planned ([ROADMAP.md](../../ROADMAP.md#future-considerations)).

The bundle format is described in
[configs.md](../architecture/configs.md#recordings).
