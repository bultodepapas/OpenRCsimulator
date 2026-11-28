# NK-3 native stage evaluator

Step NK-3 of the [native-kernel scoping](../../docs/research/native-kernel-scoping-2026-10-27.md#phases-r-research-i-implementation):
a GDExtension (godot-cpp) port of continuous aircraft evaluation. ABI 2 is the qualified Linux x86_64
default for the current aircraft catalog and admitted flight conditions. The original legacy prescribed-RPM
Ugly Stik delivery remains the rollback baseline. Build outputs stay in the ignored `tmp/native-kernel/`;
`--install-app` can stage a verified Linux library in ignored `app/native/kernel/`. The application requests native physics by default.
Unsupported or unverified configurations report a reference fallback; `--physics-backend=gdscript_reference`
selects the reference explicitly. The low-level `FlightSession` default remains reference for tools and replay.
Evidence and timings: [docs/research/native-kernel/NK-3](../../docs/research/native-kernel/NK-3/README.md).
The [promotion record](../../docs/research/native-kernel/NK-3/README.md#expanded-linux-qualification-2026-10-29)
defines the supported Linux scope and separates backend qualification from display and hardware acceptance.

## Experimental macOS ARM64

The scalar Apple Clang port uses the existing evaluator ABI and float64 state.
It is a fixed-wing source experiment, with separate source and package receipts;
the Linux fleet qualification does not transfer to Mac. Since the
[2026-11-16 decision](../../docs/DECISIONS.md#default-to-native-physics-on-supported-apple-silicon-flights)
the automatic source-editor route needs no admission marker: an ordinary ARM64
flight inside the screened stock domain (`app/sim/native_macos_domain.gd`) runs
native, and any other selection retains the reference evaluator. A collision-world
change requires renewing that domain
([DT-MAC-04n-R1](../../docs/plans/apple-silicon-performance.md#dt-mac-04n-r1--keep-the-mac-native-default-after-world-changes)).
The [dated DT-MAC evidence](../../docs/research/native-kernel/DT-MAC-04n1/README.md)
describes earlier candidates, not qualification of the current source.
The [source-default ledger](../../docs/research/native-kernel/DT-MAC-04n4/README.md)
records the November 14 adoption on the qualified M1, its actual installed
identities and remaining product gates. Its headless/Dummy audio-off Home checks
do not qualify normal audio-enabled shutdown.

Omit `--experimental-native-macos` to use automatic source-editor admission.
An explicit `false` disables that route; `true` selects the separate research
route. Companion-enabled automatic sessions retain reference. These choices
freeze before session setup, and the normal `--physics-backend=gdscript_reference`
override remains available.

The optional marker, no longer an admission prerequisite, binds the exact installed receipt, binary, sources, domain guard,
Godot executable, macOS version/build, Apple M1 CPU and `MacBookAir10,1` model.
The observed test host used macOS 27.0.1 (`26A434`) and official Godot
`4.8.beta2.official.cafc17a19`; a different binary or OS is not covered by that
host's evidence. Each admitted stock fixed-wing row also binds aircraft and
battery bytes, start, weather, contact mode and the exact solved production
start. The runtime checks the stock field, lake and collision context and guards
the installed context on live ticks. Custom or changed selections fail admission.
During an admitted flight, protected launch-configuration setters refuse a
changed value and require a new flight. Bypassed mutations fault before the next
accepted tick. Reference recovery for an unqualified selection happens during
preparation; the accepted flight keeps its backend identity.

`macos_promotion.py` revalidates the installed candidate, host preflight, a
production-trim fleet campaign and matched live-circuit evidence before writing
a new marker under `tmp/`. It requires five pairs with at least 120 measured
seconds per role and three 30-minute pairs; only independently verified fleet
rows are included. Run `python3 research/native-kernel/macos_promotion.py --help`
for its evidence arguments. After those checks pass and Godot is stopped, copy
the resulting marker unchanged to `app/native/kernel/default-admission-macos.json`
for the source editor. The marker is an artifact-consistency receipt, not
a signature or proof of physical realism. No current marker or campaign pass is
assumed by this guide.

Default adoption also requires successful CI for the qualified source, including
the native Mac job, and actual private-marker installation/fallback, Main,
backend-pinned exact replay and Home/restart/reload/re-entry checks. Validate
the original checked resource attachments after each measured process exits;
retain failed attempts and explicitly identify any replacement pair. Recheck
the complete corpus and source/tool identities before publishing the canonical
marker last, with an exclusive write of complete bytes. The source-default
ledger records the named candidate and adoption result. Public signed delivery
has separate gates.

`build_macos.py` pins Apple Clang/SDK and the existing bindings/API. It checks every
translation unit, effective strict FP options, Mach-O slice/dependencies/imports,
dSYM UUID and the selected signature. Build candidate and `--mutant` into a new
`--tool-root` under `tmp/`. Before `--install-app`, execute the complete applicable
roster from `verification_roster()` using `run.py` and its declared counts/tapes.
The installer revalidates the actual reports, checked logs, source, binary and
engine; an old report or matching fallback cannot qualify a native install.

The default `--toolchain-profile` remains `apple-clang-2100.3.34.2-sdk-27.0`.
For a host with exactly Apple Clang `2100.4.1.1` and SDK `27.2`, select
`--toolchain-profile apple-clang-2100.4.1.1-sdk-27.2` explicitly for the builder,
installer, FPCR control, diagnostics, fleet, package and promotion commands.
The selected profile and actual compiler/SDK are bound in the build receipt;
legacy receipts without a profile retain the original exact pin. A selected
profile does not qualify a host, candidate, package or performance result.

The separate local MetalFX-engine lane requires explicit independent selection;
an engine build receipt alone cannot authorize its executable. It binds the exact
ARM64 editor hash, CLI/runtime versions, original build receipt, upstream ZIP,
ordered patch files and clean locked godot-cpp 4.7 API. It also requires
`--research-engine-reference-godot` pointing to the independently pinned official
4.8-beta2 ARM64 editor. A fresh official 4.8 API dump checks custom-engine
compatibility, while the 4.7 API remains the bindings input. Diagnostic output is
checked on both streams even if Godot exits zero. Patches changing the pinned
`core/extension/` interface are refused; ordinary custom-engine launches reject
inherited `DYLD_*` overrides. Instrumented sanitizer launches use their separate
controlled injection path.

Pass the same complete selection to builder, installer, FPCR, diagnostics, fleet,
session comparison, package and promotion commands:

```sh
R=(
  --research-engine-sha256 "$EDITOR_SHA256"
  --research-engine-cli-version '4.8.beta2.openrc_metalfx'
  --research-engine-runtime-version '4.8-beta2 (openrc_metalfx)'
  --research-engine-build-receipt "$EDITOR_INTAKE/build-editor.json"
  --research-engine-archive "$GODOT_SOURCE_ZIP"
  --research-engine-extension-api "$PINNED_CPP/gdextension/extension_api-4-7.json"
  --research-engine-reference-godot "$OFFICIAL_GODOT"
  --research-engine-patch "$PATCH_1"
  --research-engine-patch "$PATCH_2"
  --research-engine-patch "$PATCH_3"
  --research-engine-patch "$PATCH_4"
  --research-engine-patch "$PATCH_5"
  --research-engine-patch "$PATCH_6"
  --research-engine-patch "$PATCH_7"
)
```

Use exactly the ordered patch list in the selected intake; omit later entries
when testing an earlier stack. The
[engine guide](../../tools/graphics/metalfx/README.md) owns the current patch list.

The engine-build toolchain is an independent selection. Its omitted
`--research-engine-toolchain-profile` retains the original Clang `2100.3.34.2` /
SDK `27.0` receipt check. When the selected engine was built with the second
exact pair, add `--research-engine-toolchain-profile apple-clang-2100.4.1.1-sdk-27.2`
to `R`. This does not select or imply the kernel
build's `--toolchain-profile`, or vice versa. Pass the independent selections to
each command that validates those identities.

`run.py` reads that identity from the verified native build receipt instead of
accepting this argument array. Identity checks reconstruct source catalogs and
launch API validators; keep them outside measured intervals. These are local
artifact-consistency checks, not cryptographic build attestation. Native loader,
oracle, fleet, performance, CI and promotion gates remain required for every new
engine hash. A marker issued for the official engine cannot admit a custom one.
The [current MetalFX evidence](../../docs/research/desktop-delivery-investigations/DT-MAC-11a/README.md)
records the still-open native qualification.

Ad-hoc signing is the development default. A Developer ID build requires an
available Developer ID Application certificate selected by its exact SHA-1 and
Team ID; candidate and mutant must use the same selection:

```sh
python3 research/native-kernel/build_macos.py --godot "$OPENRC_GODOT" \
  --tool-root "$FRESH_TOOL_ROOT" --signing-identity "$CERT_SHA1" --team-id "$TEAM_ID"
# Repeat with --mutant and the same selection, then execute the full oracle roster.
```

The builder verifies the certificate type, Apple chain, Team ID, leaf fingerprint
and secure timestamp before recording signed bytes. Re-signing invalidates that
binary's proofs. The final hardened app must use the same Team ID and normal
library validation. An ad-hoc dylib can be refused by a normally hardened app;
the observed local diagnostic entitlement exception does not qualify delivery.
The [release signing audit](../../tools/release/README.md#experimental-native-mac-bundle-identity-dt-mac-04n3)
is separate from receipt consistency and actual loader execution remains required.

After a verified installation, opt in per launch:

```sh
"$OPENRC_GODOT" --path app -- --quick-flight \
  --aircraft=jensen-das-ugly-stik-60 --physics-backend=native \
  --experimental-native-macos=true
```

The explicit research choice is frozen before session setup and does not create
an automatic marker. Intel/Rosetta, helicopter and unknown targets do not select
this evaluator. Missing, stale or changed artifacts refuse admission and retain
reference. To roll back a launch explicitly, use
`--physics-backend=gdscript_reference`. After replacing a loaded dylib or receipt,
restart Godot: a changed on-disk marker cannot qualify the library cached by the
running process. There is no saved global Mac-native preference.

Use `run.py --project` and `session_baseline.py --project` with a fresh verified
[research preparation](../../tools/graphics/README.md#isolated-mac-renderer-trials-dt-mac).
`--experimental-native-macos` on those Python runners forwards the explicit
boolean to fixed-wing sessions. The preparation records the original native
inventory: only named canonical installer outputs may subsequently advance;
every executed copy, ordinary source, fixture and asset remains checked.

For a Mac fleet campaign, additionally pass `--qualification-root` with the
verified build/oracle directory and `--tool-root` with the separate fleet-report
directory. The campaign verifies the installed receipt's exact base-oracle
citation and its FPCR observations in that separate process; fleet shards keep
their own typed-flight and native-coverage checks. Known open rows require
`--keep-going` to retain partial evidence and cannot produce a full-fleet pass.

`fpcr_control_probe.py` compiles a disposable FPCR mutant and requires the real
Godot oracle to detect the changed control and its restoration.
`macos_diagnostics.py --mode ubsan|asan` uses disposable instrumented libraries
and positive controls through the same loader. Neither tool modifies the signed
candidate or engine. Their coverage excludes uninstrumented Godot and prebuilt
bindings; a host/runtime failure is an unproven diagnostic, never a pass.

Experimental packaging uses `package.py prepare-macos` / `stage-macos` and the
separate native bundle and ZIP receipt commands in
[release tools](../../tools/release/README.md). Its identity is
`macos-arm64-native-bundle-v1`; reference retains `macos-reference-bundle-v1`.
The public six-file release contract has not adopted the experimental ZIP.

### Packaged CPU-default admission

This separate workflow covers only the CPU native backend. It has not yet
qualified a package or issued a marker. A candidate is scoped to the verified
Ugly Stik, ideal battery, calm airborne start, soft-hull and production trim
on the recorded M1 hardware, OS and signed package. MetalFX, GPU completion,
physical radio/pilot behavior, scanout and latency remain unqualified.

First rebind companion and native source identities, complete the existing
functional/oracle/fleet gates, and create the exact paired editor, template and
signed release. These commands use the admitted host and do not bypass its
ownership queue. Do not run timed captures concurrently with other workloads.

Create a non-linked, absolute JSON input file with exactly these keys. All paths
must exist and be absolute, and all report paths are original raw checked
artifacts, not manually written summaries:

```json
{
  "format": "openrc-package-default-inputs v1",
  "project": "/absolute/path/to/qualified/app",
  "godot": "/absolute/path/to/paired/editor",
  "tool_root": "/absolute/path/to/checked/fleet/shards/inside/source/tmp",
  "qualification_root": "/absolute/path/to/verified/native/build/inside/source/tmp",
  "native_toolchain_profile": "apple-clang-2100.4.1.1-sdk-27.2",
  "engine_selection": "/absolute/path/to/independent/editor-selection.json",
  "release_selection": "/absolute/path/to/independent/release-selection.json",
  "executable": "/absolute/path/to/OpenRC.app/Contents/MacOS/OpenRC",
  "preflight": "/absolute/path/to/macos-preflight.json",
  "fleet_campaign": "/absolute/path/to/production-trim/fleet.json",
  "package_checks": {
    "stage": {"checked": "/absolute/path/to/stage/report.json"},
    "lifecycle": {"checked": "/absolute/path/to/lifecycle/report.json"},
    "replay": {"checked": "/absolute/path/to/replay/report.json"},
    "session_reference": {"checked": "/absolute/path/to/reference/report.json", "output": "/absolute/path/to/reference-session.json"},
    "session_native": {"checked": "/absolute/path/to/native/report.json", "output": "/absolute/path/to/native-session.json"}
  },
  "short_pairs": [["/absolute/ref-1.json", "/absolute/native-1.json"], ["/absolute/ref-2.json", "/absolute/native-2.json"], ["/absolute/ref-3.json", "/absolute/native-3.json"], ["/absolute/ref-4.json", "/absolute/native-4.json"], ["/absolute/ref-5.json", "/absolute/native-5.json"]],
  "long_pairs": [["/absolute/ref-long-1.json", "/absolute/native-long-1.json"], ["/absolute/ref-long-2.json", "/absolute/native-long-2.json"], ["/absolute/ref-long-3.json", "/absolute/native-long-3.json"]],
  "ci_run_id": 123456789
}
```

Each packaged check must have its original `engine.log` next to the cited
checked `report.json`. The three diagnostic modes are `stage`, `lifecycle`,
and `replay`; the two session outputs are the existing fixed 24-warmup/240-sample
Ugly Stik `trim` sessions with `battery=ideal`, `trim-profile=production` and
observer enabled. Their real checked commands, native-pass markers, package
identities and typed reference/native fingerprints must match.

For each flight path the existing strict reader requires its original adjacent
health, checked, stream and log evidence, the original checked hierarchy,
resource samples and host-state attachment. Collect independent alternating
reference/native pairs: five with at least 120 measured seconds and three with
at least 1,800, each after at least 30 seconds' warmup. All use the fixed
synthetic no-radio direct AppRoot route, same qualified package and workload,
and an actually acquired 1920×1080 ordinary framebuffer texture. Each pair must
have matching initial checkpoints under the fixed screened stock domain,
6,000-tick state/input windows and sampled activation at the shared measured
ticks. The actual screened start must equal the qualified fleet row. Original
backend-bound checkpoint and configuration hashes are separately retained and
checked within each role; the screened witness is not a general configuration
equivalence claim.
The 18/25 ms p95/p99 and 0.99–1.01 simulated/wall
gates, at most 5% paired CPU/RSS/frame-tail regression, bounded long-run
early/final resource checks, nominal thermal/AC/no-low-power observations and
no observed memory-pressure warning apply. The initial pressure level and OS
notification loss remain unknown. Each short and long group must separately
show at least a 5% median benefit in **either** process CPU per accepted
simulated second or process callback-loop FPS. CPU poll boundaries introduce
uncertainty; callback FPS is not displayed FPS or GPU completion.

Each flight directory also needs the capture wrapper's adjacent
`host-witness.json`: pre/post model, CPU, memory, OS product/build and boot UUID,
with UTC and monotonic brackets around the exact checked capture ID, PID,
report SHA and log SHA. All sixteen must report one boot UUID and match the
current M1 preflight's hardware and OS. This is a reported host/boot witness,
not a cryptographic device identity. The marker's `package_session_sha256`
binds the packaged checks, host witnesses and the frame, stream, health, checked
report and resource digests for all sixteen captures; the preparation receipt
retains the individual entries.

Before the timed campaign, the same fixed launcher can exercise the normal Home
route with missing and malformed markers in two separate private profiles:

```sh
python3 research/native-kernel/macos_package_default_probe.py \
  --executable /absolute/path/to/OpenRC.app/Contents/MacOS/OpenRC \
  --fallback-only --out /absolute/path/to/new-fallback-smoke-directory
```

The resulting `fallback-smoke.json` is only a functional smoke receipt; it
cannot replace the later four-case candidate proof or authorize a marker.

The fixed capture launcher must opt in to
`OPENRC_PACKAGE_RAW_CLOCK_QUALIFICATION=1` only for the verified macOS arm64
release process. The app still checks the exact custom engine metadata and
actual helper SHA and takes bounded start/end clock anchors. Metadata is not
binary attestation: the strict package reader independently verifies the
selected executable and linked package identity. The host-state attachment,
alignment and sleep checks remain mandatory.

After creating a fresh directory under this checkout's `tmp/`, prepare the
candidate. No canonical marker is written by this step:

```sh
python3 research/native-kernel/macos_package_promotion.py prepare \
  --inputs /absolute/inputs.json \
  --candidate /absolute/source/tmp/new/candidate.json \
  --receipt /absolute/source/tmp/new/preparation.json
```

Use the printed exact candidate SHA-256 to run the fixed release-only Home
observer. It creates four separate, newly owned private HOME directories and
bundle clones, validates each clone's linked receipts and signature, and runs
missing-marker, malformed-marker, staged-candidate and explicit-reference
cases in separate checked processes. The first three use ordinary Startup and
Home with no backend override; they must use the same exact screened selection.
The reference case is a separate explicit direct-flight control. The launcher
sets HOME only in each child process and checks the actual Godot user directory
before preferences. Keep the original signed bundle and all raw case logs and
reports.

```sh
python3 research/native-kernel/macos_package_default_probe.py \
  --executable /absolute/path/to/OpenRC.app/Contents/MacOS/OpenRC \
  --candidate /absolute/source/tmp/new/candidate.json \
  --candidate-sha256 EXACT_CANDIDATE_SHA256 \
  --out /absolute/path/to/new-home-proof-directory
```

Only after all four cases pass, finalize with the same input file. The tool
revalidates the source, package, live CI, fleet, package checks, all 16 raw
flights, candidate bytes and every raw Home case. It first durably writes a
`verified_for_publication` receipt; only then does it atomically create the
previously absent marker beside the original `.app`. The receipt alone does not
say publication succeeded: check the command result and the marker's hash. It
refuses an existing marker; it never overwrites one.

```sh
python3 research/native-kernel/macos_package_promotion.py finalize \
  --inputs /absolute/inputs.json \
  --candidate /absolute/source/tmp/new/candidate.json \
  --home-proof /absolute/path/to/new-home-proof-directory/home-proof.json \
  --receipt /absolute/source/tmp/new/publication.json
```

The promotion source must match the package receipt's exact commit, tree and
worktree hash, and CI must pass that same commit. A clean checkout is accepted.
For the paired local research export, the only allowed tracked modification is
the unstaged macOS export preset: ARM64, the verified paired template ZIP path,
and `org.openrc.research.metalfx.native26production` in its bundle-identifier field.
The tool reconstructs those exact bytes from the committed preset, verifies the
ZIP against the pair, and rejects staged changes, other tracked changes,
nonignored untracked files, replacement refs, inherited Git overrides and hidden
tracked-file index flags. This check does not inventory ignored files; the
existing prepared-project, package and installation validators remain in force
for their respective inputs. This is a declared local build setting,
not an exception for another commit, proof of the bundle's actual identifier, or
a distribution-signing claim.

The bundle/receipt identities are checked at boundaries, not continuously;
avoid concurrent modification. The Home probe checks menu-playback retirement and
the checked log's reported diagnostics, not audible output or an exhaustive
leak proof. A missing, malformed, unsupported, stale or incomplete input must
leave promotion pending.

### Paired research export from a prepared project

Set the final ARM64 preset and exact custom release template before native
qualification. Keep the canonical app, project settings and preset stable through
export. The preparation tool requires the canonical project name and no custom
user-data directory; it gives the isolated copy a unique name.

Pass the complete research-engine selection, independent native/engine compiler
profiles and these four pair inputs to each Mac package command:

```sh
P=(--pair-template-intake "$TEMPLATE_INTAKE"
   --pair-receipt "$PAIR_RECEIPT"
   --pair-export-template "$EXPORT_TEMPLATE_ZIP"
   --pair-binding-pins "$PAIR_BINDING_PINS")
```

The pins identify the retained editor/template receipts, source catalog, ordered
patches and export ZIP; the producer revalidates them instead of deriving trust
from a manifest. The repaired native-compatible stack uses patches 0001–0019
followed by 0021; optional diagnostic 0020 is excluded from that pair.

After the verified native installation, run `package.py prepare-macos`. Once its
native artifacts and package manifest are final, use
`tools/graphics/prepare_research.py --dest <ROOT/tmp/new-run>`. Export the resulting
`<new-run>/app`, and copy the canonical `research/performance/session_probe.gd`
to `<new-run>/research/performance/session_probe.gd`; the plugin reads this sibling.
Import the prepared project with the checked runner and capture the reference
bundle inputs using the [release tools](../../tools/release/README.md).

Immediately before the checked export, retain the JSON proof from
`package._prepared_macos_export_project(project, package._pair_binder())`.
Immediately afterward, retain another proof and require equality. Set
`OPENRC_EXPERIMENTAL_NATIVE_MACOS_PACKAGE=1`, select the same paired editor and
preset, and require exactly the pair's ordered BEGIN/END markers. These are
endpoint consistency checks, not source-to-PCK reproducibility or protection
against changes restored during export.

Run `package.py stage-macos`, sign the app without changing the qualified dylib,
finalize its reference receipt, then run `package.py finalize-research-macos`
with the same selections and checked export report. Retain the prepared project,
preparation receipt, sibling probe, both endpoint proofs, checked report and
finalizer output: later performance readers revalidate the prepared copy.
Actual package execution, performance and delivery gates remain separate.
Public distribution of a native Mac bundle remains deferred.
Developer ID, notarization, downloaded/quarantined launch and product performance
remain separate target-hardware gates.

## Qualified aircraft coverage (NK-3)

The owner expanded the goal on 2026-10-28 to every currently simulatable aircraft and supported flight condition
on Linux x86_64. The expanded delivery preserves the shared kernel, float64 state and existing admission,
start, lifecycle and replay contracts. Future changes still require qualification against the reference.
Earlier references to the baseline as "electric Stik" were imprecise: its source uses legacy prescribed RPM.
The coupled electric sources belong to Turbo Lumber and X8.

| Coverage | Qualified implementation |
| --- | --- |
| Ten fixed-wing catalog aircraft, default battery and ideal variants; representative tested Workshop variants | Prepared flaps, wing polars, elevons, propeller axes; capability-based admission after exact oracles, not exhaustive user-authored model qualification |
| Legacy, coupled electric, finite glow two/four-stroke, liquid combustion and turbine | Same-stage shaft/source rates, batteries, live fuel mass, events and stop projections |
| X-Cell helicopter | Prepared controls, drive, rotors, skid memory, body derivative on dry terrain; independent vehicle gates |
| Admitted weather configurations | Stage-time gusts/OU, vertical atmosphere, spatial profiles/modes/thermals and local point flow |
| Supported start/contact and flight lifecycle | Retractable gear, soft contacts, transported wake, failures, resets, rollback and exact replay |
| Default delivery | Source-bound fleet qualification, separately classified refusals and terminals, package/replay checks and paired measurements |

Native joint stages cover the coupled electric, finite-liquid gas/turbine, finite glow and helicopter families.
The [dated component and stage evidence](../../docs/research/native-kernel/NK-3/revalidation-linux-2026-10-28.json)
records exact comparisons, paired tapes, source lifecycle events and remaining limits. The completed fleet
qualification covers 1,238 declared cases: 1,202 completed flights, 28 startup refusals, six runtime refusals
and two terminal scenery collisions. Refusals and terminal prefixes are not counted as completed flights.
Strict installation, native admission boundaries, UBSan, Linux package/replay/routes and paired release
measurements are recorded in the
[expanded qualification](../../docs/research/native-kernel/NK-3/README.md#expanded-linux-qualification-2026-10-29).
The existing helicopter reference rejects spatial/OU/column weather, and its hot-high start currently fails hover trim.

Shared pre-tick/discrete supervision may remain GDScript under the existing kernel contract. Continuous laws
claimed as native must execute in C++; matching reference fallbacks cannot establish native coverage.

Helicopter native admission requires an empty published lake context. The session and both direct preparation
paths refuse lake terrain; a successful stock Club lake attachment therefore selects the reference evaluator.
The [H03/H05 correction](../../docs/research/helicopter/HELI-33/README.md) carries composed bank/bed terrain
through the reference consumers and defines the unsupported-water policy. The historical fleet evidence
above predates this admission boundary; reference fallback does not establish native lake coverage.

## Normal-flight backend selection

After verification and installation below:

```bash
"$(app/get-godot.sh)" --path app -- --quick-flight --aircraft=jensen-das-ugly-stik-60 --weather=calm
```

Selection is launch-time only. ABI 2 selects a stage from the validated model's propulsion and vehicle
capabilities, with native weather and configuration guards. This replaces the baseline stock-aircraft restriction;
unsupported or unverified configurations report reference fallback. The interactive flight console prints
requested/actual backend and refusal reason.
A stale or missing build is also an engine warning on normal flights (`app/app_state/native_fallback.gd`):
a refused source/package identity on any host except the macOS release, and a missing library on Windows/Linux
x86_64. Expected domain refusals (lakes, weather, custom spawn) stay a log line. The debug bridge `state` reports
`flight.physics_backend` as `{backend, requested, kind, reason}`; check `kind == "native"` before measuring.
Native traces record the identity in metadata; its absence denotes reference and preserves pre-integration
reference CSV bytes. In source builds, the exact verified Godot executable, binary and mirrored source/data hashes must match.
Release packages instead verify the complete executable and embedded manifest before loading their pinned sidecar.

`FlightSession` prepares a fresh stage within each reset/restore transaction and primes tick-zero context before
evaluating initial loads. Rejected starts preserve the previous helper, callbacks and physical state. Accepted
surface/lake/soft-contact setters reprepare at a boundary. Per-tick comparisons detect bypassed configuration
changes before stale coefficients can run; they do not serialize, hash or decode the model each tick.

Native checkpoints use an outer `openrc-flight-checkpoint v14` envelope carrying the backend and library identity.
Helicopter native checkpoints use `openrc-helicopter-checkpoint v9`, retaining the reference v8 physical fields,
heading-memory law, contact law and lake identity, and adding the backend identity. Versions v1–v7 are explicitly
refused after the composed-terrain and conservative rotor-disc contact correction.
Fixed-wing reference checkpoint formats/hashes stay unchanged. Exact replay requires that identity; explicit candidate
replay may use reference and reports `solver_changed`. A backend change during recording leaves an incomplete
diagnostic prefix. See [flight logging](../../docs/FLIGHT-LOGGING.md).

## What is ported

| Native (src/) | Mirrors (current app/ GDScript) |
| --- | --- |
| `nk_math.hpp` | `math3d.gd` shim plus engine `absf`/`maxf`/`minf`/`clampf`/`lerpf`/`wrapf` semantics |
| `nk_terrain.hpp` | `ground_terrain.gd` `sample_validated` (micro-relief, surface-table validity) and `_compose_lake`; `lake_surface.gd` terrain sampler (covered early-out, five-point stencil, bed profile) |
| `nk_wheels.hpp` | `ground_wheels.gd` `evaluate` (diagnostics off), `frame`, `coefficients`, `compressions` |
| `nk_aero.hpp` | `air_data.gd` `compute`; `ground_effect.gd` `factors`; `aero.gd` `loads` and its strip, oracle and tail laws |
| `nk_prop.hpp` | `propulsion.gd` propeller geometry, inflow, coefficient tables, tilted-axis loads and rotor momentum |
| `nk_hull.hpp` | `hull_contact.gd` `loads` (flat and lake branches, airframe friction, shared regularization) |
| `nk_stage.hpp`, family stage headers | Fixed-wing joint/body evaluation, source rates, rotor response, live liquid/glow mass and retractable contacts |
| `nk_electric*`, `nk_liquid*`, `nk_glow*`, `nk_prescribed*` | Electric motor/battery, finite gas/turbine, glow lifecycle and prescribed-fuel shaft/turbine laws |
| `nk_weather*`, `nk_spatial*`, `nk_wake*` | Stage-time weather, atmosphere, local spatial flow and transported/quasistatic wake |
| `nk_helicopter*` | Helicopter controls, rotor/airframe forces, drive, body derivatives and ground contact |
| `nk_legacy_ground.hpp` | Legacy no-wheel-state flat/lake contact law for valid older or workshop models |
| `nk_tick.hpp` | `simulation.gd` legacy joint tick (`_rk4_substeps`, `_locate_substeps`, stage validity), `rigid_body.gd` `derivative`, `integrator.gd` RK4, `event_step.gd` and `event_bracket.gd` (NK-6a); `electric_battery_step.gd`, `electric_stop.gd` and `electric_contact_step.gd` for the finite-pack policy (NK-6c); `resource_event_step.gd` with the stock glow surfaces (NK-6d) |
| `nk_kernel.cpp` | `OpenRCNativeKernel` (RefCounted): prepare, per-call and per-tick methods, probes, counters, benches |

These rows identify implemented code, not release qualification. Installed fleet, lifecycle and package evidence
must match the exact candidate. Preparation guards retain explicit resource budgets; an over-budget input is
refused with a diagnostic and cannot count as native coverage.

Laws: `Aero.LOADS_LAW` `section-plane-source-weighted-wake-velocity-v4` (envelope, coupled or uncoupled strips,
ground effect, downwash lag, twist, `wing_cm_ac`, body terms, E0a2 or legacy tails); `Wheels.ROLLING_LAW`
`wheel-positive-terrain-excess-v2`; soft hull `soft-hull-spring-friction-v2` with the lake normal law.

## Contract

- `prepare_stage(config)` decodes everything once: the validated model, landing gear, surface table, lake and its
  validity, the session's prepared hull (`_hull_contact`), the layout indices, density and ground-effect reach.
  `stage_adapter.gd` `config_for(session)` builds it. `prepare_ground` and `prepare_aero` remain for components.
- `set_tick_context(aux, inputs, deflections, time_now)` once per tick: the aux the kernel installs after
  `pre_tick`, the inputs, the session's own `_deflections(aux)` (`[elevator, aileron_right, aileron_left, rudder]`)
  and `sim.time()`. `stage(body, continuous, t)` is then the joint stage: `{loads, derivative, rotor_momentum}` with
  `StringName` keys like the reference literal, or `{}` exactly where the reference returns `{}`.
- `stage_wing_wake(s, air, deflections, ground_up)` (NK-5a) evaluates `aero.gd` `wing_wake_velocity` with the prepared
  stage's `AeroModel` for the session pre-step's tail downwash lag. `flight_session.gd` calls it only inside
  `_kernel_pre_step` after the configuration guard passed, and evaluates the reference on NaN
  ([evidence](../../docs/research/native-kernel/NK-5a/README.md)).
- A finite-liquid gas stage's accepted-endpoint substep preview (`stage_context`) also carries
  `source_off_rpm_rate` (NK-5b), the source-off shaft rate of the same trial and wrench, published only when finite.
  `_substeps_joint` uses it instead of rebuilding `LiquidFlight.properties` and `_coupled_response`; the reference
  stage publishes the same key ([evidence](../../docs/research/native-kernel/NK-5b/README.md)).
- The configuration guard primes its watches at preparation (parent containers, `StringName` keys for untyped
  String keys, raw expected scalars) and keeps the same accept/refuse rules per tick
  ([NK-5c](../../docs/research/native-kernel/NK-5c/README.md)).
- `prepare_reach_world(proxies)` and `contact_reach(previous, candidate, hull, extra_reach, lake_threshold)` (NK-5d)
  prove, conservatively, that no collision proxy or lake water is reachable during an accepted tick; the session then
  skips only that sweep ([evidence](../../docs/research/native-kernel/NK-5d/README.md)).
- `stage_compressions(s, aux)` (NK-5e) evaluates the session's `gear_compressions(s)` at the accepted endpoint from
  the prepared stage ground, posed by the tick context when the gear retracts. `flight_session.gd` asks only while
  observing the endpoint of the tick whose guarded pre-step installed that context, and evaluates the reference on
  an empty answer ([evidence](../../docs/research/native-kernel/NK-5e/README.md)).
  The session publishes that endpoint's compressions to the `stepped` observers after it; the statistics sampler
  reads them within the same publication (NK-5f, [evidence](../../docs/research/native-kernel/NK-5f/README.md)).
- `prepare_pre_step(config)` and `pre_step(aux, inputs, dt, state, continuous, time_now, engine_running,
  flap_mix_simulator, deflections, rng_state)` (NK-5g, `nk_pre_step.hpp`) return `FlightSession._pre_step`'s next
  aux and `sim.modes[1]` for the prepared fixed-wing stage. Engine `exp`/`log`/`sin`/`cos` are the engine's utility
  functions and `RandomPCG` is reproduced in integers. `_kernel_pre_step` asks after the configuration guard passed
  and evaluates the reference on an empty answer ([evidence](../../docs/research/native-kernel/NK-5g/README.md)).
- The configuration and weather guards run a per-tick plan (NK-5h, `nk_guard_plan.hpp`). Each root container is compared
  once inside the engine against a deep snapshot taken at preparation. Watches remain only for ±0 floats, packed
  float arrays holding a zero, Callables and the containers that hold them. A NaN keeps the full leaf walk
  ([evidence](../../docs/research/native-kernel/NK-5h/README.md)).
- `stage_endpoint_facts(s, aux, time_s)` (NK-5i) answers the statistics sampler's evaluations of the accepted endpoint
  in one call: `air_data(s, t).V` (the NK-5g air sample with the endpoint aux), `Environment.ground` (stage surfaces
  and lake), `Ground.collapsed`'s comparison with each posed contact's decoded `max_compression`, and the endpoint
  compressions. `FlightSession.published_endpoint_facts` asks only within the `stepped` publication of a natively
  measured endpoint, without an RC track or pending weather reset; the sampler evaluates the reference on an empty
  answer ([evidence](../../docs/research/native-kernel/NK-5i/README.md)).
- `integrate_tick(model, state, continuous, aux, t, dt, tick, mass, gravity, inertia, inertia_inv)` (NK-6a,
  `nk_tick.hpp`) integrates a legacy, endpoint-free joint tick without a step policy whose stage is this kernel's
  `stage`. After the reference pre-step installs `aux`, it runs Simulation's tick to the accepted endpoint: the
  tick's own stage, the rigid-body derivative, RK4, substeps, the declared-event locator and bracket, every
  stage-validity check and refusal message. The model's rotor-momentum, substep, event-transition, post-step filter
  and auxiliary-projection callbacks are called where the reference calls them. `Simulation._native_integrator`
  selects it; `{}` refuses before any evaluation, `{fault}` carries the reference's refusal, and otherwise the
  endpoint is committed by `Simulation._commit_step`. `tick_stats()` counts calls, answers and faults
  ([evidence](../../docs/research/native-kernel/NK-6a/README.md)). NK-6c admits one step policy, the finite-pack
  `FlightSession._electric_step`. Its pure plan (`native_electric_step_plan`: dynamic battery, contact pieces,
  rotor index, pack supervision) comes first. The kernel then runs the battery step or the contact pieces, with
  rotor-stop and battery-exhaustion events in the policy's order, and calls back `_project_electric_stop` and
  `_supervise_pack` ([evidence](../../docs/research/native-kernel/NK-6c/README.md)). NK-6d admits `GlowFlight.step`
  with this sequence:
  - It reads the session's recording resource events (`native_glow_step_plan`), only the stock rotor-stop,
    main-tank and feed-line surfaces.
  - It runs `resource_event_step.gd` over those surfaces natively and calls the events' recording transitions.
  - It hands the bounded result to `GlowFlight.finish`, which the reference policy also calls.
  - It unpacks the policy result as `Simulation._unpack_policy_result` does
    ([evidence](../../docs/research/native-kernel/NK-6d/README.md)).
- `stage_glow_firing(body, values, time_s)` (NK-6b) answers `GlowFlight.point(...).firing_fraction`, the only point
  value the glow step policy's endpoint and counted segments read, from the prepared glow stage's own lifecycle
  point. `FlightSession.native_glow_firing` asks only inside the tick its guarded pre-step installed, and
  `GlowFlight._firing_sample` evaluates `point()` on NaN
  ([evidence](../../docs/research/native-kernel/NK-6b/README.md)).
- `prepare_glow_validity(bounds)` and `stage_glow_mass_check(values, with_mass)` (NK-6e) answer
  `GlowFlight.valid(values)` and `GlowFlight.mass_context(values).ok` from the installation's bounds and the
  prepared glow mass. `FlightSession._native_glow_mass_check` asks inside the guarded tick for the contact mass
  sampler and the auxiliary projection; -1 evaluates the reference
  ([evidence](../../docs/research/native-kernel/NK-6e/README.md)).
- `stage_hull_scrape_rows(s, properties)` (NK-6f) answers the GP-19 endpoint diagnostics rows of `HullContact.loads`
  (prepared hull) or `loads_at_properties` (live hull, packed mass properties) from the same native hull law.
  `FlightSession._native_hull_scrape_diagnostics` asks for the hull-scrape observation only under the NK-5i
  published-endpoint conditions; `[0]` (a lake-covered sample, a refused live sample) evaluates the reference
  ([evidence](../../docs/research/native-kernel/NK-6f/README.md)).
- `contact_reach(..., lake_bank)` (NK-6g) also proves a null lake sweep when its superset box misses the lake bank's
  bounds, which the sweep's horizontal reject tests; the pre-tick guard's gear collapse reads the published endpoint
  compressions (`published_gear_collapsed`)
  ([evidence](../../docs/research/native-kernel/NK-6g/README.md)).
- `prepare_liquid_terminal` and `stage_liquid_terminal_quiet(previous, s, usable_before)` (NK-6h) answer
  `HullContact.terminal_at_properties` for a liquid aircraft's contact sample at fraction 0 only where it must return
  `{ok, no event}`, with the sample's properties from the stage's live mass; 0 evaluates the reference
  ([evidence](../../docs/research/native-kernel/NK-6h/README.md)). `prepare_glow_terminal` and
  `stage_glow_terminal_quiet(previous, s, total, line)` (NK-6i) do the same for a glow aircraft's sample
  ([evidence](../../docs/research/native-kernel/NK-6i/README.md)).
- `stage_guard_collapsed(s, aux)` (NK-6j) answers the pre-tick guard's `gear_collapsed` from the endpoint compressions
  of the installed tick context; -1 evaluates the reference
  ([evidence](../../docs/research/native-kernel/NK-6j/README.md)).
- `prepare_prop_strike` and `stage_prop_strike_clear(s)` (NK-6k) prove `FlightSession._check_prop_strike` finds no
  strike: the disc's flat-datum depth is at most 0 and the disc is horizontally clear of a valid lake's bank. Every
  other case, strikes included, evaluates the reference
  ([evidence](../../docs/research/native-kernel/NK-6k/README.md)).
- `prepare_hull_guard` and `stage_hull_guard(previous, s)` (NK-6l) prove the session guard's `HullContact.terminal`
  has no event and its `HullContact.contacts` no contact; 0 evaluates the reference
  ([evidence](../../docs/research/native-kernel/NK-6l/README.md)).
- `glow_voice_block(parameters, harmonics, state, frames)` (NK-6m) runs the glow voice's per-sample synthesis loop
  byte-identically to `GlowVoice.render_telemetry`'s GDScript loop, which remains the reference and the fallback. It is
  audio only and reads no stage state ([evidence](../../docs/research/native-kernel/NK-6m/README.md)).
- `integrate_tick` answers `GlowFlight.finish` itself for a steady glow tick (NK-6n, `nk_glow_finish.hpp`): no
  resource events or transitions, the plan's steady terms present, and no failure or lifecycle stop. Every refusal
  calls finish ([evidence](../../docs/research/native-kernel/NK-6n/README.md)).
- `stage_wheel_rows(s, aux, steer, anchors, speeds, brake)` (NK-6o) gives the ground audio `Ground.evaluate`'s
  per-wheel diagnostics and `Wheels.frame` at a published endpoint, through an optional row collector on the
  qualified wheel law; [] evaluates the reference ([evidence](../../docs/research/native-kernel/NK-6o/README.md)).
- `state_valid`, `scenery_state_valid`, `arrays_finite` and `inertia_cached` (NK-6q) are pure, exact ports of
  `Simulation.step`'s own checks and the session's state checks. `Simulation` uses them only when the installed
  model's stage belongs to the kernel ([evidence](../../docs/research/native-kernel/NK-6q/README.md)).
- `retarded_emission(times, positions, listener, now, sound_speed, min_index)` (NK-6r) is `SoundscapeModel.retarded_emission`
  in the model's mixed precision, for the soundscape's propagation delay; presentation only
  ([evidence](../../docs/research/native-kernel/NK-6r/README.md)).
- `glow_vibration(geometry, crank_phase, omega, alpha, firing)` (NK-6s) gives `physics/glow/vibration.gd` `evaluate`'s numbers for
  a validated geometry, for flight audio's glow voice ([evidence](../../docs/research/native-kernel/NK-6s/README.md)).
- `stage_liquid_store_valid(values, index)` (NK-6t) answers `LiquidFlight.valid` from the prepared liquid stage, so a
  liquid aircraft's contact-mass sampler is built only when a contact asks for it
  ([evidence](../../docs/research/native-kernel/NK-6t/README.md)).
- `prepare_substeps` (NK-6u, `nk_substeps.hpp`) lets `integrate_tick` count the tick's RK4 substeps from the installed
  session's plan (`FlightSession.native_substep_plan`), as `_substeps_joint` and `_substeps` do; a tick the plan does
  not cover still calls them ([evidence](../../docs/research/native-kernel/NK-6u/README.md)).
- `stage_contact_clear` (NK-6v) proves a tick's contact step touches nothing from the store, reach, state and quiet
  terminal checks in one call, so `FlightSession._clear_contact_step` skips the reference step
  ([evidence](../../docs/research/native-kernel/NK-6v/README.md)).
- `sound_doppler`, `sound_targets`, `sound_humidity`, `sound_absorption_cutoff`, `sound_screening`, `sound_activity`
  and `sound_distance_gain` (NK-7a, `nk_soundscape.hpp`) are the soundscape model's laws, `Wildlife.activity` and
  `PowertrainAudio.distance_gain`, exact; `exp`, `log`, `pow` and `Vector3.angle_to` call the engine's own functions
  ([evidence](../../docs/research/native-kernel/NK-7a/README.md)).
- `sound_core_bind`, `sound_core_frame`, `sound_core_events`, `sound_core_heard`, `sound_core_reset` and
  `sound_core_state` (NK-7b, `nk_soundscape_core.hpp`) run `Soundscape.update_sound`: the delay history, mix state and
  voice and filter writes through the engine's method binds, refusing any frame the reference would read differently
  ([evidence](../../docs/research/native-kernel/NK-7b/README.md)).
- `sound_core_bind_bank` (NK-7c) moves the recorded powertrain bank's `update_sound` into that frame and mirrors its
  state back to the bank ([evidence](../../docs/research/native-kernel/NK-7c/README.md)).
- `ground_core_*` (NK-7d, `nk_ground_audio_core.hpp`) runs `GroundAudio` in accepted-tick mode: observation,
  touchdown queries and frame updates, writing its slots' players by method bind
  ([evidence](../../docs/research/native-kernel/NK-7d/README.md)).
- `mechanical_core_*` (NK-7e, `nk_mechanical_audio_core.hpp`) runs `MechanicalAudio` in accepted-tick mode: the motion
  observer, motion and event voices, writing its players by method bind; GDScript still makes the motion players
  ([evidence](../../docs/research/native-kernel/NK-7e/README.md)).
- `audio_unloaded_rows` and `audio_source_kinematics` (NK-7f, `nk_audio_rows.hpp`) build flight audio's airborne
  contact rows and the snapshot's source kinematics from the accepted state, exactly
  ([evidence](../../docs/research/native-kernel/NK-7f/README.md)).
- `stage_glow_audio_keys` (NK-7g) builds flight audio's whole glow key set in one call, with the GDScript's key order
  and types ([evidence](../../docs/research/native-kernel/NK-7g/README.md)).
- `stage_endpoint_air` (NK-7i) answers flight audio's wind and air data at the published endpoint, as `pre_step_air`
  evaluates them ([evidence](../../docs/research/native-kernel/NK-7i/README.md)).
- `shadow_parts_bind` and `shadow_part_poses` (NK-8a, `nk_shadow_parts.hpp`) walk a projected shadow's parts to its
  source, composing transforms with the engine's own operator and reading visibility by method bind
  ([evidence](../../docs/research/native-kernel/NK-8a/README.md)).
- `stage_terrain_sample` (NK-8b) samples the installed stage's prepared ground for render callers when they pass the
  same surface table, so `main.gd` `_ground_height` reads `FlightSession.render_terrain_sample`
  ([evidence](../../docs/research/native-kernel/NK-8b/README.md)).
- `stats_speed_*` (NK-9a, `nk_stats_speed.hpp`) hold and advance one statistics detector's speed window, exactly as
  `detector.gd`'s speed functions do ([evidence](../../docs/research/native-kernel/NK-9a/README.md)).
- `stats_sample_*` (NK-9b, `nk_stats_sample.hpp`) build the statistics adapter's published sample in one call, as
  `fixed_wing_adapter.gd` `sample(true)` does ([evidence](../../docs/research/native-kernel/NK-9b/README.md)).
- Production adapters in `app/sim/native/` install the prepared family evaluator through `VehicleModel.stage`.
  A model without continuous state uses `loads` and `rotor_momentum`; detachment restores both callbacks before
  replacing its owner. The pre-step, commit and publication, discrete supervision, collision, step policies,
  the helicopter tick and observers remain in GDScript.
- D6: preparation rejects malformed data, unsupported laws, pending configuration changes and exceeded resource
  budgets. Family adapters admit the capabilities listed above. Rejection preserves the reference callbacks;
  a later configuration mutation faults before the next native evaluation rather than using stale coefficients.
  Since NK-6p a fixed-wing native flight freezes the guarded containers, so a container write fails where it is made
  and the guard proves the frozen roots by identity; packed leaves, which stay writable in place, keep bitwise watches
  ([decision](../../docs/DECISIONS.md#a-native-flight-freezes-its-guarded-configuration),
  [evidence](../../docs/research/native-kernel/NK-6p/README.md)).

## Exactness rules (keep them when extending the port)

1. Copy the current GDScript operation by operation, including `+ 0.0` sign scrubs, grouping and branch order.
2. Every simulation value is `nk::R`: its `+ - * /` are single SSE2 instructions with the left operand first
   (inline asm). x86 returns the first operand's NaN when both are NaN; the pinned engine's GDScript evaluator is
   left-first on every path, while GCC commutes `+` and `*`. Plain `double` matched every finite result but not
   NaN signs on malformed inputs.
3. Engine C++ helpers are not the GDScript evaluator: `lerpf` computes `weight * (to - from) + from` (the pinned
   binary's NaN priority, found by the math probe).
4. `pow_` hides its exponent from constant folding (asm barrier); `build.py` refuses a library without a `pow`
   import. Transcendentals call the same glibc symbols the engine uses (NK-1).
5. Float literals must parse identically in GDScript; the oracle compiles the spellings in `literal_table()`.
   Add new literals there. GDScript's `-0.0` literal is +0.0; build -0.0 from bits in tests.
6. Dictionaries returned to the kernel use the reference's key types and order (`{loads = ...}` is `StringName`).

## Build, verify, negative control

```bash
python3 research/native-kernel/build.py --jobs 4                       # library, descriptor, receipt
python3 research/native-kernel/run.py                                  # milestone-1 component oracle
python3 research/native-kernel/run.py --script stage_oracle.gd         # stage, prop, hull, ground, D6 refusals
python3 research/native-kernel/run.py --script trajectory.gd --option ticks=14400   # + timing pairs, attribution
python3 research/native-kernel/build.py --jobs 4 --mutant              # -DNK_MUTATION negative control
python3 research/native-kernel/run.py --mutant [--script stage_oracle.gd]           # must FAIL
python3 research/native-kernel/run.py --render tmp/native-kernel/<results>.json
```

All three harnesses run with `--path app` through `tools/godot/run_checked.py`, load the extension with
`GDExtensionManager.load_extension` and the reference scripts from `app/`, so edits there are verified
automatically; `stage_oracle.gd` and `trajectory.gd` extend `oracle.gd`. Trajectory options (`--option`):
`ticks`, `pairs`, `warmup`, `samples`, `repeats`, `timing-cases`, `only=all|timing|attribution`, `skip-timing=true`.
Run one Godot process at a time under `nice`; timings on a shared VM are indicative only.

## Verification and local installation

Use `--app-library` on oracle runs to test the installed library. NK-3 must not be auto-loaded by Godot. The runner resolves
the binary from the selected descriptor and checks its receipt and SHA-256 before running. It retains the checked
Godot report, engine/binary hashes before and after, mirrored source hashes before and after, and harness hashes.
Reserved runner arguments cannot be overridden through `--option`. A negative control needs actual differing
comparisons, an orderly exit 1, and no engine/script errors; a timeout or invalid request is not mutation evidence.

`build.py --install-app` requires fresh reports for the exact binary, current mirrored sources and harness, and
the pinned Linux editor. Historical reports lacking these receipts cannot qualify an installation. The stage
oracle must actually compare at least 10,000 states across air, ground and hull domains, including malformed
inputs. Trajectory v2 must compare all five cases for at least 960 actual ticks each. Trim, runway and manoeuvre
must complete the requested length without a fault, pause or crash; only take-off and lake may end early in a
matching crash after the minimum. Native context and stage calls are checked per accepted tick. Fault injection,
checkpoint/restore and pending-weather-configuration refusal must execute their full prerequisite and comparison tapes.

Stop the editor and app before installation. The installer creates `native/kernel/.gdignore` before publishing
the descriptor and removes only NK-3's old entry from `.godot/extension_list.cfg`, preserving other registrations.
This protects the next process; it cannot undo initialization in a running process. The loader accepts only the
canonical descriptor and its exact local library, checks the engine and mirrored sources before loading, and
refuses an extension already loaded outside that check. Corrupt JSON/ABI metadata returns a clean fallback.
Do not hand-edit the descriptor or remove `.gdignore`; reinstall through the tool.

```bash
python3 research/native-kernel/test_verification.py
python3 tools/godot/run_checked.py --timeout 90 -- \
  "$(app/get-godot.sh)" --headless --path app --audio-driver Dummy \
  --script "$PWD/research/native-kernel/test_trajectory.gd"
python3 research/native-kernel/run.py --script stage_oracle.gd --states 12000
python3 research/native-kernel/run.py --script trajectory.gd \
  --option ticks=960 --option skip-timing=true
# Run every additional family/weather gate and the deliberate mutant control listed
# in build.py ORACLE_ARGUMENTS. The installer prints any missing gate's command.
python3 research/native-kernel/build.py --install-app
python3 tools/godot/run_checked.py --timeout 90 -- \
  "$(app/get-godot.sh)" --headless --path app --audio-driver Dummy \
  --script res://tests/test_native_stage.gd
python3 tools/godot/run_checked.py --timeout 120 -- \
  "$(app/get-godot.sh)" --headless --path app --script res://tests/test_native_session.gd
python3 tools/godot/run_checked.py --timeout 90 -- \
  "$(app/get-godot.sh)" --headless --path app --script res://tests/test_native_replay.gd
```

Use the temporary build for all prerequisite oracles, including after a source or ABI change; `--app-library`
selects the already installed candidate and is appropriate only after installation. All production family tests
must exercise their native branches after installation; successful absent/stale-library branches establish fallback only. The Python gate
regressions run through `research/test-tools.sh`; CI also runs the library-free GDScript policy regression.
This local installation does not qualify exports, Windows, target-host timing or the full fleet. The receipt's
mirrored-source list includes the stock aircraft data but is not a manifest of every environment input; retained
results describe their recorded snapshot, and other data changes require fresh verification.

`python3 research/native-kernel/test_installation.py` exercises guarded loading and cache migration in disposable
projects using the built library and pinned editor; it does not change the app installation. CI's
`native-kernel-linux` job builds and qualifies the library, requires explicit native-success markers in its
runtime tests, and checks a short production reference/native pair. Its diagnostics are retained on failure and
release publication depends on the job. The export job then qualifies the actual release executable as described below.

The optional `set_stage_rejection_diagnostics(true)` native diagnostic records a bounded, detached rejection
payload from the actual C++ stage. It is disabled in normal flight, does not alter stage results, and clears
when a later evaluation or context/preparation transition invalidates the evidence. The stopped-glow diagnostic
is a model-domain explanation; the application's generic RK fault message remains unchanged. Its actual-library
regression is required in Linux CI after installation:

```bash
python3 tools/godot/run_checked.py --timeout 600 --require-text 'NK3_GLOW_REJECTION_NATIVE verdict=pass' -- \
  "$(app/get-godot.sh)" --headless --path app --audio-driver Dummy \
  --script "$PWD/research/native-kernel/test_glow_rejection.gd"
python3 tools/godot/run_checked.py --timeout 1200 --require-text 'NK3_RUNTIME_DOMAIN_NATIVE verdict=pass' -- \
  "$(app/get-godot.sh)" --headless --path app --audio-driver Dummy \
  --script "$PWD/research/native-kernel/test_fleet.gd" -- --require-runtime-domain
```

## Linux release packages

After installation, also run the validated-model admission regressions. They require actual native ownership
and cover Workshop wake scaling, large wake/field tables, shared configuration data, rotating-wheel layouts
above the former fixed buffer sizes, empty states, and checkpoint replay. The large prescribed-source table
case verifies preparation only; it is not a completed flight or physical-validation claim.

```bash
python3 tools/godot/run_checked.py --timeout 600 --require-text 'NK3_NATIVE_ADMISSION verdict=pass' -- \
  "$(app/get-godot.sh)" --headless --path app --audio-driver Dummy \
  --script "$PWD/research/native-kernel/test_native_admission.gd"
python3 tools/godot/run_checked.py --timeout 600 --require-text 'NK3_NATIVE_WHEEL_ADMISSION verdict=pass' -- \
  "$(app/get-godot.sh)" --headless --path app --audio-driver Dummy \
  --script "$PWD/research/native-kernel/test_native_wheel_admission.gd"
```

After installation, run the complete declared fleet matrix before promoting expanded coverage:

```bash
python3 research/native-kernel/fleet_campaign.py --out tmp/nk3-fleet-qualified \
  --keep-going --jobs 4 --warmup 600 --samples 2400 --timeout 14400
```

The campaign reads the canonical matrix from `fleet.gd`, runs each aircraft through the existing checked runner,
and validates the exact union of row keys. All shards must share the same engine, native binary, receipt,
source and harness identities. Flight rows require every requested tick, matching fingerprints and native call
coverage. Explicitly known startup refusals require the same reset failure from both backends. Six stopped-glow
runway/gusty tapes have a separately checked runtime-domain refusal: the 61FX stops after 873 accepted ticks,
the 55AX after 801, and the FS64V after 805, with each contact option. The two-strokes reject the endpoint
trial; the four-stroke rejects the midpoint. Their next RK trial would require reverse rotation beyond
the installation's static hold domain. These outcomes require exact accepted-prefix, rejected-trial and rollback
agreement, actual native ownership and counters, and finite branch evidence from C++ and the reference.
Each model has a fixed trial phase and rejecting-call ordinal. The four-stroke also pins its captured aircraft,
trial, context and seven cause values using the original float64 bytes.
Neither startup nor runtime refusals count as completed flights. Unknown faults still fail the campaign.
The observed startup policy also distinguishes bounded runway-support nonconvergence from the X8's
half-power trim-throttle refusal. Its named aircraft/battery/start/weather/contact combinations require paired
reset observations, pinned typed setup/outcome/frame bytes and retained reference ownership. These starts
provide no native-flight coverage and do not establish physical impossibility. A new refusal needs its own
diagnosis and reviewed evidence; matching error text alone does not admit another combination.
Historical X8 pack/hand-launch/spatial-crosswind evidence records a physical terminal at tick 1,640, with
matched typed states, configuration and contact evidence, native coverage, and unchanged stopped attempts.
Those pins bind the original X8 input and native binary `d023a875…`; they do not qualify the canonical
MoonRunner X99. The historical declaration counts and observations remain in the
[NK-3 evidence record](../../docs/research/native-kernel/NK-3/README.md).

Four canonical MoonRunner rows are unqualified: ideal battery with half-power airborne start in hot-high,
and default pack with hand launch in spatial-crosswind-v1, each with soft-hull contacts on and off. A full
campaign rejects these rows until new paired evidence is reviewed; a scoped run that excludes them can
still run but cannot qualify the full fleet. The library-free and `--require-runtime-domain` CI checks verify
policy and the named runtime-domain proofs, not MoonRunner or full-fleet qualification. The optional
`--require-physical-terminal` check remains unsatisfied for the current catalog until a current terminal
is separately observed and qualified. Unknown faults and incomplete runs still fail.
A scoped report alone does not qualify the whole fleet. `--reuse-report AIRCRAFT=REPORT` accepts
only a complete, matching full-aircraft report, including one still being produced. Concurrent runs establish
software equivalence, not timing or physical validation.
`--keep-going` finishes independent shards after a shard failure, then fails the campaign; source drift still
stops all work. It does not change row acceptance or permit a partial matrix to pass.

`app/export.sh` prepares the verified identity, exports the ordinary application, stages the exact native
sidecars, and tests that executable before creating the release archive. The CI export job consumes the
library and oracle receipts from `native-kernel-linux`; the other vehicle's native artifacts keep their own gates.
A local export needs the same verified inputs for both tracks. Do not manually register NK-3 as an exported extension.

The export plugin embeds `res://native/kernel/package.json` and the fixed diagnostic sources. That immutable
manifest pins the verified library, source provenance and diagnostic digests. A sidecar artifact receipt binds
the final executable (including its embedded PCK) and manifest hashes. This is consistency checking, not a
cryptographic signature. Keep `native/kernel/` beside the executable when moving the package; a missing or
altered sidecar selects reference. No runtime C++ build or source-tree access is needed.

The package gate runs stage, lifecycle, exact-replay and helicopter tests through
`--quick-flight --native-qualification=stage|lifecycle|replay|helicopter|helicopter-radio`. It also compares typed reference/native session
fingerprints in the same executable and tests default selection, explicit reference, aircraft families and
corrupted/missing sidecar fallback. Completed diagnostics must actually exercise native code; skipped or
interrupted tests do not pass. The diagnostic route accepts fixed modes, never a script path.

For a longer paired CPU measurement of a retained release:

```bash
python3 research/performance/session_baseline.py --release-executable --godot /path/to/openrc-simulator.x86_64 \
  --out tmp/nk3-release-pairs --aircraft jensen-das-ugly-stik-60 --case trim,maneuver,runway \
  --warmup-ticks 600 --sample-ticks 2400 --repeats 3 --compare-backends
python3 research/native-kernel/test_default_route.py --release-executable /path/to/openrc-simulator.x86_64
```

Run timing alone on the measured host. These headless checks do not qualify rendering at 1080p or any other
resolution, physical realism, Windows/macOS native execution, or unsupported aircraft and weather.

## C++ development tools (NK-3)

`devtools.py` reuses the locked GCC/SCons/godot-cpp toolchain and existing stage/trajectory oracles. It provides
**development-only** builds, with separate godot-cpp checkouts and objects, symbols, frame pointers and
SCons-generated `compile_commands.json`. `ubsan` instruments both bindings and NK-3 with GCC UBSan;
`profile` keeps an optimized, unsanitized library for debugger/profiler use. Neither writes into `app/`, the
regular build directory or installation receipts. Every output directory must be new and under `tmp/`.

```bash
python3 research/native-kernel/devtools.py build --mode ubsan --jobs 2 --out tmp/nk3-ubsan
python3 research/native-kernel/devtools.py check --build tmp/nk3-ubsan --out tmp/nk3-ubsan-check \
  --script all --ticks 960
python3 research/native-kernel/devtools.py build --mode profile --jobs 2 --out tmp/nk3-profile
python3 research/native-kernel/test_devtools.py
```

The check copies and imports a private app (including its existing import cache, excluding installed native
extensions), isolates XDG user-data/config/cache paths, clears inherited loader overrides, freezes the harness and
records source, helper, engine and library hashes. Allow at least 4 GiB free for each private copy. `--script all`
copies/imports once, runs stage then trajectory sequentially and stops on the first failure. Single-oracle checks
remain available with `--script stage_oracle.gd` (default) or `--script trajectory.gd`. Source changes during the
copy fail the run. Overlapping input/output paths and directory symlinks are rejected before copying. It forces
UBSan to halt, rejects sanitizer stderr even on exit zero, and retains checked-run logs, a separate amended
`diagnostic-report.json` and `summary.json`. Before copying, a disposable library constructor deliberately causes
signed integer overflow through the same engine's `GDExtensionManager.load_extension`; it must fail with that
specific diagnostic, control marker and source identity. `positive-controls.json` records the detector proof. The production library and C++ source
are never mutated. The stage check requires at least 10,000 actual states including malformed cases, and
trajectory checks require the requested seed/tick count and all fault, restore and fallback phases; literal
probes alone cannot pass. Combined checks retain per-oracle results in `summary.json.runs`.

`--mode asan` builds ASan+UBSan and also checks a heap-buffer-overflow control. It **requires a compatible
ASan-built Godot**, supplied with `check --godot /path/to/engine`. The pinned official Linux editor uses
`RTLD_DEEPBIND`, which ASan cannot support. The actual loader control rejects that combination before copying
the app. No loader shim or system-policy change is applied. An ASan-built engine is not provided or qualified
by this tool. In this mode only, GCC's matching ASan runtime is preloaded into the Godot child.

UBSan checks undefined behavior in instrumented code, not engine internals or general memory safety. ASan leak
detection is disabled. The intentional NaN/Inf corpus remains valid input for the existing numerical oracle;
the wrapper does not enable floating-point divide-by-zero traps. A passing short development run does not
satisfy the normal installation gate, fleet validation or physical validation. Run the regular builder and
verification workflow above before promotion. Timing is disabled in development checks.

Point clangd at the build's compilation database; it includes the real NK-3 translation unit, generated includes
and strict FP flags. If clang-tidy is installed, use the database without automatic fixes, for example:

```bash
clang-tidy -p tmp/nk3-profile -checks='-*,clang-analyzer-*,bugprone-*' \
  research/native-kernel/src/nk_kernel.cpp
```

Static analysis is advisory and requires its own recorded tool version; compiler errors are not a clean result.
Use stock `perf record`/`perf report` or GDB with the profile library and its descriptor. Counter access depends
on host permissions; no tool here changes system policy. Whole-oracle profiles include the reference backend,
startup and wrappers. The regular `trajectory.gd` paired timing measures the **research stage adapter**, excluding
the production session's backend configuration checks and context handoff; it cannot establish production-native
cost. Its timing and attribution paths require completed warm-up, every requested tick advancing exactly once,
no pause/fault/crash and native-stage coverage before aggregation. Timing pairs must also match a SHA-256 digest
of the initial state and every warm-up/sample tick (state, auxiliary state, continuous state, inputs, loads and
modes). Failed or divergent work has no timing summary. Unknown modes and contradictory skip options fail.
Hashing and native stats queries are outside the stopwatch but may perturb later samples; reports declare this
instrumentation. Use an otherwise idle host and a separately qualified production-path benchmark for runtime
performance decisions.
Sanitizer/profile overhead and shared-host measurements do not qualify target performance or 1080p rendering.

Design sources and bounded execution evidence: [tooling research](../../docs/research/native-kernel/NK-3/tooling-research-2026-10-28.md).

## Windows build (NK-4)

The design note's preferred route works: MinGW-w64 GCC (15.2, msvcrt) links the same math split as the pinned
engine, and three Windows-only switches make every installer gate bit-identical, NaN bits included:
`-fno-builtin-sin -fno-builtin-cos` (no libmingwex `sincos` fusion), `NK_ENGINE_LERP_SOURCE_ORDER` (the Windows
engine's lerp operand order) and `NK_ENGINE_SQRT_SSE2` (`sqrtsd` instead of libmingwex's double-rounding x87 `sqrt`).
MSVC (`/fp:strict`, no inline assembly) remains unbuilt. Evidence: [NK-4](../../docs/research/native-kernel/NK-4/README.md).

```bash
export OPENRC_NK_TOOL_ROOT=D:/OpenRCsimulator-native/nk          # keep the toolchain off a full system drive
python research/native-kernel/build_windows.py --jobs 8           # DLL, descriptor, receipt (MinGW-w64 g++)
python research/native-kernel/build_windows.py --jobs 8 --mutant  # negative control
python research/native-kernel/run.py --script <gate> <arguments>  # every build.py ORACLE_ARGUMENTS gate
python research/native-kernel/build_windows.py --install-app      # beside the Linux install, never over it
```

The Windows installation uses `openrc_native_kernel_windows.gdextension` and `build-receipt-windows.json`; the
loader checks the exact `Godot_v4.8-beta2_win64.exe`, the descriptor, binary and mirrored sources like Linux.
`--define` diagnostic builds are never installable. On an enrolled workstation, run the headless gates with
`OPENRC_TESTQUEUE_ROOT` pointing at a private unenrolled root (no timing gate is involved). If `app/.godot` is
relocated through a junction or link, installation reads its `extension_list.cfg` and refuses only when it would
have to remove this kernel's registration there. CI job
`native-kernel-windows` repeats the build, every gate and the native production markers with the pinned nuwen
MinGW archive. It ran green on the hosted runner on 2026-11-18 and is now required.

### Windows release packages (NK-4, owner decision 2026-11-18: native kernel always)

A Windows release carries the verified DLL beside its executable, as Linux does. The package has its own
embedded manifest, `res://native/kernel/package-windows.json`, so Linux and Windows exports from one run cannot
replace each other.

```bash
python research/native-kernel/package.py prepare-windows --tool-root "$OPENRC_NK_TOOL_ROOT"   # after --install-app
"$GODOT" --headless --path app --export-release Windows "<new dir>/OpenRC Simulator.exe"
python research/native-kernel/package.py finalize-windows --executable "<new dir>/OpenRC Simulator.exe" \
  --template <windows_release_x86_64.exe> --tool-root "$OPENRC_NK_TOOL_ROOT"
```

**Commands:**

- `prepare-windows` revalidates the installed DLL, its receipt, sources, toolchain lock, builder and pinned
  Windows editor, and the exact oracle evidence the receipt cites.
- The export plugin then embeds the manifest and the six diagnostics. On a Windows editor it requires the
  qualified editor binary. A cross-export from Linux checks only that the identity is well formed.
- `finalize-windows` writes `native/kernel/` with the DLL, the LF-only descriptor and the licence. It also
  writes `package-receipt.json`, which binds the executable, manifest, template and DLL.

`app/sim/native_stage.gd` and `app/app_state/native_package.gd` load the DLL only after these identities match;
anything else selects the reference backend.

**Qualification is on the exported executable.** It runs the same five `--quick-flight --native-qualification`
modes as the Linux gate in `app/export.sh`, then `test_default_route.py --release-executable` (Windows aware).
The DLL was qualified against the editor, and the shipped template is a different binary. Only this gate shows
they agree. The [first local Windows package](../../docs/research/native-kernel/NK-4/windows-package-2026-11-18.md)
passed all five modes.

**CI release path (2026-11-18).** `native-kernel-windows` is required and uploads `nk4-native-windows-build`:
the DLL, `build-receipt-windows.json`, the oracle evidence and the mutant. The Linux `export` job restores it
beside the Linux install, and `app/export.sh` runs `prepare-windows` and `finalize-windows`. The tool root is
`OPENRC_NK4_TOOL_ROOT`, default `tmp/native-kernel-windows`. A Linux exporter has no Windows editor, so
`prepare-windows` checks the evidence against the editor and wrapper identities the receipt recorded.
`tools/release/manifest.py` binds the final ZIP's executable and DLL to that receipt. The required
`native-kernel-windows-package` job (windows-2025) then runs the five modes and the default route on the
exact released archive, and `release` waits for it. An export without a qualified Windows install now fails.

Both Windows jobs check out LF bytes (`core.autocrlf=false`), because receipts hash sources byte for byte. The
hosted runner's default had produced CRLF hashes for 127 of 138 mirrored sources, which a Linux export cannot
match. Known limits:

- On a Linux exporter the editor identities come from the same run's artifact, so a forged receipt and evidence set
  would require compromising CI itself.
- The Windows gate omits Linux's player-CLI replay, production pair and trace smoke; `replay` mode and the default
  route cover native selection.

Cross-mode acceptance was checked in WSL against requalified evidence: 19 gates accepted, a wrong wrapper identity
refused.
