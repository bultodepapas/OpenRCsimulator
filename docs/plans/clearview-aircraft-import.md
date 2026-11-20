# ClearView importer completion plan

**Updated:** 2026-11-20, revision 3. **Status:** ClearView importer v1 closed. Every aircraft root of both corpora (214) imports and test-flies: airplanes and VTOLs on an automatic estimated configuration, elevon flying wings on the stock X8 physics, helicopters on the stock X-Cell .60 physics, and the few the estimate cannot represent on the stock electric trainer physics. Saved-aircraft flight from Home, portable bundles and packaged-target qualification are Creator gates that ClearView inherits. **Owner:** Aircraft Creator / Workshop. **Step IDs:** AC-CV-00…14.

This plan owns ClearView-specific work. The [Creator plan](aircraft-creator.md) owns the shared gates (AC-12 numerical qualification, AC-18 Home, AC-19 bundles, AC-20 release evidence). [Dated research](../research/aircraft-creator/clearview-2026-11-15.md#closeout-every-corpus-aircraft-flies-ac-cv-2026-11-20) owns findings and receipts; the [2026-11-17 closeout plan](../research/aircraft-creator/import-closeout-2026-11-17/closeout-plan.md) keeps the packet history of the automatic setup and donors. Design decisions live in [DECISIONS](../DECISIONS.md#ac-cv-v1-parity).

## 1. Review of revision 1

Revision 1 (branch `docs/clearview-import-guide`, 2026-11-19) defined seven gates and a nine-box checklist. Its trust boundaries, evidence rules and refusal of invented geometry were sound and are kept. Four problems made it unclosable or misdirected:

| Finding | Evidence | Change |
| --- | --- | --- |
| v1 depended on generic Creator gates with no date | AC-12/G05 failed every registered campaign: 60/68, 64/68, 58/68 plus two unresolved, and partial studies ([campaign record](../research/aircraft-creator/AC-12-servo-arrivals-2026-11-16.md)). It blocks published flight for **every** Creator aircraft. Home (AC-18), bundles (AC-19) and packaged release (AC-20) are also shared | ClearView v1 closes on its own scope. It inherits the shared gates when they close; it does not wait for them |
| ClearView was refused what STL/GLB already had | `compiler.gd` strips `source_observations`/`source_installation` before emitting physics. A confirmed ClearView aircraft compiles to the same bytes as an STL/GLB aircraft with the same values (`test_creator_source_installation.gd`: "choice changes definition identity without changing physical bytes"). Yet ClearView was refused the experimental test flight and **Save aircraft** that STL/GLB have | Parity: once the configuration is confirmed, ClearView follows the ordinary Creator gates |
| The real player blocker was input coverage | 10 of 25 real models from 6 downloads were refused, all for fixable reasons: JPEG metadata segments (4), GIF propeller-disk textures (3), self-intersecting or coincident-corner polygons (2), a `$` editor tag line (1) | Fixed. 25/25 now convert (section 4) |
| Original-ZIP storage as a separate blob | 64 MiB of third-party bytes per model in the library and in bundles creates rights and quota exposure for no player benefit. The GLB receipt already keeps archive/member SHA-256, parameter bytes, materials and markers | Dropped from v1. The receipt is the provenance. Players keep their own ZIP, and the guide tells them to |

## 2. v1 delivery contract

A player can do all of the following in the normal UI:

1. Select a local ClearView ZIP, and pick one aircraft when it is a pack.
2. See the original appearance and a concise report of omissions.
3. Choose **Set up for flight automatically**. It takes the ClearView frame (metres, nose −X, up +Y), estimates the wing leading edge, planform and size class, fills every empty value with labelled estimates and declares the independent OpenRC configuration. A helicopter offers **Fly as a helicopter** instead; an elevon flying wing offers the stock X8 physics; a model the estimate cannot fly offers the stock electric trainer physics, with the reason.
4. Review the estimates, orientation, size, datum and moving parts; anything the player set is kept.
5. Test-fly it (Airborne or Hand-launch, labelled experimental).
6. Save it as a draft or an aircraft revision, then reopen it from the library.

| Area | Requirement |
| --- | --- |
| Input | Bounded airplane and helicopter ZIPs, flat parameter dialects v0–v5 or sectioned v6 (pre-v5 files without `modelName` use `data/body.ac`): 64 MiB ZIP, 256 MiB expansion, 32 MiB per member, 4,096 entries, 64 model roots. AC3Db visual. Textures: PNG; baseline JPEG, with APPn metadata skipped and Adobe encoder flags ignored; the first GIF frame; 24-bit BMP, up to 3 trailing alignment bytes. A missing texture is replaced by the one same-named image in the same folder, with a warning. An absolute path to the author's PC is looked up by file name in the model folder; if absent, those parts keep their plain colour, with a warning. JPEG luma sampling 4:4:4, 4:2:2 and 4:2:0 |
| Geometry | Correct concave triangulation. Coincident consecutive corners collapse. Ears that collapse at render precision with negligible source area (below extent² × 10⁻⁹) are dropped. Up to 16 self-intersecting or exactly cancelling surfaces are omitted and reported; more refuse the model. Never a triangle fan. Float32 vertex rounding is accepted up to 10⁻⁴ of the part's size or 1 µm; corners that project to one render point collapse; a visible triangle that flips still refuses. A model whose emitted meshes exceed the 128-mesh limit is converted again with static leaf parts merged per parent (transforms baked in float64, dotted group parts kept separate), with a warning. `subdiv` parts show their unsmoothed control shape, with a warning |
| Markers | `.XYZObject` helpers that cannot be read unambiguously are hidden and recorded; their moving parts are bound manually. Point/line helpers are not held to render precision |
| Helicopters | ClearView `modelType 0` (tagged `openrc_clearview_rotorcraft`) test-flies on the stock X-Cell .60 helicopter physics with its own appearance, sitting on the donor's skids; a model whose rotor differs from the donor's by more than 1.5× is shown scaled to it, and the HUD says so. Disc and blade parts switch with rotor speed. No fixed-wing configuration or aircraft revision; drafts save |
| Flight | Only OpenRC physics flies. Airplanes and VTOLs: the confirmed estimated configuration (size classes 0.7–1.45 m park flyer with 3S, 1.45–2.2 m trainer with 4S; models without a propeller as pusher park jets). Donors: elevon flying wings on the stock MoonRunner X99 (Skywalker X8); helicopters on the X-Cell .60; any other model whose estimate cannot compile (autogyro, airship, tail-sitter, multirotor, out-of-range balance) on the stock Ugly Stick electric 6S, airborne start. A donor flies its own mass, size and power, labelled in the confirmation. ClearView physics are never adopted |
| Saving | Drafts and aircraft revisions carry the v3 definition with its source-bound configuration. The store refuses a configuration that names another model |
| Language | All new app strings are in the eight app catalogs; the guide is in all eleven website languages |

**Outside v1:** ClearView flight-model adoption, runway starts and gear, glow/gasoline, moving elevons and rotors on donor flights, multi-engine, a helicopter or multirotor flight package of their own size, scenery, ClearView sounds/scripts, and original-ZIP storage. AC-CV-10…13 keep the future aircraft families.

## 3. Unchanged boundaries

- Read captured bytes only. Never extract arbitrary paths, fetch URLs, execute source settings or search the host for files.
- The kernel, `app/physics`, `app/sim`, AC-12 rules, tolerances and the 68-cell matrix are unchanged.
- The v4 compiled-publication path (`compiled_publication.capture`), the source resolver and `published_trial.prepare` keep their ClearView refusals. Published flight is closed for every Creator aircraft (`published_trial.check_start`). Opening it belongs to AC-12/AC-18, and ClearView must then pass the same admission as other sources, nothing less.
- Recognition is a workflow boundary, not origin authentication.

## 4. Status

| Step | Status and evidence |
| --- | --- |
| AC-CV-00 | **Done.** Corpus: 6 archives / 25 model roots ([check record](../research/aircraft-creator/clearview-guide-checks-2026-11-19.json), rerun 2026-11-19). Third-party ZIPs stay outside Git; CI uses synthetic fixtures |
| AC-CV-01 | **Done.** Bounded archive and parameter readers; `$` tag lines are ignored and reported |
| AC-CV-02/03 | **Done for both corpora.** Reference set 25/25; owner download set 189/191. The two refusals are landscape packs with no aircraft. Textured AC3D emission is modulated by its texture, so liveries keep their colours. Follow-ups: real AC3D subdivision smoothing, JPEGs with EXIF before JFIF, an independent Blender/Assimp fidelity comparison |
| AC-CV-04 | **Partial.** v6 hinge proposals plus manual bindings. v5 and propeller proposals are still manual |
| AC-CV-05 | **Done.** Source report, one-click automatic setup or explicit configuration, v3 definitions saved and reopened |
| AC-CV-06 | **Done.** All 214 corpus aircraft test-fly: 149 on the estimated configuration, 10 flying wings on the X8, 49 helicopters on the X-Cell .60 and 6 on the trainer fallback ([evidence](../research/aircraft-creator/clearview-2026-11-15.md#closeout-every-corpus-aircraft-flies-ac-cv-2026-11-20)). Saved-aircraft flight follows AC-12 |
| AC-CV-07/08 | **Save/reopen done.** Home launch, restart-to-fly and `.orcaircraft` bundles follow AC-18/AC-19 |
| AC-CV-09 | **Inherited.** Packaged Windows/Linux/macOS evidence follows AC-20; include one ClearView model in that journey |
| AC-CV-10…13 | **Deferred**, outside v1 |
| AC-CV-14 | **Done.** Guide and website in eleven languages: automatic setup, helicopter and donor flights, next-build note |

## 5. Hooks for the inherited gates

When a shared gate closes, the owner of that gate makes these ClearView changes in the same change:

- **AC-12 / published flight.** Remove the ClearView refusals in `source_resolver.gd`, `published_trial.gd` and `compiled_publication.capture`. Add the installation check that `trial.gd` and the store already apply, and test a saved ClearView revision end to end.
- **AC-19 bundles.** Carry the v3 definition with its configuration and the GLB receipt. Do not bundle original ZIPs.
- **AC-20 release.** Run one corpus model, with its permission confirmed, through the packaged journey on each target.

Verification for this revision is recorded in the [dated research](../research/aircraft-creator/clearview-2026-11-15.md#importer-v1-coverage-and-parity-ac-cv-2026-11-19).
