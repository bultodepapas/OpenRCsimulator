# Follow-up audit probes

The [follow-up dossier](../../../docs/research/ugly-stik-flight-physics-2026-11-15/follow-up-01/README.md) owns interpretation, exact source identity, retained observations and proposed repairs. These research tools exercise existing production classes or interpret saved evidence. They install no model/profile and change no production source. Some deliberately reproduce undesirable behavior; their own successful completion is not a product acceptance pass.

| Source | Purpose | Completion/evidence |
| --- | --- | --- |
| [input_probe.gd](input_probe.gd) | Seven injected input/mapping/calibration sequences through production classes. | `FOLLOWUP_INPUT_PROBE_JSON`, exit/check counts and explicit synthetic scope. |
| [integrations_probe.gd](integrations_probe.gd) | Two exact Electric input hashes, candidate contact validation and synthetic detector comparison. | `AUDIT_FOLLOWUP_SOURCE` records; `AUDIT_FOLLOWUP_DONE checks=30 failures=0`. |
| [modes_probe.gd](modes_probe.gd) | Production modal matrices; replicated full and projected Jacobians at three steps; trim-boundary diagnostics. | `MODES_FOLLOWUP_JSON` and `MODES_FOLLOWUP_COMPLETE`. |
| [evidence_contract_probe.gd](evidence_contract_probe.gd) | Production power-step card with a research-only 399 m safety floor. | Actual card/CSV output, `FOLLOWUP_EVIDENCE_JSON` and completion marker. |
| [tool_evidence_probe.py](tool_evidence_probe.py) | Actual wrapper and comparator against temporary child/profile fixtures; actual Python timeout. | JSON with four wrapper and five comparator outcomes. |
| [runway_evidence_probe.py](runway_evidence_probe.py) | Actual report comparison/history functions on invented metadata; image-load branch forbidden. | Exact fixture inputs and outputs; five comparison and four history cases. |
| [modes_analysis.py](modes_analysis.py) | Independent NumPy/SciPy eigensolutions and sensitivity of saved matrices. | Analysis JSON with source hash and package versions. |
| [plot_modes.py](plot_modes.py) | Plot the two separately selected real-root series from the analysis. | Standalone SVG or PNG, not a new simulation. |

## Reanalyze retained evidence without an engine

Run from the repository root with Python, NumPy, SciPy and Matplotlib available. The retained analysis used NumPy 2.3.5 and SciPy 1.17.0. Choose fresh temporary output names:

```bash
python research/ugly-stik-audit-2026-11-15/follow-up-01/modes_analysis.py \
  docs/research/ugly-stik-flight-physics-2026-11-15/follow-up-01/evidence/modes.json \
  tmp/followup-modes-reanalysis.json

python research/ugly-stik-audit-2026-11-15/follow-up-01/plot_modes.py \
  tmp/followup-modes-reanalysis.json \
  tmp/followup-modes-reanalysis.svg
```

This solves saved matrices; it cannot establish source freshness, derivative correctness or physical behavior by itself. The independent analysis uses a general nonsymmetric eigensolver, not the application's small characteristic-polynomial solver on the full matrix.

## Reproduce the Godot observations

Use the exact audited runtime, the pinned/imported Godot environment and the repository's [Godot tooling](../../../tools/godot/README.md). On an enrolled test host use its pool/slot requirements. The original execution used an isolated, unenrolled Linux workspace. A sparse or unimported checkout can fail because session dependencies include visual resources even for headless work; do not count printed numeric results from an erroring run as a pass.

From the repository root, prepare task-specific paths. These examples use the Linux executable from the original run:

```bash
AUDIT_ROOT="$PWD"
AUDIT_PROBES="$AUDIT_ROOT/research/ugly-stik-audit-2026-11-15/follow-up-01"
AUDIT_ENGINE="$AUDIT_ROOT/.tools/Godot_v4.8-beta2_linux.x86_64"
mkdir -p "$AUDIT_ROOT/tmp"
```

Run each probe through the checked runner and inspect its full receipt/log:

```bash
XDG_DATA_HOME="$AUDIT_ROOT/tmp/followup-input-userdata" \
python tools/godot/run_checked.py --timeout 120 --label followup-input \
  --out-dir tmp/followup-rerun-checks --require-text FOLLOWUP_INPUT_PROBE_JSON -- \
  "$AUDIT_ENGINE" --headless --path app --audio-driver Dummy \
  --script "$AUDIT_PROBES/input_probe.gd"

XDG_DATA_HOME="$AUDIT_ROOT/tmp/followup-electric-userdata" \
python tools/godot/run_checked.py --timeout 120 --label followup-electric \
  --out-dir tmp/followup-rerun-checks --require-text AUDIT_FOLLOWUP_DONE -- \
  "$AUDIT_ENGINE" --headless --path app --audio-driver Dummy \
  --script "$AUDIT_PROBES/integrations_probe.gd"

XDG_DATA_HOME="$AUDIT_ROOT/tmp/followup-modes-userdata" \
python tools/godot/run_checked.py --timeout 120 --label followup-modes \
  --out-dir tmp/followup-rerun-checks --require-text MODES_FOLLOWUP_COMPLETE -- \
  "$AUDIT_ENGINE" --headless --path app --audio-driver Dummy \
  --script "$AUDIT_PROBES/modes_probe.gd"

XDG_DATA_HOME="$AUDIT_ROOT/tmp/followup-floor-userdata" \
python tools/godot/run_checked.py --timeout 120 --label followup-floor \
  --out-dir tmp/followup-rerun-checks --require-text FOLLOWUP_EVIDENCE_COMPLETE -- \
  "$AUDIT_ENGINE" --headless --path app --audio-driver Dummy \
  --script "$AUDIT_PROBES/evidence_contract_probe.gd" -- \
  --aircraft=jensen-das-ugly-stik-60 --only=power_step \
  --out="$AUDIT_ROOT/tmp/followup-floor-new-output"
```

Use a new floor-card output directory. The floor probe deliberately inherits the existing card's serializers; the retained run has one NaN-to-null warning. Do not hide that warning or assume a completion marker establishes complete measurement coverage.

The JSON marker lines in each engine log are the raw structured output. Parse the suffix after the corresponding marker with a JSON parser when feeding a new modal capture to `modes_analysis.py`; retain the checked receipt and log alongside that extraction. The source embeds the **audited reference** commit in some probe labels; those labels do not dynamically inspect or certify the checkout used for a later rerun. Record actual Git/app-tree identity, dirty scope, engine hash, accepted aircraft hashes and source/probe hashes separately, as the published manifests do.

## Reproduce Python evidence boundaries

```bash
python research/ugly-stik-audit-2026-11-15/follow-up-01/tool_evidence_probe.py \
  --out tmp/followup-tool-evidence-rerun.json

python research/ugly-stik-audit-2026-11-15/follow-up-01/runway_evidence_probe.py \
  --repo "$PWD" --out "$PWD/../followup-runway-evidence-rerun.json"
```

The tool probe imports the actual flight-test wrapper and invokes the actual comparator, but substitutes child responses except for its real Python timeout. The runway probe requires NumPy/Pillow, an explicitly supplied repository and a new output file outside it; its temporary history folders are deleted after the receipt captures the outputs. It guards against image decoding. Both preserve production source unchanged. A repaired future implementation may produce different results: convert these observation fixtures into acceptance tests for the new contract rather than preserving the old defects as desired behavior.
