# R11: portable generation of Avanti high-angle polar rows

2026-10-14. The first canonical Linux run stopped at AV-15's exact generator check. The 45-degree drag entry in each polar branch serialized as `0.6414130000000001` on Windows and `0.6414129999999999` on Linux. File size, CRLF count and every other JSON value agreed. This was platform-library rounding in `sin(angle)^2`, not a new physical-model discrepancy.

The existing flat-plate continuation has four fixed angles. The [source builder](../../../../../../research/avanti-s/av17-r2/build_polar.py) now uses their analytic factors:

| Angle | Lift factor, `sin(2a)/2` | Drag factor, `sin(a)^2` |
|---|---:|---:|
| 45° | 1/2 | 1/2 |
| 60° | √3/4 | 3/4 |
| 75° | 1/4 | (2+√3)/4 |
| 90° | 0 | 1 |

Lift remains `CD90 * lift_factor`; drag remains `CD0 + CD90 * drag_factor`. No coefficient fit, global rounding, check tolerance or physical evidence classification changed. The independent trigonometric flat-plate comparison keeps its existing `1e-15` tolerance. A new one-ULP sine perturbation leaves the builder output byte-for-byte identical while changing the old formula's rows, so the regression can reject the original dependency on library rounding.

The aircraft was regenerated through AV-06 into a fresh temporary output directory. Only eight scalar values in its two high-angle polar branches changed, by at most `2.220446049250313e-16`; all other parsed JSON values and the canonical derivation report remain unchanged. The temporary report names its temporary output directory; the preflight comparison accounts for that single declared path literal. The Avanti Workshop descriptor was then regenerated using the existing descriptor builder, writing only the Avanti output. [Before/after hashes and exact numeric differences](regeneration.json), [four-file implementation identity](overlay.json). The old and regenerated aircraft/descriptor bytes are retained here.

On Windows Python 3.11.9, AV-06 `--check`, the six AV-15 geometry/inventory tests and all eight polar-builder tests pass. The final [Linux integration evidence](../README.md) owns cross-platform generator, full-suite and export outcomes. Earlier flight recordings retain their embedded aircraft bytes and original source identities; this correction does not re-record any golden flight or relabel historical recordings.

The polar-builder unittest was previously outside the canonical `app/test.sh` path: importing its builder from AV-06 does not execute that test. A separate [one-line hook](canonical-hook.patch) now runs it with the other Avanti checks. This orchestration change is identified separately from the four-file generator repair and is included in the next canonical candidate; the direct Windows invocation passes all eight tests.
