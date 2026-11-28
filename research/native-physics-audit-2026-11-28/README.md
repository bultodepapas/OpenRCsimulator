# Native physics audit: reproducible evidence

This directory belongs to the [28 November 2026 physics audit](../../docs/research/native-physics-audit-2026-11-28/README.md). The audited production source is `8d4169f8febfd7d78a028eaa817414217a54f24b`. It contains audit runners, counterexamples and compact receipts, with no production physics repair.

The [refresh review](../../docs/research/native-physics-audit-2026-11-28/refresh.md) reconciles later main `4bf5b399`, preserves all original receipts and adds independent acceptance oracles. New plan wording is verified in the [refresh ledger](evidence/refresh-verification.json); the original ledger's document hashes refer to publication `d65b7334`.

## Environment and evidence levels

The selected software baseline ran on Linux x86-64 with official Godot `4.8.beta2.official.cafc17a19`, nine exposed logical CPUs, no `/dev/dri`, no configured test pool, and no admitted native simulation library. The lead owned engine launches serially. The C++ component witnesses use the actual native headers with GCC 14.2.0 and strict floating-point options. The qualified Linux package pins GCC 13.3.0; these component executables are not that package.

The first fresh resource import exhausted disposable cache capacity and is not a pass. After preparing an independent disposable cache, a fresh import passed the checked runner with no engine errors. All 27 selected baseline scripts then passed, reporting 6,527 assertions, with unchanged physics/simulation/data/native source fingerprint. One ground-vehicle native comparison was explicitly skipped. Its incidental reference timings are shared-container observations, not target-hardware or native qualification.

`source-inventory.json` inventories 272 physics/simulation/native source files and 106,404 lines. An inventory is not an assertion that every line or operating state was exhaustively reviewed. Domain reports identify actual inspection and evidence scope.

## Existing software baselines

Use a complete checkout, including aircraft authoring proofs and runtime assets. Follow the repository's [test ownership and pool rules](../../tools/testqueue/README.md), [checked runner](../../tools/godot/README.md), and [native qualification contract](../native-kernel/README.md). Do not relax a model's admission or use reference fallback as native evidence.

```bash
audit_godot="$(app/get-godot.sh)"
python3 tools/godot/run_checked.py --label physics-audit-import --timeout 600 \
  --out-dir tmp/physics-audit-import-new -- \
  "$audit_godot" --headless --path app --audio-driver Dummy --import
python3 research/native-physics-audit-2026-11-28/run_baselines.py \
  --godot "$audit_godot" --out tmp/physics-audit-baseline-new
```

The runner refuses an existing output directory or wrong editor version. `--case NAME` selects a named script; repeat it for several cases. It retains each checked report and log, verifies a completion marker, and records source and engine identities. [The compact baseline receipt](evidence/baseline.json) includes all selected cases, counts, qualifications and hashes. Report paths in the receipt are relative to a newly generated run output, not promised committed raw logs.

## Component counterexamples

These witnesses deliberately demonstrate baseline discrepancies. Their success means the old behavior was observed, not that a proposed repair passed. Their hypotheses and controls are in the domain reports and independent verification ledger. Turn the appropriate assertions into fixed-behavior regressions when implementing a correction.

```bash
python3 research/native-physics-audit-2026-11-28/probes/aerospace_probe.py .
c++ -std=c++17 -Wall -Wextra -Werror -O2 -fno-fast-math -ffp-contract=off \
  -I research/native-kernel/src \
  research/native-physics-audit-2026-11-28/probes/helicopter_probe.cpp \
  -o /tmp/openrc-helicopter-audit
/tmp/openrc-helicopter-audit
python3 research/native-physics-audit-2026-11-28/probes/drone_probe.py .
```

The aerospace wrapper uses Linux `memfd`/procfs for its temporary executable. The drone reducer requires NumPy. The C++ outputs are actual header evaluation; the drone reducer is an independently written equation/data witness. Neither is a launched native aircraft.

Run all nine specialist component groups and capture the commands, compiler, probe hashes and exact output in a fresh receipt:

```bash
python3 research/native-physics-audit-2026-11-28/run_component_probes.py \
  --out tmp/physics-audit-components-new.json
```

The first [component receipt](evidence/components.json) records successful fixed-wing, helicopter, multirotor, combustion/turbine, electric and native-engine groups. The [additional receipt](evidence/components-additional.json) records successful mechanics, mathematics and flight-controls groups. `--case NAME` selects one group. Python drivers compile the adjacent C++ source when applicable. All executable files are temporary. Synthetic allocation counts and scalar turbine refinement are intentionally distinct from installed-package or live-flight performance. The [final helicopter receipt](evidence/helicopter-final.json) repeats that component after removing one extra blank line at the probe file’s end for publication; its output is byte-identical. The original six-group receipt retains the exact earlier probe hash and run identity.

