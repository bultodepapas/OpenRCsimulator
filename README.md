# OpenRCsimulator

An open-source RC airplane simulator, developed heavily with AI. It grows from small to large: something simple that works first, then expanding gradually. Choices stay easy to revisit; open questions are invitations to explore.

Two principles guide the project:

1. We are building an RC airplane simulator.
2. We grow from small to large, starting with something very simple that works and shows a little airplane, then expanding gradually.

## Status (2026-10-05)

**The first airplane flies.** The simulator is built with **Godot 4.7** (GDScript) in [`app/`](app/).

The first airplane is the **Jensen Das Ugly Stik 60** (Phil Kraft design, 60 in span, .61 two-stroke glow). Its CG, nose and wing were measured on the full-size plan. The visual model is plan-based, built by a parallel model team.

What works today:
- **Flight physics:**
  - six-axis aerodynamics at a fixed 240 Hz;
  - .61 engine with APC 12×6 thrust and prop torque;
  - a six-axis trim, so you start in hands-off trimmed level flight.
- **Controls and feedback:** keyboard controls with rate limits, an input panel, an engine sound that follows rpm, and flight traces (CSV) for debugging.
- **Physical sense, checked against hand predictions:**
  - trim α 3.7° at 15 m/s;
  - full-aileron roll 192°/s at 20 m/s;
  - glide 8.5 : 1;
  - static thrust 41 N (T/W 1.6).
- **Tests:** about 660 automated checks in ~30 s, plus GitHub CI.

**Next: the alpha (v0.1).** A downloadable Windows/Linux/macOS build you fly with your RC radio. Steps left: radio input, pilot aids (ground shadow, HUD), stall and crash, release builds. See [ROADMAP.md](ROADMAP.md), milestone M1.

## Quick start

On Linux; on other systems use Godot 4.7.2 directly:

```sh
app/get-godot.sh                    # downloads the pinned, checksum-verified Godot 4.7.2 into .tools/
$(app/get-godot.sh) --path app      # fly (needs a display)
app/test.sh                         # all checks, headless
```

| Keys | Action |
| --- | --- |
| ← → | aileron |
| ↓ ↑ | elevator (↓ = stick back = nose up) |
| A D | rudder |
| W S | throttle |
| R | restart |
| P | resume after a pause |
| C | camera |
| T | record a flight trace |

## Documents

| Document | What it holds |
| --- | --- |
| [ROADMAP.md](ROADMAP.md) | The route: done phases, milestones M1–M5, each ending in a playable build |
| [DECISIONS.md](DECISIONS.md) | What was chosen, why, and what would change it |
| [LEARNINGS.md](LEARNINGS.md) | Practical lessons from building and running things |
| [STACK.md](STACK.md) | The development stack and the options surveyed |
| [RESEARCH.md](RESEARCH.md) | Exploratory findings, original sources, open questions |
| [AGENTS.md](AGENTS.md) | Rules and commands for contributors and AI agents |
| [docs/UGLY-STIK-PLAN.md](docs/UGLY-STIK-PLAN.md) | The model team's plan for the Ugly Stik visual model (Spanish) |

Licensed under the [MIT License](LICENSE). Third-party data, if bundled, keeps its own license. Plans and scans used as references stay local in the gitignored `references/` folder.
