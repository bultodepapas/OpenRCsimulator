# L7 — Far forest patches

Date: 2026-10-07. Status: far-forest implementation and focused validation complete; owner-hardware performance and Gate L review remain open.

## Result

The default field keeps the original 480 L6b trees and adds 1,200 generated trees in twelve 100-tree patches. Far tree centers use a 0.25 m grid, a 55 m patch radius and a 600–1,500 m placement band. The realized centers span 650.38–1,462.30 m. Every patch retains the two existing crown-cleared gaps and the runway/mown flight corridor. Positions are `derived` visual estimates, not surveyed forest geometry.

The near positions are unchanged: SHA-256 `9b42b61ff36e5df25ef0245702e4d75965ea805f81de56a1c353fd1f0c722875`. The far-position digest is `7c8ee96a60c22241ea1f58f0fdadcba6c010e540c6d9f0fe82b7bbe10d9b442c`; the combined digest is `772d1207da670718c575c20e5b6246d8d2e6e7cdf70e006e006642c9e95ff2f3`. The existing Quaternius Standard CC0 atlas and six-triangle cards are reused; no new source asset or license was added.

The near and far instances share the existing eight sector MultiMeshes. Far instances form a suffix per sector, identified by `near_instance_count` and `far_instance_count` metadata for capture tools. The position pack offset is +8192, which exactly covers the expanded N/E range through Compatibility's 16-bit custom-data path. The CPU and shader preserve the original +2400 identity hash for all L6b positions and use an extended hash offset only when a coordinate falls below that original domain. Five frozen identity samples guard the near hash.

The tree shader raises alpha gently with screen-space mip footprint for far instances only. Near cards keep their L6b alpha behavior. In the real OpenGL review, all 1,680 tree identities matched the CPU mirror: maximum height error 0.000489 m and yaw error 0.000123 rad after the probe's quantization. The twelve fixed views repeated byte-for-byte. Vegetation cost stayed at 2–8 visible draws and zero shadow draws; the overhead view showed all eight sector draws. This software-renderer result does not establish owner-GPU frame time.

## Reproduction

```sh
python3 tools/trees/test_place.py
python3 tools/trees/place.py --check
$(app/get-godot.sh) --headless --path app --audio-driver Dummy --script res://tests/test_far_forest.gd
$(app/get-godot.sh) --headless --path app --audio-driver Dummy --script res://tests/test_treeline_data.gd
$(app/get-godot.sh) --headless --path app --audio-driver Dummy --script res://tests/test_treeline.gd
python3 tools/trees/check_review.py --app app --godot "$(app/get-godot.sh)" --out /tmp/l7-forest-review
```

The OpenGL report records every GPU identity sample and the capture hashes in [forest-review.json](forest-review.json); the packed bit readback is [forest-hash-probe.png](forest-hash-probe.png). The comparison command writes two complete repeat sets under `/tmp/l7-forest-review` and fails on any mismatch, error, more than 24 visible vegetation draws or any tree shadow draw.
