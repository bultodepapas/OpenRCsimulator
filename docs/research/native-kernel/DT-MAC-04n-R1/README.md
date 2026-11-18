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

## Pending

- Hosted Mac CI on the candidate: domain guard and the new default-route gate.
- Companion solver rebind receipt.
- Physical M1 default-route run. On 2026-11-18 ANGEL was running another track's
  rendered campaign and ANGELA_AIR had 1.4 GiB free.
