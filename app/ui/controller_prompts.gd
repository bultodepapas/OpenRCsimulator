class_name ControllerPrompts
extends RefCounted

## Presentation-only controller glyph selection. This class never changes a binding or
## translates a displayed symbol back into an input event.
const FAMILIES: PackedStringArray = ["auto", "xbox", "playstation", "nintendo", "generic"]

const _ASSET_ROOT := "res://assets/input_prompts"
const _ControllerActions = preload("res://input/controller_actions.gd")
const _SmokeAux = preload("res://input/smoke_aux.gd")
const _JetiRadio = preload("res://input/jeti_radio.gd")
const _VENDOR_FAMILY := {
	0x045E: "xbox", # Microsoft
	0x054C: "playstation", # Sony
	0x057E: "nintendo", # Nintendo
}


## Resolve a manual family override first. Automatic detection uses only an explicit vendor ID
## or unambiguous product naming; backend labels such as XInput and the `known` flag are ignored.
static func resolve_family(requested_family: String, device_info: Dictionary) -> String:
	var requested := requested_family.strip_edges().to_lower()
	if requested != "auto":
		return requested if requested in ["xbox", "playstation", "nintendo", "generic"] else "generic"
	if _identity_is_ambiguous_or_emulated(device_info):
		return "generic"
	var vendor_id := _uint_field(_info_value(device_info, "vendor_id", 0))
	if _VENDOR_FAMILY.has(vendor_id):
		return str(_VENDOR_FAMILY[vendor_id])
	var identity := ("%s %s %s" % [
		str(_info_value(device_info, "name", "")),
		str(_info_value(device_info, "raw_name", "")),
		str(_info_value(device_info, "manufacturer", "")),
	]).to_lower()
	if identity.contains("xbox") or identity.contains("x-box"):
		return "xbox"
	if identity.contains("playstation") or identity.contains("dualshock") \
			or identity.contains("dualsense") or identity.contains("ps4 controller") \
			or identity.contains("ps5 controller"):
		return "playstation"
	if identity.contains("nintendo") or identity.contains("joy-con") \
			or identity.contains("joycon") or identity.contains("switch pro controller") \
			or identity.contains("switch controller"):
		return "nintendo"
	return "generic"


## Return a readable label and optional Kenney vector path for the supplied current binding.
## A texture is selected from the physical button index, so remapped controls display correctly.
static func prompt(binding: Dictionary, requested_family: String, device_info: Dictionary,
		profile: Dictionary = {}) -> Dictionary:
	if str(binding.get("type", "")) == "switch":
		return {"text": _switch_binding_text(binding), "texture_path": ""}
	if _is_radio(binding, device_info, profile) and str(binding.get("type", "")) == "button":
		return {"text": _radio_button_text(binding, profile), "texture_path": ""}
	var family := resolve_family(requested_family, device_info)
	var text := _binding_text(binding, family)
	var texture_path := ""
	if str(binding.get("type", "")) == "button":
		var semantic := _button_semantic(int(binding.get("button", -1)))
		if not semantic.is_empty():
			texture_path = _button_texture(family, semantic)
	return {"text": text, "texture_path": texture_path}


static func _switch_binding_text(binding: Dictionary) -> String:
	if not _SmokeAux.valid_binding(binding):
		return TranslationServer.translate("Invalid switch group.")
	var group_name := str(binding.get("label", "")).strip_edges()
	if group_name.is_empty():
		group_name = TranslationServer.translate("Switch")
	var buttons: Array = _SmokeAux.bound_buttons(binding)
	var positions := ["Up", "Down"] if buttons.size() == 2 else ["Up", "Middle", "Down"]
	var entries := PackedStringArray()
	for index in buttons.size():
		entries.append(TranslationServer.translate("%s %s · Button %d") % [
			group_name, TranslationServer.translate(positions[index]), int(buttons[index]),
		])
	return " / ".join(entries)


static func _is_radio(_binding: Dictionary, device_info: Dictionary, profile: Dictionary) -> bool:
	return str(profile.get("kind", "")) == "radio" \
		or str(device_info.get("kind", "")) == "radio" \
		or _JetiRadio.matches(device_info) \
		or _JetiRadio.has_jeti_identity_claim(device_info)


static func _radio_button_text(binding: Dictionary, profile: Dictionary) -> String:
	var button := int(binding.get("button", -1))
	var aux_value: Variant = profile.get("aux", {})
	if aux_value is Dictionary:
		for aux_name in ["smoke", "flaps", "gear"]:
			var aux_binding: Variant = aux_value.get(aux_name, {})
			if not aux_binding is Dictionary or str(aux_binding.get("type", "")) != "switch" \
					or not _SmokeAux.valid_binding(aux_binding):
				continue
			var buttons: Array = _SmokeAux.bound_buttons(aux_binding)
			var position_index := buttons.find(button)
			if position_index < 0:
				continue
			var positions := ["Up", "Down"] if buttons.size() == 2 else ["Up", "Middle", "Down"]
			var group_name := str(aux_binding.get("label", "")).strip_edges()
			if group_name.is_empty():
				break
			return TranslationServer.translate("%s %s · Button %d") % [group_name, TranslationServer.translate(positions[position_index]), button]
	return TranslationServer.translate("Button %d") % button


