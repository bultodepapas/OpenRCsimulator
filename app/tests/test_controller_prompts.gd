extends SceneTree

const Prompts := preload("res://ui/controller_prompts.gd")
const Actions := preload("res://input/controller_actions.gd")

var checks := 0
var failures := 0


func _check(label: String, condition: bool, detail: String = "") -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func _initialize() -> void:
	_check("explicit Xbox VID is detected", Prompts.resolve_family("auto", {"vendor_id": 1118}) == "xbox")
	_check("hex Sony VID is detected", Prompts.resolve_family("auto", {"vendor_id": "0x054c"}) == "playstation")
	_check("Nintendo VID is detected from decimal string", Prompts.resolve_family("auto", {"vendor_id": "1406"}) == "nintendo")
	_check("strong Xbox product name is detected", Prompts.resolve_family("auto", {"raw_name": "Xbox Wireless Controller"}) == "xbox")
	_check("strong PlayStation product name is detected", Prompts.resolve_family("auto", {"name": "Sony DualSense Wireless Controller"}) == "playstation")
	_check("known flag alone does not brand generic device", Prompts.resolve_family("auto", {"known": true}) == "generic")
	_check("XInput backend alone does not brand device", Prompts.resolve_family("auto", {"backend": "xinput", "known": true}) == "generic")
	_check("ambiguous identity stays generic despite Xbox metadata", Prompts.resolve_family("auto", {"ambiguous": true, "vendor_id": 1118, "name": "Xbox Controller"}) == "generic")
	_check("virtual/emulated name stays generic", Prompts.resolve_family("auto", {"vendor_id": 1118, "name": "Xbox Virtual Controller"}) == "generic")
	_check("explicit emulated flag stays generic", Prompts.resolve_family("auto", {"vendor_id": 1118, "is_emulated": true}) == "generic")
	_check("manual family overrides ambiguous identity", Prompts.resolve_family("playstation", {"ambiguous": true, "vendor_id": 1118}) == "playstation")
	_check("manual override is independent of device brand", Prompts.resolve_family("nintendo", {"vendor_id": 1118}) == "nintendo")
	_check("invalid family safely falls back to generic", Prompts.resolve_family("future-brand", {}) == "generic")

	var bottom := {"type": "button", "button": JOY_BUTTON_A}
	var bottom_before := bottom.duplicate(true)
	var xbox_bottom := Prompts.prompt(bottom, "xbox", {})
	var ps_bottom := Prompts.prompt(bottom, "playstation", {})
	var switch_bottom := Prompts.prompt(bottom, "nintendo", {})
	var generic_bottom := Prompts.prompt(bottom, "generic", {})
	_check("same physical bottom button shows Xbox A", xbox_bottom.text == "A" and xbox_bottom.texture_path.ends_with("xbox/face_bottom.svg"))
	_check("same physical bottom button shows PlayStation Cross", ps_bottom.text == "Cross" and ps_bottom.texture_path.ends_with("playstation/face_bottom.svg"))
	_check("Nintendo uses B at the south position", switch_bottom.text == "B" and switch_bottom.texture_path.ends_with("nintendo/face_bottom.svg"))
	_check("generic face prompt stays positional and readable", generic_bottom.text == "Bottom face button" and generic_bottom.texture_path.ends_with("generic/button.svg"))
	_check("rendering prompt does not mutate binding", bottom == bottom_before)

	var remapped := {"type": "button", "button": JOY_BUTTON_X}
	var remapped_prompt := Prompts.prompt(remapped, "playstation", {})
	_check("glyph follows current remapped button index", remapped_prompt.text == "Square" and remapped_prompt.texture_path.ends_with("playstation/face_left.svg"))
	_check("back binding maps to family-specific prompt", Prompts.prompt({"type": "button", "button": JOY_BUTTON_BACK}, "nintendo", {}).text == "Minus")
	_check("menu binding maps to family-specific prompt", Prompts.prompt({"type": "button", "button": JOY_BUTTON_START}, "playstation", {}).text == "Options")
	_check("shoulder and stick bindings have readable labels", Prompts.prompt({"type": "button", "button": JOY_BUTTON_LEFT_SHOULDER}, "xbox", {}).text == "LB" and Prompts.prompt({"type": "button", "button": JOY_BUTTON_RIGHT_STICK}, "playstation", {}).text == "R3")

	var key_binding := {"type": "key", "keycode": KEY_SPACE}
	var axis_binding := {"type": "axis", "axis": 1, "sign": -1, "threshold": 0.65}
	var unknown_button := {"type": "button", "button": JOY_BUTTON_MAX - 1}
	_check("keyboard fallback keeps text and no glyph", Prompts.prompt(key_binding, "xbox", {}).texture_path == "" and Prompts.prompt(key_binding, "xbox", {}).text == Actions.binding_text(key_binding))
	_check("axis fallback keeps text and no glyph", Prompts.prompt(axis_binding, "playstation", {}).texture_path == "" and Prompts.prompt(axis_binding, "playstation", {}).text == Actions.binding_text(axis_binding))
	_check("unsupported button keeps text and no glyph", Prompts.prompt(unknown_button, "nintendo", {}).texture_path == "" and Prompts.prompt(unknown_button, "nintendo", {}).text == Actions.binding_text(unknown_button))

	_check_asset_coverage()
	if failures == 0:
		print("PASS controller prompts: %d checks" % checks)
	else:
		printerr("FAIL controller prompts: %d/%d checks failed" % [failures, checks])
	quit(1 if failures > 0 else 0)


func _check_asset_coverage() -> void:
	var common_buttons := [
		JOY_BUTTON_A, JOY_BUTTON_B, JOY_BUTTON_X, JOY_BUTTON_Y,
		JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER,
		JOY_BUTTON_LEFT_STICK, JOY_BUTTON_RIGHT_STICK,
		JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT,
		JOY_BUTTON_START, JOY_BUTTON_BACK,
	]
	for family in ["xbox", "playstation", "nintendo", "generic"]:
		for button in common_buttons:
			var prompt := Prompts.prompt({"type": "button", "button": button}, family, {})
			_check("%s button %d has a readable label" % [family, button], not str(prompt.text).is_empty())
			var texture_path := str(prompt.texture_path)
			var texture: Resource = ResourceLoader.load(texture_path) if not texture_path.is_empty() else null
			_check("%s button %d resolves to a packaged texture" % [family, button], texture is Texture2D, texture_path)
