#!/usr/bin/env bash
# Probe for research 21 (build identity in exports). Builds a throwaway Godot project in a temp dir, never in app/.
# Checks with the pinned Godot 4.7.2: application/config/version at runtime, an EditorExportPlugin that injects
# res://build_info.json with add_file() (no file on disk), which files need include_filter, and override.cfg spoofing.
# Exports PCK files only (a few KB, no templates copied). Usage: docs/research/menu-investigations/probes/21-build-info-probe.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
G="$ROOT/.tools/Godot_v4.7.2-stable_linux.x86_64"
P="$(mktemp -d)"; trap 'rm -rf "$P"' EXIT
mkdir -p "$P/addons/build_info" "$P/data" "$P/out" "$P/ov"
cat > "$P/project.godot" <<'EOF'
config_version=5
[application]
config/name="Probe21"
config/version="0.1.0"
run/main_scene="res://main.tscn"
config/features=PackedStringArray("4.7")
[editor_plugins]
enabled=PackedStringArray("res://addons/build_info/plugin.cfg")
EOF
printf '[gd_scene format=3]\n[ext_resource type="Script" path="res://main.gd" id="1"]\n[node name="Main" type="Node"]\nscript = ExtResource("1")\n' > "$P/main.tscn"
cat > "$P/main.gd" <<'EOF'
extends Node
func _ready() -> void:
	print("PROBE config/version=", ProjectSettings.get_setting("application/config/version"))
	for p in ["res://build_info.json", "res://data/static.json", "res://static.cfg"]:
		print("PROBE ", p, " exists=", FileAccess.file_exists(p), " ", FileAccess.get_file_as_string(p).strip_edges())
	get_tree().quit()
EOF
echo '{"static": true}' > "$P/data/static.json"; printf '[a]\nb=1\n' > "$P/static.cfg"
printf '[plugin]\nname="build_info"\ndescription=""\nauthor=""\nversion="0"\nscript="plugin.gd"\n' > "$P/addons/build_info/plugin.cfg"
cat > "$P/addons/build_info/plugin.gd" <<'EOF'
@tool
extends EditorPlugin
var _exp := preload("res://addons/build_info/export_plugin.gd").new()
func _enter_tree() -> void: add_export_plugin(_exp)
func _exit_tree() -> void: remove_export_plugin(_exp)
EOF
cat > "$P/addons/build_info/export_plugin.gd" <<'EOF'
@tool
extends EditorExportPlugin
func _get_name() -> String: return "build_info"
func _get_export_options_overrides(platform: EditorExportPlatform) -> Dictionary:
	return {"application/file_version": "0.1.0.2"} if platform.get_os_name() == "Windows" else {}
func _export_begin(features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	if get_export_platform().get_os_name() == "Windows":
		print("PLUGIN override seen by get_option: '", get_option("application/file_version"), "'")
	var info := {"version": OS.get_environment("OPENRC_VERSION"), "commit": OS.get_environment("OPENRC_COMMIT")}
	add_file("res://build_info.json", JSON.stringify(info).to_utf8_buffer(), false)
EOF
preset() { printf '[preset.%s]\nname="%s"\nplatform="%s"\nrunnable=%s\nexport_filter="all_resources"\ninclude_filter="%s"\nexclude_filter="addons/*"\nexport_path="out/x"\n[preset.%s.options]\nbinary_format/embed_pck=false\n' "$@"; }
{ preset 0 LinuxNoFilter Linux true "" 0; preset 1 LinuxFilter Linux false "*.cfg" 1; preset 2 Windows "Windows Desktop" true "" 2; } > "$P/export_presets.cfg"
timeout 120 "$G" --headless --path "$P" --import > /dev/null 2>&1
echo "== run from project (no export)"; timeout 60 "$G" --headless --path "$P" 2>&1 | grep PROBE
for pr in LinuxNoFilter LinuxFilter Windows; do
  echo "== --export-pack $pr, then --main-pack"
  OPENRC_VERSION=v0.1.0-rc2-5-gabc1234 OPENRC_COMMIT=abc1234 timeout 120 "$G" --headless --path "$P" --export-pack "$pr" "out/$pr.pck" 2>&1 | grep -E "PLUGIN|ERROR" || true
  (cd "$P/out" && timeout 60 "$G" --headless --main-pack "$P/out/$pr.pck" 2>&1 | grep PROBE)
done
echo "== override.cfg next to the pack changes config/version"
cp "$P/out/LinuxNoFilter.pck" "$P/ov/"; printf '[application]\nconfig/version="9.9.9-spoof"\n' > "$P/ov/override.cfg"
(cd "$P/ov" && timeout 60 "$G" --headless --main-pack "$P/ov/LinuxNoFilter.pck" 2>&1 | grep -E "config/version|build_info")
