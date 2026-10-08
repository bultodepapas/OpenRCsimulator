# VAL-8a — ground-run video reduction

**Status:** offline measurement tool; synthetic verification only. Physical video observations and simulator comparison remain [VAL-8](../../../ROADMAP.md). Python 3.10+, standard library only; no simulator inputs are changed.

From the repository root:

```sh
python3 research/validation/ground-video/reduce.py \
  research/validation/ground-video/example.synthetic.json \
  research/validation/ground-video/example.synthetic.csv --output /tmp/ground-video.json
python3 research/validation/ground-video/test_reduce.py
python3 research/validation/ground-video/check_mutations.py
```

The example is invented constant-speed motion, **not Stik measurements, takeoff performance or recommended instrument uncertainty**. Reports contain duration, signed displacement, distance along the runway, average along-runway ground speed, standard uncertainties, signed uncertainty contributions, complete parsed inputs, limitations and exact metadata/CSV/reducer/video hashes. Identical bytes yield identical output. Errors exit nonzero and preserve existing reports; output aliases to inputs/reducer, including hard links, are refused.

## Collect a usable flight card

1. Record aircraft, fuel/battery, mass/CG configuration, propeller, control/power technique, runway grade/surface, wind and observation conditions in the campaign. Keep survey records and unedited original video. Match these conditions when comparing the simulator.
2. Establish an axis in meters along the runway from a stated datum. Survey ground markers; positions read from video need a calibrated ground-plane mapping that accounts for perspective and distortion. One pixel-to-meter factor across an oblique view is insufficient. This tool does not perform that mapping.
3. Identify the same aircraft reference point at both endpoints, for example the ground projection of the main-gear midpoint. The event definition and the spatial reference are separate: define first motion, final wheel liftoff, first touchdown, or full stop explicitly. Note bounces. A changing pitch changes the offset between gear and CG; simulator CG traces need conversion to the same observed reference point.
4. Verify capture cadence from camera evidence or a recorded time reference. Frames must correspond one-to-one with original captured frames. Supply capture FPS as an integer fraction, e.g. `30000/1001`, and its relative standard uncertainty. A 240 fps capture played at 30 fps still uses 240 here. Set `constant_capture_cadence_verified` only after verification; variable cadence, interpolation, dropped/duplicated frames or unknown timing require a different timestamp-based method. The tool neither decodes video nor detects these defects.
5. Annotate original, zero-based frame numbers in strictly increasing order. Supply the total original `frame_count`, and frame/position **standard uncertainties (k=1)**. Estimate frame picks from repeated observations or a justified distribution; a uniform ±half-frame bound would give `0.5/sqrt(3)` frames, before blur/event ambiguity. No default is inserted.
6. Set `evidence` to `measured`, declare the original clip SHA-256, and pass `--video /path/to/original-clip`. The bytes must match. Hashing identifies a file; it cannot authenticate its contents, cadence, survey or observation claims. Put survey/uncertainty sources in `survey.source`, timing evidence in `video.timing_source`, and annotation method/reference-point/correlation evidence in `annotations_source` and each interval's `definition`.

CSV columns are exactly:

```text
id,frame,frame_u,x_m,x_u_m,frame_x_correlation
```

`x_m` is signed ground position, not image position. `x_u_m` excludes the shared scale and datum errors. `frame_x_correlation` is the correlation of the event's residual frame and position errors; use zero only when justified. If a frame-pick error also changes the inferred aircraft position, independence may be false. Different events' residuals must be independent; shared frame and coordinate origins cancel, while common clock/length scale errors are represented separately. More general survey/image correlations need a richer reduction and must not be hidden behind the `independent_event_residuals` confirmation.

`video.fps_relative_u` and `survey.scale_relative_u` are fractional standard uncertainties common to every event, not percentages. Each interval references two event IDs and records its physical definition. Unknown fields, non-finite values, invalid IDs, negative uncertainties, unverified cadence/positions, unknown events, non-increasing intervals and zero displacement are refused.

## Measurement model

For frame difference `n = f_end - f_start`, capture rate `F`, and surveyed displacement `D = x_end - x_start`:

```text
t = n/F                  duration (no inclusive-frame +1)
d = abs(D)               net along-runway distance
v = d/t                  magnitude of mean along-runway velocity
```

This distance is path length only for a straight, non-reversing run. The speed is not instantaneous liftoff/touchdown speed, airspeed or stall speed; wind cannot be inferred from it. An interval between known markers is useful even when it is not the complete takeoff/landing run; label it accordingly.

Uncertainty follows first-order sensitivity propagation with covariance. With independent frame and position errors at each endpoint:

```text
u(t)^2 = (u(f_start)^2 + u(f_end)^2)/F^2 + (t*u(F)_relative)^2
u(d)^2 = u(x_start)^2 + u(x_end)^2 + (d*u(scale)_relative)^2
```

The velocity derivatives with respect to `(f_start, f_end, x_start, x_end)` are `(v/n, -v/n, -sign(D)/t, sign(D)/t)`. Clock and length-scale sensitivities are both `v`. Frame/position correlation is included before combining contributions; simply treating `t` and `d` as independent would lose this term.

Signed contributions use common names for shared errors. Within an event with correlation `r`, the two independent error contributions to any result `y` are `y_f*u_f + y_x*r*u_x` and `y_x*sqrt(1-r*r)*u_x`. The result's `u` is their root-sum-square together with common calibration contributions. Covariance between any two results is the dot product of same-named contributions (units multiply). This preserves shared endpoints across adjacent intervals; do not average intervals as independent or combine reports from separate campaigns using these local names.

Warnings flag relative duration or distance uncertainty above 10%. This is a diagnostic choice, not a coverage interval or guarantee of validity below the threshold. Near-zero displacement folds the distance distribution; large timing uncertainty makes ratio linearization unreliable. Unmodeled camera/event/survey bias is not bounded by these reported uncertainties. No automatic physical acceptance or dashboard row is produced.

Method references: [NIST TN 1297 Appendix A](https://www.nist.gov/pml/nist-technical-note-1297/nist-tn-1297-appendix-law-propagation-uncertainty) supplies the first-order covariance law and the rectangular-distribution standard uncertainty; the equations above are direct derivations for this measurement model. [Tracker's video documentation](https://opensourcephysics.github.io/tracker-website/help/videos.html) discusses frame timing controls and video analysis. [Evidence and limits](../../../docs/research/validation/VAL-8a/README.md).
