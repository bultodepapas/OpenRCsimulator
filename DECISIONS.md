# Decisions

A small record of what we choose and why. The two guiding principles remain established. Every other decision is our current direction and can change as we learn. When an entry is replaced, mark it *superseded* and keep it, so its context remains visible. The route these decisions serve is in [ROADMAP.md](ROADMAP.md).

| Date | Decision | Reasoning | Status | Revisit when |
| --- | --- | --- | --- | --- |
| 2026-10-05 | Build an RC airplane simulator. | This is the project's purpose. | Established principle | — |
| 2026-10-05 | Start with something very simple that works and shows a little airplane, then grow gradually. | Small working steps let us learn and shape the project through experience. | Established principle | — |
| 2026-10-05 | Use an Ultra Stick / Ugly Stick-style .60 nitro airplane as the first model. | The project owner prefers this aircraft family and propulsion direction as a concrete starting point. Begin with a simple representation and refine it gradually. | Chosen direction | — |
| 2026-10-05 | Use the **Hangar 9 Ultra Stick .60, conventional wing, tailwheel** as the reference variant for numbers. Keep the Big Stik .60 ARF as the alternate. | Its manual gives span, length, area, weight, CG and throws in one place, and matches the chosen name. Not mixing variants was a research finding. | Provisional | Better data (plans, measurements) appears for another variant. |
| 2026-10-05 | First prototype runs **in the browser with Three.js, TypeScript and Vite**. | Zero install and easy sharing; quick edit/run loop; HTML panels for tuning; screenshots and headless tests give AI-assisted work concrete feedback. Three.js was one of the two researched candidates. | Provisional | Stage 1 checkpoint shows friction, or the Gamepad API loses transmitter channels. Then run the Three.js vs Godot comparison from RESEARCH.md. |
| 2026-10-05 | Write **our own small flight-physics module**, with no renderer imports, testable headless in Node with Vitest. | No researched library models a 2-stroke glow RC airplane out of the box (JSBSim `FGPiston` is four-stroke only). A small model stays readable, and the boundary keeps it portable. | Provisional | We find ourselves rebuilding mature features (trim, gear, tables) at high cost. Then re-evaluate JSBSim. |
| 2026-10-05 | Physics uses **SI units**, a world frame with **NED axes** (north, east, down), body axes **FRD** (forward, right, down), and quaternion attitude. Conversion to the Three.js Y-up frame happens in **one** function at the render boundary. | Aerospace conventions match the sources (JSBSim, UMN, textbooks). The research repeatedly flagged unit and axis mix-ups as a main risk. | Provisional | — |
| 2026-10-05 | **Fixed physics timestep** (start at 1/240 s) with render interpolation and a cap on catch-up steps. | *Fix Your Timestep* pattern; enables replay and convergence checks. | Provisional | The convergence test (`h`, `h/2`, `h/4`) suggests a different step or integrator. |
| 2026-10-05 | First flight model is a **linear stability-derivative model with a crude stall cap**. Its nondimensional derivatives are seeded from the UltraStick25e specimen and labeled `borrowed`; geometry and mass come from the .60 manual. | This is the smallest model that gives believable RC handling. The 25e is a geometrically similar Stick with inspectable data. Labels keep the borrowing honest. | Provisional | Playtesting or sensitivity tests show which effects matter (stall, propwash, ground effect…). |
| 2026-10-05 | Aircraft parameters live in a **data file** (JSON). Each value records its unit, source and evidence kind. | Recommended by the research (parameter manifest); keeps the model swappable and its provenance visible. | Provisional | — |
| 2026-10-05 | Default view is a **fixed ground pilot camera**. A chase camera exists for debugging. | This is how RC airplanes are actually flown; distant-aircraft readability is a core research question. | Provisional | Pilot observation suggests otherwise. |
| 2026-10-05 | Input starts with the **keyboard**, then the **browser Gamepad API with a raw channel inspector**. The sim applies no deadzone, expo or circular limit by default. | Detection, channel delivery and correct response are separate milestones; the radio already applies expo, rates and mixes. | Provisional | — |

## Open (deliberately not decided yet)

- **Project license.** Choose before the first public release. Check compatibility with UIUC "GPL'd data" terms if we bundle airfoil data.
- **Exact engine and propeller.** O.S. MAX-65AX and APC 12×6 Sport are reference candidates for Stage 5.
- Native/desktop packaging, mobile, VR, multiplayer, and a second aircraft.

The researched electric Ultra Stick 25e remains a comparison specimen. Only its nondimensional aerodynamic derivatives are borrowed, as labeled starting estimates. Its dimensions, mass properties and electric propulsion do not define the .60 nitro model.
