#!/usr/bin/env bash
# Download the pinned Godot export templates and verify the archive and installed
# release templates (Linux x86_64, Windows x86_64, macOS universal).
# Prints the install folder. The official installed templates stay unchanged.
set -euo pipefail
VERSION=4.8-beta2
TEMPLATE_DIR_NAME=4.8.beta2 # Godot reads the folder name from version.txt, not the archive suffix.
FILE=Godot_v${VERSION}_export_templates.tpz
SHA512=260de4173d9bb366110dab4f35e42e39f2eace62f29e082d6630bc5c6ea790ef92f51a9145ffbca2c0ffe97a60da46019c6780d7f88569932cd3237284085c0e
NEEDED=(linux_release.x86_64 windows_release_x86_64.exe macos.zip version.txt)
# SHA-512 of these members streamed from the archive verified against SHA512 above.
MEMBER_SHA512=(
  c0702f8d2e43f9a8168db71d404b35bc7c3b1d8a69a516b4bee8946b70faf16afd3b046dd8d9c5255da0b7fe71385cff473050dcdc874f4ac72b55868b91bc9a
  345862e92c5f1d94596ba64e9ad46dcea323280fb2ed760abdc7e0586f71921d07d049d3e5953b493e09c401cf6c7acf97718ec4cc377f028910ba5bd738fe46
  a307324eec2db7db8eef26be10c7c4b91c923c8f91fe9144aee4c5812cd17f4e65e7b03e33021d29f8ff9384fc51a8a9b2d3ea81c461b966dc795edad42a09c7
  19e82db58a24133a12f2f9514c6112bfcb9e8a3a4c2247986a24cd47548dc355eb28d10bd496b7f492df8fc711c7a9eae2f18779bc932ef6bf3215f4eec6edf7
)

TOOLS="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)/.tools"
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
    echo "The template installer requires Python 3.11+; set OPENRC_GODOT_PYTHON to its executable." >&2; return 1
  fi
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
  echo "$DEST"; exit 0
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
echo "$DEST"
