# DT-MAC-04n-R1: Mac native default after the DR-19e collision world (2026-11-18)

The [Apple plan](../../../plans/apple-silicon-performance.md#dt-mac-04n-r1--keep-the-mac-native-default-after-world-changes)
owns the procedure and remaining scope. This page records the evidence.

## Symptom

DR-19e (`3c91936ab`) changed only `app/scenery/collision_world.gd`: round-bale
core boxes and a stepped pit-shelter roof. `app/sim/native_macos_domain.gd` still
pinned the old world (`ea0bdec4…`, 6,092 proxies). Every ordinary macOS ARM64
flight was refused with "collision world differs from the screened stock context"
and ran the reference evaluator. The required `native-kernel-macos` job failed
"stock collision identity and proxy count match the screened world".

## Measured identities

The identity hashes trigonometric results, so it is platform-specific. The
proxy count and the portable fingerprint are not.

| World | Platform | Identity | Proxies | Source |
| --- | --- | --- | ---: | --- |
| Before DR-19e | macOS ARM64, physical M1 | `ea0bdec4c9ae6307…` | 6,092 | [AFC-02 Mac route record](../../ai-companions/AFC-02/rebinds/2026-11-13-main-macos-route-behavior.json) |
| Before DR-19e | macOS ARM64, hosted virtual M1 | `ea0bdec4c9ae6307…` | 6,092 | CI run 44170648090 at `a986b99ca`, `domain-guard.log` |
| Before DR-19e | Windows x86_64 | `8c49e45696cbd0c1…` | 6,092 | Local probe of `3c91936ab^` builder |
| Current | macOS ARM64, hosted virtual M1 | `4077c4fd3e1d78ef8bb2d612c7206bc397c06df8261b69c3d6b3ca23a8e12d55` | 6,139 | CI run 44394589553 at `3ab7ffd40` |
| Current | Windows x86_64 | `6a958e685bebc70b…` | 6,139 | Local probe, official 4.8-beta2 |
| Current | Linux x86_64 | `4c71cacccb1dee71…` | 6,139 | WSL, official 4.8-beta2 |

The hosted virtual M1 (`Apple M1 (Virtual)`, `VirtualMac2,1`) reproduced the
physical M1 value before DR-19e, so its current value is the renewed pin. No
application file that feeds the collision world changed between `3ab7ffd40`
and the candidate.

The portable fingerprint `2cfce9a5108d593b…` was identical on Windows and Linux.
It quantizes lengths in steps of 1000·π/3 per metre (about 0.95 mm). Decimal and
power-of-two steps put exact authored values on rounding edges: 121 values at
1 mm and 64 at 1/1024 m. With the irrational step, no value lies within 1e-12
(relative) of an edge.

## Local verification (Windows, official 4.8-beta2)

- `test_native_macos_domain_world.gd`: 9 checks, 0 failures. With the old pins it
  fails "6139 != 6092" and the fingerprint check, which is the regression witness.
- `test_ui_pause_physics.gd`: 11/0. `test_ui_pause.gd`: all checks pass, including
  the real flight's physics line. `test_ui_language.gd`: all catalog checks pass.
- `test_macos_diagnostics.py`: 13 tests; `test_ci_macos.py` with
  `test_ci_macos_selection.py`: 11 tests.

## Companion admission

- Solver: all nine retained tapes replayed byte-identically (2,881 rows each);
  pin `90499aa6` → `8cdbbf8b`,
  [receipt](../../ai-companions/AFC-02/rebinds/2026-11-18-90499aa6-to-8cdbbf8b.json).
- Behavior manifest: the telemetry commit `1c9199b5a` had changed the pinned
  `app/app_root.gd` without renewal, so `test_companions_profiles.gd` refused both
  profiles. Its 188 lines touch no companion code; only that hash was renewed.
  Profiles 95/0, behavior manifest 39/0, airspace 48/0, external rejection 63/0.

## Local Windows native install

The domain file is a mirrored native source, so the edit made this workstation's
install stale. The rebuilt DLL (`5c64d4e7…`) passed all 18 positive gates, the
mutant failed as required, and the installed receipt binds the new domain bytes.
`test_native_session.gd`: 343 checks, 0 failures, native verdict pass.

## Hosted Mac CI

`native-macos.yml` dispatched on `7dbc30243` (run 44410231374, `Apple M1 (Virtual)`,
`VirtualMac2,1`) passed every step of `ci_macos.py`:

- Domain guard: 72 checks; the stock profile measured `4077c4fd…`, 6,139 proxies.
- Oracle roster, mutant, FPCR control, install, and installed stage, lifecycle
  and replay qualification.
- New `installed-default-route`: `MACOS_DEFAULT_ROUTE verdict=pass checks=74`,
  checked report `ok`, zero errors and warnings. The ordinary Quick Flight logged
  `requested: native`, `backend: native`, binary `ee7c6126e629f535…`, with no
  refusal reason. Its `--alt=31` control stayed on the reference evaluator with
  "custom spawn is outside the screened stock scope".

This is source-editor evidence on a hosted virtual M1. It does not qualify a
package, the fleet, performance or physical hardware.

## Main CI

Run 44420818679 on `f7b348e40` repeated the Mac job with success, and the Linux
unit roster passed `test_native_macos_domain_world.gd` (9/0, fingerprint
`2cfce9a5…`), `test_ui_pause_physics.gd` (11/0), `test_ui_pause.gd`,
`test_ui_pause_responsive.gd` (1,857), `test_ui_language.gd` and
`test_companions_profiles.gd` (95/0). The run's two failures predate this
change: the H6 guard's bare `pow(` in `app/physics/event_step.gd` (`793f76ccc`)
and the telemetry Settings overflow in `test_ui_modal_responsive.gd`, fixed by
`2c8d768fb`.

## Pending

- Physical M1 default-route run. On 2026-11-18 ANGEL was running another track's
  rendered campaign and ANGELA_AIR had 1.4 GiB free.

## Club collision world (2026-11-22)

On `graphics-audit` at `1858352ca`, the club generated 7,295 collision proxies.
The portable world test and the hosted Mac domain guard both rejected the
previous 6,139-proxy world. [Failing CI](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/45097617517)

| Measurement | Value |
| --- | --- |
| Hosted M1 stock world identity | `7e5fcff5098591708406da39142768107a594eac142b3862c2f684695876cc64` |
| Linux quantized geometry fingerprint | `f020b4c86b7e98df77eacc2a35e2a95a3fc17a046e2cb9b5d719ac82abfd16a2` |

The domain renewal in `8756d93e5` uses both observations and retains the
custom-spawn refusal. On Linux the portable world test passed all 9 checks.
The nine companion replays matched across all 25,929 CSV rows. The behavior
manifest and profile checks also passed (39 and 95 checks).
[Solver receipt](../../ai-companions/AFC-02/rebinds/2026-11-23-95d5d31f-to-c06bc9c8.json)
and [qualification run](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/45101860898).

The hosted virtual M1 reproduced the 7,295-proxy identity and passed all
74 installed default-route checks, including native Quick Flight and the
custom-spawn reference control.
[Mac source qualification](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/45101860898/job/137454306870)
and [combined revision CI](https://github.com/bultodepapas/OpenRCsimulator/actions/runs/45105065689).
