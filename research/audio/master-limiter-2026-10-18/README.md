# Master limiter probes (2026-10-18, AUD-12)

Evidence for [AUD-12](../../../docs/research/audio/AUD-12/README.md). Run from the repository root. Capture each standalone Godot 4.7.2 project with Movie Maker, as in the [2026-10-13 probes](../review-2026-10-13/README.md):

```sh
G="$(app/get-godot.sh)"; P=research/audio/master-limiter-2026-10-18/limiter_transfer_probe; OUT=$(mktemp -d)
cp -r "$P" "$OUT/proj"; xvfb-run -a "$G" --path "$OUT/proj" --import
FX=limiter xvfb-run -a "$G" --path "$OUT/proj" --rendering-driver opengl3 --write-movie "$OUT/limiter.png" --fixed-fps 60
python3 -I research/audio/master-limiter-2026-10-18/measure_transfer.py "$OUT/limiter.wav"
```

- `limiter_transfer_probe/`: a 1 kHz tone ramps from −12 to +6 dBFS before the bus effect over 6 s, then holds −20 dBFS. `FX=none|limiter|hard|compressor`. `measure_transfer.py` reports output peak and distortion (residual after the fitted 1 kHz sinusoid) at fixed input levels, then the hold level.
- `repeated_burst_probe/`: a −20 dBFS tone with five 40 ms +12 dB bursts through `AudioEffectHardLimiter` (`CEIL`, `REL` environment variables). `measure_bursts.py` reports the tone level 1.5 s after each burst and at the end, relative to before the first.

## Measured (llvmpipe, 48 kHz mixer)

| Input | None | `AudioEffectLimiter` −1/−1 (soundscape since AUD-07d) | `AudioEffectHardLimiter` −1 dB, release 0.1 s | `AudioEffectCompressor` −6 dB, 20:1, 20 µs |
| ---: | --- | --- | --- | --- |
| −6 dBFS | −5.97, −54 dB | −5.97, −54 dB | −5.97, −54 dB | −6.00, −60 dB |
| −2.1 dBFS | −2.07, −54 dB | −2.07, −54 dB | −2.07, −54 dB | −9.77, −53 dB |
| −1.9 dBFS | −1.87, −54 dB | **−1.00, −26 dB** | −1.87, −54 dB | −9.96, −53 dB |
| −1.0 dBFS | −0.97, −54 dB | −1.00, −31 dB | −1.01, −61 dB | −10.84, −53 dB |
| +3.0 dBFS | 0.00 (clipped), −17 dB | −1.00, −15 dB | −1.01, −84 dB | −14.74, −51 dB |
| −20 dBFS hold, after | −20.00 | −20.00 | **−21.09** | −20.15 → −20.00 |

Entries are output peak (dBFS) and distortion (dB re fundamental); −54 dB is the 16-bit source floor. The +6 dBFS window straddles the step to the hold and is omitted.

- `AudioEffectLimiter` is a stateless per-sample clipper. Its knee sits at −`soft_clip` dBFS (−2 dB by default), independent of the ceiling, and a sample just above the knee jumps to the ceiling (Godot's `scv + db_to_linear(overdb · scmult)`). It recovers instantly but distorts from −2 dBFS.
- `AudioEffectHardLimiter` limits cleanly and is transparent below its ceiling, but remains a constant amount low after any overload. Repeated bursts do not accumulate it: −1.2 to −1.3 dB at release 0.12 s, −0.15 dB at 1 s, −0.07 dB at 2 s after the release completes (−1.6 dB while still releasing 1.5 s after a burst).
- `AudioEffectCompressor` reduces far more than its ratio implies and has no hard ceiling.

Mixer captures, not speaker listening.
