# Terrain generation tools

`gen_terrain.py` generates the committed visual hill profile used by L7. This is a partial L13a delivery: it does not create the full terrain grid, near-field swales, runway masks, collision terrain, or physics data.

Run from the repository root:

```sh
python3 tools/terrain/gen_terrain.py
python3 tools/terrain/gen_terrain.py --check
```

The default output is `app/data/fields/horizon.json`. Pass `--output PATH` to write or check a scratch copy. `--check` regenerates the profile in memory and compares the complete JSON bytes, so edited data and stale generator output fail.

The `openrc-horizon-profile v1` file stores 25 radial-major rows and 1,440 unique azimuth samples per row. Radii run from 1,500 m to 6,000 m in 187.5 m steps; each signed integer is height in 1/256 m. Azimuth zero is north and increases clockwise. The azimuth is periodic without a duplicated seam column. Heights at both radial borders are zero. Runtime adds a zero-height outer row through 20 km and builds the ring geometry.

The generator uses only Python's standard library and integer arithmetic. `lowbias32` periodic value noise is interpolated with Q16 integer smoothstep. The SHA-256 covers the radial-major height values encoded as signed int16 little-endian; JSON provenance records the seed, scales, masks, quantization, and source. No NumPy or noise package is needed. Runtime may use trigonometry to place polar vertices; generation does not. The [terrain generation investigation](../../docs/research/landscape-investigations/08-terrain-generation-tools.md) records the evidence and license; `lowbias32` comes from [hash-prospector](https://github.com/skeeto/hash-prospector) (Unlicense), and this generator is repository-authored MIT code.

The 72 m relief bias plus 24 m, 11 m, and 4 m noise amplitudes bounds the unmasked relief to 33–111 m. The radial envelope fades from zero at 1.5 km to full height at 3 km and fades to zero from 5–6 km. East and west lanes have a 20° half-width flat core and a 15° smooth feather on each side. These lane widths and hill shapes are design estimates. They leave room for optional scenery landmarks around the east wind-turbine location (about N 690 m, E 3,980 m) and the west village (about 2,100 m west); those locations came from the parallel scenery layout, not a terrain survey.

To prove that `--check` catches a mutation without touching the committed file, copy to a temporary path, alter one sample, and check that copy:

```sh
scratch="$(mktemp)"
python3 - "$scratch" <<'PY'
import json
import sys
from pathlib import Path

source = json.loads(Path("app/data/fields/horizon.json").read_text())
source["heights_q"][12][17] += 1
Path(sys.argv[1]).write_text(json.dumps(source, sort_keys=True, separators=(",", ":")) + "\n")
PY
if python3 tools/terrain/gen_terrain.py --check --output "$scratch"; then
  echo "ERROR: mutated profile passed --check" >&2
  rm -f "$scratch"
  exit 1
fi
rm -f "$scratch"
```

This profile is visual-only. L12/L13 physical sampling and collision remain unchanged.

## L7 render verification

`capture_horizon.gd` builds the production field and captures the combined L7 scene, hills with near trees only, and the original flat plane with near trees only. Four azimuths at 1.7, 30 and 140 m give 36 views; six isolated flat-ground views check the fog rim in the default/hazy/clear presets. The Python wrapper repeats all 42 images and manifests, checks exact bytes, counts draws/primitives, and gates the full rim band at a maximum adjacent-row RGB step of four levels. It is also run by `app/capture.sh`.

```sh
"$(app/tests/visual-env.sh)" tools/terrain/check_horizon.py \
  --app app --godot "$(app/get-godot.sh)" --out /tmp/l7-horizon
```

The clear preset's artificial rim fade uses inverse distance, so the transition spreads across projected rows instead of concentrating in a thin band. This is a finite-scene rendering treatment, not a change to atmospheric physics or the flight model. The default and hazy presets keep the established distance-space fade.
