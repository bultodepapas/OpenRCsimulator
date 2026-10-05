#!/usr/bin/env bash
# Download the pinned Godot export templates, verify their official SHA-512, and install only the templates the
# release builds use (Linux x86_64, Windows x86_64, macOS universal) where Godot looks for them.
# Prints the install folder. The 1.28 GB .tpz is deleted after extraction; a second run is a no-op.
set -euo pipefail
VERSION=4.7.2-stable
TEMPLATE_DIR_NAME=4.7.2.stable # Godot reads the folder name from version.txt: a dot, not "-stable"
FILE=Godot_v${VERSION}_export_templates.tpz
SHA512=ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079
NEEDED=(linux_release.x86_64 windows_release_x86_64.exe macos.zip version.txt)

TOOLS="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)/.tools"
DEST="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/$TEMPLATE_DIR_NAME"
present() { for f in "${NEEDED[@]}"; do [ -s "$DEST/$f" ] || return 1; done; }
if present; then echo "$DEST"; exit 0; fi
mkdir -p "$TOOLS" "$DEST"
if [ ! -f "$TOOLS/$FILE" ]; then
  curl -sSfL -o "$TOOLS/$FILE.part" "https://github.com/godotengine/godot/releases/download/$VERSION/$FILE"
  mv "$TOOLS/$FILE.part" "$TOOLS/$FILE"
fi
echo "$SHA512  $TOOLS/$FILE" | sha512sum -c - >&2
unzip -q -o -j "$TOOLS/$FILE" $(printf 'templates/%s ' "${NEEDED[@]}") -d "$DEST"
[ "$(cat "$DEST/version.txt")" = "$TEMPLATE_DIR_NAME" ] || { echo "unexpected template version: $(cat "$DEST/version.txt")" >&2; exit 1; }
rm "$TOOLS/$FILE"
present
echo "$DEST"
