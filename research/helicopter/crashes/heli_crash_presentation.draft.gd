# HELI-33: disposable helicopter aftermath. Never writes accepted simulation state.
extends Node3D
const Wreck=preload("res://render/rotor/heli_wreck.gd")
const Effects=preload("res://render/crash/effects.gd")
const CrashAudio=preload("res://render/crash/crash_audio.gd")
const SceneryBodies=preload("res://render/landscape_upgrade/scenery_bodies.gd")
const Frames=preload("res://render/frames.gd")
var active: bool=false
var audio_enabled: bool=true
var wreck: Node3D
var effects: Node3D
var audio: Node3D
var _composite_dust: CPUParticles3D
var _scenery_contacts: Node3D
var _world: Dictionary={}
var _ground_frame: Transform3D=Transform3D.IDENTITY
var _age: float=0.0
var _paused: bool=false
var _secondary_at: float=-1.0
var _mass: float=1.0
var _surface: String="grass"
var _report: Dictionary={}
var start_usec: int=0
var _emitter_defaults: Array[Dictionary]=[]

func configure(model: Dictionary,context: Dictionary) -> bool:
 if wreck!=null: return false
 _mass=float(context.mass_kg)
 wreck=Wreck.new(); wreck.name="HelicopterWreck"; add_child(wreck)
 if not wreck.configure(model,context): return false
 wreck.secondary_impact.connect(_secondary)
 effects=Effects.new(); effects.name="HelicopterImpactEffects"; add_child(effects)
 effects.prepare()
 effects.set_debris_colors([Color(.025,.028,.03),Color(.12,.13,.14),Color(.95,.26,.015),Color(.85,.86,.87)])
 # Nonthermal ejecta receive the same field lighting as the wreck at night.
 for emitter: CPUParticles3D in [effects.dust,effects.touch_dust]:
  var material: StandardMaterial3D=emitter.mesh.material
  material.shading_mode=BaseMaterial3D.SHADING_MODE_PER_PIXEL
 audio=CrashAudio.new(); audio.name="HelicopterImpactAudio"; add_child(audio); audio.setup()
 _composite_dust=effects._particles(48,1.7,load("res://assets/crash/smoke.png"),false)
 _composite_dust.name="CompositeImpactDust"
 _composite_dust.one_shot=true
 _composite_dust.explosiveness=.92
 _composite_dust.spread=45.0
 _composite_dust.emission_sphere_radius=.04
 _composite_dust.initial_velocity_min=.3
 _composite_dust.initial_velocity_max=2.2
 _composite_dust.scale_amount_min=.035
 _composite_dust.scale_amount_max=.11
 _composite_dust.scale_amount_curve=effects._curve([Vector2(0,.4),Vector2(.5,1.5),Vector2(1,2.4)])
 _composite_dust.color_ramp=effects._gradient([Color(.28,.29,.30,0),Color(.34,.35,.36,.38),Color(.45,.46,.47,0)],[0.0,.08,1.0])
 (_composite_dust.mesh.material as StandardMaterial3D).shading_mode=BaseMaterial3D.SHADING_MODE_PER_PIXEL
 for emitter: CPUParticles3D in effects.emitters:
  _emitter_defaults.append({node=emitter,direction=emitter.direction,gravity=emitter.gravity})
 reset()
 return true

func set_collision_world(world: Dictionary) -> void:
 _world=world.duplicate(true)

