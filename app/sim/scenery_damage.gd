## Provisional gameplay thresholds for scenery damage. They are estimates, not material tests.
extends RefCounted

const POLICY_VERSION := "cr-17a-scenery-damage-v1"

const THRESHOLDS_J := {
	"wood": 20.0,
	"wire": 8.0,
	"foam": 10.0,
	"straw": 25.0,
	"foliage": 15.0,
	"metal": 15.0,
	"masonry": 20.0,
	"wood_mark": 20.0,
	"foliage_mark": 15.0,
}

const BROKEN_PROFILES := ["wood", "wire", "foam", "straw", "foliage"]


static func profile_is_valid(profile: String) -> bool:
	return profile == "none" or THRESHOLDS_J.has(profile)


static func profile_is_destructible(profile: String) -> bool:
	return BROKEN_PROFILES.has(profile)


static func threshold_j(profile: String) -> float:
	return float(THRESHOLDS_J.get(profile, INF))


## Empty means this impact does not change the scenery state.
static func impact_state(profile: String, energy_j: float) -> String:
	if not THRESHOLDS_J.has(profile) or not is_finite(energy_j) or energy_j < float(THRESHOLDS_J[profile]):
		return ""
	return "broken" if profile_is_destructible(profile) else "marked"


static func id_is_broken(damage: Dictionary, damage_id: String) -> bool:
	var record: Variant = damage.get(damage_id, {})
	return typeof(record) == TYPE_DICTIONARY and str(record.get("state", "")) == "broken"
