## Bounded proposal-work policy; all physical acceptance stays with AR/QP.
extends RefCounted
const Strict:=preload("res://physics/contact_assembly_resolution.gd")
const QP:=preload("res://physics/ground_traction.gd")
const STRATEGY:="bounded-eight-original-KKT-probe-certified-candidates-total-budget-v1"

static func solve(a:PackedFloat64Array,v:PackedFloat64Array,d:PackedFloat64Array,groups:Array,
        mass:PackedFloat64Array,j:PackedFloat64Array,z:PackedFloat64Array,bias:PackedFloat64Array,
        responses:PackedFloat64Array,ceiling:float,budget:int=QP.MAX_ITERATIONS)->Dictionary:
    return _solve_local(a,v,d,groups,mass,j,z,bias,responses,ceiling,budget,{})

static func _solve_local(a:PackedFloat64Array,v:PackedFloat64Array,d:PackedFloat64Array,groups:Array,
        mass:PackedFloat64Array,j:PackedFloat64Array,z:PackedFloat64Array,bias:PackedFloat64Array,
        responses:PackedFloat64Array,ceiling:float,budget:int,memo:Dictionary)->Dictionary:
    if budget<1 or budget>QP.MAX_ITERATIONS or not is_finite(ceiling) or ceiling<0.0:
        return Strict.solve(a,v,d,groups,mass,j,z,bias,responses,ceiling,budget)
    var probe:=Strict._solve_with_work(a,v,d,groups,mass,j,z,bias,responses,ceiling,mini(8,budget),true,memo)
    var first:Dictionary=probe.result
    # Every ordinary strict success <=8 retains COMPLETE original result bytes.
    if first.get("ok",false) and not first.has("assembly_resolution") and probe.work.range_proposal_calls==0:return first
    var work:=_work(probe.work)
    if first.get("ok",false):return _annotate(first,work,budget,1)
    var remaining:=budget-int(work.started_sweeps)
    if remaining<1 or first.get("status","")!="nonconverged":return _annotate(first,work,budget,1)
    # A deterministic restart uses ONLY the caller's REMAINING sweep budget.
    # Probe and restart proposals/witness work are explicitly accumulated.
    var fallback:=Strict._solve_with_work(a,v,d,groups,mass,j,z,bias,responses,ceiling,remaining,false,memo,true)
    var extra:=_work(fallback.work)
    for key:String in work:work[key]+=extra[key]
    return _annotate(fallback.result,work,budget,2)

static func _work(source:Dictionary)->Dictionary:
    var qp:Dictionary=source.get("qp",{})
    return {started_sweeps=int(qp.get("started_sweeps",0)),spd_proposal_calls=int(qp.get("spd_proposal_calls",0)),
        interior_proposal_calls=int(qp.get("interior_proposal_calls",0)),extrapolation_calls=int(qp.get("extrapolation_calls",0)),
        unresolved_descent_calls=int(qp.get("unresolved_descent_calls",0)),range_proposal_calls=int(source.get("range_proposal_calls",0)),work_candidate_calls=int(source.get("work_candidate_calls",0))+int(source.get("strict_publication_calls",0))+int(qp.get("publication_work_calls",0)),
        publication_calls=int(source.get("strict_publication_calls",0))+int(qp.get("publication_work_calls",0)),assembly_witness_builds=int(source.get("assembly_witness_builds",0)),
        assembly_certificates=int(source.get("assembly_certificates",0)),assembly_witness_requests=int(source.get("assembly_witness_requests",0))}

static func _annotate(result:Dictionary,work:Dictionary,budget:int,solves:int)->Dictionary:
    result.iterations=work.started_sweeps
    var selected:=STRATEGY
    if work.get("unresolved_descent_calls",0)>0:selected="bounded-eight-KKT-probe-unresolved-descent-certified-fallback-v2"
    result.numerical_strategy=selected
    result.numerical_work=work.duplicate(true)
    if result.numerical_work.get("unresolved_descent_calls",0)==0:result.numerical_work.erase("unresolved_descent_calls")
    result.numerical_work.caller_sweep_budget=budget
    result.numerical_work.strict_solve_calls=solves
    if result.has("assembly_resolution"):
        result.assembly_resolution.selection_strategy=selected
        result.assembly_resolution.total_started_sweeps=work.started_sweeps
    return result
