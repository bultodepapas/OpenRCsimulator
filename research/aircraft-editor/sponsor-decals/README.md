# Sponsor decal Workshop handoff assets

**AE-24e-00 · 2026-11-18 · research tools, not production integration.**

Start with the [implementation plan](../../../docs/plans/sponsor-decal-workshop.md)
and [dated audit](../../../docs/research/aircraft-editor/AE-24e-00/README.md).
The [2026-11-19 research expansion](../../../docs/research/aircraft-editor/AE-24e-00-R1/README.md)
adds 60 sequential investigations and the executable exercises below; the source
image pack and flat study retain their original scope.

## Review the interaction

Open `workshop-preview.html` directly in a browser after cloning this branch.
It uses this directory's `catalog.js`, `strict-draft-json.js` and `assets/`; no server, account,
external request or simulator changes are needed. The flat aircraft board
demonstrates repeated placement, movement, scale, rotation, explicit flips,
layers, Undo/Redo and a local draft. It does **not** demonstrate 3D projection,
Godot integration, a real aircraft's geometry or simulator save compatibility.

The eight external logos are **reference cards**. Their original bytes are
included for the sourced handoff; none is represented as an unrestricted player
decal. OpenRC's own mark and three original geometric test decals exercise the
editor controls now. The [scope register](../../../docs/research/aircraft-editor/AE-24e-00/sponsor-register.md)
records the remaining work for every organization.

The **2026-11-19 logo intake** expands the catalog to 17 external organizations
and records exact official source candidates in [logo-source-intake.json](logo-source-intake.json).
ProModeler, FEETECH and Hiwonder are additional source candidates, not new public
claims of sponsorship. Newly retrieved art remains outside the public pack until
its intended use and distribution are established. The 12 existing image files
and their byte lock are unchanged. The source register gives quality notes and
the concrete promotion steps for the maintainer.

The **R2 variant pass** adds [14 new artwork-source receipts](logo-variant-intake-r2.json)
across six brands, a brand book and three source archives. The separate review
package supplies the unchanged originals. A verified ProModeler seal closes icon
coverage and a direct FEETECH color PNG improves that source; a ProModeler wordmark
and FEETECH vector master remain unresolved. Read the
[preparation and variant guide](../../../docs/research/aircraft-editor/AE-24e-00/artwork-preparation.md)
for source disagreements, master-to-texture decisions and memory calculations.

The study now enforces five explicit capabilities per asset: rotation, horizontal
and vertical mirroring, repeated placement and export. Missing or malformed
capabilities disable that entry. All external entries remain references. Local
editing/storage can remain available when export is unavailable; hidden layers
still count for repeat and export checks. The strict draft reader preserves
ambiguous or incompatible original text and pauses editing instead of repairing
it silently. Keep all study files together when opening or sharing the folder.

## Reproduce and check

From the repository root, with Python 3.11+ and Node 18+:

```sh
python research/aircraft-editor/sponsor-decals/build_catalog.py --check
python research/aircraft-editor/sponsor-decals/validate_pack.py --self-test
node research/aircraft-editor/sponsor-decals/check_study.cjs
node research/aircraft-editor/sponsor-decals/check_strict_draft_json.cjs
python research/aircraft-editor/sponsor-decals/check_capabilities.py
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
| `logo-source-intake.json` | Public source URLs and technical receipts for newly located artwork; not a permission or asset-distribution manifest |
| `logo-variant-intake-r2.json` | Follow-up vector/color/icon source receipts and source-identity caveats; no additional image binaries |
| `assets/` | Exact official reference originals and named test SVGs, outside `app/` |
| `asset-lock.json` | Reproducible byte counts, dimensions, source and packaged SHA-256 |
| `catalog.js` | Generated local data for the interaction study |
| `strict-draft-json.js` | Bounded grammar guard for exact draft recovery; study port of the existing Godot approach |
| `check_strict_draft_json.cjs` | Duplicate-key, Unicode, numeric and resource-boundary checks for that reader |
| `check_capabilities.py` | Synthetic policy checks against the actual builder and proposal validator |
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
