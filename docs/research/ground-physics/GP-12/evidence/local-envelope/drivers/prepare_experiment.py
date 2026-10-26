from pathlib import Path
import hashlib,json
root=Path(__file__).resolve().parents[2]
folder=Path(__file__).resolve().parent
original=root/'tmp/gp12-local-reuse/composition.gd'
source=original.read_text(encoding='utf-8')
(folder/'composition-before.gd').write_bytes(original.read_bytes())
source=source.replace('var selected_law := Step.TWO_SIDED_LAW','''var selected_law := Step.TWO_SIDED_LAW
var use_local_interval := false
const IntervalNormal := preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp11-local-envelope/normal_compliance.gd")''')
old='''		var bound := Normal.bounds(support.normal, X_MAX, GAP_SPEED_MAX)
		var elastic := Normal.evaluate(support.normal, X_MAX, 0.0)'''
new='''		var xmin := 0.0
		var xmax := X_MAX
		var local_kappa := KAPPA_MIN
		if use_local_interval:
			local_kappa = kappa - h * OMEGA_MAX
			if record.geometry_evaluated:
				xmax = maxf(0.0, -record.gap_m) + h * GAP_SPEED_MAX
				xmin = maxf(0.0, -record.gap_m - h * GAP_SPEED_MAX)
		var bound := IntervalNormal.bounds_interval(support.normal, xmin, xmax, GAP_SPEED_MAX) if use_local_interval \\
			else Normal.bounds(support.normal, X_MAX, GAP_SPEED_MAX)
		if not bound.ok or not bound.continuous_onset: return {ok = false, admitted = false, identity = identity}
		var elastic := Normal.evaluate(support.normal, xmax, 0.0)'''
assert source.count(old)==1
source=source.replace(old,new)
old='normal_load_bound_n = elastic.elastic_force_n + bound.rate_derivative_bound_nsm * GAP_SPEED_MAX, kappa_min = KAPPA_MIN})'
assert source.count(old)==1
source=source.replace(old,'normal_load_bound_n = elastic.elastic_force_n + bound.rate_derivative_bound_nsm * GAP_SPEED_MAX, kappa_min = local_kappa})')
source=source.replace('var identity := "composition-plane-X.18-V3-Omega5-kappa.5-v1"','''var identity := "composition-plane-X.18-V3-Omega5-kappa.5-v1"
	if use_local_interval: identity = "composition-plane-local-compression-interval-V3-Omega5-kappa-lower-v1"''')
(folder/'composition.gd').write_text(source,encoding='utf-8',newline='\n')
paths=[original,root/'app/physics/normal_compliance.gd',root/'tmp/gp12-local-reuse/checkpoint-6s.bin',
 root/'tmp/gp12-local-reuse/checkpoint-10s.bin']
paths.extend(root/'tmp/gp12-local-reuse'/name for name in ['capture_step.gd','capture_impulse.gd','traction.gd','screened_resolution.gd','resolution.gd'])
rows=[{'path':p.relative_to(root).as_posix(),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()} for p in paths]
(folder/'frozen-source-before.json').write_text(json.dumps(rows,indent=2)+'\n',encoding='utf-8')
print('Prepared local-only certificate variant; old source/checkpoints untouched.')
