# GDU-12: Godot 4.8 beta2 migration

2026-11-01. The owner requested the official beta2 development engine and completed
local checks. The starting source was `46b004c7b469448c29ef96168da4f03cee2c6d23`.
The exact build is `4.8.beta2.official.cafc17a19`, released on 2026-10-29.
[Official release](https://github.com/godotengine/godot-builds/releases/tag/4.8-beta2)
and [release notes](https://godotengine.org/article/dev-snapshot-godot-4-8-beta-2/)
identify its source and archives. Historical GDU-03/GDU-11 evidence retains its
original engine and source scope.

## Implementation

- Editor archives, extracted Windows/Linux executables, export templates and CI
  use verified official beta2 hashes. Warm caches verify the fixed executable
  hashes and exact version, rather than trusting a mutable local checksum receipt.
  Verified warm calls can overlap; cold installation remains exclusive. The
  historical beta1 getter preserves the same distinction.
- The default macOS exports use the unmodified official templates. Beta2 contains
  the fix for the beta1 debug/release inversion; the old correction helper remains
  only for historical reproduction. Release manifests bind the template actually
  selected by the macOS preset and still reject missing or changed inputs.
- Active launch, flight-log, authoring, performance and graphics tools select beta2.
  Historical performance reports remain readable, and mixed-engine comparison
  pairs are rejected. Landscape material verification requires beta2 by default;
  `--engine beta1` explicitly selects historical evidence.
- The insulator and Turbo Lumber Evolution source pipelines were rerun. Only
  engine provenance and dependent hashes changed; all mesh values are unchanged.
  [Timber measurements](verification/timber-provenance.json) agree between Windows
  and Linux. No physics law, timestep or numerical golden changed.
- [Companion qualification](../../ai-companions/AFC-02-R5/README.md) pins beta2 after
  fresh recording, exact replay and the circuit matrix. Rebind now checks the
  engine and recorded tapes even when the solver hash has not changed.
- The [brake gate](../../../../tools/godot/README.md#fixed-brake-legacy-gate-gp-12)
  first reproduces the unchanged historical goldens using verified beta1, then
  compares the current source against the reconstructed source under beta2.
  It does not rewrite metadata or claim cross-engine exact flight-log replay.
- Native toolchain identities advance only the engine pin. godot-cpp, SCons,
  compiler and extension API dependencies remain unchanged.
- The fuel registry now has an explicit LF checkout rule. Windows CRLF conversion
  changed its exact-byte hash and invalidated P-51/Avanti native startup identities
  on both beta1 and beta2. Restoring the unchanged Git blob restores the existing
  pins; a fresh checkout with `core.autocrlf=true` verifies the rule. No fuel values
  or startup pins changed.
- The [smoke scenario](smoke/README.md) settles the renderer's existing bounded
  weak-reference registry before its object census. The zero-growth assertion
  remains unchanged, and a retained-object negative control still fails.
- The [audio queue test](verification/audio-queue/README.md) accounts for a
  decreasing target while previously queued frames drain. Beta1 and beta2 show
  the same transition; the test checks no additional push and eventual drain
  without changing the production adapter or target.
- The fleet campaign's source-drift test now owns its temporary root instead of
  assuming a checkout already has a `tmp/` directory. Its assertions are unchanged.
- The population asset test now resolves the shipped outfit variants through the
  production API. Its obsolete legacy filenames had silently skipped the batch
  assertions; missing required assets now fail the test.

## Verification

Raw outputs are outside Git under `D:/OpenRCsimulator-experiments/gdu-beta2/`,
`gdu-beta2-pins/`, `gdu-beta2-brake/` and `gdu-beta2-identities/`.
The complete application and visual suites are still running; the results below
identify completed checks only.

| Check | Result and scope |
| --- | --- |
| Native Windows import | Passed through the checked runner |
| [Offline tool suite](verification/offline-tools.log) | Passed on the Linux snapshot, including the isolated fleet fixture and all 43 release-tool checks |
| [Quick preflight](verification/quick-preflight.log) | Passed; this is the orchestration/partition/export-fixture check, not hosted CI |
| [Final cache-concurrency correction](verification/getter-warm-cache.json) | Current/historical getter fixtures passed 21/5 checks on each of Windows and Linux; eight real overlapping warm calls succeeded with fixed hash/version checks intact |
| Aircraft schema | [2,070 schema/loader cases](verification/schema-contract.json), 142 valid controls and 23 runtime-only checks passed; [v2](verification/schema-v2.json) and [HX700](verification/schema-hx700.log) checks passed on Windows beta2 |
| [Windows headless smoke](smoke/README.md) | All 52 steps passed; stable soak counters, no engine errors or leaked objects at exit; retained-object negative control rejected |
| [Native Windows headless checks](verification/native-headless/README.md) | Crash integration passed 244 assertions with WASAPI, including playback and mute checks for ten aircraft; RCV session passed 168 assertions with its installed native backend and no conditional skips |
| [Frozen numerical comparison](numerical-comparison.json) | 20 current fixed-wing cases, 960 ticks / 961 rows each, byte-identical across beta1/beta2; five PCG and five OU streams identical, independent PCG recurrence passed |
| Companion matrix and replay | 148 checks per engine; sampled trajectories and scenario metrics identical; nine fresh beta2 tapes exact-replayed with 2,881 rows each, complete and `solver_changed=false` |
| Windows brake gate | All 16 original beta1 goldens, beta2 reference/candidate full-value comparisons, and 258 unit checks passed |
| [Native Windows 1080p comparison](paired-render-comparison.json) | RTX 3090, driver 617.42: six High images identical; four Standard images identical, flightline/lake differ by at most one channel byte in 3/148 pixels |
| [Native Windows renderer checks](verification/native-rendering/README.md) | All 16 checked invocations passed across Compatibility, Forward+ and Mobile on RTX 3090, including lighting pixels, High profile and scene readbacks; no engine errors or warnings |
| High capture lifecycle | Beta1 reports seven leaked Texture RIDs; the matching beta2 capture exits without that warning. This is one bounded world/capture control |
| [Cloud-density GPU oracle](cloud-probe.json) | Periodicity, shared sky/ground projection, wrong-sign negative control, drift wrap, bounds and variation passed; repeated atlases identical |
| macOS cross-export ([Windows](macos-windows-cross-export.json), [Linux](macos-linux-cross-export.json)) | Debug and release contain the matching official arm64/x86_64 slices and pass package checks; no native Mac execution |
| [Ground-native evaluator](native/README.md) | 733 evaluator checks and 2,676 exact lake scalars at 669 points passed |
| [Aircraft-native evaluator](native/README.md) | Root and Linux export source identities separately qualified: 19 oracle gates, 14,400-tick exact trajectory, rejected mutant, guarded loader and nine installed-runtime gates passed |

The [upgrade plan](../../../plans/godot-4.8-upgrade.md) retains the broader release,
hardware, audio, physical-validation and native-platform gates. No release was
published, numerical golden re-recorded or performance improvement inferred from
concurrent correctness runs. Images remain outside the repository.
