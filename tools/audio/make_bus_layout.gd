## AUD-12: generates app/default_bus_layout.tres, which Godot loads at startup: Master ends in one safety limiter
## after every per-scene bus (soundscape, crash, storm, UI). Scene buses stay dynamic and per-instance.
## Usage: godot --headless --path app --script /absolute/repo/tools/audio/make_bus_layout.gd [-- --check]
## Choice and measurements: research/audio/master-limiter-2026-10-18/README.md.
extends SceneTree

const OUTPUT: String = "res://default_bus_layout.tres"
## AudioEffectHardLimiter limits cleanly (-82 dB distortion at +3 dB overload, transparent below the ceiling) but
## Godot 4.7.2 leaves it a constant amount low after any overload; release 2 s keeps that residual at 0.07 dB and
## it does not accumulate. AudioEffectLimiter is a discontinuous clipper above -2 dBFS, so it is not used here.
const CEILING_DB: float = -1.0
const RELEASE_S: float = 2.0


func _initialize() -> void:
	var master: int = AudioServer.get_bus_index(&"Master")
	while AudioServer.get_bus_effect_count(master) > 0:
		AudioServer.remove_bus_effect(master, 0)
	while AudioServer.bus_count > 1:
		AudioServer.remove_bus(AudioServer.bus_count - 1)
	var limiter := AudioEffectHardLimiter.new()
	limiter.resource_name = "AUD-12 Master safety limiter"
	limiter.resource_scene_unique_id = "aud12_master_limiter" # deterministic bytes for --check
	limiter.ceiling_db = CEILING_DB
	limiter.release = RELEASE_S
	AudioServer.add_bus_effect(master, limiter)
	var layout: AudioBusLayout = AudioServer.generate_bus_layout()
	var check: bool = "--check" in OS.get_cmdline_user_args()
	var target: String = "user://default_bus_layout.check.tres" if check else OUTPUT
	var error: Error = ResourceSaver.save(layout, target)
	if error != OK:
		printerr("cannot save ", target, " (error ", error, ")")
		quit(1)
		return
	if check:
		var expected: String = FileAccess.get_file_as_string(OUTPUT)
		var generated: String = FileAccess.get_file_as_string(target)
		if _without_root_uid(expected) != _without_root_uid(generated):
			printerr(OUTPUT, " is stale or hand-edited; regenerate with make_bus_layout.gd")
			quit(1)
			return
		print("bus layout current: ", OUTPUT)
	else:
		print("wrote ", OUTPUT)
	quit(0)


## Editor import assigns a project-local UID to the root resource. It is not an
## audio setting. Ignore only this header attribute; every other byte stays checked.
static func _without_root_uid(text: String) -> String:
	var newline := text.find("\n")
	var header := text if newline < 0 else text.left(newline)
	if not header.begins_with("[gd_resource "):
		return text
	var uid := RegEx.new()
	uid.compile(' uid="uid://[a-z0-9]+"')
	var normalized := uid.sub(header, "", false)
	return normalized + ("" if newline < 0 else text.substr(newline))
