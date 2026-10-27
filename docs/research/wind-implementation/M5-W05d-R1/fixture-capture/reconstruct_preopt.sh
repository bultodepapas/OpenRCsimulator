#!/usr/bin/env bash
# Build a minimal Godot project holding the frozen pre-packed-mode spatial wind
# sources (the parent of the packing commit 241eaf0b5) plus the frozen R1 test,
# fixture grid and capture tool. Usage: reconstruct_preopt.sh <repo-root> <new-dir>
set -euo pipefail
repo=$(cd "$1" && pwd)
out=$2
[ -e "$out" ] && { echo "refusing existing $out" >&2; exit 2; }
here=$repo/docs/research/wind-implementation/M5-W05d-R1
mkdir -p "$out/physics" "$out/tests/fixtures"
printf 'config_version=5\n\n[application]\n\nconfig/name="spatial-wind-preopt"\n' > "$out/project.godot"
git -C "$repo" show 4c1513949:app/physics/wind_spatial_field.gd > "$out/physics/wind_spatial_field.gd"
cp "$here/candidate-source/app/physics/wind_spatial_config.gd" "$here/candidate-source/app/physics/wind_thermal_field.gd" "$out/physics/"
cp "$here/candidate-source/app/tests/test_spatial_wind_field.gd" "$out/tests/"
cp "$repo/app/tests/fixtures/spatial_wind_mode_grid_before.json" "$out/tests/fixtures/"
cp "$here/fixture-capture/capture_spatial_wind_mode_grid.gd" "$out/"
# Expected pre-packed identities: field c9e213aa..., config 75486c40..., thermal 79527765...
(cd "$out" && sha256sum physics/*.gd tests/*.gd)
