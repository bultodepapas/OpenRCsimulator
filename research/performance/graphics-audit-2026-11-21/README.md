# Graphics audit reproductions — 2026-11-21

Evidence home: [graphics audit report](../../../docs/research/graphics-audit-2026-11-21/README.md). Audited application source: `57abea025f62b20233ca281d58d2acbee4ab8b8e`.

| File | Purpose |
| --- | --- |
| `calibration_probe.gd` | Synthetic witnesses against unchanged production policy functions; no rendered benchmark |
| `reproduce.py` | Reconstruct an exact source dependency closure, verify the official Linux engine, isolate user paths, invoke the checked runner and preserve strict failures |
| `cost_models.py` | Reproduce source-byte and analytical bounds; no performance measurement |
| `nitro_voice_probe.gd` | Detached unchanged NitroVoice inputs, output/state checks and component elapsed times |
| `reproduce_nitro.py` | Extract two audio sources/UIDs from immutable newer main, verify engine/fixture, preserve strict checks and validate the result artifact |

Run from repository root using a fresh absolute output directory:

```bash
python3 research/performance/graphics-audit-2026-11-21/reproduce.py \
  --out /absolute/new-empty-audit-output \
  --godot .tools/Godot_v4.8-beta2_linux.x86_64

python3 research/performance/graphics-audit-2026-11-21/cost_models.py \
  --output /absolute/new-cost-models.json
```

The reproducer is deliberately Linux x86_64 only and accepts the exact recorded official engine checksum. It selects a Forward+ fixture configuration but uses `--headless` and Dummy audio; no GPU execution or presentation is established. Production dependencies are read from the audited Git object, not patched copies or a moving HEAD. Fifteen source/data dependencies plus available UID sidecars are recorded; the temporary project has no production autoloads/plugins. Per-output XDG paths isolate the fixture's profile/cache without changing `HOME`.

Expected current evidence: fixture import and all 24 synthetic assertions pass the strict runner. The unchanged existing calibration test passes 94 assertions but emits a leaked-Node warning, so the overall reproducer exits nonzero. This is intentional preservation of a baseline failure, not an expected-success test script. See the [validation report](../../../docs/research/graphics-audit-2026-11-21/review-and-validation.md) and [retained receipts](../../../docs/research/graphics-audit-2026-11-21/policy-checks.json). Do not disable warnings or modify the extracted test to turn that receipt green.

Keep fixtures, full logs, engines, native binaries and hardware captures outside Git. The report retains bounded evidence and hashes. A future product repair needs its own source-bound tests and target-device validation; these scripts do not implement any optimization.

## Second-pass Nitro component probe

The [continued audit](../../../docs/research/graphics-audit-2026-11-21/second-pass.md) extracts `6b2228c7633a34e38cb05d92e3ca50893810e02b`. Both audio scripts match the original baseline byte for byte; the Git object must be available locally. The same official Linux engine checksum is required.

```bash
python3 research/performance/graphics-audit-2026-11-21/reproduce_nitro.py \
  --out /absolute/new-empty-nitro-output \
  --godot .tools/Godot_v4.8-beta2_linux.x86_64
```

This creates a disposable Forward+ configuration but runs headless with Dummy audio. It never constructs a player or vehicle, plays sound, renders frames or installs a native candidate. Per-output XDG paths isolate user state. Checked import and component execution are sequential with warnings treated as errors. The wrapper verifies dependency/UID, probe/configuration, runner and engine stability and validates/hashes the persisted JSON.

Expected final result: **43 checks, zero failures/warnings/errors**, 18 input/block-size rows and 41 raw elapsed-time samples per row after 22,050 generated warm-up frames. These are process-local `render()` call timings, including host scheduling, not CPU thread-time, GPU/presented frames or target-device benchmarks. The paused-voice row is a direct-API control; the real adapter skips render while paused. The 45,000-RPM row is a voice boundary above the car's 38,000-RPM ceiling. All rows are hand-authored synthetic API inputs, not captured or verified vehicle telemetry. Fuel-empty positive RPM is a permitted state combination, not proof that the complete snapshot is a vehicle output. Final silent cases use zero fuel-flow/throttle; running cases retain synthetic flow/clutch combinations. Every final input is recorded in the result. Exact PCM/state split equality covers one initial snapshot. ASCII-hex PCM hashes are identities, not comparisons across rows ending at different sample times.

Exploratory run 01 used a synthetic positive-RPM/stalled-with-fuel input, excluded from product interpretation. Run 02 corrected fuel/running flags; run 03 added receipt validation; final review identified remaining synthetic combustion fields. Run 04 corrects silent-case flow/throttle, records all inputs and is the final numeric specimen. All four receipts are retained in [second-pass-evidence.json](../../../docs/research/graphics-audit-2026-11-21/second-pass-evidence.json). These were sequential harness refinements, not randomized paired trials; no speedup is derived from their differences.
