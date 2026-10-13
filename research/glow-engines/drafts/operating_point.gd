## Stable roots within the explicit engine envelope. All restoring roots are reported.
extends RefCounted
const Source := preload("res://physics/glow/source.gd")
const Prop := preload("res://physics/glow/propeller.gd")

static func source(prop: Dictionary, rpm: float, throttle: float, dry_density: float) -> Dictionary:
	var install: Dictionary = prop.glow
	var idle: float = install.settings.idle_admission
	return Source.evaluate(install.profile, rpm, idle + (1.0-idle)*throttle,
		install.profile.operation.nominal_mixture, dry_density)

static func residual(prop: Dictionary, rpm: float, throttle: float, u: float, rho: float, dry_density: float) -> float:
	var engine: Dictionary = source(prop,rpm,throttle,dry_density)
	var load: Dictionary = Prop.evaluate(rpm,u,rho,prop.glow.propeller)
	return engine.shaft_torque_nm-load.torque_nm if engine.ok and load.ok else NAN

static func solve(prop: Dictionary, throttle: float, u: float, rho: float, dry_density: float) -> Dictionary:
	for v in [throttle,u,rho,dry_density]:
		if not is_finite(v): return {ok=false, roots=PackedFloat64Array()}
	if throttle<0.0 or throttle>1.0 or rho<=0.0 or dry_density<=0.0: return {ok=false, roots=PackedFloat64Array()}
	var maximum: float = prop.glow.profile.operation.max_rpm
	var minimum: float = prop.glow.settings.stall_rpm
	var roots := PackedFloat64Array()
	var lo: float = minimum
	var flo: float = residual(prop,lo,throttle,u,rho,dry_density)
	for i in range(1,129):
		var hi: float = minimum+(maximum-minimum)*i/128.0
		var fhi: float = residual(prop,hi,throttle,u,rho,dry_density)
		if not is_finite(flo) or not is_finite(fhi): return {ok=false, roots=roots}
		if flo>0.0 and fhi<=0.0:
			var left: float=lo
			var right: float=hi
			for _iteration in 64:
				var mid: float=(left+right)*0.5
				var fm: float=residual(prop,mid,throttle,u,rho,dry_density)
				if not is_finite(fm): return {ok=false,roots=roots}
				if fm>0.0: left=mid
				else: right=mid
			var root: float=(left+right)*0.5
			if absf(residual(prop,root,throttle,u,rho,dry_density))>1e-10: return {ok=false,roots=roots}
			roots.append(root)
		lo=hi
		flo=fhi
	return {ok=not roots.is_empty(),roots=roots,rpm=roots[roots.size()-1] if not roots.is_empty() else NAN,
		selection="highest restoring root in supported envelope"}
