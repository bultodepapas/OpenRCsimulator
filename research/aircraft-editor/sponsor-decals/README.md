# Sponsor decal Workshop handoff assets

**AE-24e-00 · 2026-11-18 · research tools, not production integration.**

Start with the [implementation plan](../../../docs/plans/sponsor-decal-workshop.md)
and [dated audit](../../../docs/research/aircraft-editor/AE-24e-00/README.md).
The [2026-11-19 research expansion](../../../docs/research/aircraft-editor/AE-24e-00-R1/README.md)
adds 60 sequential investigations and the executable exercises below; the source
image pack and flat study retain their original scope.

## Review the interaction

Open `workshop-preview.html` directly in a browser after cloning this branch.
It uses only this directory's `catalog.js` and `assets/`; no server, account,
external request or simulator changes are needed. The flat aircraft board
demonstrates repeated placement, movement, scale, rotation, explicit flips,
layers, Undo/Redo and a local draft. It does **not** demonstrate 3D projection,
Godot integration, a real aircraft's geometry or simulator save compatibility.

The eight external logos are **reference cards**. Their original bytes are
included for the sourced handoff; none is represented as an unrestricted player
decal. OpenRC's own mark and three original geometric test decals exercise the
editor controls now. The [scope register](../../../docs/research/aircraft-editor/AE-24e-00/sponsor-register.md)
records the remaining work for every organization.

## Reproduce and check

From the repository root, with Python 3.11+ and Node 18+:

```sh
python research/aircraft-editor/sponsor-decals/build_catalog.py --check
python research/aircraft-editor/sponsor-decals/validate_pack.py --self-test
node research/aircraft-editor/sponsor-decals/check_study.cjs
python research/aircraft-editor/sponsor-decals/projection_exercises.py --check
```

The builder uses the standard library. It copies existing official logo bytes
without cropping, recoloring, tracing, resampling or stripping transparency.
It verifies source hashes and generates `assets/`, `asset-lock.json`, and
`catalog.js`. Omit `--check` only when intentionally regenerating this pack.
Sources come from the checkout or the manifest's pinned Git commit; the builder
does not fetch websites. A clean full clone has all source files.

Schema validation uses the development-only dependency in `requirements.txt`.
If needed, install it in an isolated environment with
`python -m pip install -r research/aircraft-editor/sponsor-decals/requirements.txt`.
It validates illustrative stacks and negative cases; it is not a Godot runtime
validator. The receiver fixture is synthetic, not a claim of fleet support.

The Node check executes the study's actual JavaScript against a small
DOM/event/storage/image simulation. It covers editing transactions and recovery;
it does not test browser layout, real pointer capture, image decoding or downloads.
The [verification record](../../../docs/research/aircraft-editor/AE-24e-00/validation.md)
retains the blocked browser attempt and remaining native review.

| File | Purpose |
| --- | --- |
| `catalog.json` | Research source, relationship, scope, next action and demo availability |
| `assets/` | Exact official reference originals and named test SVGs, outside `app/` |
| `asset-lock.json` | Reproducible byte counts, dimensions, source and packaged SHA-256 |
| `catalog.js` | Generated local data for the interaction study |
| `schemas/decal-stack.schema.json` | Closed proposed 3D layer contract; not accepted by presentation v4 |
| `examples/` | Valid empty and layered proposals against `receiver-fixture.json` |
| `receiver-fixture.json` | Synthetic receiver bind-local bounds, model transforms and identity |
| `fixtures/` | Original MIT geometric artwork, unrelated to sponsor marks |
| `projection_exercises.py` | 37 stdlib-only synthetic clipping, normal, linear-alpha, exact-byte and owned-job cases; [recorded results](../../../docs/research/aircraft-editor/AE-24e-00-R1/exercise-results.json) |
| `check_study.cjs` | Reproducible nonbrowser event/state and exact draft-preservation checks |

The study's draft/export format is separate from `openrc-decal-stack-proposal`.
Neither is an `.orskin` file or a current Workshop variant bundle. The study
exports IDs and transforms without embedded brand images. Production portability,
rights admission and format migration are explicit steps in the plan.

## Attribution

Software and the three geometric fixture SVGs use the repository's MIT license.
Third-party marks retain their owners' rights and existing source records; this
directory creates no additional permission. OpenRC's own mark is reused from its
existing master. No private messages, contacts, addresses, shipment details or
mailbox IDs are included. Only the small source-card pack is duplicated; no
website screenshots, model archives or stock paint atlases are added.

The projection exercises use closed-form/rational expected cases and the declared
receiver UV convention. They include a zero-UV-area projection and unsafe shared
output as counterexamples. Passing them is not native Godot, GPU, browser,
threading/lifetime, real-aircraft geometry or performance qualification.
