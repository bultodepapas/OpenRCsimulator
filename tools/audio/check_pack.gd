## Mount the export in an empty project, then resolve its imported audio and notices.
extends SceneTree

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1 or not ProjectSettings.load_resource_pack(args[0]):
		printerr("Expected one readable PCK path")
		quit(1)
		return
	var okay: bool = true
	var count: int = 0
	for base: String in ["res://assets/audio/soundscape/", "res://assets/audio/soundscape/wildlife/"]:
		var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(base + "manifest.json"))
		okay = okay and manifest is Dictionary and FileAccess.get_file_as_string(base + "LICENSE.txt").contains("MIT License")
		if not manifest is Dictionary:
			continue
		for entry: Dictionary in manifest.assets:
			var wav: AudioStreamWAV = load(base + str(entry.file)) as AudioStreamWAV
			okay = okay and wav != null
			if wav != null:
				okay = okay and wav.mix_rate == 22050 and not wav.stereo and wav.format == AudioStreamWAV.FORMAT_16_BITS
				okay = okay and wav.data.size() / 2 == int(entry.metrics.sample_count)
				count += 1
	var recorded_base: String = "res://assets/audio/soundscape/recorded/"
	var recorded: Variant = JSON.parse_string(FileAccess.get_file_as_string(recorded_base + "manifest.json"))
	okay = okay and recorded is Dictionary and FileAccess.get_file_as_string(recorded_base + "LICENSE.txt").contains("CC0 1.0")
	if recorded is Dictionary:
		for source: Dictionary in recorded.sources.values():
			okay = okay and source.license == "CC0-1.0" and not str(source.page).is_empty()
		for entry: Dictionary in recorded.assets:
			var wav: AudioStreamWAV = load(recorded_base + str(entry.file)) as AudioStreamWAV
			okay = okay and wav != null
			if wav != null:
				okay = okay and wav.mix_rate == 22050 and not wav.stereo and wav.format == AudioStreamWAV.FORMAT_16_BITS
				okay = okay and wav.data.size() / 2 == int(entry.sample_count)
				count += 1
	okay = okay and count == 33
	var new_count: int = 0
	for folder: String in ["powertrains", "landing_gear", "mechanical"]:
		var base: String = "res://assets/audio/" + folder + "/"
		var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(base + "manifest.json"))
		okay = okay and manifest is Dictionary and not FileAccess.get_file_as_string(base + "LICENSE.txt").is_empty()
		if not manifest is Dictionary:
			continue
		for entry: Dictionary in manifest.get("assets", []):
			var wav := load(base + str(entry.file)) as AudioStreamWAV
			okay = okay and wav != null
			if wav != null:
				okay = okay and not wav.stereo and wav.format == AudioStreamWAV.FORMAT_16_BITS
				okay = okay and wav.mix_rate == int(entry.sample_rate_hz) and wav.data.size() / 2 == int(entry.sample_count)
				new_count += 1
	var banks: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/powertrains/BANKS.json"))
	okay = okay and banks is Dictionary and banks.has_all(["gasoline", "electric", "turbine", "rotor"])
	var mechanical_license := FileAccess.get_file_as_string("res://assets/audio/mechanical/LICENSE.txt")
	okay = okay and mechanical_license.contains("CC-BY-4.0") and mechanical_license.contains("j_soundeffects")
	okay = okay and new_count == 27 # six engine loops, four contact clips, seventeen actuator cues
	print("Exported audio: %d original/ambience + %d powertrain/contact/mechanical sources and notices: %s" %
		[count, new_count, "PASS" if okay else "FAIL"])
	quit(0 if okay else 1)
