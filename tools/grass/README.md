# L11a grass placement

`place.py` generates the committed `app/data/fields/grass.json` disk of 6,000 pilot-relative clump offsets. The disk is universal: the renderer clips it to the actual rough field and removes centers inside every runway or mown rectangle expanded by 0.4 m.

Rows are `[north_mm, east_mm, yaw_u16, size_u8]`. All four values are integers. Yaw is one unsigned turn fraction; size maps linearly from 0.75 to 1.25 in the renderer. The row digest is SHA-256 over ASCII lines `north,east,yaw,size\n` in stored order.

The PRNG is SplitMix64 with unbiased integer range sampling. Integer-disk rejection plus `isqrt` supplies directions; another integer rejection sampler gives a capped radial density. For radii above the estimated 3 m center cap, expected clump count per metre is constant, corresponding to spatial density proportional to 1/r. Within the cap, spatial density is constant and finite. Coordinates are rounded symmetrically to millimetres, and duplicate centers are rejected.

The 6,000-clump count is an estimate based on the 6,000-clump rendering spike in [grass investigation 05](../../docs/research/landscape-investigations/05-grass-rendering.md). The 30 m extent comes from that investigation's L11 recommendation. The study asks for 1/r density but does not define a center cap; 3 m is an explicit implementation estimate. This layout is visual and unsurveyed. It does not encode field boundaries, runway/mown exclusions, collision, or terrain.

```sh
python3 tools/grass/place.py
python3 tools/grass/place.py --check
python3 tools/grass/test_place.py
```

`--check` regenerates and compares the exact canonical JSON bytes without writing. The tests cover count, disk bounds, unique centers, integer encoding, radial ring proportions, repeatability, digest integrity, the committed file, and mutation detection using a temporary copy.

## Render evidence

The guarded production A/B checks repeated bytes, the +5 draw / +100k primitive budget, wind/clock wrap and the existing SC-16 flower hook. Use a fresh output directory:

```sh
"$(app/tests/visual-env.sh)" tools/grass/check_grass.py \
  --app app --godot "$(app/get-godot.sh)" --out /tmp/l11a-grass
"$(app/tests/visual-env.sh)" tools/grass/check_grass_seam.py \
  --captures /tmp/l11a-grass/candidate-repeat-1 --out /tmp/l11a-grass/seam-summary.json --self-test
```

For initial L11a acceptance, add `--baseline-app /path/to/pre-L11a/app` to the first command; the retained acceptance run includes this exact grass-off parity check. Later regressions can run without the old checkout; a complete capture set alone is not a claim of legacy parity or human Gate L acceptance.

The second command evaluates the projected 25–35 m band in 1 m radial bins and eight screen strips. Every usable cell must keep mean absolute channel change within 3% and FLIP p99 within 0.1 (engineering estimates). A copied image with a 25 cm dark seam segment must fail. Source captures are never changed. The independent local check supplements the full-annulus average so a narrow seam cannot hide inside a large mask.
