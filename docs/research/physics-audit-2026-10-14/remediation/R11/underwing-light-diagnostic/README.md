# R11 underwing-light selector correction

2026-10-14 · The Avanti underwing strip jumped 60.127 mm at adjacent span stations, just over the existing 60 mm limit. At x=0.573965 m its merged chord piece included the `paint_fence_lower` edge at y=−0.070710 m; the neighboring point followed the wing skin. The original diagnosis and component evidence are in [`component-slice-probe.txt`](component-slice-probe.txt) and [`surface-detail-probe.txt`](surface-detail-probe.txt).

`AircraftLights.underwing_lines()` now accepts a triangle only when its geometric normal has a larger vertical component than its horizontal magnitude: `abs(n.y) > sqrt(n.x² + n.z²)`. This is a strict, winding-independent 45° face-normal criterion. The comparison is scaled before squaring, and zero-area or non-finite normals are skipped. It applies only to bottom/top strip slicing; belly and landing-light geometry retain their prior inputs. Station locations, chord-piece selection, 60 mm vertical bound and 150 mm chordwise bound are unchanged ([`aircraft_lights.gd`](../../../../../../app/render/world/aircraft_lights.gd)). The catalog bounds and synthetic `_test_underwing_face_selection()` cases live in [`test_world_field_lights.gd`](../../../../../../app/tests/test_world_field_lights.gd).

Before production edits, the exact criterion was evaluated over all five catalog meshes, with the existing selector run on the filtered triangles. Every aircraft retained 9/9 bottom and top stations on each side. Every maximum step remained within the test's existing bounds:

| Aircraft | Kept triangles / all | Bottom max Δy L/R (m) | Top max Δy L/R (m) | Max Δz, bottom/top L/R (m) |
| --- | ---: | ---: | ---: | ---: |
| Jensen Ugly Stik 60 | 20,220 / 56,763 | 0.005108 / 0.005108 | 0.002852 / 0.002852 | 0.054330 / 0.054330 |
| Extra 300S 60 | 7,984 / 19,502 | 0.000935 / 0.000935 | 0.000911 / 0.000911 | 0.004104 / 0.004104 |
| Avanti S A200 P100-RX | 66,921 / 146,652 | 0.013285 / 0.013274 | 0.017282 / 0.017274 | 0.056724 / 0.056694 |
| P-51D Mustang 120 | 22,699 / 52,693 | 0.011932 / 0.011932 | 0.006607 / 0.006607 | 0.006675 / 0.006675 |
| Turbo Timber Evolution | 13,054 / 42,519 | 0.039018 / 0.039018 | 0.011689 / 0.010949 | 0.002267 / 0.002267 |

For the Avanti's failing right-side pair, the filtered path is `(0.499100, −0.014583, 0.345643)` to `(0.573965, −0.011230, 0.367878)`, reducing Δy to 13.274 mm. The exploratory 0.85 cutoff was replaced by the simpler 45° geometric rule; this rule was tested, not fitted to pass the Avanti case.

The focused test gained synthetic cases based on known coordinates rather than a second implementation of the selector. A flat two-skin wing is crossed by a lower vertical fence and a collapsed low triangle; both bottom and top strips must remain on the specified skin. A separate 0.5 m/m sloped wing checks that a tilted but vertical-dominant skin still traces all stations. A degenerate triangle by itself must produce no station. With the old selector, the synthetic flat case dipped to y=−0.204 m at x=0.50–0.65 m, its top rose to y=0.124 m, and the degenerate-only input emitted a false station; the old full suite also reproduced the Avanti jump.

## Reproduction and identities

The 45° cross-catalog probe ran on the physical disposable copy `tmp/physics-audit-r11-p51-downwash-review-20261014/baseline-app`, with no runtime edit in that copy; it exited 0. Complete output is [`normal-45-probe.txt`](normal-45-probe.txt). The focused suite was run before and after in the same disposable project:

```powershell
.tools\Godot_v4.7.2-stable_win64_console.exe --headless --path tmp/physics-audit-r11-p51-downwash-review-20261014/baseline-app --audio-driver Dummy --script res://tests/test_world_field_lights.gd
```

Before: `64 checks, 1 failed`, reproducing only the Avanti continuity bound ([`before-test.log`](before-test.log), exit 1). After: `72 checks, 0 failed` ([`after-test.log`](after-test.log), exit 0). A negative-control run with the original selector and the new tests failed the combined fence/skin assertion (both bottom and top coordinates are shown) and the degenerate-only assertion, as intended; it also reproduced the catalog Avanti failure ([`negative-control-old-selector.log`](negative-control-old-selector.log), exit 1).

| Input | SHA-256 |
| --- | --- |
| Godot 4.7.2 stable console | `C8F0A6BC45A19B33541501E57F6F7CD972AB18453743266339D495CBBE846643` |
| Original `aircraft_lights.gd` | `00C676F4A40A95BF945BEF08D7CCE6EF6E4DD01EEBF406F6A753F27C6C95EC61` |
| Corrected `aircraft_lights.gd` | `D0363990BD3A6933BE97DFCB5639DCBFBA91422BBF1E91C7515B3C1B5AC93893` |
| Original `test_world_field_lights.gd` | `E2F1495C738E74EB93D32168A4405546C1B5077084F3120EF7B8E7B1C04057B7` |
| Corrected `test_world_field_lights.gd` | `6281250C79FC6205B261D225A6A9C59FFA22911050D059795F3353A5658648FD` |
| `selector-correction.patch` | `EF23C2AB95157C64C15745A681D874F4AF1FA00D7630A347D0D6A3B722A3DFE6` |
| Avanti imported GLB | `803D293D597D88D94CEBE1C191E6453E5D108ACA4D6E5D5EAABFA0A387CF0F36` |
| Exact 45° probe script | `F86C6F368E73E3AA57807D91A913EDD1A64E39FD8266D7F5E6B6E5EB13498056` |
| Exact 45° probe output | `4DA28DC7DA8634EAFC654D127BC4A3D081B5C4DE1006CD7E26AC8D48AF0F9848` |

The disposable copy began with the original selector SHA above; only the two focused source/test files were replaced there for the after-run. The probe reports the same Avanti imported GLB SHA as the prior asset receipt. No generated aircraft geometry, catalog data, or runtime files outside the selector/test pair were changed for this correction.
