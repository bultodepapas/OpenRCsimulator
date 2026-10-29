#!/usr/bin/env bash
# Download the pinned Godot editor into <repo>/.tools and verify its official SHA-512.
set -euo pipefail
VERSION=4.8-beta1
ENGINE_VERSION=4.8.beta1.official.4d10419ca
GODOT_GETTER_PLATFORM=other
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
  Darwin:arm64)
    GODOT_GETTER_PLATFORM=macos-arm64
    FILE=Godot_v${VERSION}_macos.arm64
    EXECUTABLE="$FILE/Godot.app/Contents/MacOS/Godot"
    SHA512=eaddf5418249373d6b7c78badc36beaaba1d2ef5972320cf68862d49f3e8cce75d3f8219f4b711c88de4656ecca62c833f2d2f91b489456cdd7157d5a81cc08f
    ;;
  *) echo "Unsupported Godot downloader host: $(uname -s) $(uname -m); install official $VERSION explicitly." >&2; exit 1 ;;
esac

TOOLS="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)/.tools"
mkdir -p "$TOOLS"
RECEIPT="$TOOLS/$FILE.sha512"
if [ "$GODOT_GETTER_PLATFORM" = macos-arm64 ]; then
  # The 4.8 beta distributes separate editor archives per architecture. Keep
  # the signed app bundle intact, rather than extracting its executable alone.
  TOOLS="$(cd "$TOOLS" && pwd -P)"
  RECEIPT="$TOOLS/$FILE.sha512"
  DEST="$TOOLS/$FILE"
  ARCHIVE="$TOOLS/$FILE.zip"
  LOCK="$TOOLS/.$FILE.lock"
  STAGING=""
  if ! mkdir "$LOCK" 2>/dev/null; then
    echo "Godot Mac editor cache is locked: $LOCK (another getter may be running)." >&2; exit 1
  fi
  cleanup_mac_getter() {
    rm -f "$LOCK/download" "$LOCK/manifest"
    rmdir "$LOCK" 2>/dev/null || true
    if [ -n "$STAGING" ] && [ -d "$STAGING" ]; then
      echo "Incomplete Mac editor extraction retained for inspection: $STAGING" >&2
    fi
  }
  trap cleanup_mac_getter EXIT

  mac_manifest() {
    # Include every regular file, so missing, changed and added bundle files
    # invalidate the local receipt. The official archive contains no symlinks.
    [ -z "$(find "$1/Godot.app" -type l -print)" ] || return 1
    (cd "$1" && find Godot.app -type f -print | LC_ALL=C sort |
      while IFS= read -r path; do shasum -a 512 "$path" || exit 1; done)
  }
  check_mac_editor() {
    local app="$1/Godot.app" exe="$1/Godot.app/Contents/MacOS/Godot" description actual_version
    [ -f "$app/Contents/Info.plist" ] && [ -f "$app/Contents/_CodeSignature/CodeResources" ] \
      && [ -f "$exe" ] && [ -x "$exe" ] || { echo "Mac editor bundle is incomplete or not executable: $app" >&2; return 1; }
    description="$(LC_ALL=C file -b "$exe")"
    case "$description" in
      *"Mach-O 64-bit executable arm64"*) ;;
      *) echo "Mac editor is not an ARM64 Mach-O executable: $description" >&2; return 1 ;;
    esac
    actual_version="$("$exe" --version | tr -d '\r')" || return 1
    [ "$actual_version" = "$ENGINE_VERSION" ] || { echo "Unexpected Godot version: $actual_version" >&2; return 1; }
  }

  if [ -e "$DEST" ] || [ -L "$DEST" ] || [ -e "$RECEIPT" ] || [ -L "$RECEIPT" ]; then
    if [ -L "$DEST" ] || [ -L "$RECEIPT" ] || [ ! -d "$DEST/Godot.app" ] || [ ! -s "$RECEIPT" ] \
        || ! mac_manifest "$DEST" > "$LOCK/manifest" || ! cmp -s "$RECEIPT" "$LOCK/manifest" \
        || ! check_mac_editor "$DEST"; then
      echo "Mac editor cache is incomplete or changed; retained for inspection: $DEST and $RECEIPT" >&2; exit 1
    fi
    echo "$TOOLS/$EXECUTABLE"; exit 0
  fi

  if [ -L "$ARCHIVE" ] || { [ -e "$ARCHIVE" ] && [ ! -f "$ARCHIVE" ]; }; then
    echo "Mac editor archive path is not a regular file; retained for inspection: $ARCHIVE" >&2; exit 1
  fi
  if [ ! -f "$ARCHIVE" ]; then
    curl -sSfL -o "$LOCK/download" \
      "https://github.com/godotengine/godot-builds/releases/download/$VERSION/$FILE.zip"
    mv "$LOCK/download" "$ARCHIVE"
  fi
  printf '%s  %s\n' "$SHA512" "$ARCHIVE" | shasum -a 512 -c - >&2 || {
    echo "Mac editor archive failed SHA-512; retained for inspection: $ARCHIVE" >&2; exit 1
  }
  STAGING="$(mktemp -d "$TOOLS/.$FILE.XXXXXXXX")"
  case "$STAGING" in "$TOOLS/.$FILE."*) ;; *) echo "Unexpected Mac extraction path: $STAGING" >&2; exit 1 ;; esac
  unzip -q "$ARCHIVE" -d "$STAGING"
  check_mac_editor "$STAGING"
  mac_manifest "$STAGING" > "$LOCK/manifest"
  [ -s "$LOCK/manifest" ] || { echo "Mac editor bundle manifest is empty." >&2; exit 1; }
  if ! mkdir "$DEST" 2>/dev/null; then
    echo "Mac editor destination appeared during extraction: $DEST" >&2; exit 1
  fi
  mv "$STAGING/Godot.app" "$DEST/Godot.app"
  rmdir "$STAGING"
  STAGING=""
  mv "$LOCK/manifest" "$RECEIPT"
  echo "$TOOLS/$EXECUTABLE"; exit 0
fi
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
