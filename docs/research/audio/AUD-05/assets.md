# AUD-05 — Stylized wildlife sound assets

2026-10-11 · **Status: complete — 15 generated WAVs imported as PCM; deterministic checks pass. No physical wildlife recording or species calibration is claimed.**

## Method

[`tools/audio/generate_wildlife.py`](../../../../tools/audio/generate_wildlife.py) creates fifteen original WAVs offline with fixed per-asset PCG64 seeds and pinned NumPy 2.4.6. There are no downloads, field recordings, or third-party sample packs. Dog barks and crow calls combine voiced harmonics with shaped breath/rasp noise; owl hoots use softer formants and breath; bird assets use short, varied chatter and trill notes. Bird calls are stylized synthesis, not real species or field recordings.

All WAVs are mono signed 16-bit PCM at 22,050 Hz. The source band limit is 9,500 Hz; at 1.1× playback its 10,450 Hz limit stays below the 11,025 Hz Nyquist frequency. Peak is capped at 0.48 (generated at 0.46). The total decoded PCM is 2,522,520 bytes (2.406 MiB), below the 2.5 MiB wildlife budget.

Only the two cricket beds are loops. Their asynchronous chirrup events and colony envelopes are built on circular sample buffers, with cyclic noise beds; one-shot phrases use soft attack/release and endpoint fades. Loop boundary steps are compared against ordinary interior sample steps. The adjacent samples at a loop boundary are not required to have equal values.

The subdirectory includes [`LICENSE.txt`](../../../../app/assets/audio/soundscape/wildlife/LICENSE.txt), copied from the repository MIT license. Per-file hashes, exact sample counts, pitch limits, levels, and seam metrics are in [`manifest.json`](../../../../app/assets/audio/soundscape/wildlife/manifest.json). Godot `.import` files explicitly use PCM (`compress/mode=0`) and keep importer looping disabled. Runtime callers set cricket loop mode and `loop_end` from the frame count; all other assets are one-shots.

## Assets and measurements

| File | Duration / nominal frequency | Peak / RMS | Edge check |
| --- | --- | ---: | ---: |
| `dog_01.wav` | 1.350 s / 112 Hz | 0.4600 / 0.0675 | faded endpoints |
| `dog_02.wav` | 1.550 s / 94 Hz | 0.4600 / 0.0710 | faded endpoints |
| `dog_03.wav` | 1.700 s / 138 Hz | 0.4600 / 0.0751 | faded endpoints |
| `crow_01.wav` | 1.500 s / 650 Hz | 0.4600 / 0.0750 | faded endpoints |
| `crow_02.wav` | 1.650 s / 510 Hz | 0.4600 / 0.0704 | faded endpoints |
| `crow_03.wav` | 1.400 s / 720 Hz | 0.4600 / 0.0768 | faded endpoints |
| `owl_01.wav` | 1.850 s / 385 Hz | 0.4600 / 0.1110 | faded endpoints |
| `owl_02.wav` | 2.050 s / 470 Hz | 0.4600 / 0.1060 | faded endpoints |
| `owl_03.wav` | 2.200 s / 342 Hz | 0.4600 / 0.1286 | faded endpoints |
| `bird_01.wav` | 1.200 s / 3,250 Hz | 0.4600 / 0.0677 | faded endpoints |
| `bird_02.wav` | 1.400 s / 4,050 Hz | 0.4600 / 0.0736 | faded endpoints |
| `bird_03.wav` | 1.600 s / 2,850 Hz | 0.4600 / 0.0499 | faded endpoints |
| `bird_04.wav` | 1.750 s / 3,650 Hz | 0.4600 / 0.0635 | faded endpoints |
| `cricket_01.wav` | 17.000 s / 4,850 Hz | 0.4600 / 0.0274 | seam / interior p99 = 0.012 |
| `cricket_02.wav` | 19.000 s / 5,400 Hz | 0.4600 / 0.0401 | seam / interior p99 = 0.078 |

## Verification

After Godot imports the WAVs as PCM, run `python tools/audio/generate_wildlife.py --check`. It regenerates every file in memory and checks bytes, headers, sample counts, hashes, 16-bit levels, source-band energy, fades, loop seam step and curvature, explicit PCM sidecars, license, and decoded-memory budget.
