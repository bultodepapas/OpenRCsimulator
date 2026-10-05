# On-screen input panel: raw -> command -> surface angle, for every channel.
extends RefCounted

const Commands := preload("res://input/commands.gd")


## Returns the Label to update; adds a CanvasLayer overlay to `parent`.
static func create(parent: Node) -> Label:
	var box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.6)
	style.set_corner_radius_all(4)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	box.add_theme_stylebox_override("panel", style)
	box.position = Vector2(8, 8)
	var label := Label.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["monospace"])
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", 13)
	box.add_child(label)
	var layer := CanvasLayer.new()
	layer.add_child(box)
	parent.add_child(layer)
	return label


static func _f(v: float, decimals := 2) -> String:
	return ("+" if v >= 0 else "") + String.num(v, decimals).pad_decimals(decimals)


## c: stick commands; flown: commands actually applied (stick + trims). Surfaces show what the airplane really does.
## throws_deg: the aircraft's maximum throws ({} = the data file's).
static func update(label: Label, raw: Dictionary, c: Dictionary, view: String, status := "", flown := {}, throws_deg := {}) -> void:
	var s := Commands.surface_deflections_deg(flown if not flown.is_empty() else c, throws_deg)
	label.text = "\n".join([
		"channel   raw   command  surface",
		"roll     %s    %s   R ail %s°" % [_f(raw.roll, 0), _f(c.roll), _f(s.aileron_right, 1)],
		"pitch    %s    %s   elev  %s°" % [_f(raw.pitch, 0), _f(c.pitch), _f(s.elevator, 1)],
		"yaw      %s    %s   rud   %s°" % [_f(raw.yaw, 0), _f(c.yaw), _f(s.rudder, 1)],
		"throttle %s    %s%%" % [_f(raw.throttle, 0), str(roundi(c.throttle * 100)).lpad(4)],
		"view: %s   [C] view  [R] reset" % view,
	]) + ("\n" + status if status != "" else "")
