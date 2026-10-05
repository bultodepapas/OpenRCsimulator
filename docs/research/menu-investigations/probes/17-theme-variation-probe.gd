# Investigation 17 probe: build a Theme in code, resolve a type variation, check contrast from the real Theme.
# Not part of the app. Run with the pinned binary from a throwaway project directory (never app/):
#   godot --headless --path <tmp_project> --script <this file> -- --out=<dir>
# Optional second pass: set gui/theme/custom="res://ui_theme.tres" in <tmp_project>/project.godot and add --project-theme.
extends SceneTree

const PALETTE := {
	"panel": "#17252A", "text": "#F5F2E9", "secondary": "#BBC8C6",
	"accent": "#B6322E", "focus": "#F5C65D", "button": "#2A3B41",
}
const TEXT_TARGET := 4.5
const NONTEXT_TARGET := 3.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame # theme owners propagate once the nodes are in the running tree
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	print("engine ", Engine.get_version_info().string)
	var failures := 0
	if args.has("project-theme"):
		failures += _check_project_theme()
	else:
		failures += _check_variation(build_theme(1.0))
		failures += _check_scale()
		failures += await _check_window_theme()
		if args.has("out"):
			failures += _check_saved(args["out"])
		failures += await _check_default_merge() # last: mutates the engine-wide default theme
	print("RESULT ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	quit(1 if failures else 0)


## The whole theme from a palette and a scale; every size is multiplied once, here.
static func build_theme(scale: float) -> Theme:
	var t := Theme.new()
	t.default_font_size = roundi(18 * scale)
	t.set_stylebox("panel", "PanelContainer", _box(PALETTE.panel, 16, scale))
	t.set_stylebox("normal", "Button", _box(PALETTE.button, 10, scale))
	t.set_stylebox("hover", "Button", _box("#34484F", 10, scale))
	t.set_stylebox("pressed", "Button", _box("#203035", 10, scale))
	t.set_stylebox("focus", "Button", _focus_ring(scale))
	t.set_color("font_color", "Button", Color(PALETTE.text))
	t.set_color("font_focus_color", "Button", Color(PALETTE.text))
	t.set_type_variation("PrimaryButton", "Button")
	t.set_stylebox("normal", "PrimaryButton", _box(PALETTE.accent, 14, scale))
	t.set_stylebox("hover", "PrimaryButton", _box("#C43B36", 14, scale))
	t.set_stylebox("pressed", "PrimaryButton", _box("#9A2A27", 14, scale))
	t.set_font_size("font_size", "PrimaryButton", roundi(24 * scale))
	return t


## Stable sub-resource ids ("Button_normal") so a re-generated .tres only diffs where a value changed.
static func stable_ids(t: Theme) -> Theme:
	for type in t.get_stylebox_type_list():
		for item in t.get_stylebox_list(type):
			t.get_stylebox(item, type).resource_scene_unique_id = "%s_%s" % [type, item]
	return t


static func _box(hex: String, margin: float, scale: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(hex)
	s.set_corner_radius_all(roundi(6 * scale))
	s.set_content_margin_all(margin * scale)
	return s


static func _focus_ring(scale: float) -> StyleBoxFlat:
	# Drawn over the base stylebox: no fill, border outside the rect so it never hides the label.
	var s := StyleBoxFlat.new()
	s.draw_center = false
	s.border_color = Color(PALETTE.focus)
	s.set_border_width_all(roundi(3 * scale))
	s.set_expand_margin_all(4 * scale)
	s.set_corner_radius_all(roundi(8 * scale))
	return s


static func contrast(a: Color, b: Color) -> float:
	var la := _lum(a)
	var lb := _lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func _lum(c: Color) -> float:
	var ch := [c.r, c.g, c.b]
	for i in 3:
		ch[i] = ch[i] / 12.92 if ch[i] <= 0.04045 else pow((ch[i] + 0.055) / 1.055, 2.4)
	return 0.2126 * ch[0] + 0.7152 * ch[1] + 0.0722 * ch[2]


func _check_variation(t: Theme) -> int:
	var f := 0
	var holder := PanelContainer.new()
	holder.theme = t
	var plain := Button.new()
	plain.text = "Ajustes"
	var fly := Button.new()
	fly.text = "Volar"
	fly.theme_type_variation = &"PrimaryButton"
	var box := VBoxContainer.new()
	box.add_child(fly)
	box.add_child(plain)
	holder.add_child(box)
	root.add_child(holder)
	print("variation base: ", t.get_type_variation_base("PrimaryButton"))
	var fly_bg := (fly.get_theme_stylebox("normal") as StyleBoxFlat).bg_color
	var plain_bg := (plain.get_theme_stylebox("normal") as StyleBoxFlat).bg_color
	var panel_bg := (holder.get_theme_stylebox("panel") as StyleBoxFlat).bg_color
	var fly_text := fly.get_theme_color("font_color")
	var ring := fly.get_theme_stylebox("focus") as StyleBoxFlat
	print("Volar normal bg ", fly_bg.to_html(false), "  Ajustes normal bg ", plain_bg.to_html(false))
	print("Volar font_color ", fly_text.to_html(false), " (inherited from Button)")
	print("Volar focus inherited: ", ring == plain.get_theme_stylebox("focus"), " border ", ring.border_color.to_html(false), " draw_center ", ring.draw_center)
	print("font_size Volar ", fly.get_theme_font_size("font_size"), "  Ajustes ", plain.get_theme_font_size("font_size"))
	f += _expect(fly_bg == Color(PALETTE.accent) and plain_bg == Color(PALETTE.button), "variation overrides normal only")
	# Contrast read back from the resolved Theme, not from a palette copy.
	var pairs := [
		["text/PrimaryButton", fly_text, fly_bg, TEXT_TARGET],
		["text/Button", plain.get_theme_color("font_color"), plain_bg, TEXT_TARGET],
		["focus/panel", ring.border_color, panel_bg, NONTEXT_TARGET],
		["focus/Button", ring.border_color, plain_bg, NONTEXT_TARGET],
		["accent/panel", fly_bg, panel_bg, NONTEXT_TARGET],
	]
	for p in pairs:
		var r := contrast(p[1], p[2])
		print("contrast %-18s %6.3f:1 target %.1f %s" % [p[0], r, p[3], "ok" if r >= p[3] else "BELOW"])
	f += _expect(contrast(fly_text, fly_bg) >= TEXT_TARGET, "Volar label contrast")
	f += _expect(contrast(ring.border_color, panel_bg) >= NONTEXT_TARGET, "focus ring contrast")
	holder.queue_free()
	return f


func _check_scale() -> int:
	var f := 0
	for scale in [1.0, 1.5, 2.0]:
		var t := build_theme(scale)
		var b := Button.new()
		b.text = "Volar"
		b.theme = t
		b.theme_type_variation = &"PrimaryButton"
		root.add_child(b)
		print("scale %.1f: font_size %d  min_size %s  focus border %d" % [scale, b.get_theme_font_size("font_size"), b.get_combined_minimum_size(), (b.get_theme_stylebox("focus") as StyleBoxFlat).border_width_left])
		b.free()
	print("root visible rect at content_scale_factor 1.0: ", root.get_visible_rect().size)
	root.content_scale_factor = 2.0
	print("root visible rect at content_scale_factor 2.0: ", root.get_visible_rect().size, " (layout space a 200 % UI must fit)")
	var b2 := Button.new()
	b2.text = "Volar"
	b2.theme = build_theme(1.0)
	b2.theme_type_variation = &"PrimaryButton"
	root.add_child(b2)
	print("content_scale_factor 2.0 + theme 1.0: font_size %d  min_size %s (logical units unchanged)" % [b2.get_theme_font_size("font_size"), b2.get_combined_minimum_size()])
	b2.free()
	root.content_scale_factor = 1.0
	return f


## Where a code-only theme must be attached: root Window vs a Control parent, with and without a CanvasLayer between.
func _check_window_theme() -> int:
	root.theme = build_theme(1.0)
	var direct := _primary()
	root.add_child(direct)
	var layer := CanvasLayer.new()
	var layered := _primary()
	layer.add_child(layered)
	root.add_child(layer)
	var layer2 := CanvasLayer.new()
	var holder := Control.new()
	holder.theme = build_theme(1.0)
	var held := _primary()
	holder.add_child(held)
	layer2.add_child(holder)
	root.add_child(layer2)
	await process_frame
	print("root Window.theme -> direct Button: ", _bg(direct), "; CanvasLayer/Button: ", _bg(layered))
	print("CanvasLayer/Control(theme)/Button: ", _bg(held))
	var f := _expect(_bg(direct) == PALETTE.accent.trim_prefix("#").to_lower(), "Window.theme reaches a direct child")
	f += _expect(_bg(held) == PALETTE.accent.trim_prefix("#").to_lower(), "Control.theme under a CanvasLayer")
	for n in [direct, layer, layer2]:
		n.free()
	root.theme = null
	return f


## Alternative to gui/theme/custom for a code-only theme: merge into the engine default theme (global, last in lookup).
func _check_default_merge() -> int:
	ThemeDB.get_default_theme().merge_with(build_theme(1.0))
	var layer := CanvasLayer.new()
	var fly := _primary()
	layer.add_child(fly)
	root.add_child(layer)
	await process_frame
	print("default theme merged -> CanvasLayer/Button: ", _bg(fly))
	var f := _expect(_bg(fly) == PALETTE.accent.trim_prefix("#").to_lower(), "merged default theme reaches CanvasLayer")
	layer.free()
	return f


func _primary() -> Button:
	var b := Button.new()
	b.theme_type_variation = &"PrimaryButton"
	return b


func _bg(b: Button) -> String:
	return (b.get_theme_stylebox("normal") as StyleBoxFlat).bg_color.to_html(false)


func _check_saved(dir: String) -> int:
	var f := 0
	var a := dir.path_join("ui_theme.tres")
	var b := dir.path_join("ui_theme_again.tres")
	f += _expect(ResourceSaver.save(build_theme(1.0), a) == OK, "save a")
	f += _expect(ResourceSaver.save(build_theme(1.0), b) == OK, "save b")
	var ta := FileAccess.get_file_as_string(a)
	var tb := FileAccess.get_file_as_string(b)
	print("saved %s: %d lines; identical to a second build: %s" % [a.get_file(), ta.count("\n"), ta == tb])
	var c := dir.path_join("ui_theme_stable.tres")
	var d := dir.path_join("ui_theme_stable_again.tres")
	f += _expect(ResourceSaver.save(stable_ids(build_theme(1.0)), c) == OK, "save c")
	f += _expect(ResourceSaver.save(stable_ids(build_theme(1.0)), d) == OK, "save d")
	var same := FileAccess.get_file_as_string(c) == FileAccess.get_file_as_string(d)
	print("with stable ids, identical to a second build: ", same)
	f += _expect(same, "deterministic .tres with stable ids")
	var back := ResourceLoader.load(a, "", ResourceLoader.CACHE_MODE_IGNORE) as Theme
	f += _expect(back.get_type_variation_base("PrimaryButton") == &"Button", "variation survives .tres round trip")
	return f


func _check_project_theme() -> int:
	var pt := ThemeDB.get_project_theme()
	print("project theme: ", pt.resource_path if pt else "<none>")
	var fly := Button.new()
	fly.theme_type_variation = &"PrimaryButton"
	root.add_child(fly)
	var bg := (fly.get_theme_stylebox("normal") as StyleBoxFlat).bg_color
	print("Volar with no theme on any ancestor: normal bg ", bg.to_html(false))
	return _expect(bg == Color(PALETTE.accent), "gui/theme/custom resolves PrimaryButton")


func _expect(ok: bool, what: String) -> int:
	if not ok:
		print("FAIL: ", what)
	return 0 if ok else 1
