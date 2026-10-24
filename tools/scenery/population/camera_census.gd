# SC-HUM-00 camera census: which field people each flight camera actually shows, and how large their heads are.
# Drives the production CameraRig (pilot with auto zoom, chase, orbit, close-up) along a reference sortie at the
# default field (take-off, circuit, low pass, landing) and projects every person's head (0.23 m) at 1920×1080.
# Geometry only: no rendering, no occlusion (shelter roofs, trees), so "in frame" is an upper bound.
#   godot --headless --path app --script res://../tools/scenery/population/camera_census.gd -- [--out=FILE.json]
extends SceneTree

const CameraRig := preload("res://render/camera/camera_rig.gd")
const PilotCamera := preload("res://render/pilot_camera.gd")
const Frames := preload("res://render/frames.gd")
const FieldLoader := preload("res://data/field_loader.gd")
const Scenery := preload("res://scenery/scenery.gd")
const SceneryLoader := preload("res://scenery/scenery_loader.gd")
const ShaderClock := preload("res://render/shader_clock.gd")

const VIEWPORT_H := 1080.0
const ASPECT := 16.0 / 9.0
const HEAD_M := 0.23
const SPAN_M := 1.8 # Ugly Stik class wingspan for the pilot auto zoom
const SPEED_MPS := 18.0
const DT := 0.1
## Reference sortie in NED (north, east, height above ground) waypoints around the 100 m east-west runway at
## north 15 m: ground roll, climb-out, rectangular circuit at 40 m, a low pass at 4 m, approach and landing.
const SORTIE := [
	[15.0, -40.0, 0.2], [15.0, 10.0, 0.2], [20.0, 120.0, 25.0], [150.0, 160.0, 40.0], [150.0, -160.0, 40.0],
	[15.0, -170.0, 20.0], [15.0, -120.0, 4.0], [15.0, 120.0, 4.0], [60.0, 170.0, 30.0], [150.0, 120.0, 40.0],
	[150.0, -150.0, 40.0], [15.0, -160.0, 25.0], [15.0, -40.0, 1.0], [15.0, 20.0, 0.2],
]


func _initialize() -> void:
	# Cameras need to be inside the tree for global transforms; run once the tree has started.
	_run.call_deferred()


func _run() -> void:
	ShaderClock.register()
	var out := "user://camera_census.json"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
	var field: Dictionary = FieldLoader.load_from(FieldLoader.DEFAULT_PATH).field
	var scenery: Dictionary = SceneryLoader.load_from(SceneryLoader.DEFAULT_PATH, field).scenery
	var world := Scenery.build(field, scenery, {audio = false, birds = false, theme = "", quality = "high"})
	var people: Array = world.get_node("Population").get_meta("people")
	print("census: %d people, scenery built in %d ms" % [people.size(), Time.get_ticks_msec()])
	var pilot: Dictionary = field.pilot
	var samples := _sortie()
	var report := {format = "openrc-camera-census v1", viewport = [1920, 1080], head_m = HEAD_M, samples = samples.size(),
		sortie_s = samples.size() * DT, occlusion = "not modelled", views = {}}
	for view: String in CameraRig.VIEWS:
		# A 1080p SubViewport: the pilot auto zoom reads the viewport height (the headless root is 64 px).
		var viewport := SubViewport.new()
		viewport.size = Vector2i(1920, 1080)
		root.add_child(viewport)
		var camera := PilotCamera.create(viewport, pilot)
		var rig := CameraRig.new(camera, SPAN_M)
		rig.set_view(view)
		var stats := {}
		for i in samples.size():
			var s: Dictionary = samples[i]
			rig.update(s.position, Transform3D(s.basis, s.position), s.basis, DT, false, func(_x: float, _z: float) -> float: return 0.0)
			var to_camera := camera.global_transform.affine_inverse()
			var tan_v := tan(deg_to_rad(camera.fov) * 0.5)
			for person: Dictionary in people:
				var key := "%s %s:%d" % [person.role, person.asset, int(person.index)]
				var head: Vector3 = (person.pivot as Vector3) + Vector3(0.0, 0.07, 0.0)
				var local := to_camera * head
				var entry: Dictionary = stats.get(key, {role = person.role, asset = person.asset, seen = 0, px = PackedFloat64Array()})
				var depth := -local.z
				if depth > camera.near and absf(local.y) <= depth * tan_v and absf(local.x) <= depth * tan_v * ASPECT:
					entry.seen = int(entry.seen) + 1
					var px: PackedFloat64Array = entry.px # packed arrays are values: append, then store back
					px.append(PilotCamera.projected_px(HEAD_M, local.length(), camera.fov, VIEWPORT_H))
					entry.px = px
				stats[key] = entry
		var rows := {}
		for key: String in stats:
			var e: Dictionary = stats[key]
			var px: PackedFloat64Array = e.px
			px.sort()
			rows[key] = {role = e.role, asset = e.asset, in_frame_share = float(e.seen) / samples.size(),
				head_px_median = px[px.size() / 2] if not px.is_empty() else 0.0, head_px_max = px[-1] if not px.is_empty() else 0.0}
		report.views[view] = rows
		print("census: view %s done at %d ms" % [view, Time.get_ticks_msec()])
		viewport.free()
	world.free()
	var file := FileAccess.open(out, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("CAMERA CENSUS DONE ", ProjectSettings.globalize_path(out))
	quit()


## Waypoints resampled at DT along straight legs at SPEED_MPS; heading and climb follow the leg.
func _sortie() -> Array:
	var samples: Array = []
	for leg in SORTIE.size() - 1:
		var a: Array = SORTIE[leg]
		var b: Array = SORTIE[leg + 1]
		var pa: Vector3 = Frames.ned_to_render([a[0], a[1], -a[2]])
		var pb: Vector3 = Frames.ned_to_render([b[0], b[1], -b[2]])
		var steps := maxi(1, int(ceil(pa.distance_to(pb) / (SPEED_MPS * DT))))
		var forward := (pb - pa).normalized()
		var basis := Basis.looking_at(forward, Vector3.UP)
		for k in steps:
			samples.append({position = pa.lerp(pb, float(k) / steps), basis = basis})
	return samples
