# Airship dynamics

Scope: the decisions, alternatives and evidence behind airship dynamics. These records retain the context of each choice; linked guides and the [current roadmap](../../ROADMAP.md) own implemented behavior and remaining work. [Decision index](../DECISIONS.md).

## The RC blimp owns a coupled added-mass law with a declared afterbody loss

**BL-03/BL-05/BL-10.** The airship supplies its own `body_derivative`:

- **Coupled solve.** (M_RB + M_A) ν̇ is solved about a fixed datum, with Kirchhoff momentum transport for calm or steady wind. Inflating scalar mass or using a previous-frame acceleration would misstate stopping and oscillation of a near-neutral hull.
- **Afterbody loss.** Ideal Munk alone made the measured hull diverge in pitch above ~2 m/s. Hopkins' afterbody loss is therefore a declared quantity rather than an undocumented Munk reduction factor. The cancelled load uses the same lateral added mass per length as C_A (Lamb k2 × `hull_scale` × ρπR²), so it never removes more potential load than C_A supplies. The resulting hull is only marginally stable directionally, as real airships are; a gentle proportional pilot holds heading within 0.2° at full-throttle cruise. Fin effectiveness was not retuned to hide this: body interference (raises fin lift) and tail boundary layer (lowers it) are unmeasured (BL-13).
- **Activity routing.** The activity shares the exclusive ground-activity slot in AppRoot. That keeps every existing "no activity running" guard and exit request, but needs no aircraft-catalog entry.

Revisit when measured restoring/turn data (BL-13) or gust admission (BL-14) need a different hull moment accounting. [Plan](../plans/rc-airship.md#14-implementation-status), [BL-12 evidence](../research/rc-airship/BL-12/README.md).
