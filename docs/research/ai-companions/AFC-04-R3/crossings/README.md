# R2 recorded crossing evidence

These fixed 20-second route-intercept fixtures compare the production pilot
(`1d5699fa89d219b26e6ff7dc58a797eb61f67152e9d9aedc64f5de1ca684615c`) with the
research R2 controller (`1c512e4bdc0c606cc575397dfe8e1d6fe3e8bf6b9bc0894bd20ce11366d47eb8`).
They ran in the same AFC-04-R3 mirror with physics at 240 Hz and planning at
60 Hz. The reports record two nominal route-intercept geometries; spawn
admission was disabled for these probes, so they are not a spawn-admission gate.

| Fixture | Production minimum | R2 minimum | R2 gate |
| --- | ---: | ---: | --- |
| 20261020 crossing-right | 4.127 m | 59.820 m | pass |
| 20261021 crossing-left | 3.860 m | 58.465 m | pass |

All four AI flights completed 4,800 requested ticks with no crash, fault or
refusal. Baseline and candidate recordings were each repeated deterministically.
The reports, 10 Hz trajectories and runner logs are retained in
[`baseline/`](baseline/) and [`candidate/`](candidate/). The copied trajectories
are text summaries; the original ORFL recordings and exact replay CSVs remain
on `D:` because they are large. Their absolute paths, sizes, SHA-256 values and
the exact used source identities are bound by
[`source-bound-receipt.json`](source-bound-receipt.json).

All 12 recorded streams (six baseline and six candidate: AI, coupled-player and
exogenous-player roles across both fixtures) replayed in exact mode with
`complete=true` and `solver_changed=false`. The coupled and exogenous player
tapes match byte-for-byte between the baseline and candidate runs. See
[`replay-verification.json`](replay-verification.json) and the per-stream
`replay.json` files under [`replays/`](replays/).

Exact replay checks recorded commands against the current solver; it does not
execute or revalidate the companion controller. These crossings supplement the
six-route 60-second survey and do not establish endurance, general recovery,
continuous trajectory containment or physical safety.
