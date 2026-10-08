# F6b — Filmed input latency reduction

**Status:** verified offline tool; physical F6 trials remain open. Python 3 standard library only. [Evidence](../../docs/research/radio-input/F6b/README.md). Follow the [F6a camera protocol](../../docs/research/radio-input/F6a/README.md#owner-camera-protocol-f6-still-pending) when recording.

```sh
python3 research/radio-latency/test_reduce.py
python3 research/radio-latency/reduce.py research/radio-latency/example.synthetic.json research/radio-latency/example.synthetic.csv
```

The CLI reads a JSON campaign manifest and CSV annotations and prints deterministic JSON. Invalid input exits 1 without a partial report. Exact input and reducer SHA-256 hashes are included. Preserve both inputs and original clips. The supplied example is invented; no video or hardware measurement exists for it.

## Record and annotate

Film the physical stick reference and the central patch region together. Use original acquisition frames at a verified constant cadence; slow-motion playback FPS is not acquisition FPS. Check for dropped/duplicated frames. Variable cadence needs timestamp-based tooling and is refused here. Keep the reference and patch at similar camera scanline heights and document exposure, scanout, the physical reference and partial-transition criteria.

Use **zero-based** frame indices. For each event, annotate the first frame satisfying the new-state criterion after the previous frame satisfied the old-state criterion. The event is modelled within `[frame-1, frame]`. A nonnegative integer pick radius `r` expands this to `[frame-1-r, frame+r]`. This is an explicit annotation bound, not a standard deviation. Both complete event intervals must lie inside the original clip. A frame-zero crossing lacks its preceding observation and is refused.

Every physical attempt stays in the CSV. Exclude gray, paused, obscured or otherwise invalid trials with a reason; excluded rows remain in the report and do not count toward the minimum. Four empty frame fields are allowed together only for an excluded row whose events could not be annotated. If frames are supplied, all four must be valid even when excluded. Unknown references, duplicate trial IDs, duplicate clip hashes and reuse of either a stick or patch crossing are refused. These checks cannot authenticate annotation truth or independence of attempts.

## Manifest contract

See [example.synthetic.json](example.synthetic.json) for the complete shape. Fields are exact; unknown/missing keys, duplicate JSON keys, nonfinite numbers, numeric strings and booleans in numeric fields are refused.

- `format`: `openrc-latency-video v1`; `evidence`: `synthetic` or `measured`; nonempty `notes`.
- `conditions`: nonempty list of `{id, build, system, radio, display_refresh_hz, vsync, frame_cap_fps, achieved_fps, marker, notes}`. Describe exact OS/GPU/driver, radio/firmware/USB/RF state, raw axis/threshold and patch criterion. Numeric rates are positive, except cap `0` means uncapped. VSync is `on`, `off`, `adaptive` or `mailbox`. Record the actual observed mode. Separate unlike setups into distinct conditions.
- `clips`: nonempty list of `{id, condition, source, sha256, frame_count, timebase, acquisition_fps, timing_notes}`. Each clip belongs to one condition. Use the original clip's lowercase 64-digit SHA-256, source reference and exact frame count. `timebase` must be `constant-acquisition-cadence`.
- `acquisition_fps`: `{value, min, max, kind, source}`. Finite positive bounds must contain the nominal value; equal bounds represent an explicitly exact cadence assumption. Kind is `synthetic`, `measured` or `derived`; measured campaigns reject synthetic cadence. Explain calibration/bounds in `source`. FPS bounds describe the acquisition clock across the whole clip, not independent frame jitter.

Source labels and hashes are operator declarations. This tool does not open videos; `video_hashes_verified` is always false. Authenticate clips separately before accepting measurements. Camera/display timing and physical-reference errors are documented but not added to the numerical bounds.

## CSV contract

Use this exact header and field order; quoted commas/newlines in reasons are supported:

```csv
condition,trial,clip,stick_frame,patch_frame,stick_pick_radius,patch_pick_radius,exclusion_reason
```

Included rows need four integer frame fields and an empty exclusion reason. Trial IDs are unique within a condition. Frames must belong to the referenced clip, and the CSV condition must match its manifest condition. No pairing across clips, sorting away errors or automatic exclusion is performed. See [example.synthetic.csv](example.synthetic.csv).

## Calculation and limits

For `d = patch_frame - stick_frame`, nominal latency is `1000*d/fps` ms. The difference interval is `[d-1-r_stick-r_patch, d+1+r_stick+r_patch]` frames. Divide every endpoint by both positive FPS bounds and retain the minimum/maximum. This handles negative and zero-crossing intervals without clamping. Even exact frame picks at 240 FPS permit a difference uncertainty of one acquisition frame (4.167 ms) in each direction under this observation model.

Per condition, median averages the two central values for even sample counts. Nearest-rank p95 is `sorted[ceil(0.95*n)-1]`; with 20 trials it selects rank 19. Summary bounds apply the same monotonic statistic separately to all lower and all upper trial endpoints, allowing ranks to change. They are conservative conditional bounds for these observed trials, including a shared clip cadence; they do not shrink as if repeated observations made systematic clock or frame-pick bounds independent.

These intervals are **not confidence intervals**, population percentile bounds or a complete uncertainty budget. They omit exposure, rolling shutter, physical-mark uncertainty and other effects named above. Small trial counts make tail estimates unstable even with exact timing. All conditions, including unused or fully excluded ones, stay visible with counts and missing statistics where appropriate. Fewer than 20 usable trials produces a warning; 20 is only the F6 minimum screen.

The report retains negative nominal latency and flags it for inspection. The proposed 60 Hz budget (50 ms median, 70 ms p95) is retained as a reference only; the tool makes no acceptance decision for any refresh rate. A synthetic result never closes F6, and this marker does not measure servo or aircraft-response delay. Hardware evidence must precede changes to jitter settings or the input reader.