static func _binding_text(binding: Dictionary, family: String) -> String:
	if str(binding.get("type", "")) != "button":
		return _ControllerActions.binding_text(binding)
	var semantic := _button_semantic(int(binding.get("button", -1)))
	match semantic:
		"face_bottom":
			return _face_text(family, "bottom")
		"face_right":
			return _face_text(family, "right")
		"face_left":
			return _face_text(family, "left")
		"face_top":
			return _face_text(family, "top")
		"menu":
			return _family_text(family, "Menu", "Options", "Plus", "Menu")
		"back":
			return _family_text(family, "Back", "Share", "Minus", "Back")
		"shoulder_left":
			return _family_text(family, "LB", "L1", "L", "Left shoulder")
		"shoulder_right":
			return _family_text(family, "RB", "R1", "R", "Right shoulder")
		"stick_left_press":
			return _family_text(family, "Left stick press", "L3", "Left stick press", "Left stick press")
		"stick_right_press":
			return _family_text(family, "Right stick press", "R3", "Right stick press", "Right stick press")
		"dpad_up":
			return TranslationServer.translate("D-pad up")
		"dpad_down":
			return TranslationServer.translate("D-pad down")
		"dpad_left":
			return TranslationServer.translate("D-pad left")
		"dpad_right":
			return TranslationServer.translate("D-pad right")
	return _ControllerActions.binding_text(binding)


static func _face_text(family: String, position: String) -> String:
	match family:
		"xbox":
			return TranslationServer.translate({"bottom": "A", "right": "B", "left": "X", "top": "Y"}[position])
		"playstation":
			return TranslationServer.translate({"bottom": "Cross", "right": "Circle", "left": "Square", "top": "Triangle"}[position])
		"nintendo":
			return TranslationServer.translate({"bottom": "B", "right": "A", "left": "Y", "top": "X"}[position])
		_:
			return TranslationServer.translate({
				"bottom": "Bottom face button", "right": "Right face button",
				"left": "Left face button", "top": "Top face button",
			}[position])


static func _family_text(family: String, xbox_text: String, playstation_text: String,
		nintendo_text: String, generic_text: String) -> String:
	match family:
		"xbox":
			return TranslationServer.translate(xbox_text)
		"playstation":
			return TranslationServer.translate(playstation_text)
		"nintendo":
			return TranslationServer.translate(nintendo_text)
		_:
			return TranslationServer.translate(generic_text)


static func _button_texture(family: String, semantic: String) -> String:
	var file_name := semantic + ".svg"
	if family == "generic":
		match semantic:
			"stick_left_press", "stick_right_press":
				file_name = "stick_press.svg"
			"shoulder_left":
				file_name = "shoulder_left.svg"
			"shoulder_right":
				file_name = "shoulder_right.svg"
			_:
				file_name = "button.svg"
	return "%s/%s/%s" % [_ASSET_ROOT, family, file_name]


static func _button_semantic(button: int) -> String:
	match button:
		JOY_BUTTON_A:
			return "face_bottom"
		JOY_BUTTON_B:
			return "face_right"
		JOY_BUTTON_X:
			return "face_left"
		JOY_BUTTON_Y:
			return "face_top"
		JOY_BUTTON_BACK:
			return "back"
		JOY_BUTTON_START:
			return "menu"
		JOY_BUTTON_LEFT_SHOULDER:
			return "shoulder_left"
		JOY_BUTTON_RIGHT_SHOULDER:
			return "shoulder_right"
		JOY_BUTTON_LEFT_STICK:
			return "stick_left_press"
		JOY_BUTTON_RIGHT_STICK:
			return "stick_right_press"
		JOY_BUTTON_DPAD_UP:
			return "dpad_up"
		JOY_BUTTON_DPAD_DOWN:
			return "dpad_down"
		JOY_BUTTON_DPAD_LEFT:
			return "dpad_left"
		JOY_BUTTON_DPAD_RIGHT:
			return "dpad_right"
	return ""


static func _identity_is_ambiguous_or_emulated(device_info: Dictionary) -> bool:
	for field in ["ambiguous", "identity_ambiguous", "emulated", "is_emulated", "virtual", "is_virtual"]:
		if _truthy(_info_value(device_info, field, false)):
			return true
	var identity := ("%s %s %s %s %s" % [
		str(_info_value(device_info, "name", "")),
		str(_info_value(device_info, "raw_name", "")),
		str(_info_value(device_info, "manufacturer", "")),
		str(_info_value(device_info, "backend", "")),
		str(_info_value(device_info, "transport", "")),
	]).to_lower()
	for marker in ["virtual", "emulat", "vjoy", "vigem", "x360ce", "rewasd"]:
		if identity.contains(marker):
			return true
	return false


static func _uint_field(value: Variant) -> int:
	if value is int or value is float:
		return int(value)
	var text := str(value).strip_edges().to_lower()
	if text.begins_with("0x"):
		return text.substr(2).hex_to_int()
	for character in text:
		if "abcdef".contains(character):
			return text.hex_to_int()
	return text.to_int()


static func _truthy(value: Variant) -> bool:
	if value is bool:
		return value
	return str(value).strip_edges().to_lower() in ["true", "yes", "1"]


static func _info_value(info: Dictionary, field: String, fallback: Variant) -> Variant:
	if info.has(field):
		return info[field]
	var string_name := StringName(field)
	if info.has(string_name):
		return info[string_name]
	return fallback
