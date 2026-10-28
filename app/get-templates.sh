#!/usr/bin/env bash
# Download the pinned Godot export templates, verify their official SHA-512, and install only the templates the
# release builds use (Linux x86_64, Windows x86_64, macOS universal) where Godot looks for them.
# Prints the install folder. The official installed templates stay unchanged.
# A pinned project-local ZIP works around beta1's universal macOS debug/release inversion.
set -euo pipefail
VERSION=4.8-beta1
TEMPLATE_DIR_NAME=4.8.beta1 # Godot reads the folder name from version.txt, not the archive suffix.
FILE=Godot_v${VERSION}_export_templates.tpz
SHA512=fa53ad6883ae6c78ee9d2f8d14ca4d34852fa21c462d1f4b0f599138d7de40897cc058f15083a1fa80c7d4b7590b2222dea6f056be7b49e3a584eb64fc30b0b7
NEEDED=(linux_release.x86_64 windows_release_x86_64.exe macos.zip version.txt)

TOOLS="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)/.tools"
PROJECT="$(cd "$(dirname "$0")" && pwd)"
CHECKSUM=(sha512sum)
GODOT_TEMPLATES_PYTHON="${OPENRC_GODOT_PYTHON:-python3}"
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) DATA_ROOT="$(cygpath -u "${APPDATA:?APPDATA is required on Windows}")/Godot" ;;
  Darwin) DATA_ROOT="$HOME/Library/Application Support/Godot"; CHECKSUM=(shasum -a 512) ;;
  *) DATA_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/godot" ;;
esac
DEST="$DATA_ROOT/export_templates/$TEMPLATE_DIR_NAME"
present() {
  for f in "${NEEDED[@]}"; do [ -s "$DEST/$f" ] || return 1; done
  [ "$(tr -d '\r\n' < "$DEST/version.txt")" = "$TEMPLATE_DIR_NAME" ]
}
check_python() {
  if ! "$GODOT_TEMPLATES_PYTHON" -c 'import hashlib, sys; sys.exit(0 if hasattr(hashlib, "file_digest") else 1)'; then
    echo "The macOS template correction requires Python 3.11+; set OPENRC_GODOT_PYTHON to its executable." >&2; return 1
  fi
}
prepare_macos() {
  "$GODOT_TEMPLATES_PYTHON" "$PROJECT/../tools/godot/macos_universal_template.py" --source "$DEST/macos.zip" --project "$PROJECT" >&2
}
check_python
if present; then prepare_macos; echo "$DEST"; exit 0; fi
mkdir -p "$TOOLS" "$DEST"
if [ ! -f "$TOOLS/$FILE" ]; then
  curl -sSfL -o "$TOOLS/$FILE.part" "https://github.com/godotengine/godot-builds/releases/download/$VERSION/$FILE"
  mv "$TOOLS/$FILE.part" "$TOOLS/$FILE"
fi
printf '%s  %s\n' "$SHA512" "$TOOLS/$FILE" | "${CHECKSUM[@]}" -c - >&2
unzip -q -o -j "$TOOLS/$FILE" $(printf 'templates/%s ' "${NEEDED[@]}") -d "$DEST"
[ "$(tr -d '\r\n' < "$DEST/version.txt")" = "$TEMPLATE_DIR_NAME" ] || { echo "unexpected template version: $(cat "$DEST/version.txt")" >&2; exit 1; }
rm "$TOOLS/$FILE"
present
prepare_macos
echo "$DEST"
