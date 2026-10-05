#!/usr/bin/env bash
# Download the pinned Godot editor into <repo>/.tools and verify its official SHA-512.
set -euo pipefail
VERSION=4.7.2-stable
FILE=Godot_v${VERSION}_linux.x86_64
SHA512=9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65

TOOLS="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)/.tools"
mkdir -p "$TOOLS"
if [ -x "$TOOLS/$FILE" ]; then echo "$TOOLS/$FILE"; exit 0; fi
curl -sSfL -o "$TOOLS/$FILE.zip" \
  "https://github.com/godotengine/godot/releases/download/$VERSION/$FILE.zip"
echo "$SHA512  $TOOLS/$FILE.zip" | sha512sum -c - >&2
unzip -q -o "$TOOLS/$FILE.zip" -d "$TOOLS"
rm "$TOOLS/$FILE.zip"
chmod +x "$TOOLS/$FILE"
echo "$TOOLS/$FILE"
