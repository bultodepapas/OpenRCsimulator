# GP-19: native accepted hull scraping

2026-10-26. The opt-in mode in the existing [audio probe](../../../../../../tools/audio/README.md#accepted-hull-friction-review)
now exercises actual Main/Session/Director hull friction and its existing CrashFX
pool. It adds a reproducible tool, not a new sound asset or physics force. The probe,
checker, tests and instructions were installed only after detached fixture/native
verification and root review. All five selected runtime integration files remained
unchanged during this tool promotion.

The source-pinned default club-field Stik capture uses explicit body reset fixtures
followed by accepted physics: airborne, opening geometric overlap with no clamped
friction, loaded wingtip brush, pause, resume, public reset and actual nose-in terminal
impact. These are several declared initial conditions, not a continuous full flight.
The default field has a lake; the actual dry force branch is qualified. Covered lake
acoustics remain unsupported. One aircraft and requested60FPS were captured.

## Measured native result

| Measure | Result |
| --- | --- |
| Driver / display | WASAPI / headless display |
| PCM | 48 kHz, stereo, signed16-bit; 576,512 frames |
| PCM / elapsed capture wall time | 12.0106667 s / 12.004941 s |
| Discarded, truncated, unaccounted or remaining frames | 0 each |
| Captured bus | CrashFX after local limiter, sent to Master; Master excluded |
| Entire captured bus peak | -6.92948 dBFS |
| Guarded airborne/opening/pause/reset PCM intervals | Exactly zero |
| Guarded loaded-brush / terminal PCM peaks | 0.28894043 / 0.45031738 linear |
| Accepted / deferred-render observations | 1,453 / 708 |
| Source stability / engine diagnostics | All selected hashes unchanged / zero errors and warnings |

Loaded contact IDs and positive instantaneous friction power, native tagged-player
state, and nonzero measured bus PCM are separate gates. Emission counts alone cannot
pass. Settled interval silence does not establish first-frame cancellation or hardware
latency. No grain-to-waveform identification, acoustic calibration, human listening,
combined Master headroom, full fleet or 1080p hardware performance is claimed.

The installed fixture passes18 checked Godot assertions; the installed Python checker
passes41 tests, including all six existing fleet-scope tests. The draft18/41 executions
are repeated verification of the same final source, not additional unique checks.
The installed checker independently reprocessed the unchanged native PCM successfully.
Raw earlier failed fixture/checker receipts remain historical and are not counted as
passes. Only final source hashes in `construction/promotion.json` are installed.

Root review added complete contiguous accepted/render partitions, phase and generation
bindings, monotone clocks and duplicate/refile rejection. The verified Session.reset
order permits one leading committedtick0 observation at the prior statistics generation,
immediately followed by its post-return fixture boundary at the new generation.
The public wrapper increments bookkeeping after the physical commit call returns;
reset notifications still precede committedtick0. This bounded exception is documented
in the tool guide and tested; it is not arbitrary mixed-generation acceptance.

`capture/review.json` retains raw observations and source/asset identities. The raw WAV
remains in ignored tmp; `capture/wav-identity.json` binds its exact bytes and format.
Native measurement cannot be independently recomputed from this Git cohort alone
without that WAV or a new capture. Selected source snapshots are not a full repository
closure. Original engine logs and draft-before-promotion paths are retained verbatim.
Folder attributes and `manifest.json` protect every retained payload across checkout.
