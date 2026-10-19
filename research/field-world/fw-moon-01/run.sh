#!/usr/bin/env bash
# FW-MOON-01 render-path bench: sky radiance re-render cost, mesh-disc cost, second directional light, cloud parity.
# Usage, from the repository root (one Godot process at a time, ~2 GB RAM):
#   research/field-world/fw-moon-01/run.sh OUT_DIR [bench|parity|lights|profiles|paired|all]
#   python3 -I research/field-world/fw-moon-01/analyze.py OUT_DIR
# Environment overrides: RES="1280x720" REPS=3 WARMUP=120 FRAMES=600 BURN=200 CASES="static uniform ..."
#   SRC_REV=780af5e1 (the app shaders are read from this commit, not the working tree, so parallel edits cannot leak in).
# The 2026-10-19 record ran, into one OUT_DIR:
#   run.sh OUT parity; run.sh OUT lights; run.sh OUT bench                      (core cases, 3 reps, 1280x720)
#   CASES="$BURN_CASES" REPS=1 run.sh OUT bench                                 (cost-amplifier detector, 1 rep)
#   RES=1920x1080 REPS=1 WARMUP=60 FRAMES=300 CASES="static uniform sky_ambient_uniform mesh_disc light2" run.sh OUT bench
#   run.sh OUT profiles; run.sh OUT paired                                    (nine presets; in-process paired timing)
# On the dev VM this is Mesa llvmpipe under Xvfb: numbers are relative, never target-GPU costs.
set -euo pipefail
REPO="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
HERE="$REPO/research/field-world/fw-moon-01"
OUT="$(mkdir -p "$1" && cd "$1" && pwd)"
WHAT="${2:-all}"
GODOT="$("$REPO/app/get-godot.sh")"
RES="${RES:-1280x720}"
REPS="${REPS:-3}"
WARMUP="${WARMUP:-120}"
FRAMES="${FRAMES:-600}"
BURN="${BURN:-200}"
SRC_REV="${SRC_REV:-780af5e1}"
# BURN_CASES (export it for the second command): burn_color_static burn_color_uniform burn_sky_static burn_sky_uniform
CASES="${CASES:-static uniform uniform_incremental uniform_realtime256 uniform_realtime32 sky_ambient_static sky_ambient_uniform sky_ambient_uniform_rt32 mesh_disc light2 light2_shadow}"

# Assemble a scratch project: the bench files plus the app's shared sky shader and includes (unmodified, at SRC_REV).
PROJ="$OUT/project"
rm -rf "$PROJ"
mkdir -p "$PROJ/render/world" "$PROJ/render/weather" "$OUT/shots" "$OUT/runs" "$OUT/logs"
cp "$HERE"/project/{project.godot,bench.tscn,bench.gd,moon_disc.gdshader,profiles.tscn,parity_profiles.gd,paired.tscn,paired.gd} "$PROJ/"
for f in render/sky.gdshader render/cloud_field.gdshaderinc render/cloud_relief.gdshaderinc render/world/engine_srgb.gdshaderinc \
		render/weather/sky_appearance.gd; do
	git -C "$REPO" show "$SRC_REV:app/$f" > "$PROJ/$f"
done
git -C "$REPO" show "$SRC_REV:app/data/sky/weather_presets.json" > "$PROJ/weather_presets.json"
echo "app shaders from $SRC_REV" > "$OUT/inputs.txt"
sha256sum "$PROJ"/render/*.gdshader* "$PROJ"/render/world/* "$PROJ"/render/weather/* "$PROJ"/*.gd* "$PROJ"/*.json > "$OUT/inputs.sha256"
# First open imports the project (creates .godot/); quit right after.
timeout 120 "$GODOT" --headless --path "$PROJ" --import > "$OUT/logs/import.log" 2>&1 || true

godot_run() { # $1 = resolution, $2 = log file, rest = user args; SCENE overrides the main scene
	local res="$1" log="$2"
	shift 2
	timeout 3600 xvfb-run -a -s "-screen 0 1920x1080x24" "$GODOT" --path "$PROJ" --rendering-driver opengl3 \
		--audio-driver Dummy --resolution "$res" --disable-vsync ${SCENE:-} -- "$@" > "$log" 2>&1
}

if [[ "$WHAT" == bench || "$WHAT" == all ]]; then
	for res in $RES; do
		for rep in $(seq 1 "$REPS"); do
			# Rotate the case order every repetition so slow drift of the shared VM does not bias one case.
			read -r -a list <<< "$CASES"
			n=${#list[@]}
			for i in $(seq 0 $((n - 1))); do
				c="${list[$(((i + rep - 1) % n))]}"
				w="$WARMUP" f="$FRAMES"
				if [[ "$c" == burn_sky_uniform ]]; then w=10; f=40; fi # one full rebuild per frame: seconds each
				tag="${c}_${res}_r${rep}"
				echo "bench $tag $(cut -d' ' -f1-3 /proc/loadavg)" | tee -a "$OUT/loadavg.txt"
				godot_run "$res" "$OUT/logs/$tag.log" --mode=bench --case="$c" --warmup="$w" --frames="$f" \
					--burn="$BURN" --out="$OUT/runs/$tag.json" || echo "FAILED $tag"
			done
		done
	done
fi
if [[ "$WHAT" == parity || "$WHAT" == all ]]; then
	echo parity
	godot_run 1280x720 "$OUT/logs/parity.log" --mode=parity --out="$OUT/parity.json" --shots="$OUT/shots"
fi
if [[ "$WHAT" == lights || "$WHAT" == all ]]; then
	echo lights
	godot_run 1280x720 "$OUT/logs/lights.log" --mode=lights --out="$OUT/lights.json" --shots="$OUT/shots"
fi
if [[ "$WHAT" == profiles || "$WHAT" == all ]]; then
	echo profiles
	SCENE=res://profiles.tscn godot_run 1280x720 "$OUT/logs/profiles.log" --mode=profiles --out="$OUT/profiles.json" --shots="$OUT/shots"
fi
if [[ "$WHAT" == paired || "$WHAT" == all ]]; then
	echo paired
	SCENE=res://paired.tscn godot_run 1280x720 "$OUT/logs/paired.log" --mode=paired --cycles="${CYCLES:-25}" --block=30 \
		--warmup="$WARMUP" --out="$OUT/paired.json"
fi
# Shader or script errors would invalidate a run: list them.
grep -l "SHADER ERROR\|SCRIPT ERROR\|Parse Error" "$OUT"/logs/*.log || echo "no shader/script errors in logs"
