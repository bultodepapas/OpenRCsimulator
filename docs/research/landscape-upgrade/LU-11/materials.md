# LU-11 — Material and twilight image checks

Status: native paired-image checks pass on Godot 4.7.2 Compatibility, 2026-10-12.

The repeatable checker is [`tools/landscape/verify_materials.py`](../../../../tools/landscape/verify_materials.py). Run `python tools/landscape/verify_materials.py --root <evidence-root>`; it reads `after-day`, `flat-day`, `before-aircraft`, and `after-sunset`, then writes `materials-checks.json` into that root. Pillow is pinned at `12.3.0` in [`tools/landscape/requirements.txt`](../../../../tools/landscape/requirements.txt).

The checker uses Pillow RGB bytes from the 1920 × 1080 Compatibility captures and their JSON reports. Day image differences are the mean of absolute RGB channel deltas and the fraction of pixels whose maximum channel delta meets a threshold. It requires visible close and parking grain, exact or near-exact distant attenuation, unchanged per-case draw counts, and exposure agreement within `0.001`. The twilight ROI is `[910, 490, 1010, 590]` with right and bottom edges excluded. It compares `twilight_aircraft.png` against `twilight_background.png` from the same capture folder. A pixel enters the aircraft mask when its maximum absolute RGB channel difference is at least 8; the accepted mask size is 40–200 pixels. Contrast is the mean absolute encoded Rec. 709 weighted luma difference (`0.2126 R + 0.7152 G + 0.0722 B`) over that mask. The after/before ratio must remain at least `0.95`, with matching report exposure within `0.001`.

| Check | Observed | Pass condition |
| --- | ---: | --- |
| Close gravel, after-day vs flat-day | Mean absolute RGB delta `2.768`; `16.44%` of pixels have max-channel delta ≥8 | Mean ≥1.0 and changed fraction ≥10% |
| Parking, after-day vs flat-day | Mean absolute RGB delta `1.005`; `5.27%` of pixels have max-channel delta ≥8 | Mean ≥0.5 and changed fraction ≥3% |
| Far gravel, after-day vs flat-day | Byte-identical | Mean delta ≤0.02 and ≤0.1% of pixels have max-channel delta ≥2 |
| Draw counts, close / parking / far | `14 / 29 / 88` in both day reports | Exact equality |
| Twilight aircraft mask, before / after | `78 / 79` of 10,000 ROI pixels | 40–200 pixels per capture |
| Encoded Rec. 709 luma contrast, before / after | `57.4529 / 66.6877`; ratio `1.1607` | Ratio ≥0.95 |
| Twilight aircraft/background exposure | Before `1.845197 / 1.845368`; after `1.845368 / 1.845368` | Each pair and before/after within `0.001` |

The verified shader calculation keeps the grain height signal independent of the footprint filter, differentiates that spatial signal with `dFdx`/`dFdy`, then multiplies the resulting gradients by the filter. This avoids differentiating a derivative-dependent expression, whose higher-order derivatives are undefined in the Godot shader reference.

Native p95 frame-time differences between `paired-day` (the actual `StandardMaterial3D` replacement comparator) and `legacy-day` were `+0.039 ms` for `gravel_close`, `+0.065 ms` for `car_park`, and `+0.074 ms` for `postcard_club`. These are observed 600-frame report deltas on the RTX 3090 at 1920 × 1080, with the same Compatibility renderer and `0.6` exposure. They are capture-run p95 comparisons, not isolated GPU cost estimates. The `flat-day` visual pair disables grain detail while the shader remains bound and executes; it does not measure shader removal.

These image metrics are deterministic engineering screens for the supplied views. They do not establish physical luminance, calibrated display contrast, or human acceptance across cameras and hardware.
