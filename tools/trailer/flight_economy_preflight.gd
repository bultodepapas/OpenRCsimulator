## Read-only crash-valuation source preflight for trailer shot selection.
## Run with the isolated project: Godot --headless --path <runtime/app> --script <absolute path> -- --aircraft=<id> [...].
extends SceneTree

const EconomicsCatalog := preload("res://economy/catalog.gd")


func _initialize() -> void:
	var aircraft_ids: Array[String] = []
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--aircraft="):
			aircraft_ids.append(argument.trim_prefix("--aircraft="))
	if aircraft_ids.is_empty():
		aircraft_ids = ["jensen-das-ugly-stik-60"]
	var results: Array[Dictionary] = []
	for aircraft_id: String in aircraft_ids:
		var loaded: Dictionary = EconomicsCatalog.load_for(aircraft_id)
		var result := {aircraft_id = aircraft_id, ok = bool(loaded.get("ok", false)), errors = loaded.get("errors", [])}
		if bool(loaded.get("ok", false)):
			var dossier: Dictionary = loaded.get("dossier", {})
			result.merge({
				valuation_kind = str(dossier.get("valuation_kind", "")),
				complete = bool(dossier.get("complete", false)),
				missing = dossier.get("missing", []),
				component_count = dossier.get("components", []).size(),
			}, true)
		results.append(result)
	print("TRAILER_ECONOMY_PREFLIGHT ", JSON.stringify(results, "\t"))
	quit(0)
