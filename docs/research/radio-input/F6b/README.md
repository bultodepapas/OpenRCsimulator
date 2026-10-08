# F6b — Filmed latency measurement reduction

2026-10-07 · **Status: COMPLETED — offline tool verified; physical F6 acceptance remains open.** Owner: Codex latency-reduction agent. Scope: `research/radio-latency/`; no runtime, input, simulation, data or dependency changes.

## Outcome

The [tool and recording contract](../../../../research/radio-latency/README.md) reduce a campaign manifest and CSV frame annotations from the existing [F6a protocol](../F6a/README.md#owner-camera-protocol-f6-still-pending). Reports preserve condition/clip identities, attempted and excluded trials, exact input/code hashes, median and nearest-rank p95. Conditions are never pooled. Fewer than 20 usable trials is flagged; unused or fully excluded conditions remain visible.

Frame picks and acquisition-cadence bounds produce per-trial and summary intervals. Negative results remain visible. The proposed 60 Hz budget is reference metadata; no automatic hardware acceptance is made. Original video hashes and camera metadata are declared provenance, not verified video evidence.

## Derivation and limits

For the first observed frame `f` after a transition, the event lies between acquisition frames `f-1` and `f` under the stated observation model. Integer pick radius `r` expands the interval to `[f-1-r, f+r]`. Subtract the stick interval from the patch interval:

```text
d = patch_frame - stick_frame
nominal latency_ms = 1000*d/acquisition_fps
frame difference bounds = [d-1-r_stick-r_patch, d+1+r_stick+r_patch]
```

Evaluate both difference endpoints at both positive FPS bounds to obtain latency bounds, including negative/zero-crossing cases. Applying median or nearest-rank p95 separately to the lower and upper trial values gives conservative order-statistic bounds, since both statistics are coordinatewise monotonic. This allows rank changes and remains conservative for a shared clip cadence; no independence assumption or division by the square root of trial count is used.

These are conditional annotation/cadence bounds for the observed sample, not standard uncertainties, confidence intervals or population-tail bounds. Exposure, rolling shutter, scanline mismatch and physical-reference errors remain unquantified. The constant-cadence declaration must be verified from the original acquisition; playback or dropped/variable-frame material requires different tooling. The local F6a protocol is the method source; equations and synthetic fixtures here are original derivations, with no external dependencies.

## Proof

- [18 tests](tests.log): exact 240 FPS reduction, annotation radii, signed interval division with FPS bounds, even/odd median, p95 ranks 19/20 at counts 20/21, changing trial ranks, condition separation, preserved exclusions, malformed inputs, duplicate identities/events, acquisition provenance and deterministic CLI hashes/failure behavior.
- **3,000 seeded trials of the interval model**, each containing 20 observed latency events: sampled per-event timings and one shared cadence stay within all trial and median/p95 bounds. This checks interval arithmetic, not real latency or population coverage.
- [Four mutation detections](mutations.json), with a passing control: omit the one-frame quantization term, ignore cadence bounds, substitute maximum for p95, or accept 19 trials as meeting the minimum. Mutations run only on disposable copies. [Reproduction](check_mutations.py).
- [Fresh-clone proof](fresh-clone.log): 18 tests pass with only this tool overlaid on the recorded tracked baseline; the example CLI output is byte-identical to the [recorded report](example-result.json).
- Independent Luna Max review checked the interval and order-statistic derivations and the recording contract. It found that a patch transition could be reused with a different stick event; the corrected reducer refuses either reused endpoint, with regression coverage.

The [invented manifest](../../../../research/radio-latency/example.synthetic.json) and [CSV](../../../../research/radio-latency/example.synthetic.csv) contain 21 attempts, 20 usable and one explicitly excluded. Median is 47.9167 ms with annotation/cadence bounds 43.75–52.0833 ms. Nearest-rank p95 is 79.1667 ms with bounds 75–83.3333 ms. The median's bounds cross the proposed 50 ms budget: a nominal value alone cannot establish a timing margin. No original video exists for this fixture.

```sh
python3 research/radio-latency/test_reduce.py
python3 docs/research/radio-input/F6b/check_mutations.py
python3 research/radio-latency/reduce.py research/radio-latency/example.synthetic.json research/radio-latency/example.synthetic.csv
```

Only offline Python and documentation changed. The Godot suite and tick-cost measurements were not rerun; none of their runtime inputs or execution paths changed. Concurrent working-tree modifications are outside this proof.

## Next evidence

Use F6a to film the actual radio, display and identified build at each VSync/frame-cap condition. Preserve every attempt, original clips, verified acquisition cadence, frame annotations and non-quantified camera/reference limitations. Use the report for owner review; F6 remains open until those physical observations exist. Input threading and jitter settings remain measurement-led decisions.

Ready-to-paste commit message:

```text
F6b: reduce filmed input latency with explicit timing bounds

Proof: 18 tests, 3,000 seeded interval trials and four isolated mutations;
fresh-clone tests pass and example CLI output is byte-identical.
Preserve condition identities, exclusions and input hashes. Hardware F6
acceptance remains open; runtime and aircraft data unchanged.
```
