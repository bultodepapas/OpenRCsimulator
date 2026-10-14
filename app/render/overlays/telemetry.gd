# Flight overlay numbers (HUD-01/08/09, docs/plans/flight-overlays.md §3, §5). Pure: 64-bit state arrays in, SI floats
# out. Nothing here reads a node or writes to the session, so a trace never changes because an overlay is shown.
extends RefCounted

const RB := preload("res://physics/rigid_body.gd")
const M := preload("res://physics/math3d.gd")
const Spec := preload("res://spec.gd")
const PilotCamera := preload("res://render/pilot_camera.gd")

## D5: STALL shows within this margin of the solved stall-blend start (aircraft data, envelope a1/n1).
const STALL_MARGIN_DEG := 2.0
## Display thresholds, not physics: below them α is ill-defined (standing, taxiing) or the airplane is on its wheels.
const STALL_MIN_SPEED := 3.0 # m/s airspeed
const AIRBORNE_HEIGHT := 1.0 # m CG above the ground
## LOW: the current sink rate would reach the ground within this time, sinking faster than a landing approach.
const LOW_TIME_S := 2.0
const LOW_MIN_SINK := 2.0 # m/s
## FAR: even the narrowest auto-zoom shows the span smaller than the readable target (Spec.AUTO_ZOOM, 720 px tall).
const FAR_VIEW_H := 720.0
const BATTERY_LOW_SOC := 0.2


## state: rigid-body state (RB layout); wind_ned: m/s; air: Air.compute() of that state.
## ctx: { pilot_ned: [n, e, d] of the pilot's eye, terrain_up: ground height under the aircraft (m, up),
## last_loads: body forces without gravity (sim.last_loads), mass (kg), gravity (m/s²), throttle (0…1), time_s }.
static func compute(state: PackedFloat64Array, wind_ned: PackedFloat64Array, air: Dictionary, ctx: Dictionary) -> Dictionary:
	var q := M.quat(state[RB.ATT], state[RB.ATT + 1], state[RB.ATT + 2], state[RB.ATT + 3])
	var v_ned := M.q_rotate(q, M.v3(state[RB.VEL], state[RB.VEL + 1], state[RB.VEL + 2]))
	var euler := M.q_to_euler(q)
	var pilot: Array = ctx.get("pilot_ned", [0.0, 0.0, 0.0])
	var dn: float = state[RB.POS] - float(pilot[0])
	var de: float = state[RB.POS + 1] - float(pilot[1])
	var dd: float = state[RB.POS + 2] - float(pilot[2])
	var loads: PackedFloat64Array = ctx.get("last_loads", PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]))
	var weight: float = float(ctx.get("mass", 1.0)) * float(ctx.get("gravity", 9.80665))
	var wind_h := M.sqrt_(wind_ned[0] * wind_ned[0] + wind_ned[1] * wind_ned[1])
	return {
		airspeed = float(air.V),
		ground_speed = M.sqrt_(v_ned[0] * v_ned[0] + v_ned[1] * v_ned[1]),
		vertical_speed = -v_ned[2],
		height_datum = -state[RB.POS + 2],
		height_agl = -state[RB.POS + 2] - float(ctx.get("terrain_up", 0.0)),
		distance_pilot = M.sqrt_(dn * dn + de * de + dd * dd),
		alpha_deg = rad_to_deg(float(air.alpha)),
		beta_deg = rad_to_deg(float(air.beta)),
		heading_deg = fposmod(rad_to_deg(euler[0]), 360.0),
		pitch_deg = rad_to_deg(euler[1]),
		bank_deg = rad_to_deg(euler[2]),
		# Load factor: specific force along body −z over g; 1 in level flight, 1/cos φ in a steady level turn.
		load_factor = -loads[2] / weight if weight > 0.0 else 0.0,
		throttle = float(ctx.get("throttle", 0.0)),
		time_s = float(ctx.get("time_s", 0.0)),
		wind_speed = wind_h,
		wind_up = -wind_ned[2],
		# Meteorological "from" bearing; NAN for calm or a purely vertical current.
		wind_from_deg = fposmod(rad_to_deg(M.atan2_(-wind_ned[1], -wind_ned[0])), 360.0) if wind_h > 0.0 else NAN,
	}


## Screen angle (degrees clockwise from "up") of the arrow showing where the wind blows TO, for a camera looking
## toward `view_heading_deg`. Up on the screen is straight ahead of the pilot.
static func wind_arrow_deg(wind_from_deg: float, view_heading_deg: float) -> float:
	return fposmod(wind_from_deg + 180.0 - view_heading_deg, 360.0)


## Compass heading (degrees) of a render-frame forward vector (x = east, y = up, z = −north).
static func heading_of_render_forward(x: float, z: float) -> float:
	return fposmod(rad_to_deg(M.atan2_(x, -z)), 360.0)


## Distance (m) beyond which the narrowest auto-zoom shows `span` below the readable target size.
static func far_distance(span: float) -> float:
	var at_one_m := PilotCamera.projected_px(span, 1.0, float(Spec.AUTO_ZOOM.min_fov_deg), FAR_VIEW_H)
	return at_one_m / float(Spec.AUTO_ZOOM.target_px)


## Active warning codes, most urgent first (plan §5). t: compute() output. ctx: { radio_connected, armed,
## pause_reason, stall_pos_deg, stall_neg_deg (NAN = unknown: no STALL), span (m), battery: {} or
## electrical_state(), experimental }.
static func warnings(t: Dictionary, ctx: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if ctx.get("controller_lost", false):
		out.append("controller_lost")
	elif str(ctx.get("pause_reason", "")) == "radio disconnected":
		out.append("failsafe")
	if ctx.get("radio_connected", false) and not ctx.get("armed", false):
		out.append("gamepad_safe" if ctx.get("controller_kind", "radio") == "gamepad" else "safe")
	var airborne: bool = float(t.height_agl) > AIRBORNE_HEIGHT
	var stall_pos: float = float(ctx.get("stall_pos_deg", NAN))
	var stall_neg: float = float(ctx.get("stall_neg_deg", NAN))
	if airborne and float(t.airspeed) >= STALL_MIN_SPEED and is_finite(stall_pos) and is_finite(stall_neg):
		var a: float = float(t.alpha_deg)
		if a >= stall_pos - STALL_MARGIN_DEG or a <= -(stall_neg - STALL_MARGIN_DEG):
			out.append("stall")
	var sink: float = -float(t.vertical_speed)
	if airborne and sink > LOW_MIN_SINK and float(t.height_agl) < sink * LOW_TIME_S:
		out.append("low")
	var span: float = float(ctx.get("span", 0.0))
	if span > 0.0 and float(t.distance_pilot) > far_distance(span):
		out.append("far")
	var battery: Dictionary = ctx.get("battery", {})
	if battery.get("ok", false) and (battery.get("exhausted", false) or float(battery.get("soc", 1.0)) < BATTERY_LOW_SOC):
		out.append("battery")
	if ctx.get("experimental", false):
		out.append("experimental")
	return out
