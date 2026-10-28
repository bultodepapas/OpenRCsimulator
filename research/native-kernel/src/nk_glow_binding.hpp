// Detached component adapter for the prepared glow source, blade and fuel mass.
// This is a qualification interface, not a complete native flight-stage admission.
#pragma once

#include <limits>
#include <vector>
#include "nk_electric_binding.hpp" // shared strict Godot snapshot decoder
#include "nk_glow_propeller.hpp"
#include "nk_glow_feed.hpp"
#include "nk_glow_source.hpp"
#include "nk_glow_stage.hpp"
#include "nk_liquid_mass.hpp"

namespace nk {

// Snapshot v1 consists solely of normalized numeric model fields; profile and
// installation provenance remain the session's responsibility. No callbacks or
// Godot values are retained after preparation.
class GlowBinding {
	bool ready_ = false;
	GlowSourceModel source_;
	GlowBladeModel blade_;
	LiquidMassModel mass_;
	bool has_feed_ = false;
	bool has_pickup_ = false;
	GlowFeedModel feed_;
	std::array<R, 3> pickup_{};
	GlowStageModel stage_model_;

	static godot::Dictionary failure(const std::string &reason) {
		godot::Dictionary out;
		out["ok"] = false;
		out["error"] = godot::String(reason.c_str());
		return out;
	}

	static bool table_domain(const std::vector<double> &table, double low, double high, bool strict_low) {
		for (size_t i = 1; i < table.size(); i += 2) {
			if ((strict_low ? table[i] <= low : table[i] < low) || table[i] > high) return false;
		}
		return true;
	}

	static bool rpm_table(const std::vector<double> &table, R maximum) {
		return table.front() <= 0.0 && table[table.size() - 2] >= maximum.v;
	}

	static godot::PackedFloat64Array pack(const std::vector<R> &values) {
		godot::PackedFloat64Array out;
		out.resize(static_cast<int64_t>(values.size()));
		for (size_t i = 0; i < values.size(); ++i) out[static_cast<int64_t>(i)] = values[i].v;
		return out;
	}

	static std::vector<R> amounts_as_r(const godot::PackedFloat64Array &amounts) {
		std::vector<R> result;
		result.reserve(static_cast<size_t>(amounts.size()));
		for (int64_t i = 0; i < amounts.size(); ++i) result.emplace_back(amounts[i]);
		return result;
	}

public:
	bool ready() const { return ready_; }
	const GlowSourceModel &source() const { return source_; }
	const GlowBladeModel &blade() const { return blade_; }
	const LiquidMassModel &mass() const { return mass_; }
	bool has_feed() const { return has_feed_; }
	bool has_pickup() const { return has_pickup_; }
	const GlowFeedModel &feed() const { return feed_; }
	const std::array<R, 3> &pickup() const { return pickup_; }
	const GlowStageModel &stage_model() const { return stage_model_; }

