# UI-06c-R1 — package refresh after checkpoint repair

2026-10-08 · **Status: complete; verified packages installed in `dist/`.** Software delivery only. Pilot handling, target-machine performance and physical acceptance remain open.

## Build identity

The frozen working-tree build is `v0.1.0-rc6-4-gce4a80c-dirty`, based on `ce4a80c4774dd4c398e6f8ae55f82e63e111a691`. It includes the [UI-06a-R1 checkpoint-origin repair](../UI-06a-R1/README.md), plus the concurrent G2-R1 propulsion and DATA-2b aircraft-loader work already present when copied. This step does not edit those runtime files.

The [source manifest](source-sha256.json) records 617 application inputs. Export and tests use the same frozen copy, with the pinned Godot 4.7.2 and existing export templates. The exported Linux executable SHA-256 is `9f245fb183e9ae68ef13d9b587bf2e27a6f1980cb00e559da22efc2a8f18b0d2`. ZIP checksums are in [SHA256SUMS](SHA256SUMS); the complete [export log](export.log) retains packaging checks.

## Checks

Full `app/test.sh` on the frozen source exited 0: all scripts parsed, 125 GDScript test processes passed, trace/model checks passed, and final state hashes matched at 30/60/144 fps. The [suite log](app-test.log.gz) and [verification manifest](verification.json) retain the result. All copied `dist/` files match the tested package hashes; the live app also matched all 617 frozen inputs at installation.

- Linux, Windows and universal ad-hoc-signed macOS exports pass their existing field/resource, numeric-version, bundle and Linux trimmed-flight checks.
- The [pack checkpoint probe](check_checkpoint_pack.gd) dynamically loads the compiled session from each package in an empty project. All three packs restore both cross-start directions, retain the exact physical checkpoint and reset recipe, and declare unknown launch origin. The prior Linux package fails exactly the two repaired-origin assertions: the probe detects the missing repair. [Results](pack-checks.json).
- The [real Linux GUI smoke](evidence/export-smoke.json) passes Home → runway, native W input, R and Pause → Restart, and Recorder metadata/first-row agreement. The manual trace has 433 rows over 1.8 simulated seconds, reaches 0.8 throttle command, moves 2.036 m east and ends at 4.537 m/s horizontal speed. This is an input/taxi smoke, not a successful takeoff or handling rating.
- Stik and Extra source/export CLI traces each have 481 rows and match exactly at CSV precision. Both start airborne while runway is saved; direct routes preserve settings bytes. Quick flight and scripted capture pass. Screenshots of [Home](evidence/home-runway.png) and [flight](evidence/flight-taxi.png) were inspected.

The empty-project probe explicitly sets both Engine and ProjectSettings to the app's 240 Hz contract. Mounting a pack alone does not apply its project configuration; the empty host's 60 Hz default correctly triggered the gear-stability guard in the first probe attempt. This was a harness setup error, not an exported-app failure.

## Reproduce

Build with `app/export.sh`, then run the existing native-input harness:

```sh
.tools/visual-venv/bin/python docs/research/menu-investigations/UI-06c/run_export_smoke.py \
  --binary dist/linux/openrc-simulator.x86_64 --out /tmp/runway-package-smoke
```

To check the repair in the Linux pack from an empty host:

```sh
runway_empty_project=$(mktemp -d)
$(app/get-godot.sh) --headless --path "$runway_empty_project" \
  --script "$PWD/docs/research/menu-investigations/UI-06c-R1/check_checkpoint_pack.gd" \
  -- "$PWD/dist/linux/openrc-simulator.x86_64"
```

Pass the Windows executable or the extracted macOS `.pck` as the final argument to inspect their compiled resources. These checks run the pack under the pinned Linux editor; only the Linux release executable received a native launch test. They do not establish native Windows/macOS operation.

Use the existing [pilot flight card](../UI-06c/FLIGHT-CARD.md) with this build's exact executable/input hashes. Preserve the original UI-06c evidence as historical proof for its earlier binary.
