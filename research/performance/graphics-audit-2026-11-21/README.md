# Graphics audit reproductions — 2026-11-21

Evidence home: [graphics audit report](../../../docs/research/graphics-audit-2026-11-21/README.md). Audited application source: `57abea025f62b20233ca281d58d2acbee4ab8b8e`.

| File | Purpose |
| --- | --- |
| `calibration_probe.gd` | Synthetic witnesses against unchanged production policy functions; no rendered benchmark |
| `reproduce.py` | Reconstruct an exact source dependency closure, verify the official Linux engine, isolate user paths, invoke the checked runner and preserve strict failures |
| `cost_models.py` | Reproduce source-byte and analytical bounds; no performance measurement |

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
