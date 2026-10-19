extends SceneTree
const Step := preload("res://physics/resource_event_step.gd")
func _initialize() -> void:
	for fixture: Dictionary in [{name="positive endpoint below residual tolerance",amount=1.0,rate=1.0,dt=1.0-5e-11},
		{name="tiny positive resource must still exhaust",amount=5e-11,rate=1e-6,dt=1e-3}]:
		var state := PackedFloat64Array()
		state.resize(13)
		state[0]=fixture.amount
		state[6]=1.0
		var rate: float=fixture.rate
		var derivative: Callable=func(values: PackedFloat64Array,_at: float) -> PackedFloat64Array:
			var result := PackedFloat64Array()
			result.resize(13)
			result[0]=-rate if values[1]==0.0 else 0.0
			return result
		var event: Dictionary={id="empty",type="empty",surface_unit="kg",sense="falling",
			enabled=func(values: PackedFloat64Array,_at: float) -> bool: return values[1]==0.0,
			surface=func(values: PackedFloat64Array,_at: float) -> float: return values[0],
			transition=func(values: PackedFloat64Array,_at: float) -> Dictionary:
				values[0]=0.0
				values[1]=1.0
				return {ok=true,state=values}}
		var result: Dictionary=Step.advance(state,0.0,fixture.dt,derivative,PackedFloat64Array(),[event])
		print(fixture.name,": ",result)
	quit()
