## Separate bounded-work strategy draft; no new physical acceptance bound.
extends RefCounted
const Strict:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-tick-profile/resolution.gd")
const QP:=preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/gp12-tick-profile/traction.gd")
const LAW:=Strict.LAW
const STRATEGY:="bounded-eight-original-KKT-probe-certified-candidates-total-budget-v1"

static func solve(a:PackedFloat64Array,v:PackedFloat64Array,d:PackedFloat64Array,groups:Array,
        mass:PackedFloat64Array,j:PackedFloat64Array,z:PackedFloat64Array,bias:PackedFloat64Array,
        responses:PackedFloat64Array,ceiling:float,budget:int=QP.MAX_ITERATIONS)->Dictionary:
    if budget<1 or budget>QP.MAX_ITERATIONS or not is_finite(ceiling) or ceiling<0.0:
        return Strict.solve(a,v,d,groups,mass,j,z,bias,responses,ceiling,budget)
    var probe:=Strict._solve_with_work(a,v,d,groups,mass,j,z,bias,responses,ceiling,mini(8,budget),true)
    var first:Dictionary=probe.result
    # Every ordinary strict success <=8 retains COMPLETE original result bytes.
    if first.get("ok",false) and not first.has("assembly_resolution") and probe.work.range_proposal_calls==0:return first
    var work:=_work(probe.work)
    if first.get("ok",false):return _annotate(first,work,budget,1)
    var remaining:=budget-int(work.started_sweeps)
    if remaining<1 or first.get("status","")!="nonconverged":return _annotate(first,work,budget,1)
    # A deterministic restart uses ONLY the caller's REMAINING sweep budget.
    # Probe and restart proposals/witness work are explicitly accumulated.
    var fallback:=Strict._solve_with_work(a,v,d,groups,mass,j,z,bias,responses,ceiling,remaining,false)
    var extra:=_work(fallback.work)
    for key:String in work:work[key]+=extra[key]
    return _annotate(fallback.result,work,budget,2)

static func _work(source:Dictionary)->Dictionary:
    var qp:Dictionary=source.get("qp",{})
    return {started_sweeps=int(qp.get("started_sweeps",0)),spd_proposal_calls=int(qp.get("spd_proposal_calls",0)),
        interior_proposal_calls=int(qp.get("interior_proposal_calls",0)),extrapolation_calls=int(qp.get("extrapolation_calls",0)),
        range_proposal_calls=int(source.get("range_proposal_calls",0)),work_candidate_calls=int(source.get("work_candidate_calls",0))+int(source.get("strict_publication_calls",0))+int(qp.get("publication_work_calls",0)),
        publication_calls=int(source.get("strict_publication_calls",0))+int(qp.get("publication_work_calls",0)),assembly_witness_builds=int(source.get("assembly_witness_builds",0)),
        assembly_certificates=int(source.get("assembly_certificates",0))}

static func _annotate(result:Dictionary,work:Dictionary,budget:int,solves:int)->Dictionary:
    result.iterations=work.started_sweeps
    result.numerical_strategy=STRATEGY
    result.numerical_work=work.duplicate(true)
    result.numerical_work.caller_sweep_budget=budget
    result.numerical_work.strict_solve_calls=solves
    if result.has("assembly_resolution"):
        result.assembly_resolution.selection_strategy=STRATEGY
        result.assembly_resolution.total_started_sweeps=work.started_sweeps
    return result

static func bounds(a:PackedFloat64Array,v:PackedFloat64Array,mass:PackedFloat64Array,j:PackedFloat64Array,
        z:PackedFloat64Array,bias:PackedFloat64Array,responses:PackedFloat64Array)->Dictionary:
    return Strict.bounds(a,v,mass,j,z,bias,responses)
static func certificate(a:PackedFloat64Array,v:PackedFloat64Array,d:PackedFloat64Array,groups:Array,
        p:PackedFloat64Array,assembly:Dictionary)->Dictionary:
    return Strict.certificate(a,v,d,groups,p,assembly)
static func impulse_digest(p:PackedFloat64Array)->String:return Strict.impulse_digest(p)
static func _add(a:float,b:float)->float:return Strict._add(a,b)

static func slip_consistency(a:PackedFloat64Array,v:PackedFloat64Array,mass:PackedFloat64Array,
        j:PackedFloat64Array,z:PackedFloat64Array,bias:PackedFloat64Array,responses:PackedFloat64Array,
        p:PackedFloat64Array,g:PackedFloat64Array,delta:PackedFloat64Array,post:PackedFloat64Array)->Dictionary:
    return Strict.slip_consistency(a,v,mass,j,z,bias,responses,p,g,delta,post)
