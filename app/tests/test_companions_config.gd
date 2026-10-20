extends SceneTree

const Config := preload("res://ai/companions/config.gd")
const STIK_ID := "jensen-das-ugly-stik-60"

var _checks: int = 0
var _failures: int = 0


func _check(label: String, passed: bool, detail: String = "") -> void:
	_checks += 1
	print(("ok   " if passed else "FAIL ") + label + ("  " + detail if not detail.is_empty() else ""))
	if not passed:
		_failures += 1


func _initialize() -> void:
	var defaults: Dictionary = Config.defaults()
	_check("defaults keep companions off", defaults.get("enabled", true) == false and int(defaults.get("count", -1)) in [0, 1])
	_check("defaults select only the accepted Stik circuit profile",
		defaults.get("aircraft_id", "") == STIK_ID and defaults.get("activity", "") == "circuits"
		and defaults.get("pilot", "") == "experienced" and defaults.get("incidents_enabled", true) == false)
	var checked: Dictionary = Config.validate({"enabled": true, "count": 3, "seed": 4294967295})
	_check("valid three-aircraft uint32 config normalizes fixed MVP choices", checked.ok
		and checked.config.count == 3 and checked.config.seed == 4294967295
		and checked.config.aircraft_id == STIK_ID and checked.config.incidents_enabled == false)
	_check("enabled with zero companions is refused", not Config.validate({"enabled": true, "count": 0}).ok)
	_check("count above the finite fleet cap is refused", not Config.validate({"enabled": false, "count": 4}).ok)
	_check("fractional count is refused", not Config.validate({"enabled": false, "count": 1.5}).ok)
	_check("boolean count is refused", not Config.validate({"enabled": false, "count": true}).ok)
	_check("negative seed is refused", not Config.validate({"enabled": false, "seed": -1}).ok)
	_check("seed above uint32 is refused", not Config.validate({"enabled": false, "seed": 4294967296}).ok)
	_check("nonfinite seed is refused", not Config.validate({"enabled": false, "seed": NAN}).ok)
	_check("unsupported aircraft is refused", not Config.validate({"aircraft_id": "gp-extra-300s-60"}).ok)
	_check("unsupported activity is refused", not Config.validate({"activity": "aerobatics"}).ok)
	_check("unsupported pilot skill is refused", not Config.validate({"pilot": "learner"}).ok)
	_check("MVP incidents cannot be enabled", not Config.validate({"incidents_enabled": true}).ok)
	_check("unknown fields are refused", not Config.validate({"internal_force": 1.0}).ok)
	var injected := {"enabled": true, "count": 2, "seed": 17}
	var seed_overlay: Dictionary = Config.from_args(PackedStringArray(["--unrelated=1", "--companions-seed=4294967295"]), injected)
	_check("explicit CLI seed overlays Home config and preserves its count",
		seed_overlay.ok and seed_overlay.config.enabled and seed_overlay.config.count == 2
		and seed_overlay.config.seed == 4294967295)
	var count_overlay: Dictionary = Config.from_args(PackedStringArray(["--companions=0"]), injected)
	_check("explicit CLI zero disables and clears the requested count",
		count_overlay.ok and not count_overlay.config.enabled and count_overlay.config.count == 0)
	_check("invalid CLI count is refused", not Config.from_args(PackedStringArray(["--companions=3.5"]), injected).ok)
	_check("invalid CLI seed is refused", not Config.from_args(PackedStringArray(["--companions-seed=4294967296"]), injected).ok)
	_check("duplicate CLI count is refused", not Config.from_args(PackedStringArray(["--companions=1", "--companions=2"]), injected).ok)
	_check("CLI count flag without a value is refused", not Config.from_args(PackedStringArray(["--companions"]), injected).ok)
	_check("CLI seed flag without a value is refused", not Config.from_args(PackedStringArray(["--companions-seed"]), injected).ok)
	print("companion config: %d checks, %d failed" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)
