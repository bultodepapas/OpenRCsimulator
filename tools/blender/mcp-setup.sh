#!/usr/bin/env bash
# Installs the official Blender Lab MCP server (v1.0.3, GPL-3.0-or-later) for agents, isolated under .tools/blender-mcp:
# the pinned git tag (server source), its dependencies at the exact versions and hashes of requirements-mcp.txt, and
# the add-on release zip (SHA-256 checked) in a separate Blender user profile. Idempotent; needs python3, git, curl
# and the pinned Blender 5.2.2 in .tools (docs/TOOLS.md). See tools/blender/README.md.
set -euo pipefail
ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
T="$ROOT/.tools/blender-mcp"
REQ="$ROOT/tools/blender/requirements-mcp.txt"
BLENDER="${BLENDER_PATH:-$ROOT/.tools/blender-5.2.2-linux-x64/blender}"
TAG=v1.0.3
COMMIT=2cea8d566dde07fbac28a61d698909d69724e853
ADDON_URL="https://projects.blender.org/lab/blender_mcp/releases/download/$TAG/mcp-1.0.3.zip"
ADDON_SHA256=a7a9da816192502e5a0a202a396444e266b47d8fc4f74ad4698048bd43040707

[ -x "$BLENDER" ] || { echo "Blender not found at $BLENDER (set BLENDER_PATH)" >&2; exit 1; }
mkdir -p "$T"

# Server source at the pinned tag (run from source: no package build, no unpinned build tools).
if [ ! -d "$T/src/.git" ]; then
  git -c advice.detachedHead=false clone -q --depth 1 --branch "$TAG" https://projects.blender.org/lab/blender_mcp.git "$T/src"
fi
[ "$(git -C "$T/src" rev-parse HEAD)" = "$COMMIT" ] || { echo "$T/src is not $TAG ($COMMIT)" >&2; exit 1; }

# Dependencies (a venv without pip, as app/tests/visual-env.sh: no python3-venv package needed).
STAMP="$T/venv/.requirements.sha256"
if [ ! -f "$STAMP" ] || [ "$(cat "$STAMP")" != "$(sha256sum "$REQ" | cut -d' ' -f1)" ]; then
  rm -rf "$T/venv"
  python3 -m venv --without-pip "$T/venv"
  python3 -m pip --python "$T/venv/bin/python" install -q --require-hashes --no-deps --only-binary=:all: -r "$REQ"
  sha256sum "$REQ" | cut -d' ' -f1 > "$STAMP"
fi

# Add-on in an isolated Blender profile (never the interactive one).
export BLENDER_USER_CONFIG="$T/blender-user/config" BLENDER_USER_SCRIPTS="$T/blender-user/scripts" \
  BLENDER_USER_DATAFILES="$T/blender-user/datafiles" BLENDER_USER_EXTENSIONS="$T/blender-user/extensions"
if [ ! -f "$BLENDER_USER_EXTENSIONS/user_default/mcp/blender_manifest.toml" ]; then
  curl -fsSL -o "$T/mcp-1.0.3.zip" "$ADDON_URL"
  echo "$ADDON_SHA256  $T/mcp-1.0.3.zip" | sha256sum -c --quiet
  "$BLENDER" --background --command extension install-file --repo user_default --enable "$T/mcp-1.0.3.zip" >/dev/null
fi
grep -q 'version = "1.0.3"' "$BLENDER_USER_EXTENSIONS/user_default/mcp/blender_manifest.toml"
echo "Blender MCP ready: server $TAG, add-on 1.0.3, $("$BLENDER" --version | head -1)"
