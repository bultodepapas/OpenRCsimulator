// GlowFlight._stage_mass_context and properties resource selection. Preserves
// separately clipped main and line inventories during left-limit trial states.
#pragma once

#include "nk_liquid_mass.hpp"

namespace nk {

struct GlowStageMass {
	bool ok = false;
	R main_fuel_kg = 0.0;
	R line_fuel_kg = 0.0;
	R total_fuel_kg = 0.0;
	LiquidMassProperties properties;
};

inline GlowStageMass glow_stage_mass(const LiquidMassModel &model, R raw_total, R raw_line,
		R main_capacity, bool has_line, R line_capacity) {
	GlowStageMass out;
	if (!is_finite(raw_total) || !is_finite(raw_line)) return out;
	const R line = clampf(raw_line, 0.0, has_line ? line_capacity : R(0.0));
	const R main = clampf(raw_total - raw_line, 0.0, main_capacity);
	const R total = main + line;
	LiquidMassProperties properties;
	if (has_line) {
		const R reconstructed_main = total - line; // GlowFlight.properties subtracts the line again.
		const R amounts[2] = {clampf(reconstructed_main, 0.0, main_capacity), clampf(line, 0.0, line_capacity)};
		properties = liquid_mass_evaluate(model, amounts, 2);
	} else {
		if (absf(line).v > 1e-15) return out;
		const R amounts[1] = {clampf(total, 0.0, main_capacity)};
		properties = liquid_mass_evaluate(model, amounts, 1);
	}
	if (!properties.ok) return out;
	out.ok = true;
	out.main_fuel_kg = main;
	out.line_fuel_kg = line;
	out.total_fuel_kg = total;
	out.properties = properties;
	return out;
}

} // namespace nk
