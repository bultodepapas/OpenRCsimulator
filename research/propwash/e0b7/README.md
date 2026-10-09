# E0b7 — propwash field observations

2026-10-09 · **Status: offline tooling; physical field checks pending.** Python 3.10+, standard library only. This tool does not run Godot or change aircraft data.

From the repository root:

```sh
python3 research/propwash/e0b7/test_reduce.py
python3 research/propwash/e0b7/check_mutations.py
python3 research/propwash/e0b7/reduce.py research/propwash/e0b7/example.synthetic.json --output /tmp/e0b7-report.json
```

The example contains six invented runs: the three E0b7 maneuvers in each of two partitions. Its numbers, bounds and duplicated responses exercise arithmetic and bookkeeping; they are not Stik predictions, instrument recommendations or observations. The [field card](../../../docs/research/propwash/E0b7/FIELD-CARD.md) specifies the evidence to collect. [Evidence report](../../../docs/research/propwash/E0b7/README.md).

## Input contract

Copy the example's structure into a new campaign beside its original recordings. Use one aircraft/environment configuration per campaign; split into separate campaigns when those conditions change. Retain a campaign-wide split plan across those files: this reducer detects leakage only within its input. Every named configuration field is required; explicitly describe unknown information rather than copying the synthetic values. Missing information may prevent a later comparison, even if reduction succeeds.

- `format`: `openrc-propwash-field v1`; `evidence`: `synthetic` or `measured`.
- `configuration`: aircraft, motor, propeller, mass/CG, gear, controls, restraint, surface, wind, heading frame, position reference and synchronization. Each is nonempty descriptive text with evidence sources, units and uncertainty where relevant; these descriptions are retained, not parsed into a physics model.
- `split_plan`: how independent trials were assigned before fitting, plus the location of the frozen assignment. `calibration` identifies development data, not a claim that the tool calibrates anything. `held_out` data must remain unused for parameter selection; if used, collect fresh independent validation trials.
- Each run has a unique `id`, `maneuver` (`nose_unloading`, `taxi_blip`, `takeoff_swing`), `role` (`calibration`, `held_out`), `independent_trial`, `notes`, `raw_sources` and `samples`. Record actual maneuver timing, corrections, end condition and deviations in notes. Multiple excerpts from one trial keep its trial ID and partition.
- `raw_sources`: original video, tachometer/control logs and calibration/annotation records as `{path, sha256}`. Paths are relative to the campaign, without `..`. Every declared file must exist and match SHA-256; measured runs require at least one. Sharing a trial ID or any source bytes across partitions is rejected, even if filenames differ. Put common instrument calibration references in configuration text rather than listing the same calibration file as an independent trial recording. Hashes cannot establish independence or authenticate observations.

Every sample contains `t`, `throttle`, `rpm`, plus the same observation channels throughout that run. Nose unloading requires `nose_load` or `nose_clearance` (both allowed); taxi blip and takeoff swing require `heading` and `lateral`. All channels use quantities:

```json
{"value": 0.01, "bound": 0.002, "unit": "m", "kind": "derived", "source": "clip.mp4 frame 120; survey and annotation method in notes"}
```

| Channel | Unit and meaning |
| --- | --- |
| `t` | `s`, common observation clock; include synchronization error in its bound |
| `throttle` | `1`, normalized command 0=idle to 1=full, not measured shaft power |
| `rpm` | `rpm`, nonnegative shaft rotational speed, with actual acquisition/filtering method |
| `heading` | `deg`, unwrapped ground-frame heading with explicit positive direction |
| `lateral` | `m`, signed position of a named aircraft reference point relative to a surveyed runway axis |
| `nose_clearance` | `m`, nose tire's lowest point above the local surface; not CG height or strut travel |
| `nose_load` | `N`, tare-corrected nose-wheel normal load from an identified sensor/setup |

`bound` is a nonnegative **absolute error bound**, not a standard uncertainty, confidence interval or hidden tolerance. State how it covers instrument calibration, camera geometry, annotation, filtering and synchronization. Do not relabel another reducer's `u` as a bound: the conversion needs a justified coverage assumption. Synthetic quantities require `kind: synthetic`; measured campaigns allow `measured` or measurement-`derived` readings with sources. Estimated/manual readings are not observed dynamics. All nominal throttle commands must lie in [0,1]; uncertainty envelopes are not clipped. Signed position/load readings may straddle zero; there is no clamping that could hide sensor bias.

The tool accepts at least two samples, with time intervals that do not overlap; otherwise their order is unresolved and reduction fails. It does not interpolate asynchronously sampled instruments. Align and annotate those observations externally, preserve originals and include the resulting timing uncertainty. If missing RPM or uncertain ordering cannot be resolved, keep that trial as incomplete evidence outside this reducer rather than inventing readings.

## Results and limits

For each channel, report the first-to-last change `last - first`, absolute bound `last.bound + first.bound`, sampled nominal minimum/maximum and envelope of all sampled intervals. Bound addition does not require independence; shared offsets can make it conservative. The timestamp change gives the observation duration. Computation uses finite float64 arithmetic; reported bounds describe observation errors and do not include formal directed-rounding numerical enclosure.

Clearance samples whose entire interval is above zero are listed by zero-based index. This does not locate first liftoff between frames, prove sustained unloading, or infer load from video. A nose-load endpoint decrease is resolved only if its entire change interval is below zero. No flag means unresolved/no supported decrease, not proof of absence. Intermediate excursions remain visible in the retained inputs and sampled ranges; unsampled peaks are unknown.

Headings must already be unwrapped from original observations: 179° → 183° is +4°, whereas 179° → −177° would be interpreted literally. The tool does not guess turns. Ground heading change is not body-axis yaw rate, and lateral excursion is not sideslip. Restraint forces, steering, pilot corrections, ground friction, wind, CG and thrust line can all affect these observations; this report does not attribute changes uniquely to propwash.

Reports retain the complete input, partition/maneuver coverage, original-file hashes and exact campaign/reducer hashes. Missing partitions/maneuvers remain visible in coverage; partial campaigns are allowed. `physical_acceptance` is always false, including for measured inputs. Later fitting must identify its model/version, objective, fitted/derived coefficients and uncertainty, then use reserved independent trials with tolerances chosen before inspection. No coefficient fitting, simulator comparison or automatic wash enablement is supplied here.

Invalid input exits nonzero and leaves an existing output unchanged. Output aliases to the campaign, originals or reducer—including symlinks/hard links—are refused. Reports are atomically replaced after successful reduction; choose a new output name for each revision to retain history.
