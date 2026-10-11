# TOD-07 — Capture tools and artifacts

2026-10-10 · **Status: capture and cloud-occlusion experiments complete.**

The canonical rendered-evidence report is [TOD-07](../../../docs/research/time-of-day-investigations/TOD-07/README.md). It records the 16-case integrated render matrix, the post-diagnostic-fix image check, and the production-sky cloud/horizon control with limits and reproduction commands.

Tools in this directory:

- [`run_capture_matrix.py`](run_capture_matrix.py) captures the fixed-time aircraft/scenery matrix.
- [`probe_cloud_occlusion.gd`](probe_cloud_occlusion.gd) renders the existing production sky shader with fixed sky/haze uniforms and cloud/Sun controls.
- [`analyze_cloud_occlusion.py`](analyze_cloud_occlusion.py) measures paired Sun-on/Sun-off image differences in a centered capture ROI.

Captured images, sidecars, logs, summaries and checksums are under [`evidence/`](evidence/). They use llvmpipe software rendering and do not establish target-GPU performance or physical sky radiance.
