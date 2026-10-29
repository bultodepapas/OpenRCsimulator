#!/usr/bin/env bash
# Download the pinned Godot export templates and verify the archive and installed
# release templates (Linux x86_64, Windows x86_64, macOS universal).
# Prints the install folder. The official installed templates stay unchanged.
# A pinned project-local ZIP works around beta1's universal macOS debug/release inversion.
set -euo pipefail
VERSION=4.8-beta1
TEMPLATE_DIR_NAME=4.8.beta1 # Godot reads the folder name from version.txt, not the archive suffix.
FILE=Godot_v${VERSION}_export_templates.tpz
SHA512=fa53ad6883ae6c78ee9d2f8d14ca4d34852fa21c462d1f4b0f599138d7de40897cc058f15083a1fa80c7d4b7590b2222dea6f056be7b49e3a584eb64fc30b0b7
NEEDED=(linux_release.x86_64 windows_release_x86_64.exe macos.zip version.txt)
# SHA-512 of these members streamed from the archive verified against SHA512 above.
MEMBER_SHA512=(
  f2176272e4ca833cbfe2cb0464b47a7e23e4751344e6fbcf6d6fd0144bbffbaf60eef30cf2539151c7a8c153999709e26d4aeb219cbefca96f8d6499e089d7c9
  cb55c2c37f649d4abf9d6263b9cc0bd27d2214084fae9421d5082aa7a6831bc78af5a72e6942387f109c1b399cb1127eff95816ca5a9c379c9f11c05380e2645
  a36d2fd593a591b19358274ad8100684740fff83cf13ad04c5a3d593c3f4bd08a266f0725bda33344d00f30a56942e726d50b74109e8d50ed4794bbd917e0363
  7b7788794a94f66b6c473d4bec4e4864a548e191cbd4b7bcb99ea88c2c1e1dac5ae60079c16ed3b9e6776e82be3a80ddf9827369a3d18351acafed2d40a8b194
)

TOOLS="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)/.tools"
PROJECT="$(cd "$(dirname "$0")" && pwd)"
CHECKSUM=(sha512sum)
GODOT_TEMPLATES_PYTHON="${OPENRC_GODOT_PYTHON:-python3}"
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) DATA_ROOT="$(cygpath -u "${APPDATA:?APPDATA is required on Windows}")/Godot" ;;
  Darwin) DATA_ROOT="$HOME/Library/Application Support/Godot"; CHECKSUM=(shasum -a 512) ;;
  *) DATA_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/godot" ;;
esac
TEMPLATE_ROOT="$DATA_ROOT/export_templates"
DEST="$TEMPLATE_ROOT/$TEMPLATE_DIR_NAME"
verify_members() {
  local dir="$1" f i
  for f in "${NEEDED[@]}"; do
    if [ ! -f "$dir/$f" ] || [ -L "$dir/$f" ] || [ ! -s "$dir/$f" ]; then
      echo "Missing or invalid template file: $dir/$f" >&2; return 1
    fi
  done
  (
    cd "$dir" || exit 1
    for i in "${!NEEDED[@]}"; do printf '%s  %s\n' "${MEMBER_SHA512[$i]}" "${NEEDED[$i]}"; done |
      "${CHECKSUM[@]}" -c -
  ) >&2
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
mkdir -p "$TOOLS" "$TEMPLATE_ROOT"
# The destination is shared by worktrees; do not inspect or publish it concurrently.
LOCK="$TEMPLATE_ROOT/.openrc-$TEMPLATE_DIR_NAME.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  echo "Template cache is locked: $LOCK (inspect a stale lock before removing it)." >&2; exit 1
fi
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT
if [ -e "$DEST" ] || [ -L "$DEST" ]; then
  if [ ! -d "$DEST" ] || [ -L "$DEST" ] || ! verify_members "$DEST"; then
    echo "Installed template cache is changed or incomplete; retained at $DEST. Move it aside before retrying." >&2; exit 1
  fi
  prepare_macos; echo "$DEST"; exit 0
fi

ARCHIVE="$TOOLS/$FILE"
DOWNLOAD_DIR=""
if [ -L "$ARCHIVE" ] || { [ -e "$ARCHIVE" ] && [ ! -f "$ARCHIVE" ]; }; then
  echo "Template archive path is not a regular file; retained at $ARCHIVE" >&2; exit 1
fi
if [ ! -f "$ARCHIVE" ]; then
  DOWNLOAD_DIR="$(mktemp -d "$TOOLS/.templates-download.XXXXXXXX")"
  ARCHIVE="$DOWNLOAD_DIR/$FILE"
  if ! curl -sSfL -o "$ARCHIVE" "https://github.com/godotengine/godot-builds/releases/download/$VERSION/$FILE"; then
    echo "Template download failed; retained at $DOWNLOAD_DIR" >&2; exit 1
  fi
fi
if ! (cd "$(dirname "$ARCHIVE")" && printf '%s  %s\n' "$SHA512" "$(basename "$ARCHIVE")" | "${CHECKSUM[@]}" -c -) >&2; then
  echo "Template archive failed SHA-512; retained at $ARCHIVE" >&2; exit 1
fi
STAGING="$(mktemp -d "$TEMPLATE_ROOT/.openrc-$TEMPLATE_DIR_NAME.XXXXXXXX")"
if ! unzip -q -j "$ARCHIVE" $(printf 'templates/%s ' "${NEEDED[@]}") -d "$STAGING" || ! verify_members "$STAGING"; then
  echo "Template extraction failed verification; retained at $STAGING" >&2; exit 1
fi
if ! mkdir "$DEST" 2>/dev/null; then
  echo "Template destination appeared during installation; staged files retained at $STAGING" >&2; exit 1
fi
# Exclusive creation cannot replace a path that appeared. Retain partial results
# on failure; copy rather than requiring filesystem hard-link support.
if ! "$GODOT_TEMPLATES_PYTHON" -c 'import os, shutil, sys
for name in sys.argv[3:]:
    source_path, target_path = (os.path.join(directory, name) for directory in sys.argv[1:3])
    with open(source_path, "rb") as source, open(target_path, "xb") as target:
        shutil.copyfileobj(source, target, 1024 * 1024)
    shutil.copymode(source_path, target_path)' "$STAGING" "$DEST" "${NEEDED[@]}" || ! verify_members "$DEST"; then
  echo "Template installation incomplete; retained at $DEST and $STAGING" >&2; exit 1
fi
for f in "${NEEDED[@]}"; do rm "$STAGING/$f"; done
rmdir "$STAGING"
if [ -n "$DOWNLOAD_DIR" ]; then rm "$ARCHIVE"; rmdir "$DOWNLOAD_DIR"; fi
prepare_macos
echo "$DEST"
