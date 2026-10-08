# VAL-8b — Complete-roll video timing

**Status:** offline measurement tool; synthetic verification only. Real flights and matched simulator comparisons remain VAL-8. Python 3.10+ standard library; no app, aircraft-data or coefficient writes. [Evidence](../../../docs/research/validation/VAL-8b/README.md).

```sh
python3 research/validation/roll-video/test_reduce.py
python3 research/validation/roll-video/check_mutations.py
python3 research/validation/roll-video/reduce.py \
  research/validation/roll-video/example.synthetic.json \
  research/validation/roll-video/example.synthetic.csv
```

The CLI emits deterministic JSON to stdout or `--output report.json`. Invalid input exits 1 without a report and preserves any existing output. The CLI is the sole provenance-bearing entry point: it verifies the declared video hash against `--video original-clip` and includes exact campaign, CSV, video and reducer SHA-256 hashes. The pure `reduce()` function performs calculations for tests; it does not authenticate file identities. No video decoding or automatic tracking is performed.

## What is measured

Time an integer number of complete rolls between repeated **physical phase events**, such as the same distinguishable top-side/upright phase. Enter a cumulative signed turn index at each event. Positive means right wing down about the forward body axis, not clockwise on a camera image. Turn-index and frame origins are arbitrary and cancel; frame numbers must still index the original clip from zero. Intermediate annotations may be omitted if the full turn count remains known. An interval with an annotated reversal or repeated turn index is refused; unannotated reversals cannot be detected.

For capture cadence F, frame difference n and signed turn-count difference k:

- Duration = n/F (no inclusive `+1` frame).
- Mean period = n/(F·|k|).
- Signed turn frequency = kF/n.
- Mean completed-roll rate = 360kF/n degrees/s.

These are averages over the annotated cycle(s), including any acceleration. They do not measure instantaneous body angular rate `p`, roll-mode damping, control derivatives or screen-projected attitude. Changing flight direction and pitch can separate roll-phase timing from body-axis rate. Do not compare this value directly to a roll-decay pole in the modal dashboard. A physical comparison needs the same maneuver definition, commands, airspeed, configuration and flight conditions. No steady-rate claim follows just from counting complete turns.

## Prepare observations

The example's events, uncertainty values and declarations are **invented**. Replace them with actual observations and documented uncertainty sources for measured evidence.

1. Preserve the original video and identify aircraft, control/rate settings, fuel/CG/prop configuration, maneuver commands and flight conditions. Record unknown conditions explicitly; this reducer cannot infer them.
2. Establish the original capture cadence from an identified timing calibration. File/playback FPS can differ for slow-motion recordings. Verify constant cadence and original one-to-one captured frames: dropped, duplicated, interpolated, edited or variable-cadence clips are unsupported. Do not set `original_cfr_verified` from container FPS alone.
3. Define a visible repeatable phase marker that distinguishes top/bottom and left/right, resolving 180° symmetry and perspective ambiguity. Confirm every complete intervening turn and its body-axis sign. `same_phase_verified` includes assessment of camera/viewpoint changes: an apparent repeated silhouette alone is insufficient. If count, sign, phase or visibility is ambiguous, refuse that interval rather than assigning Gaussian uncertainty to an integer count.
4. Pick zero-based original frames and estimate event timing standard uncertainty in **frames**. Include exposure/blur, finite frame selection, phase-pick ambiguity and relevant observer errors. Record their derivation in `annotation.source`; uncertainty is not automatically half a frame. Event residuals must be independent of one another and of the clock error for this model. Shared unmodeled annotation biases require a different error model, not a false independence declaration.
5. Set `evidence` to `measured`, compute the original clip's SHA-256, and supply that clip with `--video`. A matching hash proves byte identity only, not content, timing or measurement validity.

## Input contract

Strict JSON: unknown/missing fields, duplicate keys, nonfinite numbers, numeric booleans and strings are refused. Use the example as the complete field template.

| Object | Required fields / meaning |
| --- | --- |
| Campaign | `format: openrc-roll-video v1`, `evidence: synthetic` or `measured`, nonempty `aircraft`, `configuration`, `conditions`; `video`, `annotation`, nonempty `intervals` |
| Video | `source`, `sha256` (lowercase 64-hex; null only for synthetic), positive integer `frame_count`, rational cadence `capture_fps_num` / `capture_fps_den`, nonnegative `fps_relative_u`, `original_cfr_verified: true`, `timing_source` |
| Annotation | `source`, `phase_definition`, and exact `true` values for `sign_verified`, `complete_turns_verified`, `same_phase_verified`, `independent_event_errors` |
| Interval | Unique `id`, `start` and `end` event IDs, nonempty `notes`; end must follow start, with nonzero monotone signed turns |

CSV header is exactly `id,frame,frame_u,turn_index`. IDs follow `[a-z][a-z0-9_-]*` and must be unique. Frames are increasing nonnegative integers less than `frame_count`; `frame_u` is finite and nonnegative; turn indices are signed integers. Integer inputs are bounded to ±(2^53−1). The declared cadence, counts and uncertainties apply to this single original clip; use separate campaigns for separate clips/clocks.

## Uncertainty and shared events

Every output carries a first-order **standard uncertainty (k=1)** and named signed contributions. With duration t and any signed reciprocal timing metric r, the contributions are:

| Error term | Duration contribution | Rate contribution |
| --- | ---: | ---: |
| Start pick `event:<id>` | −t·u_start/n | +r·u_start/n |
| End pick `event:<id>` | +t·u_end/n | −r·u_end/n |
| Shared `capture_clock` | −t·u_F/F | +r·u_F/F |

The period uses the duration rule. The standard uncertainty is the root-sum-square of contributions. Covariance between outputs within **this report** is the dot product of contributions with matching names. The middle event cancels when adjacent durations are added; the shared clock does not. Do not average interval uncertainties as independent, or match event names across unrelated campaigns.

Zero uncertainty excludes an error term; it never means unknown. Large relative duration uncertainty (>10%, a diagnostic choice) warns that reciprocal linearization may be inadequate. The warning is not a coverage interval or validity gate; absence of it does not certify a measurement. No uncertainty is assigned to turn count/sign, which must first be resolved as discrete facts.

Sources and scope: [NIST uncertainty propagation](https://www.nist.gov/pml/nist-technical-note-1297/nist-tn-1297-appendix-law-propagation-uncertainty), [Kinovea capture-time calibration](https://www.kinovea.org/help/en/measurement/time.html). These support uncertainty conventions and capture/playback timing distinction; the roll-count equations are direct timing identities.
