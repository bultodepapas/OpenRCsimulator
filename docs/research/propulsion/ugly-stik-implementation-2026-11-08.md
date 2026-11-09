# Ugly Stik two-variant implementation

EL1e-STIK-00…08 · 2026-11-08. Software integration evidence; physical and release qualification remain separate. Current behavior is owned by the [Stik guide](../../UGLY-STIK-PLAN.md), [electric contract](../../ELECTRIC-PROPULSION-PLAN.md), [Workshop guide](../../AIRCRAFT-WORKSHOP.md) and [installation dossier](../../../research/propulsion/stik-6s/README.md). Remaining gates are tracked in the [integration plan](../../plans/ugly-stik-two-variants.md).

## Implemented boundary

The stock list begins basic `jensen-das-ugly-stik-60` → `stik-electric-6s` → Extra. It has nine player choices, eight of them airplanes, with exactly two Stiks. The technical catalog retains twelve configurations, including all three finite-glow Stiks and the historical Skywalker alias. Technical data, CLI routes, saved Workshop bases and specialized fuel tests retain their original identities. Natural Random v1's five-aircraft pool and companion support are unchanged.

The new aircraft uses a Scorpion SII-4020-540KV reference, APC 12x8E and estimated 6S 4000 mAh Gens ace-class pack behavior. Its 2.600082 kg inventory removes glow equipment and the donor's virtual balance fixture. One deterministic installation source generates ideal and finite-pack resources with matching physical inventory. Ordinary flight defaults to pack; Workshop uses explicitly labeled ideal voltage without depletion and refuses a finite-pack trial claim. The independent electric model reuses the airframe without mutating basic instances, shared materials or the global model binding. Its unchanged tricycle wheels use a closed profile-key alias to the donor at the default-registry loading boundary. The global wheel file stays byte-identical (`58a2526829a3e9e529ac16f79a7d135614618c3d70350c2187d804a476e40665`), preserving existing Workshop dependency pins. Explicit profile selections and caller-supplied fixture registries keep their semantics; a missing aliased donor refuses loading.

