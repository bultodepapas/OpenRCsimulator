#!/usr/bin/env bash
# Download the pinned Godot editor into <repo>/.tools and verify its official SHA-512.
set -euo pipefail
VERSION=4.8-beta2
ENGINE_VERSION=4.8.beta2.official.cafc17a19
GODOT_GETTER_PLATFORM=other
case "$(uname -s):$(uname -m)" in
  Linux:x86_64)
    FILE=Godot_v${VERSION}_linux.x86_64
    EXECUTABLE=$FILE
    SHA512=77470f53a9039cd22837935380230220167e098324e82ec448ee4b1f943f00afc424885f7d6631f385123d7a630a9399b3cc1b0e1dad1a4ac45c6356b3a0aa45
    BINARIES=("$EXECUTABLE")
    BINARY_SHA512=(428dca05774fb1b163d13a362bb00d0eb82a447634bf717d24fca9944d9f10e75a8bca30222b648ec87da7125339895d8c6985de0a8767b4df5a44d00de35dc9)
    ;;
  MINGW*:x86_64|MSYS*:x86_64|CYGWIN*:x86_64)
    FILE=Godot_v${VERSION}_win64.exe
    EXECUTABLE=Godot_v${VERSION}_win64_console.exe
    SHA512=23d6dc2561f95cf296ca88c18d843867dffe978ac23608e3e4eb3fd67c0745cf48a259d51c83650f47e9e42f23154e0f907a6a162ea6b0e47dddbb3d88aa4579
    BINARIES=("$FILE" "$EXECUTABLE")
    BINARY_SHA512=(e83c615fb181c6e1c83f204801e8c73a9340ea500d0da3d7e598f6c4213051de5df8073041c27790838b9e4eff4770c483d7dbb75545da7ad4382c53e23f6a55 dd05e00ff13faac6b863aa1e4c51599cfaa973c9b8d2e31158d717b499a4ee0b08d46661c0c91215dcce77ce1edfb33595b8af476b2862a47465ec27545962ea)
    ;;
  Darwin:arm64)
    GODOT_GETTER_PLATFORM=macos-arm64
    FILE=Godot_v${VERSION}_macos.arm64
    EXECUTABLE="$FILE/Godot.app/Contents/MacOS/Godot"
    SHA512=91e14126ad880dc31983b11fe03817771acfb20286a7543f8cde0db1c8c63c1845bcf38cb2252318165b65ddd166b362aadf874892555f4eb5e37dbc486b171e
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
verify_executables() {
  local dir="$1" i actual_version
  for i in "${!BINARIES[@]}"; do
    [ -f "$dir/${BINARIES[$i]}" ] && [ ! -L "$dir/${BINARIES[$i]}" ] \
      && [ -x "$dir/${BINARIES[$i]}" ] || return 1
  done
  (cd "$dir" && for i in "${!BINARIES[@]}"; do
    printf '%s  %s\n' "${BINARY_SHA512[$i]}" "${BINARIES[$i]}"
  done | sha512sum --status -c -) || return 1
  actual_version="$("$dir/$EXECUTABLE" --version | tr -d '\r')" || return 1
  [ "$actual_version" = "$ENGINE_VERSION" ]
}

# A local receipt is only a cache marker, never an authority for executable bytes.
# Older valid receipts remain usable; a missing receipt does not block verified files.
if [ ! -L "$RECEIPT" ] && { [ ! -e "$RECEIPT" ] || [ -f "$RECEIPT" ]; } \
    && verify_executables "$TOOLS"; then
  echo "$TOOLS/$EXECUTABLE"; exit 0
fi

# Only cold publication and diagnosis of an invalid cache need the lock.
LOCK="$TOOLS/.$FILE.lock"
STAGING=""
if ! mkdir "$LOCK" 2>/dev/null; then
  echo "Godot editor cache is locked: $LOCK (inspect a stale lock before removing it)." >&2; exit 1
fi
cleanup_editor_getter() {
  rmdir "$LOCK" 2>/dev/null || true
  if [ -n "$STAGING" ] && [ -d "$STAGING" ]; then
    echo "Incomplete editor installation retained for inspection: $STAGING" >&2
  fi
}
trap cleanup_editor_getter EXIT
CACHE_PRESENT=false
if [ -e "$RECEIPT" ] || [ -L "$RECEIPT" ]; then CACHE_PRESENT=true; fi
for binary in "${BINARIES[@]}"; do
  if [ -e "$TOOLS/$binary" ] || [ -L "$TOOLS/$binary" ]; then CACHE_PRESENT=true; fi
done
if "$CACHE_PRESENT"; then
  if [ -L "$RECEIPT" ] || { [ -e "$RECEIPT" ] && [ ! -f "$RECEIPT" ]; } || ! verify_executables "$TOOLS"; then
    echo "Godot editor cache is incomplete, changed or has the wrong version; retained for inspection: $TOOLS/$FILE" >&2; exit 1
  fi
  echo "$TOOLS/$EXECUTABLE"; exit 0
fi
ARCHIVE="$TOOLS/$FILE.zip"
if [ -L "$ARCHIVE" ] || { [ -e "$ARCHIVE" ] && [ ! -f "$ARCHIVE" ]; }; then
  echo "Godot editor archive path is not a regular file; retained for inspection: $ARCHIVE" >&2; exit 1
fi
STAGING="$(mktemp -d "$TOOLS/.$FILE.XXXXXXXX")"
case "$STAGING" in "$TOOLS/.$FILE."*) ;; *) echo "Unexpected editor extraction path: $STAGING" >&2; exit 1 ;; esac
if [ ! -f "$ARCHIVE" ]; then
  ARCHIVE="$STAGING/$FILE.zip"
  curl -sSfL -o "$ARCHIVE" \
    "https://github.com/godotengine/godot-builds/releases/download/$VERSION/$FILE.zip"
fi
printf '%s  %s\n' "$SHA512" "$ARCHIVE" | sha512sum -c - >&2
unzip -q "$ARCHIVE" -d "$STAGING"
chmod +x "${BINARIES[@]/#/$STAGING/}"
if ! verify_executables "$STAGING"; then
  echo "Extracted Godot binaries failed official SHA-512 or version verification." >&2; exit 1
fi
# noclobber creates each destination exclusively, even if a non-cooperating
# process creates a file while download or verification is in progress.
for binary in "${BINARIES[@]}"; do
  if ! (set -o noclobber; cat "$STAGING/$binary" > "$TOOLS/$binary"); then
    echo "Godot editor destination appeared during installation; retained for inspection: $TOOLS/$binary" >&2; exit 1
  fi
  chmod +x "$TOOLS/$binary"
done
if ! verify_executables "$TOOLS"; then
  echo "Published Godot binaries failed official SHA-512 or version verification." >&2; exit 1
fi
if ! (set -o noclobber; cd "$TOOLS" && sha512sum "${BINARIES[@]}" > "$RECEIPT"); then
  echo "Godot editor receipt appeared during installation; retained for inspection: $RECEIPT" >&2; exit 1
fi
for binary in "${BINARIES[@]}"; do rm "$STAGING/$binary"; done
if [ "$ARCHIVE" = "$STAGING/$FILE.zip" ]; then rm "$ARCHIVE"; fi
rmdir "$STAGING"
STAGING=""
echo "$TOOLS/$EXECUTABLE"