	godot::Dictionary prepare_glow(const godot::Dictionary &snapshot) {
		ready_ = false;
		stage_model_.ready = false;
		ElectricSnapshotDecoder dec;
		godot::String format, family;
		godot::Dictionary src, blade, mass;
		if (!dec.keys(snapshot, "glow", {"format", "source", "blade", "mass", "feed", "lifecycle", "store"}) ||
				!dec.string(snapshot, "format", format) || !dec.dictionary(snapshot, "source", src) ||
				!dec.dictionary(snapshot, "blade", blade) || !dec.dictionary(snapshot, "mass", mass)) return failure(dec.error);
		if (format != godot::String("openrc-nk3-glow-component-v1")) return failure("unknown glow component snapshot format");
		GlowSourceModel source;
		if (!dec.string(src, "family", family)) return failure(dec.error);
		const bool two = family == godot::String("glow_2t");
		if (!two && family != godot::String("glow_4t")) return failure("unsupported glow family");
		source.family = two ? GlowFamily::TwoStroke : GlowFamily::FourStroke;
		if (!dec.keys(src, "source", {"family", "max_rpm", "displacement_m3", "oil_fraction", "stoich_air_fuel_ratio",
				"fuel_lhv_j_kg", "intake_pressure_drop_pa", "breathing", "trapping_efficiency", "pumping_pressure",
				"mechanical_torque_nm", "combustion_efficiency", "indicated_efficiency", "valve_torque_nm"}) ||
				!dec.number(src, "max_rpm", source.max_rpm) || !dec.number(src, "displacement_m3", source.displacement_m3) ||
				!dec.number(src, "oil_fraction", source.oil_fraction) || !dec.number(src, "stoich_air_fuel_ratio", source.stoich_air_fuel_ratio) ||
				!dec.number(src, "fuel_lhv_j_kg", source.fuel_lhv_j_kg) || !dec.packed(src, "breathing", source.breathing) ||
				!dec.packed(src, "pumping_pressure", source.pumping_pressure) || !dec.packed(src, "mechanical_torque_nm", source.mechanical_torque_nm) ||
				!dec.packed(src, "combustion_efficiency", source.combustion_efficiency) || !dec.packed(src, "indicated_efficiency", source.indicated_efficiency)) return failure(dec.error);
		if (two) {
			if (src.has("intake_pressure_drop_pa") || src.has("valve_torque_nm") ||
					!dec.packed(src, "trapping_efficiency", source.trapping_efficiency)) return failure("invalid two-stroke fields: " + dec.error);
		} else {
			if (src.has("trapping_efficiency") || !dec.number(src, "intake_pressure_drop_pa", source.intake_pressure_drop_pa) ||
					!dec.packed(src, "valve_torque_nm", source.valve_torque_nm)) return failure("invalid four-stroke fields: " + dec.error);
		}
		const double infinity = std::numeric_limits<double>::infinity();
		if (!glow_source_model_valid(source) || !rpm_table(source.breathing, source.max_rpm) ||
				!rpm_table(source.pumping_pressure, source.max_rpm) || !rpm_table(source.mechanical_torque_nm, source.max_rpm) ||
				!rpm_table(source.indicated_efficiency, source.max_rpm) || source.combustion_efficiency.front() > 0.0 ||
				!table_domain(source.breathing, 0.0, infinity, !two) || !table_domain(source.pumping_pressure, 0.0, infinity, false) ||
				!table_domain(source.mechanical_torque_nm, 0.0, infinity, false) || !table_domain(source.combustion_efficiency, 0.0, 1.0, false) ||
				!table_domain(source.indicated_efficiency, 0.0, 1.0, false) ||
				(two ? (!rpm_table(source.trapping_efficiency, source.max_rpm) || !table_domain(source.trapping_efficiency, 0.0, 1.0, false)) :
					(!rpm_table(source.valve_torque_nm, source.max_rpm) || !table_domain(source.valve_torque_nm, 0.0, infinity, false)))) return failure("invalid glow source model");
		R diameter, pitch, chord, lift, cd0, induced, blades, zero = 0.0;
		if (!dec.keys(blade, "blade", {"diameter_m", "pitch_m", "chord_m", "lift_slope", "cd0", "induced_drag", "blades", "zero_lift_angle_rad"}) ||
				!dec.number(blade, "diameter_m", diameter) || !dec.number(blade, "pitch_m", pitch) || !dec.number(blade, "chord_m", chord) ||
				!dec.number(blade, "lift_slope", lift) || !dec.number(blade, "cd0", cd0) || !dec.number(blade, "induced_drag", induced) ||
				!dec.number(blade, "blades", blades) || (blade.has("zero_lift_angle_rad") && !dec.number(blade, "zero_lift_angle_rad", zero))) return failure(dec.error);
		const GlowBladeModel decoded_blade = glow_blade_prepare(diameter, pitch, chord, lift, cd0, induced, blades, zero);
		if (!decoded_blade.valid) return failure("invalid glow blade model");
		LiquidMassModel decoded_mass;
		std::vector<double> inertia, references, capacities;
		std::vector<std::vector<double>> centers, tensors;
		if (!dec.keys(mass, "mass", {"reference_mass_kg", "reference_inertia_kgm2", "references", "capacities", "centers", "tensors"}) ||
				!dec.number(mass, "reference_mass_kg", decoded_mass.reference_mass_kg) || !dec.packed(mass, "reference_inertia_kgm2", inertia) ||
				!dec.packed(mass, "references", references) || !dec.packed(mass, "capacities", capacities)) return failure(dec.error);
		if (inertia.size() != 6 || references.empty() || references.size() != capacities.size() ||
				references.size() > static_cast<size_t>(std::numeric_limits<int>::max())) return failure("invalid mass inventory shape");
		const int count = static_cast<int>(references.size());
		if (!dec.packed_rows(mass, "centers", count, centers) || !dec.packed_rows(mass, "tensors", count, tensors)) return failure(dec.error);
		for (int k = 0; k < 6; ++k) decoded_mass.reference_inertia[k] = inertia[static_cast<size_t>(k)];
		R total = 0.0;
		for (int i = 0; i < count; ++i) {
			const size_t j = static_cast<size_t>(i);
			if (references[j] < 0.0 || capacities[j] < references[j] || centers[j].size() != 3 || tensors[j].size() != 6) return failure("invalid mass resource");
			LiquidMassResource resource;
			resource.reference_kg = references[j]; resource.capacity_kg = capacities[j];
			for (int k = 0; k < 3; ++k) resource.center[k] = centers[j][static_cast<size_t>(k)];
			for (int k = 0; k < 6; ++k) resource.tensor_per_kg[k] = tensors[j][static_cast<size_t>(k)];
			total += resource.reference_kg;
			decoded_mass.resources.push_back(resource);
		}
		if (decoded_mass.reference_mass_kg.v <= total.v) return failure("reference mass must exceed reference resources");
		const bool decoded_has_feed = snapshot.has("feed");
		bool decoded_has_pickup = false;
		GlowFeedModel decoded_feed;
		std::array<R, 3> decoded_pickup{};
		if (decoded_has_feed) {
			godot::Dictionary feed;
			std::vector<double> carburetor, tank_center, tank_size, pickup;
			if (!dec.dictionary(snapshot, "feed", feed) ||
					!dec.keys(feed, "feed", {"carburetor_body_m", "tank_center_body_m", "tank_size_body_m", "density_kg_m3",
							"idle_drive_pressure_pa", "wot_drive_pressure_pa", "rated_rpm", "pickup_body_m"}) ||
					!dec.packed(feed, "carburetor_body_m", carburetor) || !dec.packed(feed, "tank_center_body_m", tank_center) ||
					!dec.packed(feed, "tank_size_body_m", tank_size) || !dec.number(feed, "density_kg_m3", decoded_feed.density_kg_m3) ||
					!dec.number(feed, "idle_drive_pressure_pa", decoded_feed.idle_drive_pressure_pa) ||
					!dec.number(feed, "wot_drive_pressure_pa", decoded_feed.wot_drive_pressure_pa) ||
					!dec.number(feed, "rated_rpm", decoded_feed.rated_rpm)) return failure(dec.error);
			decoded_has_pickup = feed.has("pickup_body_m");
			if (decoded_has_pickup && !dec.packed(feed, "pickup_body_m", pickup)) return failure(dec.error);
			if (carburetor.size() != 3 || tank_center.size() != 3 || tank_size.size() != 3 ||
					(decoded_has_pickup && pickup.size() != 3) || decoded_feed.density_kg_m3.v <= 0.0 ||
					decoded_feed.rated_rpm.v <= 0.0 || decoded_feed.idle_drive_pressure_pa.v <= 0.0 ||
					decoded_feed.wot_drive_pressure_pa.v < decoded_feed.idle_drive_pressure_pa.v ||
					decoded_feed.wot_drive_pressure_pa.v > 100000.0) return failure("invalid glow feed model");
			for (int k = 0; k < 3; ++k) {
				const size_t i = static_cast<size_t>(k);
				if (tank_size[i] < 0.0 || std::fabs(carburetor[i]) > 2.0) return failure("invalid glow feed geometry");
				decoded_feed.carburetor[k] = carburetor[i]; decoded_feed.tank_center[k] = tank_center[i];
				decoded_feed.tank_size[k] = tank_size[i];
				if (decoded_has_pickup) decoded_pickup[k] = pickup[i];
			}
			const R g[3] = {0.0, 0.0, 9.80665};
			const R needled = glow_feed_head(g, 1.0, decoded_feed.carburetor.data(), decoded_feed.tank_center.data(),
					decoded_feed.tank_size.data(), decoded_feed.density_kg_m3);
			if ((decoded_feed.idle_drive_pressure_pa + needled).v <= 0.0) return failure("invalid glow feed needled head");
		}
		// Optional full-stage extension; the earlier component-only schema stays
		// valid but cannot supply a prepared joint-stage model.
		GlowStageModel staged;
		const bool has_lifecycle = snapshot.has("lifecycle");
		if (has_lifecycle != snapshot.has("store")) return failure("glow stage requires lifecycle and store together");
		if (has_lifecycle) {
			godot::Dictionary lifecycle, thermal, store;
			GlowLifecycleModel &life = staged.lifecycle;
			if (!dec.dictionary(snapshot, "lifecycle", lifecycle) || !dec.dictionary(snapshot, "store", store) ||
					!dec.keys(lifecycle, "lifecycle", {"nominal_mixture", "idle_opening", "idle_offset", "travel_exponent",
							"throttle_capacity_m3_s", "servo_time_constant_s", "air_time_constant_s", "fuel_transport_time_constant_s",
							"lean_misfire_zero_ratio", "lean_misfire_start_ratio", "rich_misfire_start_ratio", "rich_misfire_zero_ratio",
							"temperature_firing_min_k", "temperature_firing_full_k", "temperature_firing_hot_full_k", "temperature_firing_hot_zero_k", "thermal"}) ||
					!dec.number(lifecycle, "nominal_mixture", life.nominal_mixture) || !dec.number(lifecycle, "idle_opening", life.idle_opening) ||
					!dec.number(lifecycle, "idle_offset", life.idle_offset) || !dec.number(lifecycle, "travel_exponent", life.travel_exponent) ||
					!dec.number(lifecycle, "throttle_capacity_m3_s", life.throttle_capacity_m3_s) ||
					!dec.number(lifecycle, "servo_time_constant_s", life.servo_time_constant_s) ||
					!dec.number(lifecycle, "air_time_constant_s", life.air_time_constant_s) ||
					!dec.number(lifecycle, "fuel_transport_time_constant_s", life.fuel_transport_time_constant_s) ||
					!dec.number(lifecycle, "lean_misfire_zero_ratio", life.lean_misfire_zero_ratio) ||
					!dec.number(lifecycle, "lean_misfire_start_ratio", life.lean_misfire_start_ratio) ||
					!dec.number(lifecycle, "rich_misfire_start_ratio", life.rich_misfire_start_ratio) ||
					!dec.number(lifecycle, "rich_misfire_zero_ratio", life.rich_misfire_zero_ratio) ||
					!dec.number(lifecycle, "temperature_firing_min_k", life.temperature_firing_min_k) ||
					!dec.number(lifecycle, "temperature_firing_full_k", life.temperature_firing_full_k) ||
					!dec.number(lifecycle, "temperature_firing_hot_full_k", life.temperature_firing_hot_full_k) ||
					!dec.number(lifecycle, "temperature_firing_hot_zero_k", life.temperature_firing_hot_zero_k) ||
					!dec.dictionary(lifecycle, "thermal", thermal) ||
					!dec.keys(thermal, "thermal", {"heat_capacity_j_k", "head_heat_fraction", "cooling_base_w_k",
							"cooling_airflow_w_s_m_k", "premix_evaporation_j_kg", "evaporation_head_fraction"}) ||
					!dec.number(thermal, "heat_capacity_j_k", life.thermal.heat_capacity_j_k) ||
					!dec.number(thermal, "head_heat_fraction", life.thermal.head_heat_fraction) ||
					!dec.number(thermal, "cooling_base_w_k", life.thermal.cooling_base_w_k) ||
					!dec.number(thermal, "cooling_airflow_w_s_m_k", life.thermal.cooling_airflow_w_s_m_k) ||
					!dec.number(thermal, "premix_evaporation_j_kg", life.thermal.premix_evaporation_j_kg) ||
					!dec.number(thermal, "evaporation_head_fraction", life.thermal.evaporation_head_fraction) ||
					!dec.keys(store, "store", {"main_capacity_kg", "unusable_kg", "has_line", "line_capacity_kg"}) ||
					!dec.number(store, "main_capacity_kg", staged.main_capacity_kg) ||
					!dec.number(store, "unusable_kg", staged.unusable_kg) ||
					!dec.number(store, "line_capacity_kg", staged.line_capacity_kg)) return failure(dec.error);
			if (!store.has("has_line") || store["has_line"].get_type() != godot::Variant::BOOL) return failure("missing glow line capability");
			staged.has_line = static_cast<bool>(store["has_line"]);
			const auto &t = life.thermal;
			if (life.nominal_mixture.v <= 0.0 || life.idle_opening.v <= 0.0 || life.idle_opening.v >= 1.0 ||
					life.idle_offset.v < 0.0 || life.idle_offset.v > 1.0 || life.travel_exponent.v <= 0.0 ||
					life.throttle_capacity_m3_s.v <= 0.0 || life.servo_time_constant_s.v <= 0.0 || life.air_time_constant_s.v <= 0.0 ||
					life.fuel_transport_time_constant_s.v <= 0.0 || life.lean_misfire_zero_ratio.v < 0.0 ||
					life.lean_misfire_zero_ratio.v >= life.lean_misfire_start_ratio.v || life.lean_misfire_start_ratio.v >= 1.0 ||
					life.rich_misfire_start_ratio.v <= 1.0 || life.rich_misfire_start_ratio.v >= life.rich_misfire_zero_ratio.v ||
					life.temperature_firing_min_k.v <= 0.0 || life.temperature_firing_min_k.v >= life.temperature_firing_full_k.v ||
					life.temperature_firing_full_k.v >= life.temperature_firing_hot_full_k.v ||
					life.temperature_firing_hot_full_k.v >= life.temperature_firing_hot_zero_k.v ||
					t.heat_capacity_j_k.v <= 0.0 || t.head_heat_fraction.v < 0.0 || t.head_heat_fraction.v > 1.0 ||
					t.cooling_base_w_k.v < 0.0 || t.cooling_airflow_w_s_m_k.v < 0.0 || t.premix_evaporation_j_kg.v < 0.0 ||
					t.evaporation_head_fraction.v < 0.0 || t.evaporation_head_fraction.v > 1.0 ||
					staged.main_capacity_kg.v <= 0.0 || staged.unusable_kg.v < 0.0 || staged.unusable_kg.v >= staged.main_capacity_kg.v ||
					(staged.has_line ? staged.line_capacity_kg.v <= 0.0 : staged.line_capacity_kg.v != 0.0) ||
					decoded_mass.resources.size() != static_cast<size_t>(staged.has_line ? 2 : 1) ||
					decoded_mass.resources[0].capacity_kg.v < staged.main_capacity_kg.v ||
					(staged.has_line && decoded_mass.resources[1].capacity_kg.v < staged.line_capacity_kg.v)) return failure("invalid glow lifecycle or store");
			life.source = source;
			staged.blade = decoded_blade;
			staged.mass = decoded_mass;
			staged.has_feed = decoded_has_feed;
			staged.feed = decoded_feed;
			staged.has_pickup = decoded_has_pickup;
			staged.pickup = decoded_pickup;
			staged.ready = true;
		}
		stage_model_ = std::move(staged);
		source_ = std::move(source);
		blade_ = decoded_blade;
		mass_ = std::move(decoded_mass);
		feed_ = decoded_feed;
		pickup_ = decoded_pickup;
		has_feed_ = decoded_has_feed;
		has_pickup_ = decoded_has_pickup;
		ready_ = true;
		godot::Dictionary out;
		out["ok"] = true;
		out["error"] = "";
		return out;
	}

