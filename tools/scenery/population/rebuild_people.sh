#!/usr/bin/env bash
# Rebuilds the field people: regenerates the requested outfit poses (all 11 by default) into persistent sources,
# merges every source into the shared atlas, packages each pose and lists which shipped files would change.
# Install the result with install_people.py. Unchanged outfits regenerate byte for byte, so the persistent sources
# let a round regenerate only what it touched (a transmitter change: the two pilots, about 2 minutes).
#   tools/scenery/population/rebuild_people.sh                        # everything (about 8 minutes)
#   tools/scenery/population/rebuild_people.sh pilot_polo:pilot veteran_cap:pilot
# Needs the isolated MPFB setup in .tools/sc-hum-authoring (docs/research/scenery-implementation/SC-HUM-00).
set -euo pipefail
ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
ST="$ROOT/.tools/sc-hum-authoring"
BLENDER="${BLENDER_PATH:-$ROOT/.tools/blender-5.2.2-linux-x64/blender}"
SOURCES="$ST/outfits"      # one folder per outfit, persistent between rounds
MERGED="$ST/merged-people"
PACKAGED="$ST/packaged-people"
ALL="pilot_polo:pilot veteran_cap:pilot casual_shirt:standing woman_tee:standing casual_jacket:standing
mechanic_overalls:standing woman_tee:seated veteran_cap:seated mechanic_overalls:working casual_shirt:working
woman_tee:working"
export BLENDER_USER_CONFIG="$ST/blender-user/config" BLENDER_USER_SCRIPTS="$ST/blender-user/scripts" \
  BLENDER_USER_DATAFILES="$ST/blender-user/datafiles" BLENDER_USER_EXTENSIONS="$ST/blender-user/extensions"
[ -d "$ST/mpfb/data" ] || { echo "MPFB data missing in $ST/mpfb (see SC-HUM-00)" >&2; exit 1; }

for spec in ${*:-$ALL}; do
  outfit="${spec%%:*}"; pose="${spec##*:}"
  log="$SOURCES/$outfit-$pose.log"
  mkdir -p "$SOURCES/$outfit"
  if ! "$BLENDER" --background --factory-startup --python "$ROOT/tools/scenery/population/generate_people.py" -- \
      --pose "$pose" --outfit "$ROOT/tools/scenery/population/outfits/$outfit.json" --mpfb-user-data "$ST/mpfb" \
      --output-dir "$SOURCES/$outfit" > "$log" 2>&1; then
    echo "FAILED $outfit $pose (see $log)" >&2; exit 1
  fi
  echo "$outfit $pose $(grep -E '^EXPORT_TRIANGLES' "$log")"
done

count=$(ls "$SOURCES"/*/person_*.gltf | wc -l)
[ "$count" -eq 11 ] || { echo "expected 11 sources in $SOURCES, found $count: run without arguments once" >&2; exit 1; }
rm -rf "${MERGED:?}" "${PACKAGED:?}"
"$BLENDER" --background --factory-startup --python "$ROOT/tools/scenery/population/merge_people_atlas.py" -- \
  --shared "$MERGED" people "$SOURCES"/*/person_*.gltf > "$ST/merge.log" 2>&1 || { echo "merge failed (see $ST/merge.log)" >&2; exit 1; }
mkdir -p "$PACKAGED/people"
for gltf in "$MERGED"/person_*.gltf; do
  name="$(basename "$gltf" .gltf)"; name="${name#person_}"; name="${name/_seated/_sitting}"
  python3 "$ROOT/tools/scenery/population/package_population.py" "$gltf" "$PACKAGED/people/$name.glb" > /dev/null
done
for glb in "$PACKAGED"/people/*.glb; do
  cmp -s "$glb" "$ROOT/app/assets/scenery/population/people/$(basename "$glb")" || echo "changed $(basename "$glb")"
done
echo "packaged in $PACKAGED; install with tools/scenery/population/install_people.py"
