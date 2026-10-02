# Check server health

Confirm the whole station is ready before a test, or after power-up or a
deploy. Takes about two minutes.

## Steps

1. **Power on** the network switch, then the ops PC and the Pi. Wait about
   40 seconds: every service starts on its own.
2. **Open the Nova Console**: `http://localhost:8080` on the ops PC, or
   `http://192.168.137.1:8080` from the operator laptop.
3. **Check every row is green**, including novaGround under **Remote hosts**.
   If one isn't, see [SUPPORT.md](../../SUPPORT.md#the-nova-console).
4. **Check the release.** On the ops PC:

   ```powershell
   .\ops\Nova.ps1 status
   ```

   Confirm prod runs the release you expect and dev is stopped.
5. **Run the checks:**

   ```powershell
   .\ops\Nova.ps1 doctor
   ```

   On the Pi:

   ```bash
   sudo ./nova-pi.sh doctor
   ```

   Every line should be OK.
6. **Open the novaOps UI** (`http://192.168.137.1:3000`). Engine values should
   be updating, and the Console page should show the FAS link connected.

> [!WARNING]
> Don't start a test with a red row, a failing `doctor` line, or prod on an
> unexpected release. Tell the test lead first.
