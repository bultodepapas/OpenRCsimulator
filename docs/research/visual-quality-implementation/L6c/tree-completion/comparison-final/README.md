# Final natural-cluster tree comparison freeze

This pair layers the visually accepted R3 woodland-edge understory onto the existing reconstructed tree baseline/candidate comparison. Its parent is the diagnostic `tmp/tree-completion/frozen-understory/{baseline,candidate}/app`; the diagnostic snapshots remain unchanged and retain the earlier straight-row shrub data. The final app source fingerprints, full per-file manifests, cache fingerprints, and parent identities are in [`freeze-natural.json`](freeze-natural.json). The exact two-file overlay is listed in [`file-map.json`](file-map.json).

The R3 recipe uses 12 seeded shrub segments in each of four patches: 48 shrub cards plus 12 grass, within the reported 1,956-triangle budget. The five-view native capture report is [candidate-native-r3-final](../woodland-edges/candidate-native-r3-final/report.json), SHA-256 `e3c2883b894ef303ab8628cc5ca27efc864deda379e91dbafd4f2d1752b38390`. The source recipe and builder hashes match that report. The builder copy also includes the reviewed one-line comment correction; the executable statements are unchanged.

Each final app differs from its own diagnostic parent only in `app/data/woodland_edges.json` and `app/scenery/woodland_edge_habitat.gd`. The UID sidecar is unchanged. Each entire `.godot` cache and its `assets/` and `tools/` directories were copied and verified byte-for-byte against the corresponding parent. The baseline/candidate historical tree-setting differences therefore remain exactly as recorded by the parent freeze receipt.

No fresh headless editor import was performed; the inherited `.godot` caches were copied and verified unchanged. After the freeze, native lifecycle checks passed for 20 Home→Fly→Home cycles (without reset) and 20 Home→RC garage→reset→Home cycles. Two exact trim/runway replays also passed with `solver_changed=false`. Reports are retained in the [lifecycle evidence](../lifecycle-final/README.md) and [world/replay evidence](../world-final/README.md). The final app source fingerprints remain baseline `0900a8238274cdd3d63d40ee43a185c1a036b3bba00f5514fd491d495d706cba` and candidate `b18a46dfa66d800e8179b7e32be5ea7a27b8e253bacab7da2c23141ca85c3eea` (2,750 source files each; `.godot` and `.git` excluded).

## Active-flight comparison

The serial native campaign completed on 2026-10-18 with five alternating baseline/candidate pairs. Each run used a 10-second warmup and 60-second measurement in a real active flight, at 1280×720 and 60 fps with V-sync disabled. The baseline ran with tree wind off; the candidate ran with tree wind on. Both used default tree cell size and default grass quality. All ten runs used the same route, weather, scenario hash `b0512c277c023bd34c1716f2790f508749722e7c13efbb810daf1d1da6a1b336`, and input-tape hash `b987a7cf4df577bb3d96fd290cdefa1824604cdec525642a6deacd87ffdcd6e5`.

All ten reports completed with exit code 0, no native `ERROR` marker, no pause, crash, or fault, and nonzero live input. Measured physics ticks ranged from 14,390 to 14,400 at 240 Hz; raw-input reads ranged from 16,759 to 16,803. Both baseline and candidate met the per-run limits of p95 ≤18 ms and p99 ≤25 ms. The candidate simulation-to-wall ratios ranged from 0.999514 to 0.999954. Every paired p95 change was within +0.5 ms; the median candidate-minus-baseline p95 change was +0.036 ms.

| Pair | Order | Baseline p95 / p99 (ms) | Candidate p95 / p99 (ms) | Δp95 (ms) | Baseline / candidate sim-to-wall | Baseline / candidate max (ms) |
|---|---|---:|---:|---:|---:|---:|
| 1 | baseline → candidate | 17.726 / 18.822 | 17.714 / 18.616 | −0.012 | 1.000037 / 0.999514 | 26.810 / 73.574 |
| 2 | candidate → baseline | 17.732 / 19.580 | 17.807 / 19.464 | +0.075 | 0.999832 / 0.999954 | 71.559 / 63.747 |
| 3 | baseline → candidate | 17.823 / 19.912 | 17.689 / 19.447 | −0.134 | 0.999746 / 0.999930 | 71.526 / 62.911 |
| 4 | candidate → baseline | 17.724 / 19.089 | 17.786 / 19.279 | +0.062 | 0.999698 / 0.999782 | 78.352 / 79.995 |
| 5 | baseline → candidate | 17.730 / 19.280 | 17.766 / 19.017 | +0.036 | 0.999630 / 0.999860 | 84.100 / 70.223 |

Across pairs, candidate p95 deltas ranged from −0.134 to +0.075 ms (median +0.036 ms); candidate p99 deltas ranged from −0.465 to +0.190 ms. The largest measured hitch was 84.100 ms in pair 5 baseline. Pair 1 candidate reached 73.574 ms against 26.810 ms for that pair’s baseline. These maxima remain in the raw reports and are not hidden by the percentile results.

