# Final woodland composition: world and replay

2026-10-18. The final R3 candidate (`b18a46dfa66d800e8179b7e32be5ea7a27b8e253bacab7da2c23141ca85c3eea`) repeats the trim and runway fixtures after the decorative shrub/grass layout is finalized. Each recording contains 2,400 ticks and 2,401 rows; both CLI replays are complete and exact, with `solver_changed=false`.

The collision world remains `6f6168e1d27274c28f07a6213017802c841788fd711e858d25df6f8d99654036`, with 4,980 proxies. Both CSVs are byte-identical to the corresponding [pre-understory candidate tapes](../world/README.md). The decoration therefore preserves the world identity and sampled states in these two cases. This is not physical validation or an assertion about every possible flight.

`summary.json` retains commands, replay results and comparisons. Gzip files preserve the exact recordings and CSVs; `sha256.json` hashes the stored bytes. `run.py` retains the reproduction runner. The [final source receipt](../comparison-final/README.md) identifies the shared runtime and final data.
