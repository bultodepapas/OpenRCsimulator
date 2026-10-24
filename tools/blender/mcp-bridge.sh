#!/usr/bin/env bash
# Starts the Blender side of the MCP connection with the isolated profile from mcp-setup.sh.
#   tools/blender/mcp-bridge.sh [file.blend]          background Blender (no window; deferred tools unsupported)
#   tools/blender/mcp-bridge.sh --gui [file.blend]    full Blender under Xvfb at 1920x1080 (screenshots, UI tools)
# Port: BLENDER_MCP_PORT (default 9876), localhost only. Stop with Ctrl+C. The MCP server runs any code an agent
# sends with this user's rights (Blender Lab warning); keep it on this development VM.
set -euo pipefail
ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
T="$ROOT/.tools/blender-mcp"
BLENDER="${BLENDER_PATH:-$ROOT/.tools/blender-5.2.2-linux-x64/blender}"
PORT="${BLENDER_MCP_PORT:-9876}"
[ -d "$T/blender-user/extensions/user_default/mcp" ] || { echo "Run tools/blender/mcp-setup.sh first" >&2; exit 1; }
export BLENDER_USER_CONFIG="$T/blender-user/config" BLENDER_USER_SCRIPTS="$T/blender-user/scripts" \
  BLENDER_USER_DATAFILES="$T/blender-user/datafiles" BLENDER_USER_EXTENSIONS="$T/blender-user/extensions"
if [ "${1:-}" = "--gui" ]; then
  shift
  # The interactive add-on reads host and port from its preferences and starts automatically.
  "$BLENDER" --background --python-expr "import bpy; p = bpy.context.preferences.addons['bl_ext.user_default.mcp'].preferences; p.host = '127.0.0.1'; p.port = $PORT; p.use_autostart = True; bpy.ops.wm.save_userpref()" >/dev/null
  exec xvfb-run -a -s '-screen 0 1920x1080x24' "$BLENDER" --online-mode "$@"
fi
# --online-mode: Blender refuses the add-on's (localhost) socket without network access allowed.
exec "$BLENDER" --background --online-mode "$@" --command blender_mcp --host 127.0.0.1 --port "$PORT"
