# HELI-07b/20b: deterministic one-speed trainer power lifecycle.
# Four seconds is an explicit simulator soft-start estimate, not an ESC measurement.
extends RefCounted
const LAW := "openrc-helicopter-soft-start-v1"
const SOFT_START_S := 4.0
const PICKUP_TOLERANCE_RAD := PI / 180.0

static func initial(airborne: bool) -> Dictionary:
	return {armed=airborne, spool_start_s=-SOFT_START_S if airborne else 0.0}

static func valid(value: Variant, time_s: float) -> bool:
	return value is Dictionary and value.size()==2 and value.has_all(["armed","spool_start_s"]) \
		and value.armed is bool and typeof(value.spool_start_s) in [TYPE_FLOAT,TYPE_INT] \
		and is_finite(float(value.spool_start_s)) and value.spool_start_s>=-SOFT_START_S \
		and value.spool_start_s<=time_s

static func scale(power: Dictionary, hold: bool, time_s: float) -> float:
	if not power.armed or hold: return 0.0
	var u: float=clampf((time_s-float(power.spool_start_s))/SOFT_START_S,0.0,1.0)
	return u*u*(3.0-2.0*u)

static func phase(power: Dictionary, hold: bool, time_s: float, omega: float, target: float) -> String:
	if not power.armed: return "DISARMED"
	if hold: return "HOLD"
	if scale(power,hold,time_s)<1.0 or omega<.95*target: return "SPOOLING"
	return "GOVERNED"

# Invert the accepted piecewise-linear pitch curve at zero cyclic. Refuse a plateau,
# multiple roots or unreachable requested pitch rather than choosing a magic stick value.
static func collective_for_pitch(model: Dictionary, mode: String, pitch_rad: float) -> Dictionary:
	if not model.has_all(["curves_by_mode","linkage"]) or not model.curves_by_mode.has(mode) or not is_finite(pitch_rad):
		return {ok=false,reason="No accepted collective curve for this start."}
	var gain: float=model.linkage.collective_rad_per_unit
	if not is_finite(gain) or gain<=0.0 or pitch_rad<model.linkage.collective_min_rad or pitch_rad>model.linkage.collective_max_rad:
		return {ok=false,reason="Startup pitch is outside the accepted linkage travel."}
	var target: float=pitch_rad/gain
	var curve: Variant=model.curves_by_mode[mode].pitch
	var roots: Array[float]=[]
	for i: int in range(curve.size()-1):
		var a: float=curve[i]
		var b: float=curve[i+1]
		if a==b:
			if target==a: return {ok=false,reason="Startup collective lies on an ambiguous pitch plateau."}
			continue
		if target<minf(a,b) or target>maxf(a,b): continue
		var stick: float=-1.0+2.0*(float(i)+(target-a)/(b-a))/float(curve.size()-1)
		if roots.is_empty() or absf(roots[-1]-stick)>1e-12: roots.append(stick)
	if roots.size()!=1: return {ok=false,reason="Startup pitch must have exactly one accepted stick position."}
	return {ok=true,stick=roots[0],collective=.5*(roots[0]+1.0),pitch_rad=pitch_rad}
