# Artwork variants and preparation for the decal Workshop

**AE-24e-00 · R2 · 2026-11-19, America/Bogota**

This follow-up turns the official-source investigation into asset choices and a
tested study capability contract. The [R2 receipt](../../../../research/aircraft-editor/sponsor-decals/logo-variant-intake-r2.json)
records 14 new artwork originals across six brands, one brand book and three
source archives. Retrieval occurred on 2026-11-20 UTC. The new binaries remain in
the separate owner/developer review package; the public research pack's original
12 files and byte lock are unchanged. No production Godot code is modified.

## Choose a source deliberately

| Brand | New material | Choice and remaining work |
| --- | --- | --- |
| SAVOX | Four transparent 4167 × 1417 PNGs: dark-background, black, orange and white; RGB/CMYK PDF and Illustrator masters with five pages each; brand book | Choose an actual supplied variant. The existing light-background PNG matches the archive and was not extracted again. Review the source discrepancies below before selecting a master/page |
| KONTRONIK | Red and black EPS originals from the manufacturer's two ZIP downloads | These are scalable print masters. Keep the previous official screen PNGs for the screen treatment unless another preparation is established. EPS is an authoring input, not a player-import/runtime texture format |
| REVOC | One-page vector PDF | Useful master alongside the existing 2000 × 420 PNG. Its page has substantial vertical margins; page size is not the visible mark's size. Record any reviewed derivative's canvas and padding |
| FEETECH | Direct manufacturer-domain transparent color PNG, 600 × 200 | Stronger raster source than the small bitmap embedded in the white wiki SVG. A true vector original remains unverified |
| ProModeler | Transparent 512 × 512 seal with stylized P | The manufacturer site cross-links the site hosting the full-size source. This closes icon coverage; it is not a standalone wordmark and does not spell the company name. Keep the name in the catalog label/credit |
| Leomotion Drives | Transparent 64 × 64 icon | Optional small UI variant. Keep the larger previous wordmark for a larger treatment; do not upscale this favicon and describe it as a higher-quality master |

