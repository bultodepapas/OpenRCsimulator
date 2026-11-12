# UI-15-UX-07: the host interface of the Setup assistant (setup_assistant.gd). The owner (the Controls screen)
# extends this class, or supplies any Object with the same methods, and keeps every write in its own draft.
# The assistant only calls these methods after a click/press on its own controls; it never stores anything itself.
# Asynchronous results come back through the assistant's notify_calibration_finished() / notify_capture_finished().
# The defaults below are inert (nothing applies, nothing saves), so a partial host fails closed.
extends RefCounted


## The device being set up. Keys the assistant reads (all optional):
## display_name / name: String; kind: "gamepad" | "radio" | "joystick" (the registry's suggestion);
## known: bool (SDL recognised a gamepad); family: glyph family "auto" | "xbox" | "playstation" | "nintendo" |
## "generic"; vendor_id/raw_name/manufacturer (family detection through ControllerPrompts);
## profile_kind: the kind of an existing configured profile; preset: the draft's current preset id;
## stick_mode: 1 | 2 (presentation stick layout).
func device_info() -> Dictionary:
	return {}


## The active vehicle's capabilities, as ControllerActions uses them ({"gear": true, "helicopter": true,
## "multirotor": true, …}).
func vehicle_capabilities() -> Dictionary:
	return {}


## Step 1 (Next): make the draft profile this kind ("radio", "gamepad" or "joystick"). false keeps the step open
## and shows last_error().
func set_profile_kind(_kind: String) -> bool:
	return false


## Step 2 (Next): apply a stick layout to the draft. Gamepads: "mode1", "mode2" or "trigger_absolute"
## (ControllerProfile presets). Radios and joysticks: "mode1" or "mode2" name only the stick layout; the host keeps
## the radio profile preset (radio_custom or jeti_mode2) and its calibration.
func apply_preset(_preset_id: String) -> bool:
	return false


## Step 3 ("Start calibration" clicked): open the owner's calibration. true means it started; the owner then calls
## assistant.notify_calibration_finished(ok, message) exactly once.
func request_calibration() -> bool:
	return false


## Step 4, polled each frame only while the Test step is visible. Keys: roll, pitch, yaw (−1…1, conditioned;
## pitch +1 = stick back), throttle (0…1, or −1…1 when throttle_centered), throttle_centered: bool (a rate
## throttle stick), throttle_level: 0…1 (optional, the aircraft throttle bar), buttons: pressed JoyButton indices,
## inverted: {roll, pitch, yaw, throttle → bool} (the draft's current Reverse states).
func preview() -> Dictionary:
	return {}


## Step 4 Reverse toggle: invert one flight channel ("roll", "pitch", "yaw" or "throttle") in the draft.
func set_channel_inverted(_channel: String, _inverted: bool) -> void:
	pass


## The current draft binding for an action id ("flaps_cycle") or an AUX channel ("aux:arm"), in the shape
## ControllerActions stores ({"type": "button" | "axis" | "switch" | "key" | "unbound", …}). An optional
## "display_label" key replaces the chip's computed text.
func binding_for(_id: String) -> Dictionary:
	return {"type": "unbound"}


## Step 5 ("Assign" clicked): start the owner's press-to-assign for this id. true means capture started; the owner
## consumes the captured input and its release, then calls assistant.notify_capture_finished(id, ok, message).
func capture(_id: String) -> bool:
	return false


## Step 6 (Save): the owner's transactional Save of its draft. false keeps the assistant open on Summary.
func save() -> bool:
	return false


## A translated, user-facing reason for the last false result.
func last_error() -> String:
	return ""
