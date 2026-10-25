#!/usr/bin/env bash
# Download the pinned Godot editor into <repo>/.tools and verify its official SHA-512.
set -euo pipefail
VERSION=4.8-beta1
ENGINE_VERSION=4.8.beta1.official.4d10419ca
case "$(uname -s):$(uname -m)" in
  Linux:x86_64)
    FILE=Godot_v${VERSION}_linux.x86_64
    EXECUTABLE=$FILE
    SHA512=aee4cbf3c5f86eee875c0f2f77cc9d816a3fbb220774e6ffc95fd5a557a6c5ec917f2b6118c0aa2008bd10f4b2a021225dc78ba7b7c54745411e0f2721f70a67
    BINARIES=("$EXECUTABLE")
    ;;
  MINGW*:x86_64|MSYS*:x86_64|CYGWIN*:x86_64)
    FILE=Godot_v${VERSION}_win64.exe
    EXECUTABLE=Godot_v${VERSION}_win64_console.exe
    SHA512=bdc79f8ef47c3794c6984751bbac2c1934cf1c7c9ceebc2d0e87db0846766411b7bbbb6fecf90f3485f951a1289c3171b1c7bebca18dcdd8e08bd81de95b6cc0
    BINARIES=("$FILE" "$EXECUTABLE")
    ;;
  *) echo "Unsupported Godot downloader host: $(uname -s) $(uname -m); install official $VERSION explicitly." >&2; exit 1 ;;
esac

TOOLS="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)/.tools"
mkdir -p "$TOOLS"
RECEIPT="$TOOLS/$FILE.sha512"
if [ -s "$RECEIPT" ] && (cd "$TOOLS" && sha512sum --status -c "$RECEIPT"); then
  echo "$TOOLS/$EXECUTABLE"; exit 0
fi
if [ ! -f "$TOOLS/$FILE.zip" ]; then
  curl -sSfL -o "$TOOLS/$FILE.zip.part" \
    "https://github.com/godotengine/godot-builds/releases/download/$VERSION/$FILE.zip"
  mv "$TOOLS/$FILE.zip.part" "$TOOLS/$FILE.zip"
fi
echo "$SHA512  $TOOLS/$FILE.zip" | sha512sum -c - >&2
unzip -q -o "$TOOLS/$FILE.zip" -d "$TOOLS"
chmod +x "${BINARIES[@]/#/$TOOLS/}"
ACTUAL_VERSION="$("$TOOLS/$EXECUTABLE" --version | tr -d '\r')"
[ "$ACTUAL_VERSION" = "$ENGINE_VERSION" ] || { echo "Unexpected Godot version: $ACTUAL_VERSION" >&2; exit 1; }
(cd "$TOOLS" && sha512sum "${BINARIES[@]}") > "$RECEIPT"
rm "$TOOLS/$FILE.zip"
echo "$TOOLS/$EXECUTABLE"
