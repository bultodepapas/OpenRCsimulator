## DT-MAC-05a: real-engine check of an isolated research project's receipt.
extends SceneTree

const HighGraphics := preload("res://render/high_graphics_profile.gd")


func _initialize() -> void:
	var receipt: Dictionary = HighGraphics.describe().get("research", {})
	var expected_name := str(ProjectSettings.get_setting("application/config/name", ""))
	var checks := [
		receipt.get("requested_method") == "forward_plus",
		receipt.get("requested_driver") == "metal",
		receipt.get("effective_method") == RenderingServer.get_current_rendering_method(),
		receipt.get("effective_driver") == RenderingServer.get_current_rendering_driver_name(),
		receipt.get("effective_profile") == "standard",
		receipt.get("requested_project_name") == expected_name,
		receipt.get("effective_project_name") == expected_name,
		bool(receipt.get("user_directory_name_matches", false)),
		receipt.get("multi_bounce_occlusion_project_setting") == false,
	]
	if checks.has(false):
		printerr("Research identity failed: ", JSON.stringify(receipt), " checks=", checks)
		quit(1)
		return
	print("Research identity verified in headless project; native renderer remains unqualified")
	quit(0)
