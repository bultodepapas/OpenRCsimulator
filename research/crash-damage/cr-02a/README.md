# CR-02a asset source record

**Status:** original offline assets generated and hash-verified on 2026-10-11. Step: **CR-02a**.

`generate_assets.py` deterministically creates the 12 mono 22,050 Hz, signed 16-bit PCM WAVs used by [`app/render/crash/crash_audio.gd`](../../../app/render/crash/crash_audio.gd). The set covers airframe cracks, tearing, grass/dirt/hard impacts, scrape, debris, secondary hits, engine cutoff, turbine rundown and a fire bed. Runtime synthesis is disabled; `fire_loop.wav` is played only when the caller supplies separate positive ignition/fuel strength.

All samples are original procedural synthesis produced offline by this repository. No recordings or third-party source audio are included. Per-file SHA-256, generation seed, duration, peak and RMS are recorded in [`sources.json`](../../../app/assets/audio/crash/sources.json); the assets use the included MIT license. Each source peak is bounded at 0.46 linear.

Reproduce and verify the committed outputs:

```powershell
python research/crash-damage/cr-02a/generate_assets.py
python research/crash-damage/cr-02a/generate_assets.py --verify
```

The verifier regenerates samples in memory and compares bytes and SHA-256 values with the manifest. The final verification reported: `CR-02a asset hashes reproduce exactly`.
