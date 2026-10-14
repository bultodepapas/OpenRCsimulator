# AS-03: real aircraft throws reach both the aerodynamic and visual boundaries.
extends SceneTree

const AD := preload("res://physics/aircraft_data.gd")
const Catalog := preload("res://app_state/aircraft_catalog.gd")
const Builder := preload("res://render/airplane.gd")
const Commands := preload("res://input/commands.gd")
const Aero := preload("res://physics/aero.gd")
var checks := 0
var failures := 0

func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL AS render: " + label)

func _initialize() -> void:
	for entry: Dictionary in Catalog.airplane_flyable_entries(): # TT-06: previews carry no data file
		var loaded: Dictionary = AD.load_file(entry.data)
		check(entry.id + " loads", loaded.ok)
		if not loaded.ok:
			continue
		var model: Dictionary = loaded.model
		var airplane: Dictionary = Builder.build(entry.id)
		var throws: Dictionary = model.controls.throw_deg
		check(entry.id + " identity", airplane.aircraft_id == model.id)
		check(entry.id + " jet has no active propeller", airplane.get("has_propeller", true) == (model.capabilities.propulsion_layout == "single_tractor"))
		for sign: float in [-1.0, 1.0, 0.0]:
			var command := {roll = sign, pitch = sign, yaw = sign, throttle = 0.0}
			var surfaces: Dictionary = Commands.surface_deflections_deg(command, throws)
			var physical: Dictionary = Aero.deflections_from_surfaces(surfaces)
			var expected := {
				aileron_right = sign * (throws.aileron if sign >= 0.0 else throws.get("aileron_down", throws.aileron)),
				aileron_left = -sign * (throws.aileron if sign <= 0.0 else throws.get("aileron_down", throws.aileron)),
				elevator = sign * throws.elevator,
				rudder = sign * throws.rudder,
			}
			Builder.apply_surfaces(airplane, Commands.hinge_rotations(command, throws))
			for surface: String in expected:
				check(entry.id + " authored throw " + surface, absf(surfaces[surface] - expected[surface]) < 1e-12)
				check(entry.id + " aerodynamic sign/unit " + surface, absf(physical[surface] + deg_to_rad(expected[surface])) < 1e-12)
				var angle: float = deg_to_rad(expected[surface]) * (1.0 if surface == "rudder" else -1.0)
				if entry.id == Builder.AVANTI_ID or entry.id == Builder.TIMBER_ID:
					var hinges: Array = ["elevator_left", "elevator_right"] \
						if entry.id == Builder.AVANTI_ID and surface == "elevator" else [surface]
					for hinge_name: String in hinges:
						var hinge: Dictionary = airplane.hinges[hinge_name]
						var relative: Basis = hinge.node.basis * hinge.rest.inverse()
						var witness: Vector3 = Vector3.FORWARD.cross(hinge.axis).normalized()
						var actual: float = witness.signed_angle_to(relative * witness, hinge.axis)
						check(entry.id + " actual hinge " + hinge_name, absf(actual - angle) < 1e-6)
						if sign == 0.0:
							check(entry.id + " neutral rest " + hinge_name, hinge.node.basis == hinge.rest)
				else:
					var hinge: Node3D = airplane.hinges[surface]
					var actual: float = hinge.rotation.y if surface == "rudder" else hinge.rotation.x
					check(entry.id + " actual hinge " + surface, absf(actual - angle) < 1e-6)
			if entry.id == Builder.AVANTI_ID:
				for flap: String in ["flap_left", "flap_right"]:
					var hinge: Dictionary = airplane.hinges[flap]
					check("inactive flap stays neutral " + flap, hinge.node.basis == hinge.rest)
		airplane.root.free()
	print("AS render contract: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
