#!/usr/bin/env bash
# MCP stdio server for agents (registered in .mcp.json). Talks to the Blender bridge (mcp-bridge.sh) on
# BLENDER_MCP_PORT (default 9876); its *_for_cli tools also open .blend files in a background Blender of their own.
set -euo pipefail
ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
T="$ROOT/.tools/blender-mcp"
if [ ! -x "$T/venv/bin/python" ] || [ ! -d "$T/src/mcp/blmcp" ]; then
  echo "Blender MCP is not installed: run tools/blender/mcp-setup.sh" >&2
  exit 1
fi
export BLENDER_PATH="${BLENDER_PATH:-$ROOT/.tools/blender-5.2.2-linux-x64/blender}"
export BLENDER_MCP_HOST="${BLENDER_MCP_HOST:-127.0.0.1}" BLENDER_MCP_PORT="${BLENDER_MCP_PORT:-9876}"
export PYTHONPATH="$T/src/mcp"
exec "$T/venv/bin/python" -m blmcp "$@"