func start(report: Dictionary,pose: Transform3D,cg_model: Vector3,wind: Vector3) -> void:
 if wreck==null or report.is_empty(): return
 var began: int=Time.get_ticks_usec()
 reset()
 _report=report.duplicate(true)
 _surface=str(report.get("surface","grass"))
 wreck.start_impact(report,pose,cg_model)
 var severity: Dictionary=wreck.severity
 var point: Vector3=Frames.ned_to_render(report.point_world_ned)
 var ground: Vector3=Frames.ned_to_render(report.get("ground_point_world_ned",report.point_world_ned))
 var up: Vector3=Frames.ned_to_render(report.get("ground_normal_world_ned",PackedFloat64Array([0,0,-1]))).normalized()
 var axis_x: Vector3=Vector3.RIGHT-up*up.dot(Vector3.RIGHT)
 if axis_x.length_squared()<.01: axis_x=Vector3.FORWARD-up*up.dot(Vector3.FORWARD)
 axis_x=axis_x.normalized()
 _ground_frame=Transform3D(Basis(axis_x,up,axis_x.cross(up)),ground)
 effects.transform=_ground_frame
 var inverse: Transform3D=_ground_frame.affine_inverse()
 var local_point: Vector3=inverse*point
 var velocity: Vector3=Frames.ned_to_render(report.velocity_world_ned)
 var local_velocity: Vector3=inverse.basis*velocity
 for binding: Dictionary in _emitter_defaults:
  binding.node.direction=binding.direction
  binding.node.gravity=binding.gravity
 effects.start(local_point,local_velocity,severity,0.0,false,inverse.basis*wind)
 # Shared flat-field effects mix global particle anchors with local marks/chips.
 # Keep its solver in a tangent frame and convert only emitter anchors/directions.
 for emitter: CPUParticles3D in effects.emitters:
  emitter.global_position=_ground_frame*Vector3(local_point.x,.04,local_point.z)
  emitter.direction=_ground_frame.basis*emitter.direction
  emitter.gravity=_ground_frame.basis*emitter.gravity
 effects.dust.gravity+=wind.limit_length(8.0)*.12
 var component: String=str(report.get("component",""))
 var rotor: bool=component in ["main_rotor","tail_rotor"]
 if rotor and int(severity.get("class",0))>=2:
  var tangent: Vector3=Frames.ned_to_render(report.get("point_velocity_world_ned",report.velocity_world_ned))
  effects.blade_chips.global_position=point
  effects.blade_chips.direction=(tangent.limit_length(10.0)+up*2.0).normalized()
  effects.blade_chips.visible=true
  effects.blade_chips.restart()
  effects.blade_chips.emitting=true
 if (rotor and int(severity.get("class",0))>=2) or int(severity.get("class",0))>=3:
  _composite_dust.global_position=ground+up*(maxf(local_point.y,0.0)+.025)
  _composite_dust.direction=(velocity.limit_length(4.0)+up*1.5).normalized()
  _composite_dust.gravity=wind.limit_length(8.0)*.15-Vector3.UP*.2
  _composite_dust.visible=true
  _composite_dust.restart()
  _composite_dust.emitting=true
 if not _world.is_empty():
  _scenery_contacts=SceneryBodies.build_near(_world,report.point_world_ned)
  add_child(_scenery_contacts)
 if audio_enabled: audio.impact(point,severity,false)
 active=true
 start_usec=Time.get_ticks_usec()-began

func update(delta: float,paused: bool) -> void:
 if not active: return
 _paused=paused
 wreck.set_paused(paused)
 effects.update(delta,paused)
 audio.update(delta,paused or not audio_enabled,0.0)
 if not paused: _age+=clampf(delta,0.0,.1)

func _secondary(point: Vector3,energy_j: float) -> void:
 if not active or _paused or _age-_secondary_at<.12: return
 _secondary_at=_age
 var strength: float=clampf(sqrt(maxf(energy_j,0.0)/maxf(_mass,.1))/8.0,0.0,1.0)
 var local: Vector3=_ground_frame.affine_inverse()*point
 if local.y<.12: effects.secondary(local,strength)
 if audio_enabled: audio.secondary(point,strength)

func focus_position() -> Vector3:
 return wreck.focus_position() if active else Vector3.ZERO

func reset() -> void:
 active=false; _age=0.0; _paused=false; _secondary_at=-1.0; _report={}
 if wreck!=null: wreck.reset()
 if effects!=null: effects.reset()
 if audio!=null: audio.reset()
 if is_instance_valid(_scenery_contacts):
  _scenery_contacts.free()
  _scenery_contacts=null

func stats() -> Dictionary:
 return {active=active,age_s=_age,paused=_paused,start_usec=start_usec,wreck=wreck.get_stats() if wreck!=null else {},effects=effects.stats() if effects!=null else {},scenery_bodies=_scenery_contacts.get_child_count() if is_instance_valid(_scenery_contacts) else 0,thermal_fire=false,smoke_policy="brief nonthermal composite dust; no declared fuel/battery fire inventory"}
