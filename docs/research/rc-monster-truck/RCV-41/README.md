# RCV-41 — Identity verification CPU optimization

2026-10-15. MONSTER CAR 2 uses **10.4% less whole-session CPU time per tick** in the paired source-runtime workload below. Artifact verification rereads the files on every check and reuses a SHA-256 digest only when the newly read bytes exactly match a retained buffer. The physics equations, 240 Hz rate, contact queries, native binary, rendering, sound and effects are unchanged.

## Exploration and accepted change

The post-RCV-40 [baseline profile](baseline.json) attributed 1.432 ms/tick to the identity guard. The [exploration receipt](exploration.json) compares five repeated batches of built-in file hashing, buffered hashing, file-existence checks, the original artifact lookup and exact-content digest reuse. Buffered hashing alone was inconsistent and was rejected. Content comparison was selected because it avoids recomputing SHA-256 while retaining a full read; it never accepts a path, timestamp or file size as proof of identical contents.

`VehicleDynamics._content_checked_file_sha256` keeps at most **two entries of 256 KiB each** (512 KiB retained file contents maximum). It reads each eligible file completely, rejects incomplete/error reads, compares the bytes, and only then returns a previous digest. New or changed contents are hashed and retained. Larger artifacts use Godot's streaming `FileAccess.get_sha256` and are not retained. Original source precedence and `.remap` fallback remain intact.

VehicleDynamics and Session also use native hexadecimal validation with the original string type, 64-character, lowercase and empty-value rules. Explicit sign rejection is necessary because Godot's native parser accepts an optional sign. Deep-copy removal, control-tape append rewrites and further road-sampler changes were reviewed but deferred to keep this phase focused on the measured identity cost and its compatibility boundary.

## Measured outcome

Godot 4.7.2 official Windows debug runtime, Ryzen 9 5900X, native ground-body backend, source project, headless and audio disabled. [Paired session measurements](paired.json) use three rounds of 60 warmup plus 960 measured ticks. Baseline and candidate alternate first execution each tick, receiving the same fixed controls. Both use the same current source bytes; the baseline restores the original artifact lookup and digest validators while inheriting the production simulation. Exact comparisons occur outside the timing window.

| CPU measurement | Before | After | Reduction |
| --- | ---: | ---: | ---: |
| Whole session, median of round means | 6.187 ms/tick | 5.545 ms/tick | 10.4% |
| Whole session, median of round p95s | 7.705 ms/tick | 7.008 ms/tick | 9.0% |
| Artifact lookup pair: Nitro + body source | 1.468 ms/pair | 0.910 ms/pair | 38.0% |

The three whole-session reductions are 10.4%, 10.0% and 9.6%. The [artifact comparison](identity.json) uses five alternating batches, 20 warmup pairs and 200 measured pairs per batch. The [candidate instrumented profile](candidate.json) attributes 0.922 ms/tick to the guard; separate profile processes are diagnostic, not the paired speedup estimate. The [summary](summary.json) retains raw-evidence hashes and checks current source identities.

Concurrent unrelated work affected absolute timings on this shared host. These are CPU measurements of the tested source runtime, not an FPS/GPU result or release-package qualification. Larger remapped bytecode may use the uncached streaming path. At 5.545 ms/tick, the measured session still exceeds the 4.167 ms interval at 240 Hz; the real-time and stricter track performance gates remain open.

## Verification and saved-state identities

- **24 artifact comparisons** match serialized result dictionaries: empty/missing files, arbitrary binary data, same-length rewrite with an observed unchanged modification timestamp, truncation, deletion/recreation, cache limit/eviction, large-file fallback, remapped payload rewrites, redirected targets, source precedence and invalid target metadata. Cache bounds are checked explicitly.
- **246 digest cases** pass: 82 VehicleDynamics cases and 164 Session cases covering both empty policies, valid and malformed seeded values, types, signs, prefixes, case, Unicode and whitespace. Permanent Session regression checks cover the strict grammar too.
- **3,060 paired ticks** preserve state and telemetry bytes, control/event tapes and checkpoints within each paired round. Independent baseline/candidate runs each pass checkpoint restoration, official replay and full-trajectory replay. All trajectory digests are `d2c255aee62148ea79908da716d1c1c6279b20b22e5b1a88bc9e261597908eb8` (1,020 states per trajectory, including warmup).
- All **eight focused regression suites** pass: **352 numbered checks** plus the aggregate course suite. They cover both vehicle sessions, Nitro dynamics/service, body dynamics with native/reference identity and backend switching, airfield sampling, damage replay and obstacle contacts. [Logs and source hashes](checks/verification.json) contain no engine/script/shader errors. The full repository suite, rendering, export and packaged native smoke were not run.

`solver_changed=true` records the changed implementation-source identity; **the equations and native binary did not change**. Course identity also changes because its manifest pins the body adapter source, and Session pins its own integration source. Historical source-pinned checkpoints/recordings remain incompatible under existing guards. The paired comparison uses matching current artifact identities to isolate implementation cost; it does not bypass an old-recording compatibility check. Numerical equivalence in these tests is not physical calibration.

## Reproduce

The [vehicle guide](../../../../research/rc-monster-truck/monster-car-2/README.md) owns operation. [`rcv41/`](../../../../research/rc-monster-truck/monster-car-2/rcv41/) retains the original artifact helpers, baseline Session overrides, paired/component harnesses, profile wrapper and validators. Run Godot processes sequentially from the repository root with an existing output directory:

```powershell
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script ../research/rc-monster-truck/monster-car-2/rcv41/bench_identity.gd -- --output=C:/path/to/identity.json
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script ../research/rc-monster-truck/monster-car-2/rcv41/bench_pair.gd -- --output=C:/path/to/paired.json
& .tools/Godot_v4.7.2-stable_win64_console.exe --headless --path app --audio-driver Dummy --script ../research/rc-monster-truck/monster-car-2/rcv41/bench_session.gd -- --output=C:/path/to/candidate.json
python research/rc-monster-truck/monster-car-2/rcv41/verify.py --godot .tools/Godot_v4.7.2-stable_win64_console.exe --out C:/path/to/checks
python research/rc-monster-truck/monster-car-2/rcv41/summarize.py
```

The summary validator reads the canonical evidence directory. The baseline profile and exploration were captured before integration; the paired harness reproduces the original identity work without replacing production files. Component fixtures are created in unique directories under ignored `tmp/rcv41/`. `verify.py --validate-existing` reparses retained logs only after verifying their hashes, source/test identities and recorded exits; it was used to recognize the damage suite's `19/19 checks passed` summary without rerunning already successful tests.

Godot's [FileAccess reference](https://docs.godotengine.org/en/4.7/classes/class_fileaccess.html) defines raw reads and empty-on-failure file hashes; [HashingContext](https://docs.godotengine.org/en/4.7/classes/class_hashingcontext.html) provides binary SHA-256; [String](https://docs.godotengine.org/en/4.7/classes/class_string.html#class-string-method-is-valid-hex-number) documents optional signs in hexadecimal validation. Consulted 2026-10-15. The [RCV-40 report](../RCV-40/README.md) owns the preceding terrain/track optimization and its measurements.