	godot::Dictionary glow_source_component(double rpm, double admission, double mixture, double density,
			bool running, double firing) const {
		godot::Dictionary out;
		out["ok"] = false;
		out["unit_ok"] = false;
		if (!ready_) return out;
		const auto point = glow_source_evaluate(source_, rpm, admission, mixture, density, running, firing);
		const auto unit = glow_unit_fuel_flow(source_, rpm, admission, mixture, density);
		out["ok"] = point.ok;
		out["unit_ok"] = unit.ok;
		if (unit.ok) out["unit_flow"] = unit.kg_s_per_mixture.v;
		if (point.ok) out["values"] = pack({point.indicated_torque_nm, point.mechanical_torque_nm, point.pumping_torque_nm,
			point.valve_torque_nm, point.shaft_torque_nm, point.delivered_fuel_kg_s, point.burned_fuel_kg_s,
			point.unburned_fuel_kg_s, point.fuel_input_power_w, point.chemical_power_w, point.indicated_power_w,
			point.mechanical_loss_w, point.pumping_loss_w, point.valve_loss_w, point.cycle_work_j, point.air_charge_kg_cycle,
			point.cycle_frequency_hz, point.opportunity_frequency_hz, point.firing_frequency_hz, point.brake_power_w,
			point.unburned_chemical_power_w});
		return out;
	}

