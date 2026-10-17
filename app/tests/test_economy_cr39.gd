extends SceneTree
## CR-39: session catalog cache, contact-to-part mapping, stale-data reason, single-calculation
## quote parity, compact archive and the provisional terminal-loss headline.

const Incident = preload("res://economy/incident.gd")
const Calculator = preload("res://economy/calculator.gd")
const ReplacementQuote = preload("res://economy/replacement_quote.gd")
const AccidentReport = preload("res://ui/accident_report.gd")
const STALE := "Cost data is out of date for this aircraft version; no prices were applied."
const ARCHIVE := "user://test_cr39_last_accident.json"

var checks := 0
var failures := 0


func _initialize() -> void:
	_test_catalog_cache()
	_test_contact_mapping()
	_test_stale_reason()
	_test_quote_parity()
	_test_compact_archive()
	_test_terminal_headline()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(ARCHIVE))
	print("CR-39 economics: %d checks, %d failed" % [checks, failures])
	quit(1 if failures > 0 else 0)


func check(label: String, ok: bool, detail: String = "") -> void:
	checks += 1
	if ok:
		print("ok   " + label)
	else:
		failures += 1
		print("FAIL " + label + ("" if detail.is_empty() else " " + detail))


func _test_catalog_cache() -> void:
	var ledger := Incident.new()
	ledger.begin("jensen-das-ugly-stik-60", "")
	var first: Dictionary = ledger._catalog_cache
	var report_before := ledger.dossier.duplicate(true)
	ledger.begin("jensen-das-ugly-stik-60", "")
	check("reset with the same route and identity reuses the validated catalog load", is_same(first, ledger._catalog_cache) and ledger.dossier == report_before and not ledger.dossier.is_empty())
	ledger.dossier.components.clear()
	ledger.begin("jensen-das-ugly-stik-60", "")
	check("a ledger cannot mutate the cached dossier", not ledger.dossier.components.is_empty())
	ledger.begin("jensen-das-ugly-stik-60", "0".repeat(64))
	check("a different physical identity reloads and is refused", not is_same(first, ledger._catalog_cache) and ledger.dossier.is_empty())
	ledger.begin("jensen-das-ugly-stik-60", "")
	check("recipe book stays loaded across resets", not ledger._recipe_book.is_empty() and ledger._recipe_hash.length() == 64)


func _test_contact_mapping() -> void:
	var ledger := Incident.new()
	ledger.begin("turbo-lumber-evolution", "")
	check("Lumber dossier loads with authored contact bindings", not ledger.dossier.is_empty() and not ledger.dossier.contact_components.is_empty())
	check("hull probe maps to its economic part", ledger._contact_components({source = "hull", contact_id = "probe_wing_left_tip"}) == ["wing_main"])
	check("scenery impact maps through its hull probe", ledger._contact_components({source = "scenery", contact_id = "tree-7", probe_id = "probe_fin_top"}) == ["tail_surfaces"])
	check("unmapped contact has no part binding", ledger._contact_components({source = "hull", contact_id = "probe_nose"}).is_empty())
	check("mapped contact opens a pending part inspection", ledger._mark_contact_inspection(["wing_main"]) and ledger._assessment.components.wing_main.disposition == "inspect" and ledger._assessment.unresolved.is_empty())
	check("repeat contact on a pending part is not a new revision", not ledger._mark_contact_inspection(["wing_main"]))
	ledger._assessment.components["gear_main"] = {"disposition": "replace", "quantity": 1}
	ledger._mark_contact_inspection(["gear_main"])
	check("contact never downgrades a confirmed replacement", ledger._assessment.components.gear_main.disposition == "replace")
	ledger._assessment.components["tail_surfaces"] = {"disposition": "reuse"}
	check("contact on an already reused part reopens structural inspection", ledger._mark_contact_inspection(["tail_surfaces"]) and not ledger._assessment.unresolved.is_empty())
	ledger._queue_assessment(1)
	ledger.evaluate_pending()
	var named := false
	for line: Dictionary in ledger.report.get("lines", []):
		named = named or (line.get("id") == "wing_main" and line.get("action") == "inspection")
	check("report names the inspected part instead of only a generic note", named, str(ledger.report.get("errors")))


