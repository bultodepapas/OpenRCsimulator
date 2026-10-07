# 12 — Diagnosable macOS releases and matching symbols

2026-10-07 · DT-00-R2 · **Research complete; no Mac crash or symbolication was performed.**

## Question and audit

What evidence will explain “does not open” or “stutters on my M1” after distribution? The current build identity and `openrc-frametimes v2` are useful, but they do not retain native crash symbols or establish Finder launch, Gatekeeper state or an ARM64 process. `app/input/input_report.gd` now provides a separate device diagnostic route; its callback timestamps are not USB or physical presentation timing.

The current macOS checker parses slices and signature flags; it does not cryptographically verify the signature or retain a complete Mach-O UUID/symbol inventory. The pipeline publishes packages/checksums without a matching-dSYM retention policy. Before promising symbolicated native crash support, determine whether exact official template symbols are available. Building a new binary from the same tag is not an automatic match.

## Primary-source findings

Apple ties a binary to its debug-symbol file using its build UUID. A dSYM from another compilation cannot be assumed compatible. Archive matching symbols for each shipped native component/architecture; a GDScript line error and a native engine crash need different evidence. [Building debugging information](https://developer.apple.com/documentation/xcode/building-your-app-to-include-debugging-information), [locating matching symbols](https://developer.apple.com/documentation/xcode/locating-a-missing-debug-symbol-file).

**Inference for Godot packaging:** different game releases can reuse the same native export template while changing packed scripts/assets. A native UUID identifies the symbol-compatible binary, not the whole game revision. Always retain package digest and embedded build identity alongside UUIDs; never replace them with the UUID alone.

Godot supports an explicit `--log-file` engine argument; file logging/output buffering are described separately from the editor Output panel. Use an absolute writable path and capture process exit/stdout/stderr as well. A process can terminate before the application initializes logging. [Command line](https://docs.godotengine.org/en/4.7/tutorials/editor/command_line_tutorial.html), [logging](https://docs.godotengine.org/en/4.7/tutorials/scripting/debug/output_panel.html).

Default macOS `user://` data resides in Application Support. Logs, diagnostic reports and traces belong in writable user-selected/user-data locations, never inside the signed application bundle. An install-directory change must not relocate personal calibration. [Godot paths](https://docs.godotengine.org/en/4.7/tutorials/io/data_paths.html).

## Small diagnostic contract

| Failure layer | Evidence to preserve | What it cannot establish |
| --- | --- | --- |
| Download/trust | Package SHA-256, quarantine/trust outcome, exact error wording, signature/notary results | A valid checksum alone is not trusted publisher identity |
| Loader/startup | macOS build, process architecture, executable/slice UUIDs, missing-library message and engine log if created | A main executable ARM64 slice does not cover every dependency |
| Godot/GDScript | Build ID, engine hash, script error/backtrace, active scene/aircraft, reproduction steps | Debug logs are not physical flight validation |
| Display/performance | Actual renderer/driver/device, backing pixels, FOV/scale, refresh/cap, RAM/power state, raw frame report | A callback timestamp is not display presentation |
| Radio/audio | Device route and identity, diagnostic format/version, reconnect sequence; omit unnecessary serials | Event arrivals do not measure hardware latency |
| Native crash/hang | OS crash report or short process sample, matched binary/dSYM UUIDs when available | Rebuilt “equivalent” symbols cannot reliably decode a different binary |

Keep collection local and manual initially: one explicit export of a bounded report to a chosen path. Do not add telemetry, upload reports, collect the entire user directory, or require Developer Tools on the pilot's Mac. Redact usernames/home paths, device serials and unrelated OS log records before publishing evidence. This is a support design proposal, not a new runtime subsystem requirement.

## Developer-side Mac recipe, unexecuted

```sh
dwarfdump --uuid "/Applications/OpenRC Simulator.app/Contents/MacOS/OpenRC Simulator"
dwarfdump --uuid "/path/to/matching/OpenRC Simulator.dSYM"
codesign --verify --deep --strict --verbose=2 "/Applications/OpenRC Simulator.app"
```

Resolve `CFBundleExecutable` and dSYM availability first; the shown basenames are illustrative. Save complete command exit/output alongside the final package hash. Verify UUID equality per architecture before using Xcode or `atos`; do not claim line-level engine symbolication if matching official template symbols cannot be obtained. Private symbols need not be bundled in the public app.

For a reproducible launch failure, compare Finder launch with a separately labeled direct-binary launch using `--verbose --log-file <absolute-path>`. Do not insert a trailing `--` diagnostic label into an ordinary Home launch: app arguments affect its route. An explicit `--input-report` run is a device diagnostic, not proof that Home or flight launches.

## Acceptance and plan change

**DT-08b:** retain package/build/UUID provenance and record symbol availability explicitly. **DT-12:** rehearse one startup failure, one recoverable settings/trace error and a controlled crash of a disposable diagnostic fixture; demonstrate that the resulting report identifies the exact candidate. Do not deliberately crash the owner's live flight or ship a crash trigger.

**DT-13:** deliver a short Mac troubleshooting page covering trusted download, supported OS/RAM/backend, windowed recovery, local log/report location and reporting steps. Keep unsupported experiments and unsigned engineering bypass instructions out of the accepted public release path.

Sources accessed 2026-10-07. Apple DocC payloads were read directly for both linked symbol documents. Availability of matching official-template dSYMs was not established; no symbols were generated or matched and no Mac command above was run. The output is an evidence-retention plan, not crash coverage certification.
