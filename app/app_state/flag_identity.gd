## L15c-F08: decorative, application-lifetime country selection, independent of simulation RNGs.
extends RefCounted

const FlagManifest := preload("res://assets/flags/manifest.gd")
const HEIGHT_M := 0.9
const FALLBACK := "US"
const LOCALE_COUNTRIES := {
	"en": "US",
	"zh_Hans": "CN",
	"fr": "FR",
	"pt_BR": "BR",
	"de": "DE",
	"it": "IT",
	"ru": "RU",
	"ja": "JP",
}

static var _shared_ref: WeakRef

var _rng := RandomNumberGenerator.new()
var _spanish_country := ""


## The application shell retains this shared instance across all scene changes.
static func shared() -> Variant:
	var instance: Variant = _shared_ref.get_ref() if _shared_ref != null else null
	if instance == null:
		instance = load("res://app_state/flag_identity.gd").new()
		_shared_ref = weakref(instance)
	return instance


## A fixed cosmetic seed is useful for tests and captures; -1 randomizes privately.
func _init(seed_value: int = -1) -> void:
	if seed_value == -1:
		_rng.randomize()
	else:
		_rng.seed = seed_value


## Accept the existing registry's supported code, not arbitrary regional aliases.
func country_for_locale(locale: String) -> String:
	if locale == "es":
		if _spanish_country.is_empty():
			var choices := spanish_countries()
			_spanish_country = choices[_rng.randi_range(0, choices.size() - 1)]
		return _spanish_country
	return LOCALE_COUNTRIES.get(locale, FALLBACK)


func countries() -> PackedStringArray:
	return PackedStringArray(FlagManifest.FLAGS.keys())


func spanish_countries() -> PackedStringArray:
	var result := PackedStringArray()
	for country: String in FlagManifest.FLAGS:
		if FlagManifest.FLAGS[country].spanish_selection:
			result.append(country)
	return result


## Paths only: the renderer owns bounded, on-demand texture loading and lifetimes.
## mirror_front means the same physical print is visible through the reverse side.
func descriptor(country: String) -> Dictionary:
	var code := country if FlagManifest.FLAGS.has(country) else FALLBACK
	var spec: Dictionary = FlagManifest.FLAGS[code]
	var aspect := float(spec.width) / float(spec.height)
	return {
		"country": code,
		"front_path": spec.front_path,
		"reverse_path": spec.reverse_path,
		"reverse_policy": spec.reverse_policy,
		"aspect": aspect,
		"height_m": HEIGHT_M,
		"length_m": HEIGHT_M * aspect,
	}