	godot::Dictionary glow_blade_component(double rpm, double axial, double density) const {
		godot::Dictionary out;
		out["ok"] = false;
		if (!ready_) return out;
		const auto point = glow_blade_evaluate(blade_, rpm, axial, density);
		out["ok"] = point.ok;
		if (point.ok) out["values"] = pack({point.thrust_n, point.torque_nm, point.shaft_power_w, point.thrust_power_w, point.dissipation_w});
		return out;
	}

	godot::Dictionary glow_mass_component(const godot::PackedFloat64Array &amounts) const {
		godot::Dictionary out;
		out["ok"] = false;
		if (!ready_ || amounts.size() != static_cast<int64_t>(mass_.resources.size())) return out;
		const auto input = amounts_as_r(amounts);
		const auto properties = liquid_mass_evaluate(mass_, input.data(), static_cast<int>(input.size()));
		out["ok"] = properties.ok;
		if (properties.ok) {
			std::vector<R> values{properties.mass_kg};
			values.insert(values.end(), properties.cg.begin(), properties.cg.end());
			values.insert(values.end(), properties.inertia.begin(), properties.inertia.end());
			values.insert(values.end(), properties.inverse.begin(), properties.inverse.end());
			values.insert(values.end(), properties.inertia_origin.begin(), properties.inertia_origin.end());
			out["values"] = pack(values);
		}
		return out;
	}

