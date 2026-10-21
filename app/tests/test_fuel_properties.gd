# FUEL-02: the liquid-fuel registry (physics/fuel_properties.gd, data/fuels/openrc-fuel-registry.json).
# Blend densities against hand sums, the glow profiles' own derived density, temperature shifts on a synthetic
# registry, and one refusal per validation rule. Run: godot --headless --path app --script res://tests/test_fuel_properties.gd
extends SceneTree

const Fuels := preload("res://physics/fuel_properties.gd")
const Profile := preload("res://physics/glow/profile.gd")

const GLOW_PROFILES := ["res://data/glow/os_max_55ax_candidate.json", "res://data/glow/os_max_61fx_candidate.json",
	"res://data/glow/os_fs_64v_candidate.json", "res://data/glow/os_max_61fx_installed_candidate.json"]

var _checks := 0
var _failed := 0


func _check(label: String, ok: bool, detail := "") -> void:
	_checks += 1
	if not ok:
		_failed += 1
	print("%s %s %s" % ["ok  " if ok else "FAIL", label, detail])


func _initialize() -> void:
	var registry: Dictionary = Fuels.load_file()
	_check("registry loads with an identity", registry.get("ok", false) and str(registry.get("identity", {}).get("sha256", "")).length() == 64,
		str(registry.get("message", "")))
	if not registry.get("ok", false):
		_finish()
		return
	_blends(registry)
	_glow_profiles(registry)
	_temperature()
	_refusals()
	_finish()


func _blends(registry: Dictionary) -> void:
	var expected := {
		"glow_10n_18castor": 0.72 * 792.0 + 0.10 * 1137.0 + 0.18 * 961.0,
		"gasoline_premix_40_1": (40.0 * 745.0 + 862.0) / 41.0,
		"kerosene_5pct_turbine_oil": 0.95 * 800.0 + 0.05 * 1003.5,
	}
	for id: String in expected:
		var got: Dictionary = Fuels.blend_density(registry, id)
		_check("%s density is the volume-weighted component sum" % id,
			got.get("ok", false) and absf(float(got.density_kg_m3) - float(expected[id])) <= 1e-9,
			"%.9f vs %.9f" % [float(got.get("density_kg_m3", NAN)), float(expected[id])])
	_check("unknown blend is refused", not Fuels.blend_density(registry, "nitro_99").get("ok", true))
	var glow: Dictionary = registry.blends.glow_10n_18castor
	_check("glow blend has no slope because nitromethane and castor oil have none", is_nan(glow.density_slope_kg_m3_k))
	_check("glow blend refuses another temperature instead of guessing",
		not Fuels.blend_density(registry, "glow_10n_18castor", 288.15).get("ok", true))
	_check("glow blend accepts its own reference temperature",
		Fuels.blend_density(registry, "glow_10n_18castor", 298.15).get("ok", false))


## The registry is the single home for densities: every glow profile must derive exactly the registry blend.
func _glow_profiles(registry: Dictionary) -> void:
	var blend: float = registry.blends.glow_10n_18castor.density_kg_m3
	for path: String in GLOW_PROFILES:
		var loaded: Dictionary = Profile.load_file(path)
		var density: float = float(loaded.model.fuel.density_kg_m3) if loaded.get("ok", false) else NAN
		_check("%s derives the registry glow blend density" % path.get_file(), absf(density - blend) <= 1e-9,
			"%.9f vs %.9f" % [density, blend])
	# A changed component must break that equality (the check above is not vacuous).
	var raw: Dictionary = _raw()
	raw.components.methanol_aiaa_2016.density.value = 793.0
	var changed: Dictionary = Fuels.prepare(raw)
	var profile: Dictionary = Profile.load_file(GLOW_PROFILES[0])
	_check("a one-component change moves the blend away from the profile",
		changed.get("ok", false) and absf(float(changed.blends.glow_10n_18castor.density_kg_m3) - float(profile.model.fuel.density_kg_m3)) > 0.5)


