# Contributing to OpenRC Simulator

Start with a small, reproducible improvement. The simulator lives in `app/`; `prototypes/stage0/three/` is frozen. Start at the [master documentation index](docs/README.md) for the relevant subject, then follow [developer setup](docs/TOOLS.md#developer-setup) and [repository rules](AGENTS.md).

## Help as a pilot

Use a [published test build](https://github.com/bultodepapas/OpenRCsimulator/releases) and include its version, aircraft, operating system and controller when [opening an issue](https://github.com/bultodepapas/OpenRCsimulator/issues/new/choose).

For handling feedback, describe the maneuver, speed if known, stick input, expected response and actual response. Identify the real RC aircraft used for comparison. Record a fixed-wing [flight log with F10 and maneuver markers with F11](docs/FLIGHT-LOGGING.md#quick-start), or a diagnostic CSV trace with **T**. For visibility feedback, include a screenshot, resolution and auto-zoom (**Z**) state. The [player guide](docs/FIRST-LAUNCH.md) explains frame-time reports.

## Make a change

1. Read the relevant outcome in the [current roadmap](ROADMAP.md), then its linked task contract. Use an issue to discuss large changes before investing in them.
2. Keep the change focused, whether working directly on `main` or on a branch. Preserve other developers' in-progress work; only stage files belonging to your change.
3. Follow the [verification scope](docs/tools/shared.md#verification-scope): select focused tests based on the changed behavior and affected consumers; do not run the entire local app/physics/visual suite after each narrow change. The [local impact examples](docs/tools/shared.md#local-impact-examples) show menu and radio-calibration cases. Verify affected contracts on a stable candidate, state which checks ran and which remain pending, and inspect the required CI result before claiming automated verification complete. Changes to paths, ignore rules or generated outputs need verification from a fresh clone.
4. Record any new reusable lesson using [LEARNINGS.md's criteria](docs/LEARNINGS.md#keeping-this-useful), and include the applicable plan step and proof in the commit or pull request: test, capture, trace or measurement.
5. In a commit or pull request, explain the problem, resulting behavior and validation. State any pending manual checks, especially real-radio, GPU or native-platform testing. Resolve a failed CI gate before considering software verification of a direct `main` change complete.

For documentation-only changes, check content, local links and anchors, explicit instruction imports and `git diff --check`. If a runtime tool or evidence manifest consumes the document, check that dependency too. Check inbound references before removing paths or headings. Required hosted CI remains governed by the [verification scope](docs/tools/shared.md#verification-scope).

## Preserve the simulation contract

- Keep simulation state in 64-bit GDScript `float`s. Do not use `Vector3`, `Basis`, `Quaternion` or `Transform3D` for state in `sim/` or `physics/`; rendering converts at the boundary.
- Sessions install one `VehicleModel` into the shared kernel; keep vehicle-specific laws in that model. See [kernel boundaries](docs/STACK.md#boundaries-and-data-flow).
- Aircraft parameters use [openrc-aircraft v2](docs/AIRCRAFT_CONTRACT.md) in `app/data/aircraft/`. Physical quantities carry `{value, unit, kind, source}`. Label estimates; invalid data must refuse flight.
- Regenerate generated geometry and physics data through their source scripts. Do not hand-edit generated files. The [ownership registry](docs/TRACKS.md) identifies the relevant tracks and shared boundaries.
- Preserve aircraft node names and control-surface hinge interfaces. Re-record golden flights only for an intentional, explained physics change.
- Do not leave broken scripts in `app/`: the test runner parses every script. Keep drafts outside the app until ready to validate.

## Assets and research

Keep dated evidence and primary sources in `docs/research/`, and experiments, generators and measurement reducers in `research/`. Pin dependency versions. Reuse suitable free assets with redistribution rights; include their license, provenance and processing steps. Keep reference scans with unclear redistribution rights out of commits.

For a new landscape, follow the [landscape contributor guide](docs/LANDSCAPES.md). Green paradise demonstrates the folder, field data and adapter interface; add one explicit registry entry, keep Club field available, and verify loading, switching, lighting and exported resources.

## Documentation

Use the [documentation index](docs/README.md) for authoritative topic homes, the [track registry](docs/TRACKS.md) for ownership and step IDs, and [documentation maintenance](docs/DOCUMENTATION.md) for writing and evidence conventions. Keep current guides concise and accurate to implementation. Preserve sources and required evidence; consolidate useful information before removing completed/superseded plans. Commands belong in [TOOLS](docs/TOOLS.md), controls in [FIRST-LAUNCH](docs/FIRST-LAUNCH.md), and aircraft authoring in [AIRCRAFT_CONTRACT](docs/AIRCRAFT_CONTRACT.md). For `AGENTS.md`, `CLAUDE.md` and scoped instructions, follow the [instruction-file conventions](docs/DOCUMENTATION.md#agent-instruction-files).

## Releases

`app/export.sh` builds Windows, Linux and macOS packages, runs a trimmed-flight smoke test on the exported Linux binary, and checks packaged resources and metadata. CI exports on `main`, `v*` tags and manual dispatch; only `v*` tags publish releases. Numeric `vX.Y.Z` tags publish stable releases; suffixed tags such as `vX.Y.Z-rc.N` publish prereleases using `docs/releases/<tag>.md`. Release tags identify the tested code and must stay fixed. See [release commands and sequence](docs/TOOLS.md#release-sequence).
