## Independent identities/counterexamples, not aircraft or runtime admission.
extends SceneTree
const Normal:=preload("res://physics/normal_compliance.gd")
var checks:=0
var failures:=0

func check(label:String,ok:bool)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL ",label)

func _law()->Dictionary:
	var values:={stiffness=1000.0,compression_damping=3.0,rebound_damping=8.0,damping_onset=.002,
		stroke=.02,stop_stiffness=3000.0,stop_scale=.01,stop_exponent=3.0,stop_damping=5.0}
	var raw:={format=Normal.FORMAT}
	for key:String in values:
		raw[key]={value=values[key],unit=Normal.SPECS[key][0],kind="derived",source="Independent analytic heat-identity numerical fixture"}
	return Normal.prepare(raw)

func _bump(t:float)->PackedFloat64Array:
	var f:float=t*(t-.5)*(t-1.0)
	var df:float=3.0*t*t-3.0*t+.5
	return PackedFloat64Array([.064*f*f,.128*f*df])

func _initialize()->void:
	var law:=_law()
	var start:=Normal.evaluate(law,.001,-1.0)
	var end:=Normal.evaluate(law,-.001,-1.0)
	check("fixed-law fixture is clipped compressed unloading",law.ok and start.normal_load_n==0.0 and start.clipped)
	check("gap exit leaves exactly zero normal potential",end.potential_j==0.0 and end.normal_load_n==0.0)
	var exact:float=start.potential_j-end.potential_j
	check("known antiderivative is initial spring energy",absf(exact-.0005)<1e-18)
	var heat:=0.0
	var all_zero:=true
	var monotone:=true
	var previous:float=start.potential_j
	for i in 512:
		var t:float=.002*(i+.5)/512.0
		var point:=Normal.evaluate(law,.001-t,-1.0)
		heat+=point.dissipation_w*.002/512.0
		all_zero=all_zero and point.normal_load_n==0.0
		monotone=monotone and point.potential_j<=previous
		previous=point.potential_j
	check("entire analytic clipped/gap-exit trajectory has zero reaction",all_zero)
	check("independent rate integral matches exact potential difference",absf(heat-exact)<1e-17)
	check("normal potential is nonincreasing without a heat clamp",monotone)
	check("detached endpoints give zero normal heat",Normal.evaluate(law,-.1,2.0).potential_j-Normal.evaluate(law,-.2,2.0).potential_j==0.0)
	# Body gravity changes independently of normal constitutive potential.
	var fake_gravity_heat:float=(-2.0*9.80665*1.0)-(-2.0*9.80665*2.0)
	check("using combined gravity potential would manufacture nonzero detached heat",fake_gravity_heat>19.0 and end.potential_j==0.0)
	# For x=1-t/2, k=1+t and N=0 supplied by a large rebound damper,
	# D=integral(-k*x*xdot)=13/24; endpoint V drop=1/4. Parameter
	# work integral(.5*kdot*x^2)=7/24 is missing from the frozen-law identity.
	check("time-varying stiffness invalidates endpoint-only identity",absf(13.0/24.0-.25-7.0/24.0)<1e-15)
	# A manufactured smooth compression cycle has zeros at EVERY distinct RK4
	# stage time0,.5,1, yet loads between them. Counts/zero samples are no guard.
	var stages_zero:=true
	for t:float in [0.0,.5,.5,1.0]:
		var p:=_bump(t)
		stages_zero=stages_zero and Normal.evaluate(law,p[0],p[1]).normal_load_n==0.0
	var middle:=_bump(.25)
	var loaded:=Normal.evaluate(law,middle[0],middle[1])
	check("all four zero RK samples alone miss interior normal force",stages_zero and loaded.normal_load_n>.1)
	var cycle_heat:=0.0
	for i in 4096:
		var p:=_bump((i+.5)/4096.0)
		cycle_heat+=Normal.evaluate(law,p[0],p[1]).dissipation_w/4096.0
	check("loaded/mixed cycle cannot telescope zero endpoint potential into heat",cycle_heat>1e-10)
	print("CONSTITUTIVE_HEAT_ORACLES ",JSON.stringify({unloaded_heat_j=exact,independent_integral_j=heat,
		hidden_interstage_load_n=loaded.normal_load_n,hidden_cycle_heat_j=cycle_heat,endpoint_potential_drop_j=0.0}))
	print("Independent unloaded heat review: %d checks, %d failed"%[checks,failures])
	quit(1 if failures else 0)
