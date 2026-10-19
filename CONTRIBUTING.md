# Contributing to OpenRC Simulator

Start with a small, reproducible improvement. The simulator lives in `app/`; `prototypes/stage0/three/` is frozen. Use [TOOLS](docs/TOOLS.md#developer-setup) for developer setup, [STACK](docs/STACK.md) for architecture and [AGENTS](AGENTS.md) for repository rules.

## Help as a pilot

Use a [published test build](https://github.com/bultodepapas/OpenRCsimulator/releases) and include its version, aircraft, operating system and controller when [opening an issue](https://github.com/bultodepapas/OpenRCsimulator/issues/new/choose).

For handling feedback, describe the maneuver, speed if known, stick input, expected response and actual response. Identify the real RC aircraft used for comparison. Record a fixed-wing [flight log with F10 and maneuver markers with F11](docs/FLIGHT-LOGGING.md#quick-start), or a diagnostic CSV trace with **T**. For visibility feedback, include a screenshot, resolution and auto-zoom (**Z**) state. The [player guide](docs/FIRST-LAUNCH.md) explains frame-time reports.

## Make a change

1. Read the relevant step in [ROADMAP.md](ROADMAP.md) or the linked implementation plan. Use an issue to discuss large changes before investing in them.
2. Work on a branch and keep the change focused. Preserve other developers' in-progress work; only stage files belonging to your change.
3. Run the checks relevant to the change. For Godot code, run `app/test.sh`; for rendering changes, also run `app/capture.sh` and inspect the images. Changes to paths, ignore rules or generated outputs need verification from a fresh clone.
4. Record any new reusable lesson using [LEARNINGS.md's criteria](docs/LEARNINGS.md#keeping-this-useful), and include the applicable plan step and proof in the commit or pull request: test, capture, trace or measurement.
5. Open a pull request explaining the problem, resulting behavior and validation. State any pending manual checks, especially real-radio, GPU or native-platform testing.

Documentation-only changes need link and content checks; they do not require rerunning the flight simulation.

## Preserve the simulation contract

- Keep simulation state in 64-bit GDScript `float`s. Do not use `Vector3`, `Basis`, `Quaternion` or `Transform3D` for state in `sim/` or `physics/`; rendering converts at the boundary.
- Sessions install one `VehicleModel` into the shared kernel; keep vehicle-specific laws in that model. See [kernel boundaries](docs/STACK.md#boundaries-and-data-flow).
- Aircraft parameters use [openrc-aircraft v2](docs/AIRCRAFT_CONTRACT.md) in `app/data/aircraft/`. Physical quantities carry `{value, unit, kind, source}`. Label estimates; invalid data must refuse flight.
- Regenerate generated geometry and physics data through their source scripts. Do not hand-edit generated files. [AGENTS.md](AGENTS.md) identifies the relevant tracks and ownership boundaries.
- Preserve aircraft node names and control-surface hinge interfaces. Re-record golden flights only for an intentional, explained physics change.
- Do not leave broken scripts in `app/`: the test runner parses every script. Keep drafts outside the app until ready to validate.

## Assets and research

Keep dated evidence and primary sources in `docs/research/`, and experiments, generators and measurement reducers in `research/`. Pin dependency versions. Reuse suitable free assets with redistribution rights; include their license, provenance and processing steps. Keep reference scans with unclear redistribution rights out of commits.

## Documentation

Use the [documentation map](docs/README.md) for authoritative topic homes, track ownership, step IDs and writing conventions. Keep current guides concise and accurate to implementation. Preserve sources and required evidence; consolidate useful information before removing completed/superseded plans. Commands belong in [TOOLS](docs/TOOLS.md), controls in [FIRST-LAUNCH](docs/FIRST-LAUNCH.md), and aircraft authoring in [AIRCRAFT_CONTRACT](docs/AIRCRAFT_CONTRACT.md).

## Releases

`app/export.sh` builds Windows, Linux and macOS packages, runs a trimmed-flight smoke test on the exported Linux binary, and checks packaged resources and metadata. CI exports on `main`, `v*` tags and manual dispatch; only `v*` tags publish releases. Numeric `vX.Y.Z` tags publish stable releases; suffixed tags such as `vX.Y.Z-rc.N` publish prereleases using `docs/releases/<tag>.md`. Release tags identify the tested code and must stay fixed. See [release commands and sequence](docs/TOOLS.md#release-sequence).
