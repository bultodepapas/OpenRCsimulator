# E0b6p required-field decoder experiment

2026-10-08 · **Status: verified; single-lookup readers retained in the research evaluator.** [Results and limits](../../../../docs/research/propwash/E0b6p/decoder/README.md).

The builder reconstructs the original double-lookup and candidate single-lookup versions of three required-field readers. It uses the locked native toolchain and writes separate libraries under `.tools/native-decoder/`. The candidate gets a distinct registration name so both implementations can run in one Godot process. Optional readers and numerical code are identical.

```sh
python3 research/propwash/e0b6p/decoder/build.py --jobs 2
python3 research/propwash/e0b6p/decoder/run.py \
  --godot "$(app/get-godot.sh)" --output /tmp/e0b6p-decoder
```

The runner stages a disposable app, verifies both libraries against the 297-case oracle and 165 decoder contract cases, compares all native load bytes, and runs the candidate through the 41 dense accuracy checks. It then alternates backend order for six fixed-input profiles and twelve whole-flight cases, comparing every body/auxiliary boundary over 240 ticks. Native class identities and per-backend route counters are checked. Raw timings, proof reports and source/library hashes go into the output directory; the staged app is retained for inspection.

Fixed-input timing uses three warm-up pairs and 24 measured pairs of 64 calls, including the adapter. Whole-flight timing uses one warm-up pair and 15 measured pairs of 24 ticks. Backend selection, checkpoint restoration and counter snapshots occur outside the timed regions. Shared-host timing remains noisy: use paired differences and report whole-flight results separately from direct-call savings.
