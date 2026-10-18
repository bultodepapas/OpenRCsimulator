# Native foliage patch readback

2026-10-18, Godot 4.7.2 Compatibility, RTX 3090 / NVIDIA 617.42. The production `tree_patch_noise()` shader include is evaluated through an actual MultiMesh `MODEL_MATRIX` for all 1,680 field positions, then repeated with a parent translation of (321, 0, -123) rendering metres. A synthetic quad only transports each value into a 32-bit binary image; it is a measurement fixture, not tree geometry.

All **3,360 comparisons pass**. Maximum CPU/GPU differences are 0.000001306 and 0.000001009 against the 0.00002 tolerance, including the 0.000001 readback quantization. The translated case verifies that patch color follows absolute world position instead of repeating the container origin. Source identity remains independent of this material variation.

`report.json`, both binary readback images, the exact external fixture and their SHA-256 hashes are retained. The immutable candidate contains shader SHA-256 `e0895d0239ed87a0695081a366bdb90c872d027104c1de8454b990553fa8c353`. Native command:

```powershell
Godot_v4.7.2-stable_win64.exe --path <frozen-candidate-app> --audio-driver Dummy --script <repo>/tools/trees/palette_probe.gd -- --out=<new-absolute-report.json>
```

An initial fixture attempt decoded the manually positioned clip-space image upside down. Correcting its clip-space Y direction produced this passing run; no production shader change was needed. This test verifies world-space color computation, not artistic preference or aircraft readability.
