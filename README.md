# APF Cassette AutoLoader — Step 3.4

This build fixes the batch-file regression introduced by version 0.3.3.

## Cause

Version 0.3.3 relied on MAME's machine-reset notifier to identify `apfimag`.
With some command-line and frontend launches, that callback occurs before the
running driver is fully available. The plugin therefore remained silently
inactive and never processed frames.

## Fix

Version 0.3.4:

- Remains completely silent on non-APF systems.
- Detects `apfimag` from the running frame loop instead of depending on reset
  timing.
- Initializes the plugin once the APF driver is genuinely available.
- Automatically starts one loading attempt when:
  - the driver is `apfimag`;
  - a cassette is mounted; and
  - natural-keyboard posting is ready.
- Waits approximately three seconds before beginning, allowing the BASIC
  cartridge screen to initialize.
- Retains the manual menu start and abort commands.

## Test

Launch the same batch file that mounts the BASIC cartridge and cassette.

Expected sequence without opening the plugin menu:

```text
BASIC screen appears
CLOAD is typed
Tape begins playing
Second Return is sent
Program loads
RUN is typed
Game starts
```

For unrelated MAME systems, no `[APF AutoLoader]` lines should appear.

If it stops, report the final `[APF AutoLoader] Loader state:` line and what was
visible on the emulated screen.
