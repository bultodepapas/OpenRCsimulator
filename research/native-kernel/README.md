# NK-3 native stage evaluator

Step NK-3 of the [native-kernel scoping](../../docs/research/native-kernel-scoping-2026-10-27.md#phases-r-research-i-implementation):
a GDExtension (godot-cpp) port of the joint RK stage of the legacy prescribed-RPM Ugly Stik (`jensen-das-ugly-stik-60`),
`FlightSession._wheel_evaluate`, proven byte-identical to the GDScript reference per component and through the real
kernel tick. Build outputs stay in the ignored `tmp/native-kernel/`; `--install-app` can stage a verified Linux
library in ignored `app/native/kernel/`. The application requests native physics by default.
Unsupported or unverified configurations report a reference fallback; `--physics-backend=gdscript_reference`
selects the reference explicitly. The low-level `FlightSession` default remains reference for tools and replay.
Evidence and timings: [docs/research/native-kernel/NK-3](../../docs/research/native-kernel/NK-3/README.md).
The [promotion record](../../docs/research/native-kernel/NK-3/README.md#promotion-to-the-default-backend)
defines the supported Linux scope and separates backend qualification from display and hardware acceptance.

## Coverage expansion in progress (NK-3)

The owner expanded the goal on 2026-10-28 to every currently simulatable aircraft and supported flight condition
on Linux x86_64. The accepted Stik package remains the rollback baseline; new C++ headers are unqualified until
their component, stage, lifecycle and replay gates pass. A committed header is not production support.
Earlier references to the baseline as "electric Stik" were imprecise: its source uses legacy prescribed RPM.
The coupled electric sources belong to Turbo Lumber and X8.

| Required coverage | Integration and acceptance still required |
| --- | --- |
| Ten fixed-wing catalog aircraft, default battery and ideal variants, validated workshop models | Prepared flaps, wing polars, elevons, propeller axes; capability-based admission after exact oracles |
| Legacy, coupled electric, finite glow two/four-stroke, liquid combustion and turbine | Same-stage shaft/source rates, batteries, live fuel mass, events and stop projections |
| X-Cell helicopter | Prepared controls, drive, rotors, skid memory, body derivative; independent vehicle gates |
| Every validated weather configuration | Stage-time gusts/OU, vertical atmosphere, spatial profiles/modes/thermals and local point flow |
| Every supported start/contact and flight lifecycle | Retractable gear, soft contacts, transported wake, failures, resets, rollback and exact replay |
| Default delivery | Strict complete native fleet coverage, source-bound receipt, package tests and paired measurements |

Shared pre-tick/discrete supervision may remain GDScript under the existing kernel contract. Continuous laws
claimed as native must execute in C++; matching reference fallbacks cannot establish native coverage.

## Optional normal-flight backend

After verification and installation below:

```bash
"$(app/get-godot.sh)" --path app -- --quick-flight --aircraft=jensen-das-ugly-stik-60 --weather=calm
```

Selection is launch-time only. The Linux x86_64 route admits the stock Ugly Stik, calm weather and
the capabilities accepted by the native stage. Workshop variants, other aircraft and unsupported weather keep
the reference evaluator. The interactive flight console prints requested/actual backend and refusal reason.
Native traces record the identity in metadata; its absence denotes reference and preserves pre-integration
reference CSV bytes. In source builds, the exact verified Godot executable, binary and mirrored source/data hashes must match.
Release packages instead verify the complete executable and embedded manifest before loading their pinned sidecar.

`FlightSession` prepares a fresh stage within each reset/restore transaction and primes tick-zero context before
evaluating initial loads. Rejected starts preserve the previous helper, callbacks and physical state. Accepted
surface/lake/soft-contact setters reprepare at a boundary. Per-tick comparisons detect bypassed configuration
changes before stale coefficients can run; they do not serialize, hash or decode the model each tick.

Native checkpoints use an outer `openrc-flight-checkpoint v14` envelope carrying the backend and library identity.
Reference checkpoint formats/hashes stay unchanged. Exact replay requires that identity; explicit candidate
replay may use reference and reports `solver_changed`. A backend change during recording leaves an incomplete
diagnostic prefix. See [flight logging](../../docs/FLIGHT-LOGGING.md).

## What is ported

| Native (src/) | Mirrors (current app/ GDScript) |
| --- | --- |
| `nk_math.hpp` | `math3d.gd` shim plus engine `absf`/`maxf`/`minf`/`clampf`/`lerpf`/`wrapf` semantics |
| `nk_terrain.hpp` | `ground_terrain.gd` `sample_validated` (micro-relief, surface-table validity) and `_compose_lake`; `lake_surface.gd` terrain sampler (covered early-out, five-point stencil, bed profile) |
| `nk_wheels.hpp` | `ground_wheels.gd` `evaluate` (diagnostics off), `frame`, `coefficients`, `compressions` |
| `nk_aero.hpp` | `air_data.gd` `compute`; `ground_effect.gd` `factors`; `aero.gd` `loads` and its strip, oracle and tail laws |
| `nk_prop.hpp` | `propulsion.gd` legacy propeller: datum stage inflow, `coefficient`, `thrust_torque`, untilted `loads_from_thrust_torque`; `dynamics.gd` `rotor_momentum` |
| `nk_hull.hpp` | `hull_contact.gd` `loads` (flat and lake branches, airframe friction, shared regularization) |
| `nk_stage.hpp` | `flight_session.gd` `_wheel_evaluate`, `_ground_evaluation` (fixed gear), `_ground_up`, calm `air_data`; `dynamics.gd` `loads_from_air` without slipstream |
| `nk_kernel.cpp` | `OpenRCNativeKernel` (RefCounted): prepare, per-call and per-tick methods, probes, counters, benches |

Laws: `Aero.LOADS_LAW` `section-plane-source-weighted-wake-velocity-v2` (envelope, coupled or uncoupled strips,
ground effect, downwash lag, twist, `wing_cm_ac`, body terms, E0a2 or legacy tails); `Wheels.ROLLING_LAW`
`wheel-positive-terrain-excess-v2`; soft hull `soft-hull-spring-friction-v2` with the lake normal law.

## Contract

- `prepare_stage(config)` decodes everything once: the validated model, landing gear, surface table, lake and its
  validity, the session's prepared hull (`_hull_contact`), the layout indices, density and ground-effect reach.
  `stage_adapter.gd` `config_for(session)` builds it. `prepare_ground` and `prepare_aero` remain for components.
- `set_tick_context(aux, inputs, deflections, time_now)` once per tick: the aux the kernel installs after
  `pre_tick`, the inputs, the session's own `_deflections(aux)` (`[elevator, aileron_right, aileron_left, rudder]`)
  and `sim.time()`. `stage(body, continuous, t)` is then the joint stage: `{loads, derivative, rotor_momentum}` with
  `StringName` keys like the reference literal, or `{}` exactly where the reference returns `{}`.
- `stage_adapter.gd` `install(session, native)` swaps exactly one boundary (`sim.model.stage`, SF-08) and wraps
  `sim.model.pre_tick` to hand over the tick context; the tick transaction, pre-step, collision and observers stay
  GDScript. A refusal changes nothing on the session.
- D6: decoding refuses unknown keys in every dictionary the laws read and unported capabilities: retractable gear,
  glow, coupled shaft, turbine, liquid or finite fuel, flaps, slipstream or wash pieces, rotor dynamics or another
  stage method, tilted or non-legacy propellers, live-mass (geometry-only) hulls, and any weather that is not calm,
  uniform and settled (spatial, turbulence, vertical column, pending reset). The caller keeps the reference.

## Exactness rules (keep them when extending the port)

1. Copy the current GDScript operation by operation, including `+ 0.0` sign scrubs, grouping and branch order.
2. Every simulation value is `nk::R`: its `+ - * /` are single SSE2 instructions with the left operand first
   (inline asm). x86 returns the first operand's NaN when both are NaN; the pinned engine's GDScript evaluator is
   left-first on every path, while GCC commutes `+` and `*`. Plain `double` matched every finite result but not
   NaN signs on malformed inputs.
3. Engine C++ helpers are not the GDScript evaluator: `lerpf` computes `weight * (to - from) + from` (the pinned
   binary's NaN priority, found by the math probe).
4. `pow_` hides its exponent from constant folding (asm barrier); `build.py` refuses a library without a `pow`
   import. Transcendentals call the same glibc symbols the engine uses (NK-1).
5. Float literals must parse identically in GDScript; the oracle compiles the spellings in `literal_table()`.
   Add new literals there. GDScript's `-0.0` literal is +0.0; build -0.0 from bits in tests.
6. Dictionaries returned to the kernel use the reference's key types and order (`{loads = ...}` is `StringName`).

## Build, verify, negative control

```bash
python3 research/native-kernel/build.py --jobs 4                       # library, descriptor, receipt
python3 research/native-kernel/run.py                                  # milestone-1 component oracle
python3 research/native-kernel/run.py --script stage_oracle.gd         # stage, prop, hull, ground, D6 refusals
python3 research/native-kernel/run.py --script trajectory.gd --option ticks=14400   # + timing pairs, attribution
python3 research/native-kernel/build.py --jobs 4 --mutant              # -DNK_MUTATION negative control
python3 research/native-kernel/run.py --mutant [--script stage_oracle.gd]           # must FAIL
python3 research/native-kernel/run.py --render tmp/native-kernel/<results>.json
```

All three harnesses run with `--path app` through `tools/godot/run_checked.py`, load the extension with
`GDExtensionManager.load_extension` and the reference scripts from `app/`, so edits there are verified
automatically; `stage_oracle.gd` and `trajectory.gd` extend `oracle.gd`. Trajectory options (`--option`):
`ticks`, `pairs`, `warmup`, `samples`, `repeats`, `timing-cases`, `only=all|timing|attribution`, `skip-timing=true`.
Run one Godot process at a time under `nice`; timings on a shared VM are indicative only.

## Verification and local installation

Use `--app-library` on oracle runs to test the installed library. NK-3 must not be auto-loaded by Godot. The runner resolves
the binary from the selected descriptor and checks its receipt and SHA-256 before running. It retains the checked
Godot report, engine/binary hashes before and after, mirrored source hashes before and after, and harness hashes.
Reserved runner arguments cannot be overridden through `--option`. A negative control needs actual differing
comparisons, an orderly exit 1, and no engine/script errors; a timeout or invalid request is not mutation evidence.

`build.py --install-app` requires fresh reports for the exact binary, current mirrored sources and harness, and
the pinned Linux editor. Historical reports lacking these receipts cannot qualify an installation. The stage
oracle must actually compare at least 10,000 states across air, ground and hull domains, including malformed
inputs. Trajectory v2 must compare all five cases for at least 960 actual ticks each. Trim, runway and manoeuvre
must complete the requested length without a fault, pause or crash; only take-off and lake may end early in a
matching crash after the minimum. Native context and stage calls are checked per accepted tick. Fault injection,
checkpoint/restore and the P-51 refusal must execute their full prerequisite and comparison tapes.

Stop the editor and app before installation. The installer creates `native/kernel/.gdignore` before publishing
the descriptor and removes only NK-3's old entry from `.godot/extension_list.cfg`, preserving other registrations.
This protects the next process; it cannot undo initialization in a running process. The loader accepts only the
canonical descriptor and its exact local library, checks the engine and mirrored sources before loading, and
refuses an extension already loaded outside that check. Corrupt JSON/ABI metadata returns a clean fallback.
Do not hand-edit the descriptor or remove `.gdignore`; reinstall through the tool.

```bash
python3 research/native-kernel/test_verification.py
python3 tools/godot/run_checked.py --timeout 90 -- \
  "$(app/get-godot.sh)" --headless --path app --audio-driver Dummy \
  --script "$PWD/research/native-kernel/test_trajectory.gd"
python3 research/native-kernel/run.py --app-library --script stage_oracle.gd
python3 research/native-kernel/run.py --app-library --script trajectory.gd \
  --option ticks=14400 --option skip-timing=true
python3 research/native-kernel/build.py --install-app
python3 tools/godot/run_checked.py --timeout 90 -- \
  "$(app/get-godot.sh)" --headless --path app --audio-driver Dummy \
  --script res://tests/test_native_stage.gd
python3 tools/godot/run_checked.py --timeout 120 -- \
  "$(app/get-godot.sh)" --headless --path app --script res://tests/test_native_session.gd
python3 tools/godot/run_checked.py --timeout 90 -- \
  "$(app/get-godot.sh)" --headless --path app --script res://tests/test_native_replay.gd
```

For the first installation, omit `--app-library` from both oracle runs. All three tests must exercise their native
branches after installation; successful absent/stale-library branches establish fallback only. The Python gate
regressions run through `research/test-tools.sh`; CI also runs the library-free GDScript policy regression.
This local installation does not qualify exports, Windows, target-host timing or the full fleet. The receipt's
mirrored-source list includes the stock aircraft data but is not a manifest of every environment input; retained
results describe their recorded snapshot, and other data changes require fresh verification.

`python3 research/native-kernel/test_installation.py` exercises guarded loading and cache migration in disposable
projects using the built library and pinned editor; it does not change the app installation. CI's
`native-kernel-linux` job builds and qualifies the library, requires explicit native-success markers in all three
runtime tests, and checks a short production reference/native pair. Its diagnostics are retained on failure and
release publication depends on the job. The export job then qualifies the actual release executable as described below.

## Linux release packages

`app/export.sh` prepares the verified identity, exports the ordinary application, stages the exact native
sidecars, and tests that executable before creating the release archive. The CI export job consumes the
library and oracle receipts from `native-kernel-linux`; the other vehicle's native artifacts keep their own gates.
A local export needs the same verified inputs for both tracks. Do not manually register NK-3 as an exported extension.

The export plugin embeds `res://native/kernel/package.json` and the fixed diagnostic sources. That immutable
manifest pins the verified library, source provenance and diagnostic digests. A sidecar artifact receipt binds
the final executable (including its embedded PCK) and manifest hashes. This is consistency checking, not a
cryptographic signature. Keep `native/kernel/` beside the executable when moving the package; a missing or
altered sidecar selects reference. No runtime C++ build or source-tree access is needed.

The package gate runs the existing stage, lifecycle and exact-replay tests through
`--quick-flight --native-qualification=stage|lifecycle|replay`. It also compares typed reference/native session
fingerprints in the same executable and tests default selection, explicit reference, unsupported aircraft and
corrupted/missing sidecar fallback. Completed diagnostics must actually exercise native code; skipped or
interrupted tests do not pass. The diagnostic route accepts fixed modes, never a script path.

For a longer paired CPU measurement of a retained release:

```bash
python3 research/performance/session_baseline.py --release-executable --godot /path/to/openrc-simulator.x86_64 \
  --out tmp/nk3-release-pairs --aircraft jensen-das-ugly-stik-60 --case trim,maneuver,runway \
  --warmup-ticks 600 --sample-ticks 2400 --repeats 3 --compare-backends
python3 research/native-kernel/test_default_route.py --release-executable /path/to/openrc-simulator.x86_64
```

Run timing alone on the measured host. These headless checks do not qualify rendering at 1080p or any other
resolution, physical realism, Windows/macOS native execution, or unsupported aircraft and weather.

## C++ development tools (NK-3)

`devtools.py` reuses the locked GCC/SCons/godot-cpp toolchain and existing stage/trajectory oracles. It provides
**development-only** builds, with separate godot-cpp checkouts and objects, symbols, frame pointers and
SCons-generated `compile_commands.json`. `ubsan` instruments both bindings and NK-3 with GCC UBSan;
`profile` keeps an optimized, unsanitized library for debugger/profiler use. Neither writes into `app/`, the
regular build directory or installation receipts. Every output directory must be new and under `tmp/`.

```bash
python3 research/native-kernel/devtools.py build --mode ubsan --jobs 2 --out tmp/nk3-ubsan
python3 research/native-kernel/devtools.py check --build tmp/nk3-ubsan --out tmp/nk3-ubsan-check \
  --script all --ticks 960
python3 research/native-kernel/devtools.py build --mode profile --jobs 2 --out tmp/nk3-profile
python3 research/native-kernel/test_devtools.py
```

The check copies and imports a private app (including its existing import cache, excluding installed native
extensions), isolates XDG user-data/config/cache paths, clears inherited loader overrides, freezes the harness and
records source, helper, engine and library hashes. Allow at least 4 GiB free for each private copy. `--script all`
copies/imports once, runs stage then trajectory sequentially and stops on the first failure. Single-oracle checks
remain available with `--script stage_oracle.gd` (default) or `--script trajectory.gd`. Source changes during the
copy fail the run. Overlapping input/output paths and directory symlinks are rejected before copying. It forces
UBSan to halt, rejects sanitizer stderr even on exit zero, and retains checked-run logs, a separate amended
`diagnostic-report.json` and `summary.json`. Before copying, a disposable library constructor deliberately causes
signed integer overflow through the same engine's `GDExtensionManager.load_extension`; it must fail with that
specific diagnostic, control marker and source identity. `positive-controls.json` records the detector proof. The production library and C++ source
are never mutated. The stage check requires at least 10,000 actual states including malformed cases, and
trajectory checks require the requested seed/tick count and all fault, restore and fallback phases; literal
probes alone cannot pass. Combined checks retain per-oracle results in `summary.json.runs`.

`--mode asan` builds ASan+UBSan and also checks a heap-buffer-overflow control. It **requires a compatible
ASan-built Godot**, supplied with `check --godot /path/to/engine`. The pinned official Linux editor uses
`RTLD_DEEPBIND`, which ASan cannot support. The actual loader control rejects that combination before copying
the app. No loader shim or system-policy change is applied. An ASan-built engine is not provided or qualified
by this tool. In this mode only, GCC's matching ASan runtime is preloaded into the Godot child.

UBSan checks undefined behavior in instrumented code, not engine internals or general memory safety. ASan leak
detection is disabled. The intentional NaN/Inf corpus remains valid input for the existing numerical oracle;
the wrapper does not enable floating-point divide-by-zero traps. A passing short development run does not
satisfy the normal installation gate, fleet validation or physical validation. Run the regular builder and
verification workflow above before promotion. Timing is disabled in development checks.

Point clangd at the build's compilation database; it includes the real NK-3 translation unit, generated includes
and strict FP flags. If clang-tidy is installed, use the database without automatic fixes, for example:

```bash
clang-tidy -p tmp/nk3-profile -checks='-*,clang-analyzer-*,bugprone-*' \
  research/native-kernel/src/nk_kernel.cpp
```

Static analysis is advisory and requires its own recorded tool version; compiler errors are not a clean result.
Use stock `perf record`/`perf report` or GDB with the profile library and its descriptor. Counter access depends
on host permissions; no tool here changes system policy. Whole-oracle profiles include the reference backend,
startup and wrappers. The regular `trajectory.gd` paired timing measures the **research stage adapter**, excluding
the production session's backend configuration checks and context handoff; it cannot establish production-native
cost. Its timing and attribution paths require completed warm-up, every requested tick advancing exactly once,
no pause/fault/crash and native-stage coverage before aggregation. Timing pairs must also match a SHA-256 digest
of the initial state and every warm-up/sample tick (state, auxiliary state, continuous state, inputs, loads and
modes). Failed or divergent work has no timing summary. Unknown modes and contradictory skip options fail.
Hashing and native stats queries are outside the stopwatch but may perturb later samples; reports declare this
instrumentation. Use an otherwise idle host and a separately qualified production-path benchmark for runtime
performance decisions.
Sanitizer/profile overhead and shared-host measurements do not qualify target performance or 1080p rendering.

Design sources and bounded execution evidence: [tooling research](../../docs/research/native-kernel/NK-3/tooling-research-2026-10-28.md).

## Windows design note (not built)

MSVC x64 has no inline assembly, so rule 2 needs another left-first mechanism there; none is verified yet:

1. **Preferred:** build the Windows library with MinGW-w64 GCC, like the official Godot Windows binaries. The same
   `nk::R` asm applies, and the extension links the same CRT math as the engine, which may restore NK-1's
   same-library identity. Verify with these oracles on a Windows host.
2. MSVC with a tiny MASM object exporting `nk_add/sub/mul/div(xmm0, xmm1)`: guaranteed operand order, at a call per
   operation (roughly 1–2 µs more per stage). Intrinsics such as `_mm_add_sd` do not guarantee operand order.
3. If neither proves identical, D3's tolerance tier applies on Windows: NaN-sign differences occur only on outputs
   the kernel rejects anyway, so NaN-class equality plus bit identity of finite outputs would be the criterion.
