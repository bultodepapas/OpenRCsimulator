# Sonda de investigación 16 (tipografía). No forma parte de app/.
# Uso: Godot --headless --script font_probe.gd -- <fuente1.ttf> [<fuente2.ttf> ...]
# Informa la fuente predeterminada de Godot, cómo resuelve SystemFont "monospace",
# cobertura de glifos españoles/HUD y si la característica OpenType tnum iguala cifras.
extends SceneTree

const GLYPHS := "áéíóúüñÁÉÍÓÚÜÑ¿¡°±·×"
const DIGITS := "0123456789"


func _digit_widths(font: Font, size: int) -> Array:
	var widths := {}
	for d in DIGITS:
		widths[snappedf(font.get_string_size(d, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x, 0.01)] = true
	var out := widths.keys()
	out.sort()
	return out


func _report(label: String, font: Font) -> void:
	var missing := ""
	for c in GLYPHS:
		if not font.has_char(c.unicode_at(0)):
			missing += c
	var tnum := FontVariation.new()
	tnum.base_font = font
	var ts := TextServerManager.get_primary_interface()
	tnum.opentype_features = {ts.name_to_tag("tnum"): 1}
	print("%s | name=%s | missing=[%s] | digit_widths@32=%s | with tnum=%s" % [
		label, font.get_font_name(), missing, _digit_widths(font, 32), _digit_widths(tnum, 32)])


func _init() -> void:
	print("engine=", Engine.get_version_info().string, " text_server=", TextServerManager.get_primary_interface().get_name())
	_report("ThemeDB.fallback_font", ThemeDB.fallback_font)
	print("ThemeDB.fallback_font_size=", ThemeDB.fallback_font_size)
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["monospace"])
	_report("SystemFont(monospace)", mono)
	for key in ["gui/theme/custom_font", "gui/theme/default_font_antialiasing", "gui/theme/default_font_hinting",
			"gui/theme/default_font_subpixel_positioning", "gui/theme/default_font_multichannel_signed_distance_field",
			"gui/theme/default_font_generate_mipmaps", "gui/theme/lcd_subpixel_layout", "gui/fonts/dynamic_fonts/use_oversampling"]:
		print(key, " = ", ProjectSettings.get_setting(key, "<absent>"))
	for path in OS.get_cmdline_user_args():
		var f := FontFile.new()
		var err := f.load_dynamic_font(path)
		if err != OK:
			print(path.get_file(), " | load error ", err)
			continue
		_report(path.get_file(), f)
		var msdf := FontFile.new()
		msdf.load_dynamic_font(path)
		msdf.multichannel_signed_distance_field = true
		var w400 := FontVariation.new()
		w400.base_font = f
		w400.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 400}
		var w700 := FontVariation.new()
		w700.base_font = f
		w700.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 700}
		print("   default wght: '0000'@32 width=", f.get_string_size("0000", 0, -1, 32).x, " wght400=", w400.get_string_size("0000", 0, -1, 32).x, " wght700=", w700.get_string_size("0000", 0, -1, 32).x, " supported axes=", f.get_supported_variation_list())
		print("   msdf=", msdf.multichannel_signed_distance_field, " size('Volar')@16=", f.get_string_size("Volar", 0, -1, 16), " msdf@16=", msdf.get_string_size("Volar", 0, -1, 16))
	quit()
