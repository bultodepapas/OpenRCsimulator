extends SceneTree
## CR-39 audit-only timing probe for the accident economics path. Reads private incident
## fields; not part of the app. Run from the repository root:
## <godot> --headless --path app --audio-driver Dummy --script <absolute repo path>/research/crash-economics/probe_timing.gd

const Catalog = preload("res://economy/catalog.gd")
const Calculator = preload("res://economy/calculator.gd")
const Incident = preload("res://economy/incident.gd")
const ReplacementQuote = preload("res://economy/replacement_quote.gd")

const N := 20


## Mean wall time in microseconds over n calls.
func _us(callable: Callable, n: int = N) -> float:
	var total := 0.0
	for i in n:
		var t0 := Time.get_ticks_usec()
		callable.call()
		total += float(Time.get_ticks_usec() - t0)
	return total / n


func _initialize() -> void:
	for id: String in ["jensen-das-ugly-stik-60", "p51d-mustang-120", "turbo-lumber-evolution"]:
		var t_load := _us(func(): Catalog.load_for(id, ""))
		var loaded: Dictionary = Catalog.load_for(id, "")
		if not loaded.ok:
			print(loaded.errors)
		var dossier: Dictionary = loaded.get("dossier", {})
		var prop: String = str(dossier.get("propeller_component_id", ""))
		var assessment := {components = {}, terminal = true, total_loss = false, unresolved = ["x"]}
		if not prop.is_empty():
			assessment.components[prop] = {disposition = "replace", quantity = 1}
		var t_calc := _us(func(): Calculator.calculate(dossier, assessment), 200)
		var t_quote := _us(func(): ReplacementQuote.quote(dossier, assessment, []), 200)
		var inc := Incident.new()
		inc.archive_path = "user://probe_last_accident.json"
		var t_begin := _us(func(): inc.begin_with_catalog(loaded, id, ""))
		var t_recalc := _us(func():
			inc._queue_assessment(1)
			inc.evaluate_pending(), 200)
		var t_flush := _us(func():
			inc._dirty = true
			inc._persisted_revision = -1
			inc._flush_attempt_revision = -1
			inc.flush())
		# Fresh ledger, then one terminal observation with no contact events (hull crash, no prop strike).
		inc.begin_with_catalog(loaded, id, "")
		inc.observe({tick = 5, events = []}, {}, true)
		inc.evaluate_pending()
		print("  terminal, no prop strike: outcome=%s total=%s low=%s high=%s subtotal=%s complete_build=%s..%s" % [
			inc.report.outcome, inc.report.total_minor, inc.report.low_minor, inc.report.high_minor,
			inc.report.known_subtotal_minor, inc.report.get("replacement_quote_low_minor"), inc.report.get("replacement_quote_high_minor")])
		var bytes := JSON.stringify(inc.report, "\t", true, true).to_utf8_buffer().size()
		print("%s ok=%s load_for=%.0fus begin=%.0fus calculate=%.0fus quote=%.0fus recalc(emit)=%.0fus flush=%.0fus report_bytes=%d" % [
			id, loaded.get("ok"), t_load, t_begin, t_calc, t_quote, t_recalc, t_flush, bytes])
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://probe_last_accident.json"))
	quit(0)