Saved hidden selections resolve to basic for Home before preview construction. A localized notice explains the effective selection. Loading never rewrites preferences; unrelated saves retain the original ID until an explicit stock choice or successful Fly save. Schema 6 remains unchanged. Readers and writers share a bounded directory lock; temporary serialization and staged validated recovery protect accepted bytes during replacement failure. Interrupted Windows replacement is recoverable from one verified previous file. An orphaned lock fails closed and requires the documented [explicit recovery](../../TOOLS.md#preference-file-recovery) after closing all instances. This does not claim power-loss durability or automatic dead-process lock reclamation.

Composed debug setup/fly requests reject hidden or unknown stock IDs before changing other fields or starting a previous aircraft. Technical catalog IDs are reported separately. The existing strict physical, presentation and source-pin validation remains enabled.

## Identity and preservation

Implementation started from `f96f9e678a0583176b0cb273e4b15abfb4d73652` with unrelated work present. Parallel helicopter, rendering, UI, CI and recorder changes subsequently entered the shared tree; a whole-tree test result is valid only for its recorded inputs. The contact adapter was isolated in commit `84a0d98d1e1ffaae4950532e653390f5a9abe590`; the wheel-key alias and independent compatibility test are in `b219c6b21df523359b16f87b870788a4cbac96cd`.

| Resource | SHA-256 |
| --- | --- |
| Basic aircraft, unchanged | `5635e7f7b2a44bdfc7db5ad2646c74654af42944133bc39a91a0908bac887b66` |
| Basic physical model manifest, unchanged | `912bee8177251ecf7ed58cb50ee05439d2806ca181c41f86b397b40555b40e55` |
| Basic Workshop descriptor, unchanged | `325ec9ba7e1ab684683e7c1c1d398f5d7961f524e0f6adf861bf23eabb70a236` |
| Electric ideal aircraft | `830137e2daaf43295c404ad0af6676ac44a8fb0102c2d2b81c2c0b4a395337e6` |
| Electric pack aircraft | `fbbfd74512b8e3141adc530296687721c5ca7e3d94a38c384fbaf10f03c2c73e` |
| New BAT pack record | `bda884c9bd3d82a0535bef32517cf82773c5aba9ee38178012659f9086e981d1` |
| Windows Godot console, 4.8-beta2 `cafc17a19` | `1a470886fc810b81a61e01bad7678e38989f1c94cf8e9733bfd1026224b3f42b` |

Basic goldens and tolerances were not re-recorded or relaxed. Existing pack records and donor-derived aircraft outputs remain unchanged. The generated economy worked example refreshes only its physical/costing source hashes; all amounts and calculations remain unchanged. The shared overlay-registry source change legitimately refreshed MoonRunner's proof/model/customization/descriptor chain; it did not alter MoonRunner physical data. Historical documents remain readable; stale strict trial pins are refused instead of silently rebased. Exact-byte generated proof and historical fixtures now have explicit LF checkout rules.

## Executed checks

Godot scripts ran through `tools/godot/run_checked.py` with the pinned Windows editor, headless reference solver and isolated test settings. Zero exit alone was not treated as success. Retained local artifacts are under `D:/OpenRCsimulator-evidence/stik-two-variants-20261108/`; images and exported packages are outside Git. Counts below are bounded assertions, not physical validation or a substitute for required CI.

| Check | Result and scope |
| --- | --- |
| Basic goldens | Four flights pass before and after the contact change; unchanged data/tolerances, maximum position difference about `7.1e-15 m`. |
| Technical catalog | 120 checks pass, admitting all twelve configurations and retaining the three hidden fuel-law cases. |
| New electrical installation | 32 checks pass, including explicit wheel-profile admission and unchanged donor gear: v2 admission, malformed input refusal, inventory/mode consistency, steady screening, sag/cutoff and exact checkpoint replay. |
| Wheel alias and compatibility | 15 checks pass, including an unchanged pre-cutover basic Workshop dependency manifest, actual aircraft ID, exact gear, explicit-profile precedence, Workshop renaming, custom source paths and malformed/wrong-pin refusal. Disposable donor removal refuses both modes (2/2); original source bytes restored. |
| Contact composition | 12 checks pass: one-piece equivalence, bounded piece/event counts, chronology at late absolute clocks, rotor/energy ties and failure atomicity. |
| New ground lifecycle | 22 checks pass: 80.47 mm static prop clearance, 67.55 mm minimum over the bounded two-second roll, strike/reset, depleted-start refusal, installed-policy guard and exact ground replay. |
| Flight card, both modes | Each mode completes all six requested `ft-card-v5` cases: trim sweep, power-off stall, maximum speed, hands off, takeoff and landing. Ideal takeoff: 2.86 s / 13.2 m / 15.92 m/s; pack: 2.71 s / 12.7 m / 16.16 m/s. Both land at 0.50 m/s sink without bounce, with 49.4 m / 49.3 m rollout. Hands-off runs complete for 30 s. All maneuver traces report applied wheel profiles and the original registry hash. No missing/skipped cases. See the test-only pack routing scope below. |
| Low charge | At estimated 8% charge, soft cutoff occurs at tick 3,817 / 15.90 s; throttle release resets the supervisor. |
| Existing battery/contact cases | Battery step 63, battery session 43, ground battery 384 and SF event-publication 60 checks pass; battery data 56 and ESC 36 checks pass. |
| Models and Workshop | Electric overlay 29, MoonRunner 55, synthetic package 154, general manifest 97, descriptor 126 and presentation 92 checks pass. Final stable compiler 392, store 151, bundle 28, trial 48 and presentation 92 checks pass; Workshop UI also passes. |
| Stock/persistence/automation | `test_stik_stock_selection.gd` passes three hidden IDs × schemas 1/6/99, no-write load, unrelated saves, explicit commits, replacement/recovery failures, protected schemas, busy readers/writers and composed debug rejection. |
| UI | Aircraft navigation, flow, preserved choices, Home and Workshop suites pass. Finite-fuel UI coverage uses the still-stock finite-glow Extra rather than dropping that behavior. |
| Debug | Bridge suites pass; contract suite 26 checks; Python debug client 66 tests pass with one existing skip. |
| Economy | Python source/runtime suite 67 tests pass; Godot 102 checks pass with all twelve technical routes; electric prices remain explicitly incomplete. |
| Flight logs | 4,387 checks pass across the retained paths plus ideal/pack E6; complete recordings and negative cases retained under `lead/flight-log-suite`. |
| Mass/balance report | Eight tests and drift check pass; two new mode rows added with all eighteen existing rows semantically unchanged. The same-airframe neutral-point estimate gives about 3.8% MAC static margin; powered stability and actual CG range remain unqualified. |
| Fresh checkout | Model generation's 19 tests pass in LF and CRLF clones after pinning the electric source proof; the two historical fixtures also remain byte-stable. |
| Generated inputs | Source checker passes the new BAT/installation/costing/proof/model/customization/descriptor/economy checks and retained donor generation. |
| Native Linux | All 19 source-bound oracle gates accepted by the unchanged installer; 24 verifier self-tests pass. Actual production native/reference fingerprints match in all six E6 ideal/pack × trim/half-power/runway rows and all three corresponding basic rows, 1,200 ticks each. Calm/soft-hull scope only. |
| Broad integration | The local source phase and 714/714 non-unit parse complement passed before the final wheel-loader alias. The final generated-source checker passes again on the frozen alias. Final loader compilation and affected behavior pass the focused tests; no whole-tree or required-CI pass is claimed. |

Parse receipt: `full-checks/roster-parse-tmp.Lc0RHENwAz.json`, SHA-256 `9902c547726a58986dfd8c883493547071fdbed986b28e8af4fefcd5c723c632`. This is the pre-alias non-unit complement, not a final whole-tree receipt.

The new `test_*.gd` files enter the existing `phase_roster.py` full unit roster automatically. No replacement runner, reduced physics tolerance or omitted technical fixture was introduced.

The lighter pack installation needs two runway contact pieces at 240 Hz. The finite-battery session policy composes the existing battery step internally and samples its supervisor once per outer tick. It suppresses the kernel substep request only while the installed callback is exactly its own electric policy. A cleared callback returns the true contact count; a foreign policy remains subject to the kernel's original rejection. `Simulation` and the one-piece route remain unchanged.

## Basic replay and companion source pins

The final stable alias candidate passes all four unchanged basic goldens and all 4,387 flight-log assertions, including ideal/pack E6 recordings, exact replay and negative cases. Artifacts are under `lead/alias-final-flight-logs` and the matching `lead/alias-final-test_*.log` files.

An earlier implementation recording, `lead/basic-live.orfl`, contains 6,428 samples / 26.779 s. Its matching-snapshot exact replay reports `status=ok`, `complete=true`, `solver_changed=false`, `mode=exact`, and `gdscript_reference`. Log SHA-256 is `f9845ce9e28a77b540eaf1f46d84e8bf64a16d41e765bc40512ae211823ec5c5`; that recorded/replayed solver identity is `0506cabe2f96eab59ccadf3dd2f2ca58d620edbdd5431b26ae9ad53ca00cb362`. It predates the wheel-loader alias and is not a pre-change baseline or exact replay of the final source. Old checkpoints/logs retain their strict matching-source requirement.

Nine retained companion tapes, each 2,881 rows, compare byte-identically after the alias. The [final source rebind receipt](../ai-companions/AFC-02/rebinds/2026-11-08-1ebf4fdf-to-b5332032.json) qualifies committed source `b219c6b21…` at normalized AFC identity `b53320325161999038a54036ff057bf83eb8dcfe6425e2b214b1d7907e0c1cd3`. It was produced by the unchanged acceptance tool in an isolated clean worktree, with `--baseline full`. The strict companion profile test passes 44/44 there. Profile, qualification and receipt were committed together in `67cec4f52`; the earlier contact adapter was qualified in the preceding [integrated receipt](../ai-companions/AFC-02/rebinds/2026-11-08-4b9ae898-to-1ebf4fdf.json).

The shared tree still contains unrelated uncommitted recorder/trace changes, yielding AFC identity `bfd0003bda1bb766c90bc9c564d692de56e634fc30f2dea6a8377142ddd68db0`. That combined draft is not the accepted source revision and remains correctly refused by the companion guard. Preserve those edits; their owner must commit and requalify the combined solver. No guard or source hash was bypassed to qualify this feature's committed solver changes.

## Export and rendered inspection

The frozen-alias PCK `electric-models/stik-frozen-alias-candidate.pck` is 1,612,511,468 bytes, SHA-256 `9ae37c31b8660b789fea119de6b0c1b333ed1110cd775f68d3bb015d3774538d`. An empty project launched with `--main-pack` passes 64 checks for both data modes, applied donor wheels/original registry hash, model/customization, paint, strike radius, descriptors, all twelve economy routes, hidden compatibility fixtures and the three frozen basic identities. All four overlay GDScripts are compiled/remapped; raw script fallback is absent. The required ground DLL is staged beside the host, SHA-256 `5a89d82a25b0144859c7e96963ca2ef4888f19997acbf6a23d760bcd26235032`, matching the checkout.

Report: `electric-models/frozen-alias-pck-smoke-lu8ki_pn/report.json`; probe SHA-256 `7380937aa2b74fc53d36fd1e33a522dd3620f6f1db2b8ff1788168d96bd9ccc6`. The export identifies itself as `export-manual` because release identity variables were unset. This proves resources on the pinned editor host, not a Windows executable, release, native flight-stage parity or companion qualification of the combined recorder draft. The separate committed-source companion pin refresh followed this resource export.

Actual Windows rendering at 1920×1080 inspected the final electric Home preview, pack-mode flight/HUD and ideal-mode Workshop. `lead/rendered/shots/shot-7756-002.png` shows the ready electric model; `004` shows its 6S pack flight; `005` shows Workshop's ideal limitation. `lead/rendered-final/shots/shot-58576-001.png` shows the localized retained-glow fallback, and `002` shows Russian Practice after reducing utility margins while keeping 22 px text. Home tests also pass the corrected layout. Both debug sessions ended cleanly without leaked objects.

The uncontrolled full-throttle runway flight eventually nosed over and struck the propeller. It demonstrates stop/crash handling. The separate closed-loop flight cards (`electric-models/ft-frozen-alias-ideal` and `electric-models/ft-frozen-alias-pack`) complete all six requested cases in each mode, including takeoff and landing. These are numerical controller cases, not pilot acceptance. The [retained case/trace assessment](ugly-stik-flight-card-2026-11-08.json) has SHA-256 `361b86a9f20b0c565b42a184806986b84de595d65d187fbf08544c4200e5625b`; its source summaries are `f0d69eb173d3027101904e2c443a6146505d5882c1a95274b9c6621f193d9e3f` (ideal) and `e59beeb421f94568f31a7930d2c295b1c78d3332dbb18ace0cfa1e7da59c5465` (pack). Each case starts afresh; they are not a continuous flight or endurance test. The existing card always loads the catalog principal source and has no battery flag. Its pack run therefore uses a disposable app whose sole difference among 1,858 script/JSON/project inputs is replacing that principal resource with the exact declared pack bytes (`fbbfd745…`). Trace metadata confirms `electric-pack-ecm-coupled-events-v1`; this is a documented test-only route, with ordinary catalog/UI routing verified separately. Concurrent-workload hitches were observed; these captures do not qualify performance.

The broad run found the missing E6 wheel registration. The final alias closes that failure without changing the global registry. An intermediate run while inputs were changing also failed four ground-battery identity comparisons; all 384 checks pass on the frozen alias candidate. Intermediate failed reports and superseded wheel-append exports/cards remain diagnostic evidence on D:, not final qualification.

## Scoped Linux native qualification

The isolated build accepts all 19 required oracle gates, including the deliberately failing mutant control. The native builder now pins both E6 data modes, its BAT record, the contact helper and the unchanged wheel registry. The common oracle stamps that registry too. The propeller-specific exact set includes E6; the existing two-model electric component-oracle set remains unchanged. Verifier fixtures reject missing/unexpected propeller IDs and a mutated wheel registry (24 tests pass under WSL/Linux).

The actual Linux x86_64 production fleet runs pass six E6 rows (ideal/pack × trim, half-power and runway) and three basic rows under calm weather with soft-hull contacts. Each row uses 240 warmup plus 960 sample ticks and reports `actual=native` on every requested tick, with the same reference fingerprint. Each electric runway row makes 9,600 native stage calls because its ground policy owns two pieces. These are scoped software checks, not a full fleet, weather envelope or timing qualification.

Evidence root: `D:/OpenRCsimulator-evidence/stik-two-variants-20261108/native-e6-qualification-20261108/`; the E6 fleet report is `tmp/native-kernel/fleet-20261108T223148183384Z.json`. Linux Godot SHA-256 is `34d0599a1f17acc76583610969878065d1b1701615af77271e32201351b9c564`; qualified library SHA-256 is `2b92233178be5a5fdaf803846d1ef123939b68380e19fb367c251d8538a7662c`. The [retained installed receipt](ugly-stik-native-receipt-2026-11-08.json) SHA-256 is `b36b7f172ce2cd50bfcae26fd912a57bc3a74bc3cab66bfd0dca30b2543e046f`, identical to the isolated accepted receipt.

After confirming all 135 mirrored inputs and the harness/builder/toolchain identities still matched the shared tree, the unchanged installer also accepted the live installation. Its CLI fixes the evidence directory, so the retained `tmp/nk3-ci/shared-install-guarded.py` redirects only `TOOL_ROOT` and `locked.TOOL_ROOT` to the verified D: evidence and invokes the original `install_app()`. No source, identity, expected-set or guard result was overridden. Historical installed artifacts are preserved under `tmp/nk3-ci/shared-historical-native-kernel/`; the shared extension list's bytes/mtime stayed unchanged. No qualification engine remains active.

## Open qualification

- The conditional motor fit differs from the manufacturer nominal static point by about −12% current and +15% thrust. It is estimated, not a measured winding identification. APC tables are computational predictions.
- The estimated zero-speed full-duty pack transient reaches about 194.85 A. No motor/ESC current limiter, thermal state, startup ramp or overspeed protection is implemented. Generic LVC is not a claim about Tribunus firmware. Hardware startup/cooling/wiring, physical pack fit, normal landing/taxi clearance and held-out flight/endurance measurements remain open.
- Broader native fleet/weather coverage, Windows/macOS native admission, 1080p Gate P, required CI and full platform exports retain their existing acceptance gates. The scoped Linux proof, Windows reference fallback, package smoke test and screenshots do not close them.
- A shared dirty tree cannot be a final accepted companion source identity. Rebind after the recorder owner commits, then run `test_companions_profiles.gd` on that stable candidate.

Final working-tree checks also report no whitespace errors across the owned paths, 760 existing local documentation targets and the four preserved basic/model/descriptor/global-wheel hashes above. The documentation check validates target existence, not every historical anchor or external page.

Useful reproduction commands are the existing `app/test.sh`, `tools/companions/rebind.py --baseline full`, and the checked runner for `test_stik_electric_6s.gd`, `test_stik_electric_6s_ground.gd`, `test_stik_electric_6s_low_soc.gd`, `test_stik_electric_overlay.gd`, `test_stik_stock_selection.gd`, `test_electric_contact_step.gd` and `test_golden.gd`. Run a source generator only through its own documented entry point; each supports the existing freshness workflow.