	// A valid context can still yield NaN when stage apparent gravity or pickup is
	// malformed; that matches FuelFeed.factor_for_stage's explicit failure signal.
	godot::Dictionary glow_feed_component(double remaining, double capacity, double unusable, double admission,
			double rpm, const godot::PackedFloat64Array &force, double mass, const godot::PackedFloat64Array &arm,
			const godot::PackedFloat64Array &alpha, const godot::PackedFloat64Array &omega) const {
		godot::Dictionary out;
		out["ok"] = false;
		if (!ready_ || !has_feed_) return out;
		const auto context = glow_feed_prepare_context(feed_, remaining, capacity, unusable, admission, rpm);
		out["ok"] = context.ok;
		if (!context.ok) return out;
		out["context"] = pack({context.fill_fraction, context.drive_pa, context.needled_head_pa});
		R factor = kNan;
		if (force.size() == 3 && arm.size() == 3 && alpha.size() == 3 && omega.size() == 3) {
			std::array<R, 3> f{}, a{}, acceleration{}, rate{};
			for (int i = 0; i < 3; ++i) { f[i] = force[i]; a[i] = arm[i]; acceleration[i] = alpha[i]; rate[i] = omega[i]; }
			factor = glow_feed_factor_for_stage(context, feed_, f.data(), mass, a.data(), acceleration.data(), rate.data(),
					has_pickup_ ? pickup_.data() : nullptr);
		}
		out["factor"] = factor.v;
		return out;
	}

