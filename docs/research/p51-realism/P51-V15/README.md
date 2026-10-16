# P51-V15: control-surface audit, picture against physics

2026-10-15 · Revision 1 · **Status: implemented and verified in software.**
- After [P51-V14](../P51-V14/README.md) found the 3D rudder 30 % smaller than the physics rudder, every movable surface was audited against the physics data and clearance.
- Three defects fixed: the drawn flap was 10 % short in chord, the wing-tip panel overlapped each aileron by 10 mm, and the "flown" clearance pose used placeholder throws.
- Physics data is unchanged.

Prefix: P51-V15. [P-51 guide](../../../P51-PLAN.md) · Probe: [`clearance_probe.gd`](../../../../research/p51/p51-v14/clearance_probe.gd) (now any hinge)

## Audit

| Surface | Physics | 3D model before | Result |
| --- | --- | --- | --- |
| Rudder | Aerodynamic hinge, 10.41 ft² | Matched since P51-V14 (10.61 ft²) | Checked by `verify_p51` |
| Ailerons | Span 0.8438–1.3743 m, chord fraction 0.19 (`geometry.json`) | Same fields | Match |
| Elevator | Chord fraction 0.35 (`elevator_hinge_fraction`) | Same field, plus the tip horn balance the physics omits | Match |
| Flaps | Hinge fraction 0.79 (c_f/c 0.21), 0.1249–0.7996 m | Hinge pivot at 0.79, but the panels drawn at the aileron's 0.19 | **Fixed** |
| Wing tip | — | Rounding stations from 1.3645 m, inboard of the aileron end at 1.3743 m | **Fixed** |
| Throws | Data `controls.max_throw` 18° / 15° / 30° | Clearance "flown" pose used kit placeholders 16.1° / 14.7° / 33.5° | **Fixed** |

## Defects and fixes

**Flap chord.** `_wing_panel()` drew every hinged part at `1 − aileron_chord_fraction`, with the comment "flap_chord_fraction is the same 0.21". That stopped being true when P51-13 set the ailerons to the XP-51's 0.19. The flap panel and the fixed panel ahead of it therefore split at 81 % chord. The flap pivot and the physics flap are at 79 %. So the drawn flap was a 19 % chord flap (about 10 % less area than it flies) and turned about a point 2 % chord ahead of its own nose. That offset also explains part of the nose-penetration fix P51-11a needed. The function now takes the surface's chord fraction; the flap and the panel ahead of it pass the flap's 0.21.

**Wing tip over the ailerons.** The tip panel's planform-rounding stations began at `half − tip_round_plan − 0.008` = 1.3645 m. That is inboard of the aileron's outer end at 1.3743 m, so the full-chord tip panel overlapped the outer 10 mm of each aileron: 0.00 mm gap even at neutral. Only rounding stations outboard of the aileron end are kept now. The probe gives 1.68–1.93 mm from −45° to +45° ([before](tests/probe-aileron-tip-before.txt), [after](tests/probe-aileron-tip-after.txt)).

**Throws.** `p51d_model.gd` `manual_throws_deg()` returned kit placeholders "until the P-51 data file sets flight throws". The data file now sets them, so the function reads `controls.max_throw` from it. The inspector and clearance check now pose the surfaces the simulator flies.

## New checks

- **Flap chord (`verify_p51`):** at every vertex of the left flap and the fixed panel ahead of it (straight-LE chord at the vertex's own station, flaps up), the flap's nose and the fixed trailing edge must lie within 0.012 of the data file's `flaps.hinge_fraction`. Mutation proof: with the fix removed on a disposable copy, it fails (nose 0.8171, fixed TE 0.8077 against 0.7900).
- **Aileron clearance (`verify_p51_clearance`):** each aileron is now checked against the fixed panel ahead of it, the panel between flap and aileron, and the tip, at the flown throws both ways. These pairs had never been checked; they exposed the tip overlap.

## Verification

Godot 4.7.2, native Windows ([logs](tests/)).

- `verify_p51`: 251/251.
- `verify_p51_clearance`: 72/72 in 71 s, including the 12 new aileron checks; flaps pass at 15° and 45° with the corrected chord.
- **Other tests:** see the [summary](tests/summary.txt).
- **Data:** physics data unchanged. Model manifests and Workshop descriptors regenerated through their generators.

## Limits

The flap and aileron chord fractions are scaled full-size values. Clearance is checked at the flown throws and at 45° (rudder, elevators) only. Software verification is not physical validation.
