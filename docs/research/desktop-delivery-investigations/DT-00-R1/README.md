# DT-00-R1 — Twelve desktop delivery investigations

2026-10-07 · **Complete: research and isolated probes. Native desktop acceptance and optimization measurements remain pending.**

This second round strengthens [Desktop Delivery Plan, revision 2](../../../DESKTOP-DELIVERY-PLAN.md) after the [initial three reports](../DT-00/README.md). Each investigation answers a different delivery question, links primary sources, distinguishes observations from proposals, and defines implementation proof. None changes application behavior.

## Findings and decisions

| Investigation | Main finding | Plan consequence |
| --- | --- | --- |
| [01 — Windows installer lifecycle](01-windows-installer-lifecycle.md) | Different builds can share the same PE version; installer defaults can retain the old executable | DT-09b tests same-version replacement, stable installation identity, graceful close and every signature |
| [02 — macOS trust pipeline](02-macos-trust-pipeline.md) | ZIP and DMG require different notarization/stapling sequences | DT-09c freezes the container recipe and verifies the downloaded, quarantined artifact online/offline |
| [03 — Linux runtime contract](03-linux-runtime-contract.md) | An ELF dependency inventory does not establish supported distributions, display backends or radio access | DT-01/09d require native evidence; defer AppImage/Flatpak until a measured need |
| [04 — Fullscreen transactions](04-fullscreen-transactions.md) | A mode request is not confirmation of an effective, usable display | DT-03/04 bound transitions, read back state, recover interruption and preserve automation routes |
| [05 — DPI, camera and readability](05-dpi-camera-readability.md) | OS scaling, rendering resolution, UI scale and camera autozoom are separate variables | DT-05/11c record all four and compare matched aircraft pose/distance |
| [06 — Native close, suspend and audio](06-native-close-suspend-audio.md) | Native close bypasses the current trace-save guard; a naive redirect still hides failed saves | DT-05a adds visible retry/discard/cancel and real close/sleep/audio-device tests |
| [07 — Release provenance](07-release-provenance.md) | Executed Git probe: untracked files do not change `git describe --dirty` | DT-08a requires a complete source/input inventory and promotes tested final bytes without rebuilding |
| [08 — Native test strategy](08-native-test-strategy.md) | Cross-export, native CI and owner hardware acceptance establish different support levels | DT-02 records these tiers and tests the final artifact with host-level events |
| [09 — Performance statistics](09-performance-statistics.md) | Callback cadence does not measure presentation; three runs are screening evidence | DT-10a qualifies clocks, quantiles, paired differences and uncertainty |
| [10 — Settings durability](10-settings-durability.md) | Executed copied-module probe reproduces lost updates from stale readers; future-schema protection works | DT-03a defines writer policy, stable data identity and interrupted-save recovery |
| [11 — Startup and loading](11-startup-loading.md) | Threaded resource loading does not move procedural construction; shader baking does not support Compatibility | DT-11a follows a measured stage breakdown and keeps simulation/audio held until ready |
| [12 — Installed USB radio](12-radio-export-contract.md) | Persistent keys omit runtime ID; synthetic profile-selection cases expose assumptions requiring real-device proof | DT-05b records hardware/firmware/mode, selection, calibration and safe reconnection |

Priority remains **DT-01 → DT-02 → DT-03/03a/04**: baseline, native harness, then recoverable fullscreen. Native shutdown and settings integrity are correctness prerequisites for installation/upgrade acceptance. DT-06–08 packaging work can proceed with its owners once the native baseline exists. Performance changes remain conditional on measured cost; no renderer migration or physics change follows from this research.

## Evidence and limits

| Evidence | What it establishes |
| --- | --- |
| [Pure-module probe](probes/pure_module_probe.py), [recorded results](probes/pure-module-results.json) | Copied production preferences/catalog/input modules on Godot 4.7.2, isolated XDG paths; stale-reader lost update, future-schema preservation, unknown-key removal and synthetic radio identity/profile behavior. Before/after lint passed |
| [Disposable Git probe](probes/git_untracked_identity.py), [recorded results](probes/git_untracked_identity.result.json) | An untracked resource leaves `git describe --dirty` unchanged while porcelain status detects it |
| [Static ELF probe](probes/linux-elf-static-probe.py), [recorded results](probes/linux-elf-static-probe.json) | Existing local export inspected with `file`/`readelf`, identified by digest; its source provenance is unknown, so it is not the DT-01 baseline |
| [Audit snapshot](audit-snapshot.json) | Final inspected-source hashes and concurrent-work context; probe results retain their own exact source hashes |
| [Source inventory](sources.json) | Deduplicated external references cited by the twelve reports; access limitations remain in each report |
| [Documentation validator](probes/validate_documents.py), [results](validation.json) | Report count, local links, plan step uniqueness, registry consistency, Python syntax, JSON parsing and whitespace |

No full application suite, export, installation, signing, notarization, native display/radio/audio test or performance benchmark ran in this round. A synthetic input dictionary is not a physical transmitter result. A deterministic stale-reader interleaving is not concurrent-process or power-loss testing. Primary documentation describes vendor contracts; native behavior still requires the named hardware and final package.

The shared tree changed during the audit. In particular, input-owner calibration validation and a standalone input-report route supersede parts of the initial snapshot; reports 04, 10 and 12 identify this work without claiming its validation. Freeze a clean candidate before implementation baselines. Existing historical reports remain snapshots of their inspected versions.

Sources were consulted on 2026-10-07. Prefer versioned Godot 4.7 docs and pinned 4.7.2 source; moving vendor pages must be rechecked when selecting tool versions. Reports paraphrase sources and import no third-party code or assets. Repository-authored research/probes retain the repository license; referenced material retains its upstream terms.

Refresh documentation evidence from the repository root with `python3 docs/research/desktop-delivery-investigations/DT-00-R1/probes/validate_documents.py`. This updates the end-of-round snapshot/source inventory and validates files; it does not rerun the recorded probes. Each probe's report supplies its own reproduction command.