	godot::Dictionary glow_body_component(const godot::PackedFloat64Array &body, const godot::PackedFloat64Array &amounts,
			const godot::PackedFloat64Array &force, const godot::PackedFloat64Array &moment, double gravity,
			const godot::PackedFloat64Array &rotor) const {
		godot::Dictionary out;
		out["ok"] = false;
		if (!ready_ || body.size() != 13 || force.size() != 3 || moment.size() != 3 || rotor.size() != 3 ||
				amounts.size() != static_cast<int64_t>(mass_.resources.size())) return out;
		const auto input = amounts_as_r(amounts);
		const auto properties = liquid_mass_evaluate(mass_, input.data(), static_cast<int>(input.size()));
		if (!properties.ok) return out;
		std::array<R, 13> s{};
		std::array<R, 3> f{}, m{}, h{};
		for (int i = 0; i < 13; ++i) s[i] = body[i];
		for (int i = 0; i < 3; ++i) { f[i] = force[i]; m[i] = moment[i]; h[i] = rotor[i]; }
		const auto derivative = liquid_fixed_datum_derivative(s.data(), properties, f.data(), m.data(), gravity, h.data());
		out["ok"] = true;
		out["values"] = pack(std::vector<R>(derivative.begin(), derivative.end()));
		return out;
	}
};

} // namespace nk
