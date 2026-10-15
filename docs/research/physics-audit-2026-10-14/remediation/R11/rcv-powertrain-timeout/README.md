# RCV powertrain timeout diagnosis

2026-10-15. The frozen Linux candidate's 60-second timeout was caused by running the powertrain sweep through the GDScript reference fallback when its pinned Linux native extension was not staged. It was not evidence of a solver hang or an invalid powertrain result. The same test, source, Godot binary, and 60-second cap completed with the native backend in 3.976 seconds after building and verifying the pinned extension in an isolated diagnostic copy.

The original bounded remainder log, [linux-gd-remainder-after-contact-contract.log](../linux-gd-remainder-after-contact-contract.log), records exit 124 at 60.009 seconds without an engine error. It had printed checks through 240/480 Hz braking, then entered the final high-power refinement at `test_rcv_powertrain.gd:60`. That call runs 2,880 `Vehicle.step()` ticks plus telemetry every 12 ticks (`:87-110`); it prints no intermediate progress. The exact same candidate test source then passed 9/9 with native enabled, including that convergence check.

The candidate had no `app/native/` files. In `vehicle_dynamics.gd:155-184`, the loader requires the platform binary, extension descriptor, receipt, and matching runtime identity; absent any of them it returns `null`. `_evaluate_active()` then selects the GDScript `_evaluate()` fallback (`:603-618`). The candidate's own `test_rcv_session.gd` already warns that its native backend-switch guard is skipped when the pinned backend is not staged. The pinned build instructions in `research/rc-monster-truck/native/README.md` describe Linux verification through `verify_linux.py`, which was the route used here.

The isolated pinned build passed its GDExtension load, float64 round-trip, and native/reference parity checks (50 parity cases). The staged runtime probe reported `backend=native`, ABI 1, solver `openrc-ground-vehicle-dynamics-rk4-v3`, and the expected binary/source/toolchain hashes. The unchanged frozen powertrain test then reported 9/9 checks: the 240/480 Hz stopping-distance and attitude comparison passed, high-power distance delta was `0.0000068 m`, speed delta `0.0000000 m/s`, and active/reference derivative maximum delta `0.0000000000`.

The build and test ran only in disposable output locations. The immutable candidate remained unchanged. The builder input snapshot is `410cbd7a780d3399d5f2a8712b68377bbdf5d4eb2cfa030e30719596f4772ace`; the resulting Linux x86_64 library SHA-256 is `08c8c08e74bd9c9465d1c0f732b082fc23829dcf243287eac51f25ed4e98f3a3`. Build provenance and source identities are in [verification.json](native-build-01/verification.json), and the physically copied diagnostic app staging receipt is [stage-receipt.json](native-build-01/stage-receipt.json).

Reproduce from WSL Ubuntu with literal paths and a fresh empty output directory (the recorded working directory is `/mnt/c/DEVELOPMENT/OpenRCsimulator`). The example writes to `/tmp`; the original build evidence remains unchanged:

```sh
python3 /home/bulto/openrc-r11-b09-r05b-20261014-03/research/rc-monster-truck/native/verify_linux.py \
  --source-root /home/bulto/openrc-r11-b09-r05b-20261014-03 \
  --godot /home/bulto/openrc-r11-b09-r05b-20261014-03/.tools/Godot_v4.7.2-stable_linux.x86_64 \
  --out /tmp/openrc-rcv-native-repro-20261015 \
  --jobs 2
```

The native powertrain run used the same 60-second inner timeout and a separate 65-second outer safety bound. Its command, hashes, exit status, elapsed time, and output digest are recorded in [test_rcv_powertrain-native-60s.json](native-build-01/test_rcv_powertrain-native-60s.json); the complete output is [test_rcv_powertrain-native-60s.log](native-build-01/test_rcv_powertrain-native-60s.log). The loader identity is in [backend-identity-probe.log](backend-identity-probe.log). The bounded runner and staging scripts are retained beside this note.

This is software verification on the pinned Linux toolchain. It diagnoses backend selection and confirms the existing convergence/parity assertions; it does not provide physical validation or a performance acceptance result. The library is not yet part of the next candidate; its inclusion awaits review of the candidate allowlist.