Godot’s renderer-reported video-memory counter was 366,793,839 B at p95 for every baseline run and 378,032,375–380,162,567 B for candidate runs. Visible draw-call p95 increased from 75 to 76 and visible primitive p95 from 186,956 to 187,111. These are renderer counters; physical GPU residency was not measured. GPU render-time p95 ranged from 3.789–5.242 ms in baselines and 4.375–5.221 ms in candidates. The full per-run wall, render, memory, input and clock metrics are in [`active-flight/series.json`](active-flight/series.json); compressed raw frame reports and their hash bindings are described in [`active-flight/report-storage-receipt.json`](active-flight/report-storage-receipt.json).

The measured host was not idle or exclusive. The 1 Hz census retained 726 samples from 17:02:21Z through 17:15:35Z. It saw no additional Godot or FFmpeg process during any measured window. Blender PID 3340 remained low activity (0.9–1.3% mean and at most 5.7% of one logical CPU per run), which does not indicate an active Blender render. Task Manager used 26.7–27.7% of one logical CPU on average and stayed at or above 20% in nearly every sampled second of every run. Other editor processes also had intermittent CPU bursts; whole-host CPU averaged 11.9–14.5% per run and peaked between 19.6% and 37.8%. A brief codebase-memory lookup intersected pair 2 for six samples total. No runs were discarded or repeated. These results describe the observed desktop conditions and do not establish exclusive-host performance or general hardware coverage. The complete privacy-limited census is [`process-census-final.jsonl`](process-census-final.jsonl).

The executed runner used the native `.tools/Godot_v4.7.2-stable_win64.exe` (SHA-256 `ab1824f85bfd8e0e4128182c000c4003a3e042245b2967848d089b2a04b22424`) and these selectors:

```powershell
python tools/trees/flight_quality.py `
  --baseline tmp/tree-completion/frozen-natural/baseline/app `
  --candidate tmp/tree-completion/frozen-natural/candidate/app `
  --out docs/research/visual-quality-implementation/L6c/tree-completion/comparison-final/active-flight `
  --pairs 5 --warmup 10 --sample 60 `
  --width 1280 --height 720 --fps 60 `
  --baseline-env OPENRC_TREE_WIND=off `
  --candidate-env OPENRC_TREE_WIND=on
```

The captured output is `active-flight/`; a new execution needs a different empty `--out` directory. Do not substitute the console wrapper or add the enhanced-grass selector to this tree-only comparison. Runner, route, clock definitions and acceptance details are in the [active-flight harness guide](../flight-quality-harness.md).

## Process and CPU census

The external sampler ran in a second terminal, waited for `flight_quality.py`, followed the complete series at 1 Hz, and stopped three seconds after the runner exited. It recorded its Python/psutil versions and sampling policy in the census header.

```powershell
python tools/trees/flight_process_census.py `
  --out docs/research/visual-quality-implementation/L6c/tree-completion/comparison-final/process-census-final.jsonl
```

The sampler records UTC and monotonic time, total CPU, PID, name and CPU for Godot, Blender and FFmpeg processes. It retains full command lines only when a renderer's executable or arguments identify this repository. Other current-user processes at or above 1% of one logical CPU are recorded with PID, name and CPU only; other processes' arguments are never written. All renderer names are scanned regardless of user, while total CPU covers the whole system. It refuses to overwrite an existing census file. No process was stopped or reprioritized.

Each recorded Godot process and its available project command line was reconciled to the ten runner commands and their start/end times. There was no additional Godot process during any measurement. The observed Task Manager CPU use exceeded the harness’s 20%-for-five-consecutive-samples contention flag in all ten runs. The five observed pairs were retained without repeats; interpret them as desktop-condition measurements rather than an exclusive-host qualification.

The runner validates nonzero live input, advancing physics, no pause/crash/fault, matching route/scenario identities, monotonic wall-clock measurement windows, and absence of native `ERROR` markers. A successful process exit alone is not sufficient. Human review of tree readability remains separate from this performance comparison.

The reports are stored as deterministic gzip files to avoid retaining a second uncompressed copy. `frame_report_sha256` in `series.json` continues to hash the original uncompressed JSON; the receipt binds that hash to each gzip file’s stored-byte hash. To restore all raw reports in place for a downstream reducer:

```powershell
python -c "import gzip,json,pathlib; b=pathlib.Path('docs/research/visual-quality-implementation/L6c/tree-completion/comparison-final/active-flight'); s=json.loads((b/'series.json').read_text()); [(b/r['report_storage']['original_uncompressed_path']).write_bytes(gzip.decompress((b/r['report_storage']['stored_path']).read_bytes())) for r in s['runs']]"
```

The runner’s already-computed paired reduction remains in `series.json`; the restoration command does not alter it.

The prior [comparison-understory stage](../comparison-understory/README.md) is diagnostic only; the original oak-era [temporal clips](../temporal/README.md) also predate the understory and do not depict this freeze.
