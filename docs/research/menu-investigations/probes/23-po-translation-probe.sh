#!/usr/bin/env bash
# Probe for UI-01d (English by default, Spanish catalog). Throwaway project in a temp dir, never app/.
# Checks with the pinned Godot 4.7.2: (1) a gettext .po listed in internationalization/locale/translations loads
# from a fresh project with no import step (no .godot/), (2) it is packed by --export-pack with export_filter
# all_resources and no include_filter, (3) which locale the engine picks by itself under LANG=es_ES.UTF-8.
# Usage: docs/research/menu-investigations/probes/23-po-translation-probe.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../../.." && pwd)"
G="$ROOT/.tools/Godot_v4.7.2-stable_linux.x86_64"
P="$(mktemp -d)"; trap 'rm -rf "$P"' EXIT
export XDG_CONFIG_HOME="$P/xdg/config" XDG_DATA_HOME="$P/xdg/data" XDG_CACHE_HOME="$P/xdg/cache"
mkdir -p "$P/i18n" "$P/out"
cat > "$P/project.godot" <<'EOF'
config_version=5
[application]
config/name="Probe23"
run/main_scene="res://main.tscn"
config/features=PackedStringArray("4.7")
[internationalization]
locale/translations=PackedStringArray("res://i18n/es.po")
EOF
printf '[gd_scene format=3]\n[ext_resource type="Script" path="res://main.gd" id="1"]\n[node name="Main" type="Node"]\nscript = ExtResource("1")\n' > "$P/main.tscn"
cat > "$P/main.gd" <<'EOF'
extends Node
func _ready() -> void:
	print("PROBE engine locale at start = ", TranslationServer.get_locale())
	print("PROBE loaded locales = ", TranslationServer.get_loaded_locales())
	var b := Button.new()
	b.text = "Fly"
	add_child(b)
	TranslationServer.set_locale("es")
	await get_tree().process_frame
	print("PROBE es: tr(Fly) = ", tr("Fly"), "  auto-translated Button = ", b.text, " / shown ", b.get_text())
	TranslationServer.set_locale("en")
	print("PROBE en: tr(Fly) = ", tr("Fly"))
	get_tree().quit()
EOF
cat > "$P/i18n/es.po" <<'EOF'
msgid ""
msgstr ""
"Language: es\n"
"Content-Type: text/plain; charset=UTF-8\n"

msgid "Fly"
msgstr "Volar"
EOF
printf '[preset.0]\nname="Linux"\nplatform="Linux"\nrunnable=true\nexport_filter="all_resources"\ninclude_filter=""\nexclude_filter=""\nexport_path="out/x"\n[preset.0.options]\nbinary_format/embed_pck=false\n' > "$P/export_presets.cfg"
echo "== fresh project, no import, LANG=es_ES.UTF-8"
LANG=es_ES.UTF-8 timeout 60 "$G" --headless --path "$P" 2>&1 | grep -E "PROBE|ERROR"
echo "== --export-pack (all_resources, no include_filter), then run the pack"
timeout 120 "$G" --headless --path "$P" --export-pack Linux "out/x.pck" > "$P/export.log" 2>&1 || { cat "$P/export.log"; exit 1; }
grep -E "ERROR" "$P/export.log" || true
(cd "$P/out" && LANG=en_US.UTF-8 timeout 60 "$G" --headless --main-pack "$P/out/x.pck" 2>&1 | grep -E "PROBE|ERROR")
