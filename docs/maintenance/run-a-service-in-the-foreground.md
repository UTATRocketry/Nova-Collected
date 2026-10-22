# Run a service in the foreground

When a service won't start or stay up, run the same program in a visible window
to see its error.

> [!IMPORTANT]
> Stop the service first. The foreground copy can't share the serial port or
> the broker client ID with a running service.

## Backend, frontend and FAS bridge (ops PC)

1. Read the logs first. The error is often already there:

   ```powershell
   .\ops\Nova.ps1 logs -Env prod -Only backend
   ```

2. Stop the stack:

   ```powershell
   .\ops\Nova.ps1 stop -Env prod
   ```

3. Run it in the foreground from the backend repo:

   ```powershell
   cd C:\Nova\prod\backend
   .\scripts\prod_windows.ps1
   ```

   For the dev stack with hot reload and simulated hardware, use
   `C:\Nova\dev\backend\scripts\dev_windows.ps1 -WithMock`.
4. Read the error, fix the cause, and press **Ctrl+C**.
5. Start the services again:

   ```powershell
   .\ops\Nova.ps1 start -Env prod
   ```

## novaGround (Pi)

1. Read the logs (`novaGround@dev` if dev is live):

   ```bash
   journalctl -u novaGround@prod -n 100
   ```

2. Stop the service:

   ```bash
   sudo ./nova-pi.sh stop
   ```

3. Run it interactively. `run.sh` opens a tmux session, so it keeps running if
   your SSH connection drops. It uses the same settings as the service:

   ```bash
   cd /home/admin/prod/novaGround && ./run.sh --env prod
   ```

   Add `--target novaMock` to run without hardware.
4. Fix the cause, quit (`./run.sh --kill`), and start the service again:

   ```bash
   sudo ./nova-pi.sh use prod
   ```
