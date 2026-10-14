# HELI-33: the existing deterministic ground-cycle pilot with production scenery.
extends "../ground_start/cycles.gd"
const CollisionSetup=preload("res://scenery/collision_setup.gd")
func run_cycle(cycle: int) -> Dictionary:
 if cycle==0:
  var world: Dictionary=CollisionSetup.build(Field.load_from(Field.DEFAULT_PATH).field)
  if not world.ok or not session.set_collision_world(world.world) or not session.reset():
   failure="production obstacle inventory refused"
   return {ok=false,failure=failure}
 return super.run_cycle(cycle)
