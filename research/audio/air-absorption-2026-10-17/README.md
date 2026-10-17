# Air absorption probes (2026-10-17, AUD-11b)

Evidence scripts for [AUD-11b](../../../docs/research/audio/AUD-11/README.md#aud-11b--air-absorption-iso-9613-1). Run from the repository root.

- `filter_probe/`: standalone Godot 4.7.2 project. Seeded white noise (a 2 s loop, one per segment, so every segment filters the same samples) and a 1 kHz tone through `AudioEffectLowPassFilter` / `AudioEffectHighShelfFilter` on a bus, then an `AudioStreamPlayer3D` distance filter at 30 and 200 m. Segments are printed as `PROBE_SEGMENTS` JSON. Capture the real mixer with Movie Maker and measure:

```sh
G="$(app/get-godot.sh)"; P=research/audio/air-absorption-2026-10-17/filter_probe; OUT=$(mktemp -d)
cp -r "$P" "$OUT/proj"
xvfb-run -a "$G" --path "$OUT/proj" --import
xvfb-run -a "$G" --path "$OUT/proj" --rendering-driver opengl3 --write-movie "$OUT/out.png" --fixed-fps 60 > "$OUT/log.txt"
python3 -I research/audio/air-absorption-2026-10-17/measure_filters.py "$OUT/out.wav" "$OUT/log.txt"
```

`measure_filters.py` (numpy) reports each noise segment's Welch PSD ratio to the bypass at fixed frequencies and the −3 dB point; for tone segments, the largest 1 ms second-difference peak over its 21 ms local median, inside the segment and across its boundary (1.0 = clean; the bench click threshold is 8). [Results](filter_probe_results.json) from the 2026-10-17 run.

## Measured on Godot 4.7.2 (llvmpipe, 48 kHz mixer)

| Setting | Result |
| --- | --- |
| Low-pass, `FILTER_6DB`, resonance 0.7071, 1 kHz | −3.01 dB at 1 kHz, −12.37 at 2 kHz, −24.48 at 4 kHz: one 12 dB/octave Butterworth biquad |
| Low-pass, `FILTER_12DB` (the default), resonance 0.7071 | two cascaded biquads: −6.02 dB at the cutoff, 24 dB/octave |
| Low-pass, defaults (resonance 0.5, `FILTER_12DB`), 1 kHz | −3 dB at 439 Hz, −12.0 at 1 kHz |
| Low-pass at 20 kHz, `FILTER_6DB` | flat within 0.02 dB to 12 kHz, −0.20 dB at 16 kHz |
| High-shelf, `gain` 0.5, `FILTER_6DB` | −12.0 dB above the shelf: the effect applies **gain squared** (RBJ amplitude A = `gain`) |
| `AudioStreamPlayer3D` shelf 6.5 kHz, `attenuation_filter_db` −12 | −13.5 dB at 8 kHz at 30 m, −16.4 / −24.0 dB at 8 / 16 kHz at 200 m: the configured depth doubles and barely depends on distance |
| Same with 1.5 kHz / −24 dB (the old full canopy screen) | −15.6 dB at 1 kHz, −47 dB above 4 kHz at 200 m |
| Enabling a bus effect mid-stream | 15–27× click |
| Disabling a bus effect | 1.8× |
| Cutoff step 19.5 → 5 kHz | 3.6× |
| Fixed cutoff | 1.000 (clean) |
| Moving cutoff below 15 kHz | ≤ 1.05 (25× sweep in 2 s), ≤ 1.02 (4× in 2 s) |
| Moving cutoff above 15 kHz | up to 1.3–1.8 |

These follow from Godot's `AudioFilterSW::prepare_coefficients` (RBJ biquad, `Q = resonance`; the shelf uses `gain` as A) and `AudioStreamPlayer3D`, which passes `db_to_linear(db_att)` to that shelf. Mixer captures, not speaker listening.

## ISO 9613-1 oracle

`app/audio/soundscape_model.gd` implements ISO 9613-1:1993 (formulas as summarised by [sengpielaudio](https://sengpielaudio.com/AirdampingFormula.htm)). At exact octave midbands it reproduces the 10 °C / 70 % table printed in earlier ISO 9613-2 editions (EMD [windPRO Appendix A](https://help.emd.dk/knowledgebase/content/windPRO4.1/Appendix_A_DECIBEL.pdf): 0.1, 0.4, 1.0, 1.9, 3.7, 9.7, 32.8, 117 dB/km, 63 Hz–8 kHz) within half its last printed digit; nominal frequencies differ by up to 1 % at 4–8 kHz. Its Annex B saturation pressure agrees with the atmosphere model's Buck formula within 0.09 % from 0 to 40 °C.
