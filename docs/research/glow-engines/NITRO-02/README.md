# NITRO-02 — Installed two-stroke and four-stroke candidates

2026-10-13. **Both engine families are implemented and playable as experimental installations. Physical/pilot and release acceptance remain open.** [Operating/configuration guide](../../../GLOW-ENGINES.md), [plan](../../../plans/RC_NITRO_ENGINE_REALISM_PLAN.md), [2T calibration dossier](../NITRO-2T/README.md), [4T calibration dossier](../NITRO-4T/README.md), [audio evidence](../NITRO-audio/README.md).

## Implemented and tested

- Separate ported 360° and valve/intake/pumping 720° mean-cycle kernels, independent maps and fuel accounting; no family-wide power or efficiency multiplier.
- Closed finite-fuel aircraft extension; manufacturer-constrained candidate engine profiles and two generated propeller combinations per family. Exact engine/installation bytes participate in identity and replay.
- RK-stage engine/propeller/body coupling; a passive annular propeller surrogate; forward windmill breakaway, stopped drag and visible refusal of unsupported reverse rotation.
- Transport-driven mixture, servo/charge/fuel response, temperature feedback, opportunity/success counters, warm starter, cut, stall, overheating and exact nonnegative tank exhaustion.
- Fixed-body-datum variable mass/CG/full inertia with co-moving efflux; independent force/momentum fixtures, no phantom inertia-derivative torque.
- Separate catalog selections, stable Stik renderer adapter, mixture/cut/start controls, telemetry, versioned checkpoints and trace recording, procedural 2T/4T native sound.
- Propeller diameter drives the rendered blade/blur, aerodynamic load and inventory. Relative shaft inertia includes the full inventory propeller polar plus estimated crank inertia; changing props changes their acceleration and gyroscopic contribution.

The ground solver correctly refused stationary idle starts when calculated idle thrust exceeded the wheels' static hold. Glow runway starts therefore use a stopped warm engine; explicit starting releases the aircraft into ordinary force-driven rolling. The software test commands full throttle, then elevator after three seconds, and checks both installations climb. It does not fit or validate a real takeoff distance.

## Retained software evidence

- [Verification manifest](verification.json) and [test output](verification.log): **632/632 commands pass**, including 566 GDScript parses, independent source/installation checks, both families and legacy/electric/turbine regression coverage. The complete installed-session test passes 132 checks across four engine/propeller configurations; legacy propulsion retains 25,001 byte-exact comparisons. Existing flight goldens were not re-recorded. The `app/test.sh` float64 state guard and `git diff --check` also pass.
- [Refinement report](refinement.json): 36 runs, six scenarios per family at 240/480/960 Hz; all 12 paired cases meet every declared budget. Worst 240-versus-960 mean-cycle trajectory discrepancies are 0.000505% normalized RPM, 0.000607% shaft work, 0.000336% fuel and 0.000114 K temperature. These figures measure numerical agreement within the same reduced model.
- [Deliberate formula defects](mutations.json), [output](mutations.log): unchanged control passes; 2T cycle-angle, 4T opportunity-frequency, premix-oil and valve-loss mutations fail the independent oracle on disposable copies.
- [Compiled PCK](pack.json), [native Windows](native-windows.json) and [Linux under WSL](native-linux.json): both engine families each emit 721 finite samples over three seconds, consume fuel and advance successful-fire counters. They run from an empty directory with no loose-source fallback. Binary/pack and trace hashes are retained. The [three-platform export record](platform-exports.json) also records macOS universal slices, ad-hoc signatures and version-field checks; macOS execution was not tested. The template archive passed the exact SHA-512 pinned in `app/get-templates.sh`. These are working-tree candidate exports, not published releases.
- [Audio evidence](../NITRO-audio/README.md): 38 direct-renderer and native software-mixer checks pass, including physical phase/count reconciliation, 2T/4T firing/blade orders, cut/restart and rich-2T distinction. Authored timbre and Dummy-driver capture do not qualify real acoustics or speaker output.
- [Long-duration stand](endurance.json), [per-second log](endurance.log): full throttle, nominal mixture, 0.12 kg initial fuel, 240 Hz. MAX-55AX exhausted its tank at 292.408 s; FS-64V remained running at the 600 s bound with 0.0002134 kg. Both stayed finite, never accepted negative fuel and reported no simulator fault. Head-temperature proxies reached approximately 472.9 K and 433.4 K respectively. These are inferred-model results, not comparative manufacturer endurance or temperature claims. The artificial stand restores body position/attitude/velocity after each accepted tick; engine states evolve continuously, but support impulses preclude treating its work trace as a free-flight or physically constrained dynamometer energy balance.

## Reproduce

From the repository root (Windows; use the same pinned Godot on other platforms):

```powershell
python research/glow-engines/build_profiles.py --check
python research/glow-engines/build_installations.py --check
python research/glow-engines/verify_integration.py --godot .tools/Godot_v4.7.2-stable_win64_console.exe --out C:/temp/glow-proof --parse-all
& ./.tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --script ../research/glow-engines/flight_bench.gd -- --hz=240 --out=C:/temp/glow-240.json
```

Repeat the flight experiment at 480 and 960 Hz. Run timing separately from other test processes. The experiment records each family's cruise, throttle-up/down/cut, rich mixture, lean mixture, exhaustion and takeoff trajectory. Output is model-generated evidence, not observed engine or aircraft data.

`python research/glow-engines/refinement_report.py --check` verifies the retained trajectories, exact configuration identities and regenerated report. `packaged_smoke.py --godot <editor> --pack <exported.pck> --out <fresh-directory>` checks compiled resources; use `--godot <exported-executable> --exported` for a native application. `mutations.py --godot <editor> --out <fresh-directory>` reproduces the disposable formula faults.

The standalone `endurance_bench.gd` runs from `--headless --path app --script ../research/glow-engines/endurance_bench.gd`; it takes minutes and refreshes the canonical endurance JSON/log. `-- --validate-only` checks both initial setups without running the long experiment.

## Interpretation and remaining gates

The manufacturer rated power/RPM points constrain both profiles. MAX-55AX APC12×7 additionally has a single-condition static RPM observation used for a **conditional** surrogate-chord fit; the alternate APC13×6 is an inference, not a held-out measurement. FS-64V uses its own manufacturer constraints and analogous four-stroke research, with inferred shape/transients/thermal/propeller coefficients. The two dossiers retain disagreements, assumptions and uncertainty. This implements the user's permission to infer missing parameters; it does not relabel estimates as measured calibration.

Changes from the dated NITRO-01 fixture include FS-64V low-RPM torque hypotheses, an inferred high-RPM unloading tail, rich-combustion zero-completion support, and explicit manufacturer recommended versus numerical supported maxima. Old source hashes and standalone evidence remain historical, not silently refreshed.

Mean-cycle refinement is not a crank-angle pressure/compression oracle. Mechanical high-frequency torque ripple, measured vibration/mount response, propeller side-force/P-factor/wake qualification, full propeller data coverage, matched real-engine transients/flow/temperature, flight observations and experienced-pilot trials remain unclosed. The measured native debug-build physics cost exceeds the plan's 500 µs release target. Neither family is certified physically validated or release-qualified by these software checks.
