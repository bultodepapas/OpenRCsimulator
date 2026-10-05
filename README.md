# OpenRCsimulator

An open-source RC airplane simulator, developed heavily with AI. It grows from small to large: something simple that works first, then expanding gradually. Choices stay easy to revisit; open questions are invitations to explore.

Two principles guide the project:

1. We are building an RC airplane simulator.
2. We grow from small to large, starting with something very simple that works and shows a little airplane, then expanding gradually.

## Status (2026-10-05)

**The alpha (v0.1) is feature-complete and waiting for its first pilots.** The simulator is built with **Godot 4.7** (GDScript) in [`app/`](app/).

The first airplane is the **Jensen Das Ugly Stik 60** (Phil Kraft design, 60 in span, .61 two-stroke glow). Its CG, nose and wing were measured on the full-size plan. The visual model is plan-based, built by a parallel model team.

What works today:
- **Flight physics** at a fixed 240 Hz in 64-bit floats:
  - six-axis aerodynamics with a full envelope (stall at ~9 m/s, flat-plate flow at any attitude);
  - asymmetric stall: wing drop, spins;
  - .61 engine with APC 12×6 thrust, prop torque and gyroscopic precession;
  - servos;
  - a six-axis trim, so you start in hands-off level flight.
- **Controls:** keyboard, or a USB RC radio or gamepad. The radio has arming (the throttle must be seen low), an unplug failsafe and in-app calibration.
- **Pilot aids:** ground shadow, grass texture, HUD, performance numbers, auto-zoom, live reload of the aircraft data, engine sound, flight traces (CSV), crash and restart.
- **Flown checks** (not formulas):
  - trim α 3.7° at 15 m/s;
  - full-aileron roll 148°/s coordinated and 123°/s with the feet still, at 15 m/s;
  - dead-stick glide 8.5 : 1;
  - stall at 8.9 m/s;
  - spin about 1.2 turns/s, recovered with opposite rudder and the stick forward;
  - golden-flight regression tests.
- **Release builds:** Windows, Linux and macOS, built and checked by `app/export.sh` and by CI on `v*` tags. The exported Linux binary flies the trimmed-flight check, and the macOS app is universal and ad-hoc signed. See [docs/FIRST-LAUNCH.md](docs/FIRST-LAUNCH.md) for how to start an unsigned build on each system.
- **Tests:** about 1,250 automated checks in ~45 s, plus GitHub CI.

**Next: Gate 2.** The owner (and ideally 1–2 RC pilots) fly v0.1 with a radio and rate how it feels against a real Stik. See [ROADMAP.md](ROADMAP.md), milestone M1.

## Quick start

On Linux; on other systems use Godot 4.7.2 directly:

```sh
app/get-godot.sh                    # downloads the pinned, checksum-verified Godot 4.7.2 into .tools/
$(app/get-godot.sh) --path app      # fly (needs a display)
app/test.sh                         # all checks, headless
app/export.sh                       # release builds into dist/ (downloads the 1.28 GB export templates once)
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
