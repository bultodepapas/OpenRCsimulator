# R11: rate-guard square evaluation

2026-10-14. The Linux run after the Avanti generator repair stopped at H4's exact selector comparison: one of 20,000 samples differed. H12's 20,001 unchanged-domain load comparisons passed. This failed run is retained; it is not a full-suite pass.

## Reproduced cause

The fixture is `gp-extra-300s-60`, RNG seed `44117`, sample `1894`. The unchanged frozen selector returns zero. The independent R02 rate guard forms the Euclidean norm of `omega × r` with direct squares; production instead called the general `pow(component, 2)` wrapper. In the vertical tail's z component:

| Quantity | General power | Direct multiplication |
|---|---:|---:|
| Component squared | 12.849006078244738 | 12.849006078244736 |
| Squared-component little-endian float64 bytes | `2e55b8ecb0b22940` | `2d55b8ecb0b22940` |
| Final selector little-endian float64 bytes | `7ae30666c0aec23f` | `6ee30666c0aec23f` |

The square, squared speed and speed differ by one ULP; the final smoothstep weight differs by 12 ULP, or `3.3306690738754696e-16`. The power-based reconstruction matches the production result exactly. The multiplication-based reconstruction matches the independent expected result exactly. The shortened decimal printed by Godot is insufficient to measure this difference.

The [seeded probe](h4_case_1894_probe.gd), [captured case](h4_case_1894.json) and [Linux output](linux-h4-case-1894.log) retain both calculations. The raw JSON key `rate_components_rad_s` is mislabeled: these components are `omega × r`, in **m/s**. The original capture is preserved with this correction. Its displayed JSON decimals are not a lossless state serialization; use the float64 byte fields and the seeded probe to reproduce the rounding diagnosis.

An independent [exact-rational oracle](../../../../../../research/physics-audit-2026-10-14/remediation/rate_guard_square_oracle.py) decodes the captured component bytes and squares that rational value exactly. Direct multiplication gives the unique nearest float64: its absolute rounding error is `8.837912929494461e-16`, versus `8.925655464508044e-16` for the captured power result. Both neighboring floats are checked using exact fractions. [Oracle result and source/case hashes](square-rounding-oracle.json). This establishes the better-rounded square at this input without relying on the production `pow` or the H4 expected decimal.

## Change and compatibility

The [runtime patch](runtime.patch) replaces only the six constant-exponent squares in the wing and tail rate guards with explicit scalar products. The norm, angle and smoothstep formulas remain the same; floating-point evaluation changes. This can change the blend weight in its transition regime, so existing golden flights and H7 branch-sensitivity checks must pass without refreshing them. It is not a change to the physical calibration, state layout or wake units. Recordings retain their original solver identity; new recordings must identify the corrected source.

The H4 test, random seed, exact comparator and frozen oracle remain unchanged. [Previous production source](aero-before.gd.txt) SHA-256: `fed08e735494b6d2597f639cca118d84c978f75828811f0d09968bfc67a85be5`. Corrected source SHA-256: `7ac94f6003f2cb7660a56dd94755c6a7d6143d90cc446c6b6c20433038ce38e3`. H4 test SHA-256: `7db6ab897ee5c6bc7e95081ee59a863c5e5322d5c3cb2ecb99e3fd67e783d45d`.

The frozen oracle's Windows checkout SHA-256 is `d80e056f9897653330c8b6a716cc847fa9ea1089fe2e696eda5a2411582395e0`; its Linux LF checkout SHA-256 is `392d7b90f442ddfd7fb2219eb4b6b6904b22d3fb4f6a589c5d09b2f7ff05eb1e`. Replacing exactly its 138 CRLF line endings with LF reproduces the latter hash; its code did not change.

## Regression checks and H7 instrumentation

The corrected Linux candidate passes [H4/H12](h4-focused.log) at 20,000/20,001 comparisons, [H6 and its self-test](h6-focused.log), and all [four existing golden flights](golden-focused.log). No golden was refreshed.

The first H7 attempt then [failed before simulation](h7-focused-failure.log): its global replacement expected one wing saturation branch, but R02 had already introduced two rate guards with the same text. The original and corrected rate-square sources both contain those three branches. The [harness-only repair](h7-instrumentation.patch) scopes instrumentation to `local_flow_weight`, anchors each exit by its actual context, preserves the initial/wing-angle IDs, and gives the wing/tail rate exits distinct IDs. Missing, duplicated or additional uninstrumented exits fail the check. [In-memory rejection checks](h7-anchor-check.json) also confirm that an unrelated function remains unchanged.

The [corrected Linux H7 run](h7-focused-patched.log) passes the existing one-ULP perturbations, same-machine wrapper/direct-built-in trajectory identity, and the deliberate branch mutation in all four goldens. The worst perturbation error is `0.000777156` times the existing `tolerance/1000` bound. Tolerances and mutation semantics remain unchanged. This tests selected recorded paths; it is not proof of all branches or all possible flights.

An adversarial follow-up found that checking only the exact uninstrumented `if blend == 1.0` spelling could miss a new exit written differently. The [additional preflight](h7-return-inventory.patch) checks the declared return inventory before applying anchors. [Negative controls](h7-return-inventory-check.json) reject an extra equivalent-condition exit, an inline return, a changed return expression and a changed known condition. The instrumented production source is byte-identical to the previously passing harness output. This extension is validated separately after the already-running canonical suite; the running checkout is not modified.

The [Windows rerun](../final-scenarios-04/verified/README.md) also passes H4/H6/H7 and the unchanged goldens, plus two complete recordings with exact replay and 28 actual-session control scenarios. [R11](../README.md) owns the final canonical/export disposition. No physical-validation claim follows from resolving this numerical regression.
