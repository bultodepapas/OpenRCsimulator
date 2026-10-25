# GDU-05a: native cloud shader contract

2026-10-25, official `4.8.beta1.official.4d10419ca`, RTX 3090, OpenGL Compatibility.
The existing cloud-density checker passes natively on Windows. Its two repeated
3072×256 atlas captures are byte-identical; four periodic comparisons are exact.
Projection, drift wrapping, density bounds and the wrong-sign negative control
pass the unchanged numerical gates. [Summary](summary.json).

The checker now uses the shared checked runner for native Windows deadlines,
bounded diagnostics and process-tree cleanup, while retaining Xvfb elsewhere.
It rejects an unexpected engine build before rendering. Five focused CLI tests
pass, and reuse of the owned output directory was exercised.
[Tool receipt](tool-verification.json).

No shader changed. This mathematical atlas is not a 1080p appearance benchmark,
performance result or qualification for other GPUs. Images and raw logs remain
in the D: experiment paths recorded in the receipts.
