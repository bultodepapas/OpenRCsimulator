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
		check(entry.id + " jet has no active propeller", airplane.get("has_propeller", true) == (model.capabilities.propulsion_layout in ["single_tractor", "single_pusher"]))
		if throws.has("elevon"):
			_check_elevons(entry.id, airplane, throws)
			airplane.root.free()
			continue
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
				# Imported V2 scenes (Ventage Jet, Timber, F4U Corsair) bind rest-relative hinge records.
				if str(airplane.model_manifest.builder.adapter) == "imported_glb":
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


## X8-02/03: an elevon family draws each elevon as elevator + its side's aileron, the radio mix clipped at the end
## point; the aerodynamic decomposition and the rendered hinges must agree, saturation included.
func _check_elevons(id: String, airplane: Dictionary, throws: Dictionary) -> void:
	for command: Dictionary in [{roll = 0.0, pitch = 1.0}, {roll = 1.0, pitch = 0.0}, {roll = 1.0, pitch = 1.0},
			{roll = -1.0, pitch = -1.0}, {roll = 0.0, pitch = 0.0}]:
		var full := {roll = command.roll, pitch = command.pitch, yaw = 1.0, throttle = 0.0}
		var surfaces: Dictionary = Commands.surface_deflections_deg(full, throws)
		var right := clampf(command.pitch * throws.elevator + command.roll * throws.aileron, -throws.elevon, throws.elevon)
		var left := clampf(command.pitch * throws.elevator - command.roll * throws.aileron, -throws.elevon, throws.elevon)
		check(id + " elevon mix right %s" % command, absf(surfaces.elevator + surfaces.aileron_right - right) < 1e-12)
		check(id + " elevon mix left %s" % command, absf(surfaces.elevator + surfaces.aileron_left - left) < 1e-12)
		check(id + " no rudder %s" % command, surfaces.rudder == 0.0)
		Builder.apply_surfaces(airplane, Commands.hinge_rotations(full, throws))
		for item: Array in [["elevon_right", right], ["elevon_left", left]]:
			var hinge: Dictionary = airplane.hinges[item[0]]
			var relative: Basis = hinge.node.basis * hinge.rest.inverse()
			var witness: Vector3 = Vector3.FORWARD.cross(hinge.axis).normalized()
			var actual: float = witness.signed_angle_to(relative * witness, hinge.axis)
			check(id + " actual hinge %s %s (%.6f vs %.6f)" % [item[0], command, actual, -deg_to_rad(item[1])],
				absf(actual + deg_to_rad(item[1])) < 1e-6)
			if command.roll == 0.0 and command.pitch == 0.0:
				check(id + " neutral rest " + item[0], hinge.node.basis == hinge.rest)
