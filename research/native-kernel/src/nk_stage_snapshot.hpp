// Strict preparation-boundary binding of detached source snapshots to the
// committed aircraft model. No physics is evaluated and no snapshot can admit
// another valid aircraft's numerically different motor, engine or inventory.
#pragma once

#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>
#include <godot_cpp/variant/variant.hpp>

#include <cstdint>
#include <cstring>
#include <initializer_list>
#include <string>

#include "nk_glow_lifecycle.hpp"

namespace nk {

// Godot's numeric == treats +0 and -0 as equal. Snapshot identity must retain
// IEEE-754 bits (including NaN payloads) and packed-array bytes instead.
inline bool stage_snapshot_exact_bounded(const godot::Variant &a, const godot::Variant &b,
		int depth, size_t &budget) {
	using godot::Variant;
	if (depth > 32 || budget == 0) return false;
	--budget;
	if (a.get_type() != b.get_type()) return false;
	switch (a.get_type()) {
		case Variant::NIL: return true;
		case Variant::BOOL: return static_cast<bool>(a) == static_cast<bool>(b);
		case Variant::INT: return static_cast<int64_t>(a) == static_cast<int64_t>(b);
		case Variant::FLOAT: {
			const double x = static_cast<double>(a), y = static_cast<double>(b);
			return std::memcmp(&x, &y, sizeof(double)) == 0;
		}
		case Variant::STRING: return static_cast<godot::String>(a) == static_cast<godot::String>(b);
		case Variant::STRING_NAME: return a == b;
		case Variant::PACKED_FLOAT64_ARRAY: {
			const godot::PackedFloat64Array x = a, y = b;
			if (x.size() != y.size() || static_cast<size_t>(x.size()) > budget) return false;
			budget -= static_cast<size_t>(x.size());
			return x.is_empty() || std::memcmp(x.ptr(), y.ptr(), static_cast<size_t>(x.size()) * sizeof(double)) == 0;
		}
		case Variant::PACKED_STRING_ARRAY: {
			const godot::PackedStringArray x = a, y = b;
			if (x.size() != y.size() || static_cast<size_t>(x.size()) > budget) return false;
			budget -= static_cast<size_t>(x.size());
			for (int64_t i = 0; i < x.size(); ++i) if (x[i] != y[i]) return false;
			return true;
		}
		case Variant::ARRAY: {
			const godot::Array x = a, y = b;
			if (x.size() != y.size()) return false;
			for (int64_t i = 0; i < x.size(); ++i) if (!stage_snapshot_exact_bounded(x[i], y[i], depth + 1, budget)) return false;
			return true;
		}
		case Variant::DICTIONARY: {
			const godot::Dictionary x = a, y = b;
			if (x.size() != y.size()) return false;
			const godot::Array keys = x.keys();
			for (int64_t i = 0; i < keys.size(); ++i) {
				const Variant key = keys[i];
				if (!y.has(key) || !stage_snapshot_exact_bounded(x[key], y[key], depth + 1, budget)) return false;
			}
			return true;
		}
		default: return false; // This source schema has no vector, object or arbitrary Variant fields.
	}
}

// The bound rejects recursive/cyclic Variants and caps preparation work. Each
// public comparison has its own budget; normal prepared model arrays are far
// smaller than one million elements.
inline bool stage_snapshot_exact(const godot::Variant &a, const godot::Variant &b) {
	size_t budget = 1024 * 1024;
	return stage_snapshot_exact_bounded(a, b, 0, budget);
}

struct StageSnapshotGuard {
	std::string &error;

	bool fail(const std::string &message) {
		if (error.empty()) error = message;
		return false;
	}

	bool keys(const godot::Dictionary &d, const char *where, std::initializer_list<const char *> required,
			std::initializer_list<const char *> optional = {}) {
		for (const char *key : required) if (!d.has(key)) return fail(std::string(where) + " missing " + key);
		const godot::Array names = d.keys();
		for (int64_t i = 0; i < names.size(); ++i) {
			const godot::Variant value = names[i];
			if (value.get_type() != godot::Variant::STRING && value.get_type() != godot::Variant::STRING_NAME) return fail(std::string(where) + " has non-string key");
			const godot::String name = value;
			bool known = false;
			for (const char *key : required) if (name == godot::String(key)) { known = true; break; }
			for (const char *key : optional) if (name == godot::String(key)) { known = true; break; }
			if (!known) return fail(std::string("unsupported ") + where + "." + name.utf8().get_data());
		}
		return true;
	}