func _temperature() -> void:
	var raw: Dictionary = _synthetic()
	var prepared: Dictionary = Fuels.prepare(raw)
	_check("synthetic registry with slopes prepares", prepared.get("ok", false), str(prepared.get("message", "")))
	if not prepared.get("ok", false):
		return
	# a at 288.15 K: 800, slope -1; b at 298.15 K: 1000, slope -0.5 → at 288.15 K b is 1005.
	_check("component referenced at another temperature is shifted by its slope",
		absf(prepared.blends.mix.density_kg_m3 - (0.5 * 800.0 + 0.5 * 1005.0)) <= 1e-9, str(prepared.blends.mix.density_kg_m3))
	var warm: Dictionary = Fuels.blend_density(prepared, "mix", 308.15)
	_check("blend density follows the volume-weighted slope",
		warm.get("ok", false) and absf(float(warm.density_kg_m3) - (902.5 - 0.75 * 20.0)) <= 1e-9, str(warm))
	_check("nonphysical temperature is refused", not Fuels.blend_density(prepared, "mix", 50.0).get("ok", true))


func _refusals() -> void:
	var cases := {
		"fractions summing to 0.99": func(r: Dictionary) -> void: r.blends.mix.volume_fractions.a = 0.49,
		"unknown component in a blend": func(r: Dictionary) -> void: r.blends.mix.volume_fractions = {"a": 0.5, "zz": 0.5},
		"negative density": func(r: Dictionary) -> void: r.components.a.density.value = -1.0,
		"empty source": func(r: Dictionary) -> void: r.components.a.density.source = " ",
		"unknown kind": func(r: Dictionary) -> void: r.components.a.density.kind = "guessed",
		"wrong unit": func(r: Dictionary) -> void: r.components.a.density.unit = "g/ml",
		"extra component key": func(r: Dictionary) -> void: r.components.a.viscosity = 1.0,
		"extra blend key": func(r: Dictionary) -> void: r.blends.mix.colour = "blue",
		"unknown family": func(r: Dictionary) -> void: r.blends.mix.family = "diesel",
		"positive slope": func(r: Dictionary) -> void: r.components.a.density_slope.value = 0.5,
		"other temperature without a slope": func(r: Dictionary) -> void: r.components.b.erase("density_slope"),
		"wrong format": func(r: Dictionary) -> void: r.format = "openrc-fuel-registry v2",
		"zero fraction": func(r: Dictionary) -> void: r.blends.mix.volume_fractions = {"a": 0.0, "b": 1.0},
		"uncertainty above 20 %": func(r: Dictionary) -> void: r.blends.mix.relative_uncertainty.value = 0.5,
	}
	for label: String in cases:
		var raw: Dictionary = _synthetic()
		cases[label].call(raw)
		var result: Dictionary = Fuels.prepare(raw)
		_check("refuses %s" % label, not result.get("ok", true) and str(result.get("message", "")) != "", str(result.get("message", "")))


func _raw() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(Fuels.DEFAULT_PATH))


func _q(value: float, unit: String) -> Dictionary:
	return {"value": value, "unit": unit, "kind": "estimated", "source": "synthetic test fixture"}


func _synthetic() -> Dictionary:
	return {
		"format": Fuels.FORMAT, "note": "synthetic",
		"components": {
			"a": {"name": "a", "density": _q(800.0, "kg/m3"), "reference_temperature": _q(288.15, "K"), "density_slope": _q(-1.0, "kg/m3/K")},
			"b": {"name": "b", "density": _q(1000.0, "kg/m3"), "reference_temperature": _q(298.15, "K"), "density_slope": _q(-0.5, "kg/m3/K")},
		},
		"blends": {
			"mix": {"name": "mix", "family": "glow", "volume_fractions": {"a": 0.5, "b": 0.5},
				"reference_temperature": _q(288.15, "K"), "relative_uncertainty": _q(0.02, "1"), "use": "test"},
		},
	}


func _finish() -> void:
	print("FUEL-02 fuel registry: %d checks, %d failed" % [_checks, _failed])
	quit(1 if _failed > 0 else 0)
