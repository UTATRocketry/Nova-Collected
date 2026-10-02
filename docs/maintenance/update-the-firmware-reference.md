# Update the firmware reference

Record that Nova is compatible with a new FAS firmware release. The firmware
is developed seperately from Nova; this repo only pins the version Nova works with.

> [!CAUTION]
> `fas_bridge.py` re-implements the firmware's wire protocol (`gs/protocol.py`)
> instead of importing it. If the protocol changed, the bridge must change to
> match **before** you pin the new firmware.

## Steps

1. Fetch the firmware changes:

   ```powershell
   git -C C:\Nova\firmware fetch
   ```

2. Compare the protocol with the version currently pinned:

   ```powershell
   git -C C:\Nova\firmware diff HEAD <their commit or tag> -- gs/protocol.py shared/protocol/
   ```

3. **If anything changed**, update the backend's `tools/fas_bridge.py` to
   match, through a normal PR into `dev`. Use a `!` PR title, for example
   `feat(fas)!: decode the new charger status`.
4. Test the new firmware with the bridge on the dev stack
   ([RELEASING.md](../../RELEASING.md#releasing-a-version), steps 1-2).
5. Record it with the next pin:

   ```powershell
   .\ops\Nova.ps1 pin -Test "integration test, new FAS firmware" -Firmware <their commit or tag>
   ```

Never commit to the firmware repo.
