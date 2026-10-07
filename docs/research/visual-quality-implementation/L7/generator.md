# L7 · Deterministic visual hill profile

Date: 2026-10-07. **Status: partial L13a visual-only slice, integrated into the L7 ring.** This adds the offline profile generator and its committed output; it does not implement the runtime ring, full L13a terrain, collision, or physical height sampling.

## Output

`app/data/fields/horizon.json` contains an `openrc-horizon-profile v1` radial-major grid with 25 rows × 1,440 periodic azimuth samples. Radius runs from 1,500 m to 6,000 m in 187.5 m steps; heights are signed int16 values in 1/256 m. The first and last rows are exactly zero. Runtime can append a zero outer row to 20 km. Azimuth zero is north, increasing clockwise; geometry trig remains a runtime concern.

The current byte-level height payload SHA-256 is `401309462ff3172b4e1a6c7878a29b02cc7b1dddfe4ac366e06b28bc1c2146fe`. The 25 × 1,440 grid and radii are unchanged from the first shape; maximum height remains 25,868 q (101.046875 m). The envelope now fades from zero at 1.5 km to full height at 3 km, then fades to zero from 5–6 km. At sampled full-height 3–5 km radii and outside the east/west corridor feathers, heights span 11,404–25,868 q (44.546875–101.046875 m), within the 30–120 m target. East and west each have a 20° flat half-width plus a 15° integer-smoothstep feather. These are design estimates intended to leave the optional scenery landmarks at about N 690 m/E 3,980 m and 2,100 m west readable; they are not survey data.

## Silhouette readback

Computed from vertex heights at a 1.7 m eye point: for each of 321 azimuth samples spanning north ±40° (inclusive), take the highest `atan((height - 1.7 m) / radius)` over the radial rows. The final column converts the angular span to pixels at 720p and 50° vertical FOV.

| Profile | Mean angle | Standard deviation | Angular span | Span at 50° FOV |
| --- | ---: | ---: | ---: | ---: |
| Original, full height at 2 km (`e17cc…`) | 1.834° | 0.095° | 0.437° | 6.3 px |
| Revised, full height at 3 km (`401309…`) | 1.480° | 0.212° | 0.646° | 9.3 px |

This profile readback lowers the average northern skyline and increases its angular variation. It supports the visual change but is not a rendered-pixel or human-readability test.

The generator uses only Python stdlib integer arithmetic: `lowbias32` periodic value noise, Q16 integer smoothstep, and symmetric quantization. The output stores the seed, radii, octaves, radial masks, corridor parameters, units, and source/licence notes. It creates no terrain outside the visual horizon profile.

## Reproduction and proof

From the repository root:

```sh
python3 tools/terrain/gen_terrain.py
python3 tools/terrain/gen_terrain.py --check
```

The second command passed and compared the complete generated JSON byte-for-byte. A scratch copy with one height changed was checked with `--check --output <temporary-path>`; the command rejected it with exit code 1. The repository file was not mutated by that negative check.

Detailed output and mutation-check instructions are in [`tools/terrain/README.md`](../../../../tools/terrain/README.md). The runtime ring and its crack/capture checks remain separate L7 work.