func _test_stale_reason() -> void:
	var ledger := Incident.new()
	ledger.begin_with_catalog({ok = false, errors = ["economics dossier is stale for current aircraft source"], catalog_hash = ""}, "p51d-mustang-120", "")
	ledger.observe({tick = 3, events = []}, {}, true)
	ledger.evaluate_pending()
	check("stale dossier names the out-of-date cause", ledger.report.get("unresolved", []).has(STALE) and ledger.report.get("total_minor") == null, str(ledger.report.get("unresolved")))
	var missing := Incident.new()
	missing.begin_with_catalog({ok = false, errors = ["cannot read economics catalog"], catalog_hash = ""}, "p51d-mustang-120", "")
	missing.observe({tick = 3, events = []}, {}, true)
	missing.evaluate_pending()
	check("other load failures keep the generic unavailable reason", not missing.report.get("unresolved", []).has(STALE) and missing.report.get("unresolved", []).has("Compatible aircraft cost dossier is unavailable."))


func _test_quote_parity() -> void:
	var ledger := Incident.new()
	ledger.begin("jensen-das-ugly-stik-60", "")
	var assessment := {"components": {"propeller": {"disposition": "replace", "quantity": 1}}, "terminal": false, "total_loss": false, "unresolved": []}
	var direct: Dictionary = ReplacementQuote.quote(ledger.dossier, assessment)
	var reused: Dictionary = ReplacementQuote.quote_calculated(ledger.dossier, assessment, Calculator.calculate(ledger.dossier, assessment))
	check("quote from a held calculation equals a recomputed quote", direct == reused and direct.get("status") == "optimal", str(direct))


func _test_compact_archive() -> void:
	var ledger := Incident.new()
	ledger.archive_path = ARCHIVE
	ledger.begin("jensen-das-ugly-stik-60", "")
	ledger.observe({tick = 4, events = []}, {}, true)
	check("terminal report flushes", ledger.flush() == OK)
	var text := FileAccess.get_file_as_string(ARCHIVE)
	check("archive is compact JSON", not text.is_empty() and not text.contains("\n\t"))
	var reader := Incident.new()
	reader.archive_path = ARCHIVE
	var loaded: Dictionary = reader.load_archive()
	check("compact archive round-trips through validation", not loaded.is_empty() and loaded.get("high_minor") == ledger.report.get("high_minor"))
	check("terminal Stik crash without a prop strike archives its 0..ceiling range", ledger.report.get("low_minor") == 0 and ledger.report.get("high_minor") == 133134 and ledger.report.get("total_minor") == null, str(ledger.report))


func _test_terminal_headline() -> void:
	var report := AccidentReport.new()
	var hull := {currency = "USD", complete = false, outcome = "inspection", total_minor = null, known_subtotal_minor = 0,
		low_minor = 0, high_minor = 133134, range_basis = "complete_build_replacement_ceiling", lines = []}
	TranslationServer.set_locale("en")
	var state: Dictionary = report._headline_state(hull)
	check("terminal crash headline shows a provisional loss ceiling", state.status == "ESTIMATED LOSS · PROVISIONAL" and state.amount == "Up to US$1,331", str(state))
	var struck := hull.duplicate(true)
	struck.low_minor = 539
	struck.known_subtotal_minor = 539
	state = report._headline_state(struck)
	check("known prop cost becomes the floor of the provisional range", state.amount == "US$5.39 – US$1,331", str(state))
	var ordinary := hull.duplicate(true)
	ordinary.range_basis = "component_price_bounds"
	ordinary.high_minor = null
	check("without a ceiling the existing unknown labels remain", report._headline_state(ordinary).status == "AMOUNT UNKNOWN")
	TranslationServer.set_locale("es")
	state = report._headline_state(hull)
	check("provisional loss headline is translated", state.status == "PÉRDIDA ESTIMADA · PROVISIONAL" and state.caption.begins_with("Límite superior"), str(state))
	TranslationServer.set_locale("en")
	report.free()
