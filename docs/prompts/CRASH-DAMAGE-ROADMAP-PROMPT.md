# Prompt: crash, damage and destruction roadmap

2026-10-06 · revision 1 · **Status: brief, not started.** Task brief for a future plan (crash/damage/destruction system integrated into [ROADMAP.md](../../ROADMAP.md)).

---

Act as a senior game developer, Godot expert, physics/simulation engineer, and experienced RC pilot.

Review the current repository, architecture, existing roadmap, physics systems, aircraft structure, audio, VFX, and damage-related code before proposing anything.

Your task is to create a detailed, phased roadmap for a realistic aircraft crash, damage, and destruction system, fully integrated with the existing project roadmap.

Do not treat this as an isolated feature. First determine:

- what the repository already supports;
- which existing systems can be reused;
- what technical limitations currently exist;
- where this work belongs in the main roadmap;
- which dependencies should be implemented earlier or later.

Design the feature as **small, incremental phases**, where every phase produces a visible improvement and becomes the foundation for the next one. Avoid throwaway work or systems that will need to be replaced later.

Start simple and progressively increase fidelity. For example:

- impact detection and better crash sound;
- impact intensity and surface-dependent audio;
- basic visual crash feedback;
- separating aircraft into a few logical structural sections;
- damage based on impact location and direction;
- breaking wings, landing gear, tail, fuselage, canopy, etc.;
- debris with appropriate mass, momentum, collisions, and lifetime;
- structural damage thresholds based on impact energy and aircraft construction;
- partial crashes where the aircraft remains damaged but flyable;
- realistic destruction for high-energy impacts;
- turbine-jet-specific effects such as fire, smoke, fuel-related effects, and post-impact behavior when appropriate;
- progressively better particles, sound, camera feedback, terrain interaction, and visual polish.

These are examples, not requirements. Use your judgment as the senior developer and adapt the plan to the actual repository.

The final system should respond to **how the crash happens**, not simply trigger a generic destruction animation. Impact speed, angle, location, aircraft mass, structural properties, terrain, aircraft type, and remaining energy should influence the result where technically appropriate.

Research extensively before defining the later phases. Study Godot techniques, physics and fracture approaches, game destruction systems, aircraft crash behavior, RC aircraft construction, turbine-jet crashes, audio design, particles, debris simulation, performance strategies, and relevant open-source examples.

Do not over-engineer early phases. Keep each step small, testable, visually useful, and compatible with future improvements.

For each phase define:

- objective;
- systems affected;
- implementation approach;
- dependencies;
- files or architecture likely involved;
- validation/tests;
- performance risks;
- research or reference documents that should accompany that phase.

Add complementary technical documents when deeper research would help the future developer.

Be creative about ways to make crashes feel convincing and satisfying, but keep simulation logic grounded in physics and the actual capabilities of the repository.

The end goal is a scalable destruction system where a minor wing strike, landing-gear failure, hard landing, medium crash, and high-energy turbine-jet impact can produce meaningfully different outcomes.

Integrate the resulting plan cleanly into the existing roadmap and place each phase where it makes the most technical sense.
