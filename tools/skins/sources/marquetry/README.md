# Marquetería Real authoring sources

Downloaded 2026-11-14; exact URLs and SHA-256 hashes are in `sources.json`.

- `Cinzel-wght.ttf`: Cinzel (variable, Bold instance used) by the Cinzel Project
  Authors, Google Fonts commit `d50a0d29b`, unmodified. SIL Open Font License 1.1,
  reproduced in `OFL-Cinzel.txt`. Used only to bake the inlaid numerals.
- Wood veneers: ambientCG 1K-JPG `Color` and `Displacement` maps, CC0 1.0
  (<https://docs.ambientcg.com/license/>), unmodified:
  Wood066 walnut, Wood028 ebony, Wood022 maple, Wood023 satinwood,
  Wood029 knotty cherry, Wood026 mahogany, Wood069 padauk. The species names
  are art-direction roles, not botanical identifications.

The photographs are not committed. `../../build_vehicle_paints.py` reads them from
the ignored cache `.tools/skin-sources/marquetry/`; when a member is missing or its
hash differs, it downloads that asset's archive from ambientCG once and verifies
each member against `sources.json` before use.

Leaf layout, book-matching, stringing, cross-banding, the compass-rose medallions
and the brass fittings are authored by the generator. The design is original.
