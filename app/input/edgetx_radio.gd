extends RefCounted
## DR-14d: identity of EdgeTX/OpenTX radios in USB joystick mode, for the FPV quad's preconfigured draft
## (docs/plans/drone-racing.md §17.1). Only chooses a starting draft in Controls: a saved profile is never rewritten,
## and the radio's primary channels still require calibration before flight.
## D6-ETX-01/02 (docs/plans/edgetx-airplane-controls.md): device classification by the USB pair, and the OpenRC EdgeTX
## airplane layout that the Setup assistant's switch check, the control guide and Help present.

const JetiRadio := preload("res://input/jeti_radio.gd")

## The USB pair every EdgeTX radio reports in joystick mode (EdgeTX "Joystick mapping information for game
## developers").
const VENDOR_ID := 0x1209
const PRODUCT_ID := 0x4F54
## Names of radio families that run EdgeTX or OpenTX (lower case, matched as substrings).
const FAMILY_NAMES := ["edgetx", "opentx", "radiomaster", "jumper", "taranis", "betafpv", "horus", "zorro", "boxer",
	"pocket", "tx16s", "tx12", "t-pro", "t20", "t-lite", "x9 lite", "x-lite"]

## D6-ETX-02: the OpenRC EdgeTX airplane layout v1. A recommendation for the radio's mixer, never a trusted mapping:
## the switch check binds whichever control actually moves. `channel` is the radio channel; `switch` the suggested
## source (EdgeTX Plane-wizard default where it has one); `off` the safe position the check asks for first; `prefer`
## the expected Classic transport. Classic sends CH1-CH8 as axes and CH9-CH32 as buttons pressed when the channel
## is above 0 (EdgeTX radio/src/usb_joystick.cpp, docs/research/radio-input/D6-ETX-00).
const AIRPLANE_LAYOUT := [
	{"id": "aux:gear", "channel": 5, "switch": "SD", "off": "DOWN (gear down)", "prefer": "axis"},
	{"id": "aux:flaps", "channel": 6, "switch": "SA", "off": "UP (flaps up)", "prefer": "axis"},
	{"id": "aux:smoke", "channel": 10, "switch": "SE", "off": "OFF (smoke off)", "prefer": "button"},
	{"id": "aux:rates", "channel": 7, "switch": "SC", "off": "LOW (normal rates)", "prefer": "axis", "simulated_rates": true},
	{"id": "restart_flight", "channel": 9, "switch": "SH", "off": "released", "prefer": "button"},
]
## D6-ETX-06: the quad channel that shares each airplane switch in one EdgeTX profile, with the quad's own DR-14d
## endpoints (arm only at the high end; flight mode low Angle, middle and high Acro). Only the axis is shared.
const QUAD_SHARED_AUX := {
	"gear": {"aux": "arm", "off": 0.0, "on": 1.0},
	"flaps": {"aux": "flight_mode", "off": -1.0, "on": 1.0},
}
const PRESETS: PackedStringArray = ["edgetx_airplane", "edgetx_fpv"]
## Functions that stay on the radio with this layout (shown in Help and the control guide).
const RADIO_OWNED_SWITCHES := {"throttle_cut": "SF", "dual_rates": "SC"}


## True for the EdgeTX USB pair or an EdgeTX/OpenTX family name; never for a JETI identity claim.
static func matches(info: Dictionary) -> bool:
	if JetiRadio.has_jeti_identity_claim(info):
		return false
	if usb_pair_matches(info):
		return true
	for field: String in ["name", "raw_name", "manufacturer"]:
		var text := str(info.get(field, "")).to_lower()
		for family: String in FAMILY_NAMES:
			if family in text:
				return true
	return false


## The complete EdgeTX/OpenTX joystick USB pair (integer, decimal-string or hexadecimal-string IDs).
static func usb_pair_matches(info: Dictionary) -> bool:
	return JetiRadio.normalize_usb_id(info.get("vendor_id", -1)) == VENDOR_ID \
		and JetiRadio.normalize_usb_id(info.get("product_id", -1)) == PRODUCT_ID


## D6-ETX-01: whether a device may be classified as a radio from its identity alone. Only the USB pair counts (the
## family names are broad: "pocket", "boxer"), never for a JETI claim, and never for a device SDL already reports as
## a known gamepad (Linux Classic): reclassifying those waits for hardware evidence (F1-ETX-01) and an owner decision.
static func classifies_as_radio(info: Dictionary) -> bool:
	return usb_pair_matches(info) and not JetiRadio.has_jeti_identity_claim(info) and not bool(info.get("known", false))


## The layout entry for an assistant/AUX id ("aux:gear", "restart_flight"), or {}.
static func layout_entry(id: String) -> Dictionary:
	for entry: Dictionary in AIRPLANE_LAYOUT:
		if str(entry.id) == id:
			return entry
	return {}


## The radio channel a Classic control would carry on a raw (non-gamepad) joystick: axis N = CH(N+1) for the eight
## axes, button N = CH(N+9) for the 24 buttons; 0 when the binding is neither.
static func classic_channel(binding: Dictionary) -> int:
	match str(binding.get("type", "")):
		"axis":
			var axis := int(binding.get("axis", -1))
			return axis + 1 if axis >= 0 and axis < 8 else 0
		"button":
			var button := int(binding.get("button", -1))
			return button + 9 if button >= 0 and button < 24 else 0
	return 0
