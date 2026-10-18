# Temporal flight clips

This evidence set contains ten repeatable native flight clips captured on 2026-10-18: five production camera/input routes at 1280×720 and 1920×1080. The clips use the frozen oak-era candidate, before the woodland-edge understory change (`app` source SHA-256 `1300b6a77533315e4f67c0689a3064f7bf6bd8b4792ada6460f968fecef1d1cc`). The probe script SHA-256 is `795d0983fe3d159abc6bae52cd25f294b28fd0c7a8afbaf5593fa7fdf17f4f7d`; the Godot 4.7.2 executable SHA-256 is `ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`.

Each route records 120 deterministic samples at 24 frames per second. Samples follow the active flight session's input and camera paths; physics runs at 240 ticks per second. All ten probes completed 1,190 simulation ticks without pause, crash, fault, lost focus, or disabled input/physics. Each AVI contains 123 frames and lasts 5.124918 seconds. That AVI duration includes bounded startup and audio-drain frames, and is separate from the 120 route samples; the AVI was not trimmed. All 12–13 tracked audio playbacks drained to zero within the one-second shutdown bound (observed 72–164 ms). MP4/H.264 review copies are retained below, with each clip's manifest and probe report beside it. The raw AVI sources remain in `tmp/tree-completion/temporal-raw-avi-final-20261018-r1/`.

| Route | 1280×720 | 1920×1080 |
|---|---|---|
| Slow pan | [MP4](slow-pan-1280x720/slow-pan-1280x720.mp4) | [MP4](slow-pan-1920x1080/slow-pan-1920x1080.mp4) |
| Pilot input pulse | [MP4](pilot-input-pulse-1280x720/pilot-input-pulse-1280x720.mp4) | [MP4](pilot-input-pulse-1920x1080/pilot-input-pulse-1920x1080.mp4) |
| Pilot bank reversal | [MP4](pilot-bank-reversal-1280x720/pilot-bank-reversal-1280x720.mp4) | [MP4](pilot-bank-reversal-1920x1080/pilot-bank-reversal-1920x1080.mp4) |
| Chase control pulse | [MP4](chase-control-pulse-1280x720/chase-control-pulse-1280x720.mp4) | [MP4](chase-control-pulse-1920x1080/chase-control-pulse-1920x1080.mp4) |
| Camera cut | [MP4](camera-cut-1280x720/camera-cut-1280x720.mp4) | [MP4](camera-cut-1920x1080/camera-cut-1920x1080.mp4) |

`series.json` records the complete run matrix, source identities, frame counts, AVI/MP4 hashes, and process results. Each clip directory contains `manifest.json`, `probe.json`, and native logs. These clips establish repeatable active-flight camera/input footage and temporal traces; they do not claim a forest traversal or tree-transition test, and they do not determine human readability approval. The later understory snapshot and its current diagnostic status are described in the [comparison evidence](../comparison-understory/README.md).