The lead also exercised the actual stock FPV production contact response:

```bash
python3 tools/godot/run_checked.py --label audit-drone-frame-energy --timeout 60 \
  --out-dir tmp/physics-audit-drone-energy-new \
  --require-text 'DRONE_FRAME_ENERGY_COUNTEREXAMPLE: 8 checks, 0 failed' -- \
  "$audit_godot" --headless --path app --audio-driver Dummy \
  --script "$PWD/research/native-physics-audit-2026-11-28/probes/drone_frame_energy.gd"
```

The [receipt](evidence/drone-frame-energy.json) preserves the rigid-body and complete rotor/body energy differences and the zero-shaft control. The contact state uses admitted stock aircraft parameters. This is a prescribed production-function witness, with no complete-session or pilot-frequency claim.

## Actual controller and airship witnesses

The lead additionally ran actual stock prepared FPV controller functions and the actual airship data loader, stage and shared reference RK4. These are counterexample checks, not repaired-behavior tests or complete flights. The [controller receipt](evidence/controls-actual.json) records 12 passing assertions; the [airship receipt](evidence/mathematics-actual.json) records 28. Airship fixtures include custom admitted cutoff, shape and gear parameters with stock or resolved controls. The more extreme near-sphere coefficient case is authoring-accepted but model-derive-refused; it is not a runnable negative-mass blimp.

```bash
python3 tools/godot/run_checked.py --label audit-controls-actual --timeout 60 \
  --out-dir tmp/physics-audit-controls-new \
  --require-text 'CONTROLS_COUNTEREXAMPLES: 12 checks, 0 failed' -- \
  "$audit_godot" --headless --path app --audio-driver Dummy \
  --script "$PWD/research/native-physics-audit-2026-11-28/probes/controls_actual.gd"
python3 tools/godot/run_checked.py --label audit-mathematics-actual --timeout 60 \
  --out-dir tmp/physics-audit-mathematics-new --require-text MATH_ACTUAL_OK -- \
  "$audit_godot" --headless --path app --audio-driver Dummy \
  --script "$PWD/research/native-physics-audit-2026-11-28/probes/mathematics_actual.gd"
```

These 48 new production-function assertions (8 contact, 12 controller, 28 airship) are separate from the 6,527 existing baseline assertions. A counterexample assertion succeeds by observing the audited discrepancy and its discriminating controls.

## Refresh acceptance oracles

Run the six additional groups without an engine:

```bash
python3 research/native-physics-audit-2026-11-28/run_refresh_oracles.py \
  --out tmp/physics-audit-refresh-new.json
```

`--case drone|propulsion|electric|mechanics|mathematics|verifier` selects one group and can be repeated. Use a fresh output path. The script records every input hash, command, stdout/stderr, exit code and compiler/Python/library identity. It compiles into disposable temporary directories. The [published final receipt](evidence/refresh-oracles-final.json) has six successful groups. The environment used Python 3.12.14, NumPy 2.3.5, SciPy 1.17.0 and GCC 14.2 with strict floating-point options. NumPy/SciPy support the drone matrix and independently refined trajectory; most other oracles use only the standard library. The electric group additionally uses the original electric probe pair and existing native headers.

These groups test false-pass controls and proposed acceptance boundaries, not implemented repairs. The electric temperature fixture is a component root solve, not a warm-cache installed session. The math phase sweep and rotor activation use scalar/equation trajectories. The new mechanics padding witness establishes geometric candidate exclusion; its incoming speed is below the ordinary nonterminal response floor. The independent verifier uses a separate rational face polynomial and literal quaternion controls. It was authored independently and the lead reproduced its exact output.

The recorded `git_head` remains `d65b7334` because the runs occurred with main merged into the working tree before the merge commit was created. Recorded case input hashes, the unchanged law trees and [refresh identity verification](evidence/refresh-verification.json) identify the actual inputs. This is separate from the original 27-suite and 48-production-assertion evidence. No new installed-native, package, hardware, pilot or target-performance result follows from these component exits.

The [hosted job receipt](evidence/hosted-ci.json) identifies successful source/editor native checks and the failed original CI aggregate, with the actual PR checkout SHA. See the [CI analysis](../../docs/research/native-physics-audit-2026-11-28/hosted-ci.md) for inherited failures, upstream corrections and unqualified release/package scope.
