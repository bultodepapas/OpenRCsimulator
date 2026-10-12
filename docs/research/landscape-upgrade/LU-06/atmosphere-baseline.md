# LU-06 — Extreme-atmosphere reset baseline

Date: **2026-10-11** · Step: **LU-06** · **Status: diagnosis complete; no physics or test code changed.**

## Comparison

I ran `test_atmosphere_flight.gd` in disposable copies using Godot 4.7.2 (`ed1daf0bf`). The native current copy and native copy with `app/sim/simulation.gd` and `app/sim/flight_session.gd` restored from `git show HEAD:` both pass **140 checks, 0 failures**. On WSL Ubuntu ext4, the current copy and the copy with those same two files restored from `HEAD` both fail with **137 checks, 1 failure**. The compact output excerpts are in the adjacent `baseline-*.log` files.

The environment case starts with a hot-high configuration, then accepts 4,000 m elevation, 45 °C, 870 hPa QNH, and 100% relative humidity. On Linux, reset attempts to refit the previous 15 m/s level start at the new density. The trim returns `ok=false` after 50 iterations with residual `0.16638981173064932`. The session records:

`atmosphere trim refused: did not converge (|residual| 0.16638981173064932)`

Reset then parks the session through `_fail_selected_start`, so `checkpoint()` is empty. The test next reads `extreme_checkpoint.format` without checking for an empty checkpoint, producing the secondary invalid-key script error. The diagnostic print used to reveal `start_error` was inserted only into scratch copies of the test; the repository test was not edited.

## Scope and reproduction

Each native scratch project was copied from the working `app/`. The native `HEAD` project was copied from the current scratch, then only its two simulation/session files were replaced from `HEAD`:

```text
git show HEAD:app/sim/simulation.gd       -> <scratch>/sim/simulation.gd
git show HEAD:app/sim/flight_session.gd   -> <scratch>/sim/flight_session.gd
```

Both native runs used the matching Windows console build and the same test script:

```text
.tools/Godot_v4.7.2-stable_win64_console.exe --headless --path .tools/landscape-upgrade/atmosphere-diagnosis-<current|head> --script res://tests/test_atmosphere_flight.gd
```

The Linux current project was copied to `/var/tmp/openrc-collision-audit-current` on WSL Ubuntu ext4 from `/mnt/c/DEVELOPMENT/OpenRCsimulator/app`. The Linux `HEAD` project at `/var/tmp/openrc-collision-audit-head` was copied from that current project and received the same two `HEAD` file substitutions. The scratch copies retained all other working-tree files, including atmosphere and trim code. Both Linux tests used:

```text
/mnt/c/DEVELOPMENT/OpenRCsimulator/.tools/Godot_v4.7.2-stable_linux.x86_64 --headless --path <scratch> --script res://tests/test_atmosphere_flight.gd
```

This comparison is limited to the collision-owned changes in `simulation.gd` and `flight_session.gd`; it shows that restoring both files to `HEAD` does not change the Linux failure. It does not establish the cause of the native/Linux trim difference in the atmosphere or trim implementation. The direct-session test installs no collision world, so the new post-step filter is inactive there.

The log excerpts omit repeated inertia warnings and the remainder of the long diagnostic start dictionary after the failure summary. In the diagnostic run, the temporary print adds two lines to the test copy, so the secondary error moves from line 184 in the unmodified test to line 186 in the instrumented scratch test.
