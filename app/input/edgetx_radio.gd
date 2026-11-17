extends RefCounted
## DR-14d: identity of EdgeTX/OpenTX radios in USB joystick mode, for the FPV quad's preconfigured draft
## (docs/plans/drone-racing.md §17.1). Only chooses a starting draft in Controls: a saved profile is never rewritten,
## and the radio's primary channels still require calibration before flight.

const JetiRadio := preload("res://input/jeti_radio.gd")

## The USB pair every EdgeTX radio reports in joystick mode (EdgeTX "Joystick mapping information for game
## developers").
const VENDOR_ID := 0x1209
const PRODUCT_ID := 0x4F54
## Names of radio families that run EdgeTX or OpenTX (lower case, matched as substrings).
const FAMILY_NAMES := ["edgetx", "opentx", "radiomaster", "jumper", "taranis", "betafpv", "horus", "zorro", "boxer",
	"pocket", "tx16s", "tx12", "t-pro", "t20", "t-lite", "x9 lite", "x-lite"]


## True for the EdgeTX USB pair or an EdgeTX/OpenTX family name; never for a JETI identity claim.
static func matches(info: Dictionary) -> bool:
	if JetiRadio.has_jeti_identity_claim(info):
		return false
	if JetiRadio.normalize_usb_id(info.get("vendor_id", 0)) == VENDOR_ID \
			and JetiRadio.normalize_usb_id(info.get("product_id", 0)) == PRODUCT_ID:
		return true
	for field: String in ["name", "raw_name", "manufacturer"]:
		var text := str(info.get(field, "")).to_lower()
		for family: String in FAMILY_NAMES:
			if family in text:
				return true
	return false