	bool dict(const godot::Dictionary &parent, const char *key, godot::Dictionary &out) {
		if (!parent.has(key) || parent[key].get_type() != godot::Variant::DICTIONARY) return fail(std::string("missing dictionary ") + key);
		out = parent[key];
		return true;
	}

	bool field(const godot::Dictionary &snapshot, const char *name, const godot::Dictionary &owner,
			const char *owner_name, const char *where) {
		if (!snapshot.has(name) || !owner.has(owner_name) || !stage_snapshot_exact(snapshot[name], owner[owner_name])) {
			return fail(std::string(where) + "." + name + " differs from committed model");
		}
		return true;
	}

	bool fields(const godot::Dictionary &snapshot, const godot::Dictionary &owner,
			std::initializer_list<const char *> names, const char *where) {
		for (const char *name : names) if (!field(snapshot, name, owner, name, where)) return false;
		return true;
	}

	bool optional_field(const godot::Dictionary &snapshot, const godot::Dictionary &owner,
			const char *snapshot_name, const char *owner_name, const char *where) {
		if (snapshot.has(snapshot_name) != owner.has(owner_name)) return fail(std::string(where) + "." + snapshot_name + " presence differs from committed model");
		return !snapshot.has(snapshot_name) || field(snapshot, snapshot_name, owner, owner_name, where);
	}
};

inline bool stage_snapshot_mass(StageSnapshotGuard &guard, const godot::Dictionary &model,
		const godot::Dictionary &snapshot, const godot::Dictionary &inventory) {
	if (!guard.keys(snapshot, "mass", {"reference_mass_kg", "reference_inertia_kgm2", "references", "capacities", "centers", "tensors"}) ||
			!guard.fields(snapshot, inventory, {"reference_mass_kg", "reference_inertia_kgm2", "references", "capacities", "centers", "tensors"}, "mass") ||
			!guard.field(snapshot, "reference_mass_kg", model, "mass_kg", "mass") ||
			!guard.field(snapshot, "reference_inertia_kgm2", model, "inertia", "mass")) return false;
	return true;
}

inline bool stage_snapshot_electric(const godot::Dictionary &model, const godot::Dictionary &snapshot, std::string &error) {
	error.clear();
	StageSnapshotGuard g{error};
	godot::Dictionary prop, motor, battery, esc, sm, sb, se;
	if (!g.keys(snapshot, "electric", {"format", "motor", "battery", "esc"}) ||
			!snapshot.has("format") || snapshot["format"] != godot::String("openrc-nk3-electric-snapshot-v1") ||
			!g.dict(model, "propulsion", prop) || !g.dict(prop, "motor", motor) || !g.dict(prop, "battery", battery) ||
			!g.dict(prop, "esc", esc) || !g.dict(snapshot, "motor", sm) || !g.dict(snapshot, "battery", sb) ||
			!g.dict(snapshot, "esc", se)) return g.fail("invalid electric snapshot or model");
	if (!prop.has("kind") || prop["kind"] != godot::String("electric_prop") || !stage_snapshot_exact(sm, motor)) return g.fail("electric motor differs from committed model");
	if (!g.keys(se, "esc", {"kind", "command_mapping"}) || !g.fields(se, esc, {"kind", "command_mapping"}, "esc") ||
			!g.field(sb, "kind", battery, "kind", "battery")) return false;
	const godot::String kind = sb["kind"];
	if (kind == godot::String("fixed_voltage")) {
		return g.keys(sb, "battery", {"kind", "voltage_v"}) && g.fields(sb, battery, {"voltage_v"}, "battery");
	}
	if (kind == godot::String("ocv_resistance")) {
		return g.keys(sb, "battery", {"kind", "capacity_ah", "resistance_ohm", "auxiliary_current_a", "initial_soc", "ocv_points"}) &&
				g.fields(sb, battery, {"capacity_ah", "resistance_ohm", "auxiliary_current_a", "initial_soc", "ocv_points"}, "battery");
	}
	if (kind == godot::String("pack_ecm")) {
		return g.keys(sb, "battery", {"kind", "series", "branches", "group_capacity_c", "initial_soc", "weak_capacity_factor",
				"weak_resistance_factor", "weak_soc_offset", "interconnect_ohm", "auxiliary_current_a", "cooling_airflow_fraction",
				"thermal_capacity_j_per_k", "h_still_w_per_k", "h_forced_w_per_k_sqrt_mps", "lvc_filter_s", "soc_knots",
				"temperature_knots_k", "ocv", "r0", "rc_r", "rc_tau"}) &&
				g.fields(sb, battery, {"series", "branches", "group_capacity_c", "initial_soc", "weak_capacity_factor",
				"weak_resistance_factor", "weak_soc_offset", "interconnect_ohm", "auxiliary_current_a", "cooling_airflow_fraction",
				"thermal_capacity_j_per_k", "h_still_w_per_k", "h_forced_w_per_k_sqrt_mps", "lvc_filter_s", "soc_knots",
				"temperature_knots_k", "ocv", "r0", "rc_r", "rc_tau"}, "battery");
	}
	return g.fail("unsupported committed battery kind");
}

inline bool stage_snapshot_liquid(const godot::Dictionary &model, const godot::Dictionary &snapshot, std::string &error) {
	error.clear();
	StageSnapshotGuard g{error};
	godot::Dictionary prop, adapter, inventory, mass, store, source;
	if (!g.keys(snapshot, "liquid", {"format", "family", "mass", "store", "source"}) ||
			snapshot["format"] != godot::String("openrc-nk3-liquid-component-v1") ||
			!g.dict(model, "propulsion", prop) || !g.dict(prop, "liquid_fuel", adapter) ||
			!g.dict(adapter, "prepared_inventory", inventory) || !g.dict(snapshot, "mass", mass) ||
			!g.dict(snapshot, "store", store) || !g.dict(snapshot, "source", source) ||
			!stage_snapshot_mass(g, model, mass, inventory) ||
			!g.keys(store, "store", {"capacity_kg", "unusable_kg", "bound_index"}) ||
			!g.fields(store, adapter, {"capacity_kg", "unusable_kg"}, "store")) return g.fail("invalid liquid snapshot or model");
	if (!adapter.has("tank_id") || !inventory.has("resources") || inventory["resources"].get_type() != godot::Variant::ARRAY ||
			!store.has("bound_index") || store["bound_index"].get_type() != godot::Variant::INT) return g.fail("invalid liquid bound resource");
	const godot::Array resources = inventory["resources"];
	int64_t index = -1;
	for (int64_t i = 0; i < resources.size(); ++i) {
		if (resources[i].get_type() != godot::Variant::DICTIONARY) return g.fail("invalid liquid resource record");
		const godot::Dictionary resource = resources[i];
		if (resource.has("id") && stage_snapshot_exact(resource["id"], adapter["tank_id"])) {
			if (index >= 0) return g.fail("duplicate liquid bound resource");
			index = i;
		}
	}
	if (index < 0 || static_cast<int64_t>(store["bound_index"]) != index) return g.fail("liquid bound resource differs from model");
	// Liquid.properties consults normalized per-store values even when the RK
	// coordinate targets one tank; bind those values to the prepared inventory.
	if (!adapter.has("store_ids") || adapter["store_ids"].get_type() != godot::Variant::PACKED_STRING_ARRAY ||
			!adapter.has("stores_by_id") || adapter["stores_by_id"].get_type() != godot::Variant::DICTIONARY ||
			inventory["references"].get_type() != godot::Variant::PACKED_FLOAT64_ARRAY ||
			inventory["capacities"].get_type() != godot::Variant::PACKED_FLOAT64_ARRAY) return g.fail("malformed normalized liquid stores");
	const godot::PackedStringArray ids = adapter["store_ids"];
	const godot::Dictionary stores = adapter["stores_by_id"];
	const godot::PackedFloat64Array refs = inventory["references"], caps = inventory["capacities"];
	if (resources.size() != ids.size() || resources.size() != stores.size() || resources.size() != refs.size() || resources.size() != caps.size()) return g.fail("liquid store count mismatch");
	for (int64_t i = 0; i < resources.size(); ++i) {
		const godot::Dictionary resource = resources[i];
		if (!resource.has("id") || resource["id"].get_type() != godot::Variant::STRING) return g.fail("liquid resource id missing");
		const godot::String id = resource["id"];
		if (!stores.has(id) || stores[id].get_type() != godot::Variant::DICTIONARY) return g.fail("liquid resource store missing");
		int matches = 0;
		for (int64_t k = 0; k < ids.size(); ++k) if (ids[k] == id) ++matches;
		if (matches != 1) return g.fail("liquid resource ids differ from normalized stores");
		const godot::Dictionary item = stores[id];
		if (!item.has("id") || item["id"] != id || !item.has("capacity_kg") || !item.has("unusable_kg") || !item.has("reference_kg")) return g.fail("liquid resource store malformed");
		for (const char *name : {"capacity_kg", "unusable_kg", "reference_kg"}) if (item[name].get_type() != godot::Variant::FLOAT && item[name].get_type() != godot::Variant::INT) return g.fail("liquid resource mass not numeric");
		const R capacity = static_cast<double>(item["capacity_kg"]), unusable = static_cast<double>(item["unusable_kg"]), reference = static_cast<double>(item["reference_kg"]);
		if (!is_finite(capacity) || !is_finite(unusable) || !is_finite(reference) || capacity.v <= 0.0 ||
				unusable.v < 0.0 || unusable.v >= capacity.v || reference.v < 0.0 || reference.v > capacity.v ||
				!stage_snapshot_exact(godot::Variant((capacity - unusable).v), godot::Variant(caps[i])) ||
				!stage_snapshot_exact(godot::Variant(maxf(reference - unusable, 0.0).v), godot::Variant(refs[i]))) return g.fail("liquid prepared store differs from inventory");
		if (i == index && (!g.fields(store, item, {"capacity_kg", "unusable_kg"}, "bound store") ||
				!g.field(adapter, "reference_kg", item, "reference_kg", "bound store"))) return false;
	}
	if (!snapshot.has("family") || snapshot["family"].get_type() != godot::Variant::STRING || !adapter.has("law")) return g.fail("liquid family missing");
	const godot::String family = snapshot["family"];
	if (family == godot::String("gas")) {
		godot::Dictionary shaft;
		if (adapter["law"] != godot::String("gasoline_bsfc_v1") || !g.dict(prop, "shaft", shaft) ||
				!g.keys(source, "gas source", {"power_curve", "friction", "idle_power", "peak_indicated_power", "bsfc_kg_kwh", "idle_flow_kg_s"}) ||
				!g.fields(source, shaft, {"power_curve", "friction", "idle_power", "peak_indicated_power"}, "gas source") ||
				!g.fields(source, adapter, {"bsfc_kg_kwh", "idle_flow_kg_s"}, "gas source") ||
				!g.field(source, "idle_power", adapter, "idle_power_w", "gas source")) return g.fail("gas source differs from committed model");
		return true;
	}
	if (family == godot::String("turbine")) {
		if (!prop.has("kind") || prop["kind"] != godot::String("turbine") || adapter["law"] != godot::String("turbine_map_v1") ||
				!g.keys(source, "turbine source", {"max_rpm", "axis", "offset", "intake_offset", "throttle_map", "accel_limit", "decel_limit",
						"static_thrust", "mass_flow", "fuel_flow", "governor_tau", "installed_factor", "rotor_inertia", "rotor_sense"}, {"ram_jet", "ram_flow"}) ||
				!g.fields(source, prop, {"max_rpm", "axis", "offset", "intake_offset", "throttle_map", "accel_limit", "decel_limit",
						"static_thrust", "mass_flow", "fuel_flow", "governor_tau", "installed_factor", "rotor_inertia", "rotor_sense"}, "turbine source") ||
				!g.optional_field(source, prop, "ram_jet", "ram_jet", "turbine source") ||
				!g.optional_field(source, prop, "ram_flow", "ram_flow", "turbine source") ||
				!g.field(source, "fuel_flow", adapter, "fuel_flow_kg_s_by_rpm", "turbine source")) return g.fail("turbine source differs from committed model");
		return true;
	}
	return g.fail("unsupported liquid source family");
}

inline bool stage_snapshot_glow(const godot::Dictionary &model, const godot::Dictionary &snapshot, std::string &error) {
	error.clear();
	StageSnapshotGuard g{error};
	godot::Dictionary prop, install, profile, parameters, operation, settings, thermal;
	godot::Dictionary source, blade, mass, lifecycle, source_thermal, store, original_blade, inventory;
	if (!g.keys(snapshot, "glow", {"format", "source", "blade", "mass", "lifecycle", "store"}, {"feed"}) ||
			snapshot["format"] != godot::String("openrc-nk3-glow-component-v1") ||
			!g.dict(model, "propulsion", prop) || !g.dict(prop, "glow", install) || !g.dict(install, "profile", profile) ||
			!g.dict(profile, "parameters", parameters) || !g.dict(profile, "operation", operation) ||
			!g.dict(install, "settings", settings) || !g.dict(settings, "thermal", thermal) ||
			!g.dict(install, "propeller", original_blade) || !g.dict(install, "mass_reference", inventory) ||
			!g.dict(snapshot, "source", source) || !g.dict(snapshot, "blade", blade) || !g.dict(snapshot, "mass", mass) ||
			!g.dict(snapshot, "lifecycle", lifecycle) || !g.dict(lifecycle, "thermal", source_thermal) ||
			!g.dict(snapshot, "store", store) || !stage_snapshot_mass(g, model, mass, inventory)) return g.fail("invalid glow snapshot or model");
	if (!g.field(source, "family", profile, "family", "source") || !g.field(source, "max_rpm", operation, "max_rpm", "source") ||
			!g.fields(source, parameters, {"displacement_m3", "oil_fraction", "stoich_air_fuel_ratio", "fuel_lhv_j_kg",
					"mechanical_torque_nm", "combustion_efficiency", "indicated_efficiency"}, "source")) return false;
	const godot::String family = source["family"];
	const bool two = family == godot::String("glow_2t");
	if (!two && family != godot::String("glow_4t")) return g.fail("unsupported committed glow family");
	if (!g.keys(source, "glow source", {"family", "max_rpm", "displacement_m3", "oil_fraction", "stoich_air_fuel_ratio", "fuel_lhv_j_kg",
				"breathing", "pumping_pressure", "mechanical_torque_nm", "combustion_efficiency", "indicated_efficiency"},
				{"trapping_efficiency", "intake_pressure_drop_pa", "valve_torque_nm"}) ||
			!g.field(source, "breathing", parameters, two ? "delivery_ratio" : "volumetric_efficiency", "source") ||
			!g.field(source, "pumping_pressure", parameters, two ? "scavenge_pressure_pa" : "pumping_pressure_pa", "source")) return false;
	if (two) {
		if (!g.field(source, "trapping_efficiency", parameters, "trapping_efficiency", "source") || source.has("intake_pressure_drop_pa") || source.has("valve_torque_nm")) return g.fail("two-stroke source fields differ");
	} else {
		if (source.has("trapping_efficiency") || !g.fields(source, parameters, {"intake_pressure_drop_pa", "valve_torque_nm"}, "source")) return g.fail("four-stroke source fields differ");
	}
	if (!g.keys(blade, "blade", {"diameter_m", "pitch_m", "chord_m", "lift_slope", "cd0", "induced_drag", "blades"}, {"zero_lift_angle_rad"}) ||
			!g.fields(blade, original_blade, {"diameter_m", "pitch_m", "chord_m", "lift_slope", "cd0", "induced_drag", "blades"}, "blade") ||
			!g.optional_field(blade, original_blade, "zero_lift_angle_rad", "zero_lift_angle_rad", "blade")) return false;
	if (!g.keys(lifecycle, "lifecycle", {"nominal_mixture", "idle_opening", "idle_offset", "travel_exponent", "throttle_capacity_m3_s",
				"servo_time_constant_s", "air_time_constant_s", "fuel_transport_time_constant_s", "lean_misfire_zero_ratio", "lean_misfire_start_ratio",
				"rich_misfire_start_ratio", "rich_misfire_zero_ratio", "temperature_firing_min_k", "temperature_firing_full_k",
				"temperature_firing_hot_full_k", "temperature_firing_hot_zero_k", "thermal"}) ||
			!g.field(lifecycle, "nominal_mixture", operation, "nominal_mixture", "lifecycle") ||
			!g.field(lifecycle, "idle_offset", install, "throttle_idle_offset", "lifecycle") ||
			!g.field(lifecycle, "throttle_capacity_m3_s", install, "throttle_capacity_m3_s", "lifecycle") ||
			!g.field(lifecycle, "travel_exponent", settings, "throttle_travel_exponent", "lifecycle") ||
			!g.fields(lifecycle, settings, {"idle_opening", "servo_time_constant_s", "air_time_constant_s", "fuel_transport_time_constant_s",
					"lean_misfire_zero_ratio", "lean_misfire_start_ratio", "rich_misfire_start_ratio", "rich_misfire_zero_ratio",
					"temperature_firing_min_k", "temperature_firing_full_k", "temperature_firing_hot_full_k", "temperature_firing_hot_zero_k"}, "lifecycle") ||
			!g.keys(source_thermal, "thermal", {"heat_capacity_j_k", "head_heat_fraction", "cooling_base_w_k", "cooling_airflow_w_s_m_k",
					"premix_evaporation_j_kg", "evaporation_head_fraction"}) ||
			!g.fields(source_thermal, thermal, {"heat_capacity_j_k", "head_heat_fraction", "cooling_base_w_k", "cooling_airflow_w_s_m_k",
					"premix_evaporation_j_kg", "evaporation_head_fraction"}, "thermal")) return false;
	if (!g.keys(store, "store", {"main_capacity_kg", "unusable_kg", "has_line", "line_capacity_kg"}) ||
			!g.field(store, "main_capacity_kg", install, "capacity_fuel_kg", "store") ||
			!g.field(store, "unusable_kg", install, "unusable_fuel_kg", "store") ||
			store["has_line"].get_type() != godot::Variant::BOOL || static_cast<bool>(store["has_line"]) != install.has("feed_line")) return g.fail("glow store differs from model");
	if (install.has("feed_line")) {
		godot::Dictionary line;
		if (!g.dict(install, "feed_line", line) || !g.field(store, "line_capacity_kg", line, "capacity_kg", "store")) return false;
	} else if (!stage_snapshot_exact(store["line_capacity_kg"], godot::Variant(0.0))) {
		return g.fail("unexpected glow line capacity");
	}
	if (snapshot.has("feed") != install.has("fuel_feed")) return g.fail("glow feed capability differs from model");
	if (snapshot.has("feed")) {
		godot::Dictionary feed, original_feed;
		if (!g.dict(snapshot, "feed", feed) || !g.dict(install, "fuel_feed", original_feed) ||
				!g.keys(feed, "feed", {"carburetor_body_m", "tank_center_body_m", "tank_size_body_m", "density_kg_m3",
						"idle_drive_pressure_pa", "wot_drive_pressure_pa", "rated_rpm"}, {"pickup_body_m"}) ||
				!g.fields(feed, original_feed, {"carburetor_body_m", "density_kg_m3", "idle_drive_pressure_pa", "wot_drive_pressure_pa", "rated_rpm"}, "feed") ||
				!g.field(feed, "tank_center_body_m", install, "tank_position", "feed") ||
				!g.field(feed, "tank_size_body_m", install, "tank_size", "feed") ||
				!g.optional_field(feed, install, "pickup_body_m", "pickup_position", "feed")) return false;
	}
	return true;
}

} // namespace nk
