# AUD-02 — Original loop-ready audio assets

2026-10-11 · **Status: complete — generated assets and deterministic check pass; no physical sound calibration is claimed.**

## Method and use

[`tools/audio/generate.py`](../../../../tools/audio/generate.py) creates all assets offline with fixed per-file seeds. Each WAV is mono, signed 16-bit PCM at 22,050 Hz. The noise beds use shaped periodic Fourier spectra with integer-bin frequencies, so the underlying waveform and analytic slope repeat at the loop point. The six bird phrases use varied synthetic whistle contours and harmonic tone, with zero-value and zero-slope fades at both ends. They are stylized calls, not field recordings or representations of real species.

A final circular low-pass accounts for pitch-shift resampling. Combustion, propeller, and electric sources are limited to 2,400 Hz for up to 4× playback; turbine and airframe are limited to 4,300 Hz for up to 2.4× and 2.325× respectively; the wind, foliage, and bird assets are limited to 10,000 Hz for up to 1.06×. Their highest shifted passband limits are 9,600 Hz, 10,320 Hz, 9,998 Hz, and 10,600 Hz respectively, below the 11,025 Hz Nyquist frequency. Quantization leaves a very low out-of-band floor, measured per asset in the manifest.

Every asset is original synthesis; there are no recordings or third-party sample packs. The WAV directory includes a copy of the repository's MIT notice in [`LICENSE.txt`](../../../../app/assets/audio/soundscape/LICENSE.txt); the generator uses the same repository [`LICENSE`](../../../../LICENSE). NumPy is pinned in [`tools/audio/requirements.txt`](../../../../tools/audio/requirements.txt). Per-file SHA-256 hashes and complete machine-readable metadata are in [`manifest.json`](../../../../app/assets/audio/soundscape/manifest.json).

Set `AudioStreamWAV.loop_mode` to `LOOP_FORWARD` and `loop_end` to the frame count when loading a loop. The WAVs do not depend on import-sidecar loop settings. Keep the ambient layers and motor sources at separate runtime gains; peak normalization is per file.

## Assets and measurements

All outputs target a peak of 0.48, leaving headroom below 0.6. The seam ratio is the absolute last-to-first sample step divided by the 99th percentile of interior sample steps; it screens for an unusually large boundary step. The end and start samples are adjacent points in a periodic signal and are not required to be equal. The check compares their step with normal interior steps and rejects an outlier; analytic seam continuity comes from the cyclic construction described above.

| File | Duration / base frequency | Peak / RMS | Source cap → max shifted frequency | Seam / p99 | SHA-256 |
| --- | --- | ---: | --- | ---: | --- |
| `wind_low.wav` | 29 s / broadband low wind | 0.4800 / 0.0802 | 10,000 Hz × 1.06 → 10,600 Hz | 0.062 | `d05420530a967f2fe2727f4315ddae98cbbe00b42ede2de7df5abaac9e687151` |
| `wind_high.wav` | 31 s / airy broadband wind | 0.4800 / 0.0779 | 10,000 Hz × 1.06 → 10,600 Hz | 0.240 | `087c8a86354f9999edd76c8f92a030da9d0537261feb242b31752fcf5401f156` |
| `foliage.wav` | 23 s / leafy broadband rustle | 0.4800 / 0.0500 | 10,000 Hz × 1.06 → 10,600 Hz | 0.067 | `4c710aeff0f56754e111f687ab652e1bd72013f6b00ce541ff8f6cec691b6f8f` |
| `airframe.wav` | 7 s / buffet and airflow | 0.4800 / 0.1035 | 4,300 Hz × 2.325 → 9,998 Hz | 0.531 | `79f3390fbba8b7facea2b01e8048f8565152574927c494734f340afd135c0fa8` |
| `motor_combustion.wav` | 1 s / 100 Hz firing cycle | 0.4800 / 0.2026 | 2,400 Hz × 4 → 9,600 Hz | 0.187 | `bdec71c124bd227ed201fe3935202f23e21116e27d81c18c545533c4254b8392` |
| `motor_propeller.wav` | 1 s / 200 Hz blade-pass tone | 0.4800 / 0.2346 | 2,400 Hz × 4 → 9,600 Hz | 0.868 | `03ed9ef0b6a189073e37a3f32e8d7cfa2e753ca765d2b9341aa34813ed0431e1` |
| `motor_electric.wav` | 1 s / 600 Hz electrical whine | 0.4800 / 0.2336 | 2,400 Hz × 4 → 9,600 Hz | 1.017 | `cea433f311f2a47cde2052af3a6348282b700a661cca2e1ac5c3aba0f1ac657a` |
| `motor_turbine.wav` | 5 s / 760 Hz whistle plus jet hiss | 0.4800 / 0.1506 | 4,300 Hz × 2.4 → 10,320 Hz | 0.779 | `a06f807e0f29ec2854b343aad80b889e78b07671dabc7df9d9cbd43bfe9af65b` |
| `birds_01.wav` | 2.40 s / stylized synthetic phrase | 0.4800 / 0.1225 | 10,000 Hz × 1.06 → 10,600 Hz | 0.000 | `863f888cbdf42c0365e1b0380865080d2e116342a8fe135e9b6613337897c078` |
| `birds_02.wav` | 1.90 s / stylized synthetic phrase | 0.4800 / 0.1337 | 10,000 Hz × 1.06 → 10,600 Hz | 0.000 | `ce1ada316793539212ebd7e67c3151c901ca04e0b943d0faa7826ccba6f4343f` |
| `birds_03.wav` | 2.76 s / stylized synthetic phrase | 0.4800 / 0.1232 | 10,000 Hz × 1.06 → 10,600 Hz | 0.000 | `1fce8141a67e6d5b4c8c15c8300f8f8b6d802beb4a6980fc886bb5b8c50ea7b6` |
| `birds_04.wav` | 2.30 s / stylized synthetic phrase | 0.4800 / 0.1323 | 10,000 Hz × 1.06 → 10,600 Hz | 0.000 | `21c088990b3f032b43e3ea54a05a0808a9da5a8a2f114cc55e6cf030b6dbd486` |
| `birds_05.wav` | 2.56 s / stylized synthetic phrase | 0.4800 / 0.1483 | 10,000 Hz × 1.06 → 10,600 Hz | 0.000 | `61072fee53600d932e4a98625356540ebedb6edf933e8d6f48c6b506e1a1bb83` |
| `birds_06.wav` | 1.72 s / stylized synthetic phrase | 0.4800 / 0.1311 | 10,000 Hz × 1.06 → 10,600 Hz | 0.000 | `5c8aef65e2b0dff7c37b9da57b4345db54da422addff0fa5f73ddca403d5bb61` |

## Verification

Install the pinned generator dependency with `python -m pip install -r tools/audio/requirements.txt`, then run `python tools/audio/generate.py --check` from the repository root. It regenerates expected PCM in memory, then checks the committed WAV bytes, headers, sample counts, peaks, seam-step outliers, shifted passband against Nyquist, quantized energy above each source cap, hashes, and manifest. The recorded generation toolchain is Python 3.11.9 and NumPy 2.4.6. The check passes for all 14 WAVs; peaks are 0.48, shifted passband limits stay below Nyquist, and quantized out-of-band energy is at most -83.5 dB relative to total energy.