The manufacturer download pages are [SAVOX](https://www.teamsavox.com/download/),
[KONTRONIK](https://kontronik.com/en/downloads) and
[REVOC](https://shop.revoc.eu/download). FEETECH's
[exact header](https://www.feetechrc.com/Data/feetechrc/template/en/images/logo.png)
is on the manufacturer domain. ProModeler's
[cross-link](https://www.promodeler.com/profiles/NPL-ProModeler-and-steering-lasers)
leads to its matching founder-authored article; the linked site's
[public media record](https://jbeech.com/wp-json/wp/v2/media/416) lists the full
512-pixel seal URL. This is documented provenance, not independent domain-ownership
proof or a project-specific artwork license.

JETI's mobile logo and SonicModell's current header match the existing bytes.
The GEMFAN shop response has different encoded bytes but identical decoded pixels
to the earlier source, so it was not retained as another artwork variant.
Hiwonder's earlier path-only header SVG remains the preferred source found.
The [receipt](../../../../research/aircraft-editor/sponsor-decals/logo-variant-intake-r2.json)
preserves these negative/deduplication results so the next developer need not
repeat the same searches.

### Source disagreements that affect preparation

SAVOX's [brand book](https://www.teamsavox.com/TeamSavox-Brandbook.pdf) depicts filled
letterforms, while its linked logo archive depicts outlined forms. Some gray
swatch RGB and hex values disagree. Retain the selected revision and obtain a
specific treatment; do not redraw the package to resemble the book. Inspection
also found different background rendering on the dark/white pages of the AI and
PDF masters. Prefer the matching supplied transparent PNG when it satisfies the
intended quality, and review the exact master/page/renderer for any derivative.

Leomotion GmbH's storefront vector was deliberately excluded as a Drives AG
variant. The [manufacturer announcement](https://download.leomotion.com/LeomotionNewOwnership.pdf)
documents separate entities and a production/distribution relationship. That is
not a sufficient reason to substitute one entity's mark for the other.

## Source-to-runtime preparation contract

1. **Select identity first.** Record brand, stable variant ID, original hash,
   source URL, source archive hash/member where applicable, and the precise
   approved treatment. Preserve the original separately from derivatives.
2. **Inspect actual content.** A `.svg` can wrap a bitmap; an EPS can contain a
   low-resolution preview in addition to vector artwork. A transparent PNG can
   include large intentional margins. Identify the actual artwork, canvas,
   source color space and background; do not infer these from the suffix.
3. **Prepare offline.** Treat AI, EPS and PDF as authoring inputs. Record converter
   name/version, selected page/artboard, color conversion, output canvas,
   aspect-preserving fit, retained clear space and output hash. Use the approved
   variant for the background instead of automatically recoloring a mark.
4. **Choose bounded runtime resolution.** Retain a high-quality source without
   loading every original at full resolution. Choose runtime tiers using actual
   output pixels, camera range and readability, then check near/far views at the
   repository's primary display targets. Repeated instances should share admitted
   image data; sixty-four copies do not require sixty-four decoded source images.
5. **Review alpha and filtering.** Compare the prepared image on light/dark and
   representative paint backgrounds, including small sizes and oblique views.
   Record any alpha-edge preparation as a derivative operation. Preserve the
   renderer's expected straight/premultiplied-alpha convention; do not apply a
   color conversion to alpha. Test required mip/filter behavior on the pinned
   engine and renderer.
6. **Admit and reproduce.** Fill the existing source catalog fields only after
   distributable bytes and scope are established, regenerate the pack, verify
   hashes and capabilities, and review the generated source lock. Never replace
   a saved asset merely because a live URL changed.

Godot's [image-import documentation](https://docs.godotengine.org/en/stable/tutorials/assets_pipeline/importing_images.html)
describes SVG rasterization and limited SVG feature support, including the need
to convert text to paths. The SVG [viewport specification](https://www.w3.org/TR/SVG2/coords.html#ViewBoxAttribute)
distinguishes user-space coordinates from output pixels. Hiwonder's
`0 0 472.07 57.14` viewBox is therefore an aspect/coordinate definition, not a
fractional pixel texture. Its current source lacks the integer width/height
attributes required by this pack's header reader. A separately recorded PNG
derivative is a viable preparation path; changing that reader alone would not
qualify SVG filters or native decoding. No derivative is generated in this pass.

Godot's [Image API](https://docs.godotengine.org/en/stable/classes/class_image.html)
documents image data and mip/alpha operations. These references inform the
pipeline; they do not establish behavior on this repository's pinned
`4.8.beta2.official.cafc17a19` build. Native acceptance remains in
[validation](validation.md).

### The new masters change the memory calculation

The table below is arithmetic for hypothetical **uncompressed RGBA8** storage,
with each mip dimension halved using integer division and clamped to one until
1 × 1. It is not measured VRAM, an assertion of the imported format, or a quality
recommendation. Alignment, uploads, retained revisions and other resources are
excluded.

| Source canvas | Base RGBA8 bytes | Full mip payload bytes |
| --- | ---: | ---: |
| SAVOX 4167 × 1417 | 23,618,556 | 31,481,768 |
| RadioLink 2754 × 434 | 4,780,944 | 6,372,104 |
| GEMFAN 1807 × 462 | 3,339,336 | 4,449,144 |
| FEETECH 600 × 200 | 480,000 | 639,844 |
| ProModeler seal 512 × 512 | 1,048,576 | 1,398,100 |

One full-resolution SAVOX source would consume most of the proposed 32 MiB
aggregate feature target in this hypothetical format. Its small PNG file size
does not remove that decoded cost. Keep originals in the authoring pipeline and
measure a bounded shared runtime set instead of preloading every supplied variant.

## Implemented study capabilities

The source and generated catalogs now require an exact five-boolean
`study_capabilities` object. The placement gate remains separate. All seventeen
external references retain disabled placement and false capabilities; the four
project/test entries retain every operation. These fields are local study
configuration, not a license record, authentication system or production policy.

| Capability | Implemented behavior |
| --- | --- |
| `rotate` | Disables the angle control and rejects nonzero rotations in edit transactions and restored drafts |
| `flip_x` / `flip_y` | Independently control horizontal/vertical artwork mirroring; direct event calls also pass the transaction check |
| `repeat` | Allows multiple instances of the same asset ID. If false, add/duplicate and restored second instances are rejected; hidden copies still count |
| `export` | Checks every layer before creating an export, including hidden and locked layers. No partial export silently drops a restricted layer. Local editing and draft storage remain available |

Movement and proportional resizing remain part of admitted placement in this
study. Aircraft restrictions, recolor, prescribed angle/size ranges, per-brand
cross-variant repetition limits, credit generation and portable image payloads
are future production contract work. Do not map a narrower permission onto an
unsupported capability. The study export still contains IDs/transforms rather
than an `.orskin` or a simulator-compatible bundle.

The visible controls explain unavailable operations without showing legal or
implementation administration. Search, deletion and Undo/Redo retain the correct
one-copy/export state. A centralized transaction check protects against disabled
controls being fired directly, rather than relying on button state alone.

### Draft preservation

The study now uses [strict-draft-json.js](../../../../research/aircraft-editor/sponsor-decals/strict-draft-json.js),
a bounded JavaScript port of the grammar-guard approach in the existing
[`StrictJSON`](../../../../app/workshop/strict_json.gd). It checks duplicate decoded
keys, syntax, finite numbers, Unicode surrogates, a 65,536-byte UTF-8 bound,
32-level depth and 20,000 value nodes before native decoding. A supplemental
underflow check rejects a nonzero numeric token that would become zero; genuine
zero with an exponent remains valid. The Python proposal reader has the matching
underflow check. This is not a claim of full cross-language parser equivalence.

Invalid, ambiguous or policy-incompatible drafts retain their exact original
local-storage text, display no silently normalized layers, and pause editing and
export. A missing helper also pauses an empty board rather than creating drafts
that cannot reload. The production Godot parser is unchanged and remains the
integration authority.

## Next implementation work

- **AE-24e-01/05:** exercise the chosen projection/rendering path with original
  asymmetric fixture artwork, then with the exact admitted brand variants. Verify
  readable opposite-side placement without turning text into a mirror image.
- **AE-24e-02/03:** bind production capability decisions and variant identities to
  the trusted catalog and saved visual identity. Revalidate old drafts against
  changed or withdrawn availability while preserving their recovery bytes.
- **AE-24e-04:** port the demonstrated independent controls into the existing
  Workshop history/input flow; retain repeat, hidden-layer and search semantics.
- **AE-24e-07/09:** complete image preparation, exact distributable payloads,
  credits and required previews. Source access alone does not activate a mark.

The focused checks and remaining native/browser limits are recorded in
[validation](validation.md#r2-variant-and-capability-verification--2026-11-19).
