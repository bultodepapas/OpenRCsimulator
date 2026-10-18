## Presentation camera for the Lumber twilight take; flight inputs stay inherited.
extends "flight_director.gd"


func _place_camera(t: float) -> void:
	var aircraft: Node3D = main._airplane.root
	var center: Vector3 = aircraft.global_position
	var forward := Vector3(-aircraft.global_basis.z.x, 0.0, -aircraft.global_basis.z.z).normalized()
	var right: Vector3 = forward.cross(Vector3.UP).normalized()
	var elapsed: float = clampf(t / maxf(duration_s, 0.001), 0.0, 1.0)
	# Look back toward the evening horizon, with a clear three-quarter silhouette.
	main._camera.global_position = center + forward * lerpf(5.4, 4.5, elapsed) \
		+ right * lerpf(2.2, 1.8, elapsed) + Vector3.UP * 0.1
	main._camera.look_at(center + Vector3.UP * 0.4, Vector3.UP)
	main._camera.fov = 33.0
