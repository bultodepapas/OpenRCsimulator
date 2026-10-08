# Contributing to OpenRC Simulator

Start with a small, reproducible improvement. The simulator lives in `app/`; `prototypes/stage0/three/` is an archived experiment. [README.md](README.md) covers installation, and [AGENTS.md](AGENTS.md) defines the repository's development rules.

## Help as a pilot

Use a [published test build](https://github.com/bultodepapas/OpenRCsimulator/releases) and include its version, aircraft, operating system and controller when [opening an issue](https://github.com/bultodepapas/OpenRCsimulator/issues/new/choose).

For handling feedback, describe the maneuver, speed if known, stick input, expected response and actual response. Identify the real RC aircraft you are comparing against. A flight trace recorded with **T** helps reproduce the observation. For visibility feedback, include a screenshot, resolution and whether auto-zoom (**Z**) was enabled. The [first-launch guide](docs/FIRST-LAUNCH.md) explains frame-time reports.

## Make a change

1. Read the relevant step in [ROADMAP.md](ROADMAP.md) or the linked implementation plan. Use an issue to discuss large changes before investing in them.
2. Work on a branch and keep the change focused. Preserve other developers' in-progress work; only stage files belonging to your change.
3. Run the checks relevant to the change. For Godot code, run `app/test.sh`; for rendering changes, also run `app/capture.sh` and inspect the images. Changes to paths, ignore rules or generated outputs need verification from a fresh clone.
4. Record any new reusable lesson using [LEARNINGS.md's criteria](LEARNINGS.md#keeping-this-useful), and include the applicable plan step and proof in the commit or pull request: test, capture, trace or measurement.
5. Open a pull request explaining the problem, resulting behavior and validation. State any pending manual checks, especially real-radio, GPU or native-platform testing.

Documentation-only changes need link and content checks; they do not require rerunning the flight simulation.

## Preserve the simulation contract

- Keep simulation state in 64-bit GDScript `float`s. Do not use `Vector3`, `Basis`, `Quaternion` or `Transform3D` for state in `sim/` or `physics/`; rendering converts at the boundary.
- Aircraft parameters live in `app/data/aircraft/*.json`. Each value carries a unit, evidence kind and source. Label estimates; never present a guess as a measurement.
- Regenerate generated geometry and physics data through their source scripts. Do not hand-edit generated files. [AGENTS.md](AGENTS.md) identifies the relevant tracks and ownership boundaries.
- Preserve aircraft node names and control-surface hinge interfaces. Re-record golden flights only for an intentional, explained physics change.
- Do not leave broken scripts in `app/`: the test runner parses every script. Keep drafts outside the app until ready to validate.

## Assets and research

Record useful research in `docs/`, with original sources, limitations and a reproducible experiment when practical. Pin dependency versions. Include license, provenance and processing steps for any third-party asset; a free download alone does not establish redistribution rights. Keep reference scans with unclear redistribution rights out of commits.

## Documentation

Start at the [documentation map](docs/README.md): it names the canonical document for each question, lists every track, plan and step-ID prefix with the paths each owns, and states the writing conventions. In short: English, short and precise, one language per file; every plan carries a date, revision, status line and step-ID prefix; a step's status lives in its plan and ROADMAP.md keeps one line per track; evidence folders are named after the step they prove; never link the gitignored `references/` or `app/captures/` folders as if they were in the repository. Research reports go under `docs/research/` and are listed in its [index](docs/research/README.md).

## Releases

`app/export.sh` builds and smoke-tests packages for all three platforms. CI exports `main` and `v*` tags; a `v*` tag also publishes a GitHub prerelease using `docs/releases/<tag>.md`. Release tags identify the tested code and must stay fixed. Later documentation improvements belong in a new commit.
