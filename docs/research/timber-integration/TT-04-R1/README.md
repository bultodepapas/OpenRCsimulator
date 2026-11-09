# TT-04-R1 — mipmaps for script-bound foam and rubber

2026-11-09. Baseline `f47d1dc6cccb141936407d0217eafdc465558190`; official Godot `4.8.beta2.official.cafc17a19`, Windows, Compatibility, RTX 3090, NVIDIA 617.42. Native captures are 1920×1080; the project configures 4× MSAA. This is a bounded import correction within TT-04, not completion of that step. Commands and channel conventions live in the [aircraft guide](../../../../assets/aircraft/turbo-lumber-evolution/README.md).

## Finding and correction

Two supplied external text analyses, reviewed against commit `4667f1c`, recommended starting with texture filtering before adding material detail or new lighting systems. Inspection of the current build confirmed that the four script-bound foam/rubber textures had **zero mip levels**, although the actual stock materials use `TEXTURE_FILTER_LINEAR_WITH_MIPMAPS` (enum 3). The custom-paint shader also requests mip filtering. Runtime resource inspection confirms the saved-setting finding.

Only `mipmaps/generate=false → true` changes in the four production import descriptors. The pinned engine regenerated them in an isolated four-texture project before the app reimport. Source JPEGs, lossless compression, channel mapping, normal-Y direction, material strengths, local texture scale, geometry and physics stay the same. This follows the [earlier roof correction](../../visual-quality-implementation/VQ-02a/roof-mipmaps/README.md); [Godot's importer documentation](https://docs.godotengine.org/en/latest/classes/class_resourceimportertexture.html#class-resourceimportertexture-property-mipmaps-generate) explains the mipmap setting.

| Imported resources | Before | After |
| --- | --- | --- |
| Foam normal, foam roughness, rubber normal | RGB8, 1024², no mips | RGB8, 1024², 10 mips |
| Rubber roughness | L8, 1024², no mips | L8, 1024², 10 mips |
| Total decoded image bytes | 10,485,760 | 13,981,010 |
| Full-resolution decoded pixels | Decoded source pixels | Exactly identical |

The extra 3,495,250 bytes are decoded image data, not measured resident VRAM. A fresh isolated import and its exported PCK return exactly the same complete image-data hashes as the app. This checks these four resources through packing, not a full application/platform release.

## Paired rendered evidence

The existing inspector now supports a repeatable fixed-light camera pan and a solid-color custom-paint fixture. Each finish has 24 gear and 24 foam camera positions. Twelve further stock captures cover level, ±60° bank and nose-on views at 20/50/100 m. Both sides use the same inspector, builder, lighting and camera definitions; the production delta is the four import flags. The reducer verifies the declared metadata and image hashes, rather than independently discovering every source dependency.

[comparison.json](comparison.json) retains all 108 pairs' image hashes, changed-pixel counts and interior-region measurements. All pairs preserve their non-background silhouette support. Distance images change by at most two RGB8 channel levels over 1–69 pixels per image. Full-size images and magnified crops were inspected locally; no new image files are committed.

| Fixed surface interior, 24 positions | RGB8 second-difference RMS before | After | After / before |
| --- | ---: | ---: | ---: |
| Tire, stock and custom paint | 0.296167 | 0.185219 | 0.625386 |
| Foam, stock | 0.262467 | 0.262323 | 0.999450 |
| Foam, solid-color custom paint | 0.340862 | 0.299115 | 0.877525 |

The tire sample has less camera-pan variation; stock foam is effectively unchanged. These small, dark-pixel differences include legitimate shading and quantization. They do **not** establish perceptible in-flight shimmer reduction or physical material accuracy. The foam crop excludes the nearby moving marking edge. The paint fixture exercises the actual shader and shared foam maps with a color factor; it does not supply a player PNG.

## Verification and retained identity

[verification.json](verification.json) binds source, import, engine, external-analysis and checked-log hashes. Local raw artifacts are under ignored `tmp/texture-review-20261109/`; the committed comparison and this summary retain the results without adding screenshots to Git.

| Check | Result |
| --- | --- |
| Actual resource/mip/base-pixel and paint-map regression | 23 checks passed; the original resources failed all four mip guards |
| Procedural-paint compatibility | 3,458 checks passed |
| Custom-skin behavior | 47 checks passed |
| Timber fleet-paint integration and lifetime | 89 checks passed |
| Existing visual/control/wreck isolation | 164 checks passed |
| Modified GDScript parse checks | Passed |
| Detail generator, model manifests, Workshop descriptors | Current; no regeneration needed |
| Reducer malformed-input controls | Empty texture records, missing frame, wrong frame names and mismatched camera all rejected in disposable fixtures |
| Fresh import and isolated exported PCK | Four complete mip chains; app/PCK image hashes match |
| Full fleet-paint check | **525 checks, 3 failures**: electric Stik kit missing; Extra stock identity mismatch and rejected import |

The same three kit failures reproduce on a HEAD-code snapshot with the unchanged affected-family assets and existing import/native caches. That diagnostic shares those assets read-only; it is not a fresh complete baseline import. Timber's targeted suite passes. The broader failures remain open and are not hidden by the focused result. No full app/capture suite, whole-flight benchmark, renderer promotion or full release export was run for this localized correction. Concurrent flight-session and overlay edits appeared during final review; they were preserved and are outside this evidence's scope.

## Other supplied recommendations

The two text summaries, rather than their linked PDF, were available for this work. Their hashes are retained in `verification.json`. Their broader ideas remain useful hypotheses with separate acceptance work:

| Recommendation | Current disposition |
| --- | --- |
| Linear-light Stik color mips | Separate experiment: the reported sampled atlas boundary does not prove a visible wing defect. Preserve level zero and validate attitude/marking motion, then regenerate model and skin identities if adopted. |
| Normal-driven roughness filtering | Keep separate. Shared foam maps serve normal strengths 0.012–0.12; one unscaled correction cannot represent every material. The Stik also has deliberate amplified normal encoding. |
| New Workshop reflection setup | Use existing controlled inspectors and outdoor references first. A new probe needs bounded capture settling and exposure comparison; this patch adds no reflection work. |
| Aircraft cloud-light receiver | Requires a current cloud-edge reproduction and direct-light-only treatment, including custom/crash materials. No verified field mismatch is claimed here. |
| Foliage AA, lower-resolution clouds and extra GI | Require family/renderer-specific integration and attributed cost. Preserve wind-adapter admission and existing coverage behavior. |

TT-04, VQ-01c/d, ordinary-flight perception, Standard/High comparison and target-hardware frame-time gates remain open. The correction supplies valid mip levels and a reusable comparison fixture for that further work.
