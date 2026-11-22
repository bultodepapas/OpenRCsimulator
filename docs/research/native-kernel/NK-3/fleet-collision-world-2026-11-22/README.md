# NK-3 runway reset evidence after the scenery collision change

The Linux fleet policy passed all 598 checks against source `85a2475f`. It failed 16 checks against `847d8d1a`, whose tree includes the changed scenery and collision geometry from `843f357c`. The trajectory policy still passed all 130 checks. The fleet test reproduced the failure without running the offline Python suite. For each of eight crosswind runway configurations, both the typed reference-reset check and the paired-refusal check rejected the previous live-configuration digest. [Hosted integration job](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/45079559400/job/137385028525)

The two captures cover P-51D with the ideal battery, Avanti with the ideal battery and Turbo Lumber with each of the pack and ideal batteries. Each battery choice was tested with soft hull enabled and disabled. Each baseline observation matched its V6 digest. The Linux editor was Godot 4.8 beta 2, engine commit `cafc17a192acf67903910a68aeb3c076c0907a4b`. The source identities, editor digest, file checksums and test results are in the [validation record](source-validation.json).

The existing typed comparator performed 460 checks with zero failures. Across all eight rows, the refusal reason, physical state frame, configuration payload, reset outcome and reference ownership were byte-identical. Each live-configuration array changed at exactly two positions. Index 2 is the checkpoint configuration hash, which incorporates world identity. Index 7 is the digest of the detached collision world. The V7 table changes only the expected live digest for those eight reset cases. Its evidence covers a Linux reference-owned reset before native execution. Native flight, companion-route clearance and hardware acceptance have separate qualification paths. [Paired comparison](fleet-comparison.json) · [Original comparator](../fleet-collision-world-2026-11-18/compare_fleet.gd)

## Reproduce the comparison

Decompress the two retained captures into a fresh directory. From the repository root, run the original comparator with the verified pinned Linux editor and an imported app project. The commands below use Bash.

```bash
set -euo pipefail
repo_root=$(pwd)
evidence="$repo_root/docs/research/native-kernel/NK-3/fleet-collision-world-2026-11-22"
comparator="$repo_root/docs/research/native-kernel/NK-3/fleet-collision-world-2026-11-18/compare_fleet.gd"
work=$(mktemp -d)
godot=$("$repo_root/app/get-godot.sh")

gzip -dc "$evidence/baseline-fleet.json.gz" > "$work/baseline.json"
gzip -dc "$evidence/candidate-fleet.json.gz" > "$work/candidate.json"
OPENRC_AUDIT_LEFT="$work/baseline.json" OPENRC_AUDIT_RIGHT="$work/candidate.json" \
  OPENRC_AUDIT_COMPARISON="$work/comparison.json" \
  python3 "$repo_root/tools/godot/run_checked.py" --timeout 90 --out-dir "$work/checks" \
    --label runway-comparison --require-text 'DR19E_FLEET_COMPARISON checks=460 failures=0 cases=8' -- \
    "$godot" --headless --path "$repo_root/app" --audio-driver Dummy --script "$comparator"
```

To regenerate the observations, use separate clean, imported checkouts at the two full source revisions in the validation record. Set `source_root` to the relevant checkout, use the same verified Linux editor, and choose a fresh output path per revision. Capture the candidate at its recorded pre-renewal revision so the observation also records whether V6 accepted it.

```bash
capture_dir=$(mktemp -d)
OPENRC_FLEET_SCRIPT="$source_root/research/native-kernel/fleet.gd" \
  OPENRC_AUDIT_CAPTURE="$capture_dir/observation.json" \
  python3 "$repo_root/tools/godot/run_checked.py" --timeout 90 --out-dir "$capture_dir/checks" \
    --label runway-observation --require-text 'FLEET_CAPTURE cases=8' -- \
    "$godot" --headless --path "$source_root/app" --audio-driver Dummy --script "$evidence/fleet_capture.gd"
```

The capture observer now frees its temporary Fleet instance after writing. Fleet extends `SceneTree`, so the earlier observer's `Node` check skipped cleanup and the checked runner flagged leaked resources at shutdown. Both corrected captures passed the checked runner and reproduced the earlier observers' JSON byte-for-byte. The comparator is the original file from 2026-11-18. [Capture observer](fleet_capture.gd) · [Baseline capture](baseline-fleet.json.gz) · [Candidate capture](candidate-fleet.json.gz)
