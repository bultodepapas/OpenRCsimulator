extends RefCounted
## Accepted-position evidence for one continuous clockwise lap enclosing the runway.
## Guidance is experimental. This observer never changes simulation state.

const FORMAT := "openrc-godtest-runway-circuit-v1"
const MIN_AGL_M := 20.0
const MAX_AGL_M := 140.0
const MAX_BEARING_STEP := PI / 4.0
const SWEEP_ROUNDING_RAD := 1.0e-9 # Only floating-point closure, far below a measurable route segment.

var center_north_m := 0.0
var center_east_m := 0.0
var radius_m := 0.0
var runway_radius_m := 0.0
var inner_radius_m := 0.0
var outer_radius_m := 0.0
var configured := false
var acquired := false
var complete := false
var failed := false
var reason := ""
var sweep_rad := 0.0
var quadrants := 0
var resets := 0
var samples := 0
var last_tick := -1
var last_sim_s := -1.0
var previous_bearing := 0.0
var previous_north := 0.0
var previous_east := 0.0
var lap_start_sim_s := 0.0
var lap_end_sim_s := 0.0
var minimum_radius_m := 0.0
var maximum_radius_m := 0.0
var minimum_agl_m := 0.0
var maximum_agl_m := 0.0


func configure(surface: Dictionary, speed_mps: float) -> Dictionary:
	for key: String in ["center_north", "center_east", "length_east_west", "width_north_south"]:
		var value: Variant = surface.get(key)
		if not (value is float or value is int) or not is_finite(float(value)):
			return {ok = false, reason = "runway geometry must contain finite normalized scalars"}
	if float(surface.length_east_west) <= 0.0 or float(surface.width_north_south) <= 0.0 or not is_finite(speed_mps) or speed_mps < 5.0:
		return {ok = false, reason = "positive runway dimensions and a usable trim speed are required"}
	center_north_m = float(surface.center_north)
	center_east_m = float(surface.center_east)
	runway_radius_m = 0.5 * sqrt(pow(float(surface.length_east_west), 2) + pow(float(surface.width_north_south), 2))
	# Twenty-degree nominal bank leaves authority below the existing pilot's bank limit.
	radius_m = maxf(maxf(120.0, runway_radius_m + 60.0), speed_mps * speed_mps / (9.80665 * tan(deg_to_rad(20.0))))
	inner_radius_m = maxf(runway_radius_m + 20.0, radius_m * 0.65)
	outer_radius_m = radius_m * 1.65
	configured = true
	return {ok = true, geometry = receipt()}


func course(north_m: float, east_m: float) -> float:
	var dn := north_m - center_north_m
	var de := east_m - center_east_m
	var distance := sqrt(dn * dn + de * de)
	return atan2(de, dn) + PI / 2.0 + atan2(distance - radius_m, radius_m * 0.5)


func observe(north_m: float, east_m: float, agl_m: float, tick: int, sim_s: float) -> Dictionary:
	if complete or failed: return receipt()
	if not configured or not is_finite(north_m) or not is_finite(east_m) or not is_finite(agl_m) or not is_finite(sim_s) or tick < 0 or sim_s < 0.0:
		return _refuse("invalid accepted-position sample")
	if last_tick >= 0 and (tick <= last_tick or sim_s <= last_sim_s):
		return _refuse("nonmonotonic circuit tick or simulation clock")
	last_tick = tick
	last_sim_s = sim_s
	samples += 1
	var dn := north_m - center_north_m
	var de := east_m - center_east_m
	var distance := sqrt(dn * dn + de * de)
	if distance < inner_radius_m or distance > outer_radius_m or agl_m < MIN_AGL_M or agl_m > MAX_AGL_M:
		_reset_lap()
		return receipt()
	var bearing := atan2(de, dn)
	if not acquired:
		acquired = true
		lap_start_sim_s = sim_s
		minimum_radius_m = distance
		maximum_radius_m = distance
		minimum_agl_m = agl_m
		maximum_agl_m = agl_m
	else:
		var step := wrapf(bearing - previous_bearing, -PI, PI)
		if absf(step) > MAX_BEARING_STEP:
			return _refuse("circuit position jump is too large to establish angular continuity")
		# Both endpoints can be outside the runway while their connecting segment cuts it.
		var sn := dn - previous_north
		var se := de - previous_east
		var length_squared := sn * sn + se * se
		var along := clampf(-(previous_north * sn + previous_east * se) / length_squared, 0.0, 1.0) if length_squared > 0.0 else 0.0
		var nearest_n := previous_north + along * sn
		var nearest_e := previous_east + along * se
		if sqrt(nearest_n * nearest_n + nearest_e * nearest_e) <= runway_radius_m + 10.0:
			_reset_lap()
			return receipt()
		sweep_rad += step # Signed progress: rocking or a left circuit cannot pass.
		minimum_radius_m = minf(minimum_radius_m, distance)
		maximum_radius_m = maxf(maximum_radius_m, distance)
		minimum_agl_m = minf(minimum_agl_m, agl_m)
		maximum_agl_m = maxf(maximum_agl_m, agl_m)
	previous_bearing = bearing
	previous_north = dn
	previous_east = de
	# A tiny negative bearing can round to exactly TAU after fposmod; that is
	# quadrant zero, never a fifth quadrant that invalidates an otherwise full lap.
	quadrants |= 1 << (int(floor(fposmod(bearing, TAU) / (PI / 2.0))) % 4)
	lap_end_sim_s = sim_s
	complete = sweep_rad >= TAU - SWEEP_ROUNDING_RAD and quadrants == 15 and sim_s - lap_start_sim_s >= 10.0
	return receipt()


func _reset_lap() -> void:
	if acquired: resets += 1
	acquired = false
	sweep_rad = 0.0
	quadrants = 0
	lap_start_sim_s = 0.0
	lap_end_sim_s = 0.0


func _refuse(message: String) -> Dictionary:
	failed = true
	reason = message
	return receipt()


func receipt() -> Dictionary:
	return {format = FORMAT, complete = complete, failed = failed, reason = reason,
		center_north_m = center_north_m, center_east_m = center_east_m,
		target_radius_m = radius_m, runway_enclosing_radius_m = runway_radius_m,
		inner_radius_m = inner_radius_m, outer_radius_m = outer_radius_m,
		agl_limits_m = [MIN_AGL_M, MAX_AGL_M], acquired = acquired,
		clockwise_sweep_rad = sweep_rad, quadrants_mask = quadrants, acquisition_resets = resets,
		accepted_samples = samples, lap_sim_seconds = lap_end_sim_s - lap_start_sim_s,
		minimum_radius_m = minimum_radius_m if acquired else null,
		maximum_radius_m = maximum_radius_m if acquired else null,
		minimum_agl_m = minimum_agl_m if acquired else null,
		maximum_agl_m = maximum_agl_m if acquired else null,
		evidence = "accepted NED positions; continuous annulus and signed winding about the runtime runway"}
