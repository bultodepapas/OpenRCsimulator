# Poly Haven source license and provenance

Poly Haven states that all assets on its site are released under CC0 1.0. The two source assets in this intake are Fern 02 and Flower Empodium.

- Fern 02: https://polyhaven.com/a/fern_02
  - Modeling: Rico Cilliers; scanning: Rob Tuytel.
  - API metadata snapshot: `fern_02/polyhaven_info.json`.
- Flower Empodium: https://polyhaven.com/a/flower_empodium
  - API metadata snapshot: `flower_empodium/polyhaven_info.json`.
- Poly Haven asset license statement: https://polyhaven.com/license
- CC0 1.0 legal code copied from: https://creativecommons.org/publicdomain/zero/1.0/legalcode.en
- Accessed: 2026-10-20.

Attribution is not required under CC0; provenance is retained here for review. Supplier glTFs, buffers, color/normal/ARM maps, and separate 16-bit alpha maps are retained unchanged. The staged candidates extract one complete supplied mesh node each, preserve its mesh primitives, accessor references, positions, normals and UVs, and remove only its side-by-side gallery translation. Conversion mechanically packs the supplied grayscale alpha samples into an RGBA8 copy of the original diffuse JPEG; each 16-bit sample is rounded linearly to 8-bit. No resampling or color editing is performed.

The Fern candidate keeps its supplied MASK mode and 0.5 cutoff. Flower Empodium is staged with MASK at 0.5 instead of the supplier's BLEND mode to assess foliage alpha scissor for a bounded runtime candidate. This deliberate material adaptation thresholds fractional coverage and needs later rendered review before runtime use. The supplier files and their original BLEND material remain intact.
