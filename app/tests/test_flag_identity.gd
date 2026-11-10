## L15c-F08: application-lifetime cosmetic identity and bounded country descriptors.
extends SceneTree

const FlagIdentity := preload("res://app_state/flag_identity.gd")
const Languages := preload("res://i18n/languages.gd")

var _checks := 0
var _failures := 0


func _initialize() -> void:
	_test_locales()
	_test_spanish_identity()
	_test_rng_isolation()
	_test_manifest()
	print("flag identity tests: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _test_locales() -> void:
	var identity = FlagIdentity.new(15)
	var expected := {"en": "US", "zh_Hans": "CN", "fr": "FR", "pt_BR": "BR", "de": "DE", "it": "IT", "ru": "RU", "ja": "JP"}
	for locale: String in expected:
		_check("%s mapping" % locale, identity.country_for_locale(locale) == expected[locale])
	_check("all nine supported locale codes covered", expected.size() + 1 == Languages.NAMES.size() and Languages.NAMES.has("es"))
	for locale: String in ["", "zz", "zh", "zh_CN", "en_GB", "es_ES", "pt"]:
		_check("unsupported code %s uses US" % locale, identity.country_for_locale(locale) == "US")
	_check("unknown country uses US", identity.descriptor("PY") == identity.descriptor("US"))


func _test_spanish_identity() -> void:
	var identity = FlagIdentity.new(437)
	var peer = FlagIdentity.new(437)
	var chosen: String = identity.country_for_locale("es")
	_check("seed reproducible", chosen == peer.country_for_locale("es"))
	_check("Spanish selection is admitted", chosen in identity.spanish_countries())
	for index in 100:
		identity.country_for_locale("en")
		_check("Spanish choice survives locale switch %d" % index, identity.country_for_locale("es") == chosen)
	var app_shell_identity = FlagIdentity.shared()
	var scene_identity = FlagIdentity.shared()
	var shared_choice: String = scene_identity.country_for_locale("es")
	scene_identity = null
	_check("shared choice survives scene replacement while shell retains identity", FlagIdentity.shared() == app_shell_identity
		and FlagIdentity.shared().country_for_locale("en") == "US"
		and FlagIdentity.shared().country_for_locale("es") == shared_choice)
	var seen := {}
	for seed_value in 512:
		var seeded = FlagIdentity.new(seed_value)
		seen[seeded.country_for_locale("es")] = true
	_check("all admitted Spanish countries are reachable", seen.size() == identity.spanish_countries().size(), str(seen.keys()))


func _test_rng_isolation() -> void:
	seed(123456)
	var expected_first := randi()
	var expected_second := randi()
	seed(123456)
	var first := randi()
	var identity = FlagIdentity.new(9831)
	identity.country_for_locale("es")
	identity.country_for_locale("en")
	identity.country_for_locale("es")
	var randomly_seeded = FlagIdentity.new()
	randomly_seeded.country_for_locale("es")
	var second := randi()
	_check("seeded and random identity do not consume global RNG", first == expected_first and second == expected_second)


func _test_manifest() -> void:
	var identity = FlagIdentity.new(10)
	var countries: PackedStringArray = identity.countries()
	var spanish: PackedStringArray = identity.spanish_countries()
	_check("known Spanish countries admitted", "ES" in spanish and "CO" in spanish and "MX" in spanish and "AR" in spanish and "CL" in spanish)
	_check("Paraguay excluded until a licensed reverse exists", "PY" not in countries)
	_check("Spanish subset nonempty and unique", not spanish.is_empty() and spanish.size() == 19)
	for country: String in countries:
		var desc: Dictionary = identity.descriptor(country)
		_check("%s descriptor" % country, desc.country == country and desc.height_m == 0.9
			and desc.aspect >= 4.0 / 3.0 and desc.aspect <= 2.0
			and is_equal_approx(desc.length_m, desc.height_m * desc.aspect)
			and desc.reverse_policy == "mirror_front" and desc.front_path == desc.reverse_path)
		_check("%s packaged texture exists" % country, ResourceLoader.exists(desc.front_path, "Texture2D"))
		var texture: Texture2D = load(desc.front_path)
		if texture == null:
			_check("%s packaged texture loads" % country, false)
			continue
		var image: Image = texture.get_image()
		_check("%s image is bounded and has aspect" % country,
			image != null and image.get_width() == 512 and image.get_height() == roundi(512.0 / desc.aspect))
		_check("%s image is opaque" % country, image != null and image.detect_alpha() == Image.ALPHA_NONE)
		_check("%s image has mipmaps" % country, image != null and image.has_mipmaps())


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: %s %s" % [label, detail])
