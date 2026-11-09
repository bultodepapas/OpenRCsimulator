extends SceneTree
const Catalog = preload("res://economy/catalog.gd")
const Calculator = preload("res://economy/calculator.gd")
const Incident = preload("res://economy/incident.gd")
const AircraftData = preload("res://physics/aircraft_data.gd")
var checks := 0
var failures := 0
var observations: Array = []

func note(id: String, actual: Variant, condition: bool, scope: String) -> void:
	checks += 1
	if not condition: failures += 1
	observations.append({"id":id,"observed":actual,"matched_current_source":condition,"scope":scope})
	print(("ok " if condition else "FAIL ") + id + " " + JSON.stringify(actual))

func report_fields(r: Dictionary) -> Dictionary:
	return {"ok":r.get("ok"),"complete":r.get("complete"),"total_minor":r.get("total_minor"),
		"known_subtotal_minor":r.get("known_subtotal_minor"),"low_minor":r.get("low_minor"),
		"high_minor":r.get("high_minor"),"range_basis":r.get("range_basis"),"outcome":r.get("outcome")}

func assessment(terminal: bool, components: Dictionary) -> Dictionary:
	# Production Incident.observe adds this uncertainty when a terminal contact arrives.
	return {"components":components,"terminal":terminal,"total_loss":false,
		"unresolved":["Crash inspection pending; component survival is not yet established."] if terminal else []}

func _initialize() -> void:
	var stik = Catalog.load_for("jensen-das-ugly-stik-60", "").dossier
	var lumber = Catalog.load_for("turbo-lumber-evolution", "").dossier
	var extra = Catalog.load_for("gp-extra-300s-60", "").dossier
	var r = Calculator.calculate(stik,assessment(true, {}))
	note("terminal_stik_whole_build_ceiling",report_fields(r),r.high_minor == 133134 and r.low_minor == 0 and r.total_minor == null,"Calculator with unassessed terminal incident; not a flown crash.")
	r = Calculator.calculate(stik,assessment(true, {"propeller":{"disposition":"replace"}}))
	note("terminal_stik_prop_floor",report_fields(r),r.low_minor == 539 and r.high_minor == 133134 and r.total_minor == null,"Confirmed propeller plus unresolved terminal assessment.")
	r = Calculator.calculate(stik,assessment(false, {"propeller":{"disposition":"replace"}}))
	note("resolved_stik_prop_only",report_fields(r),r.total_minor == 539 and r.complete,"Constructed fully resolved prop-only assessment, not normal inspection-producing strike path.")
	r = Calculator.calculate(extra,assessment(false, {"propeller":{"disposition":"replace"}}))
	note("extra_whole_dossier_blocks_local_total",report_fields(r),r.known_subtotal_minor == 539 and r.total_minor == null and not r.complete,"Same isolated priced action; source-wide missing notes block completion. Does not establish all other real-flight damage absent.")
	r = Calculator.calculate(stik,assessment(true, {"engine_and_muffler":{"disposition":"inspect","inspection_minor":500}}))
	note("terminal_ceiling_excludes_inspection_fee",report_fields(r),r.low_minor == 500 and r.high_minor == 133134,"Conditional accounting risk if the 500-cent inspection is already incurred: replacement upper plus sunk fee is 133634 cents.")
	var wing: Dictionary = {}
	for c: Dictionary in lumber.components:
		if c.id == "wing_main": wing = c
	r = Calculator.calculate(lumber,assessment(false, {"wing_main":{"disposition":"replace"}}))
	note("lumber_wing_bundle",{"wing_unit_minor":wing.get("unit_minor"),"report":report_fields(r)},wing.unit_minor == 11595 and r.known_subtotal_minor == 11595,"Authored composite wing price includes four servo proxies; not bare wing price or proof all four servos failed.")
	var ledger := Incident.new()
	ledger.begin("turbo-lumber-evolution", "")
	ledger._assessment.components.tail_surfaces = {"disposition":"reuse"}
	var changed = ledger._mark_contact_inspection(["tail_surfaces"])
	note("later_contact_keeps_earlier_reuse",{"changed":changed,"disposition":ledger._assessment.components.tail_surfaces.disposition},not changed and ledger._assessment.components.tail_surfaces.disposition == "reuse","Existing component helper; real inspection producer is not connected in normal play.")
	ledger._assessment.components.motor_main = {"disposition":"replace"}
	ledger._mark_propeller()
	note("prop_strike_downgrades_replacement",ledger._assessment.components.motor_main,ledger._assessment.components.motor_main.disposition == "inspect","Existing propeller helper; integration risk once prior inspection/replacement receipts are used.")
	var event = {"source":"lake","contact_id":"lake:audit:water","probe_source":"propeller","probe_id":"propulsion_main"}
	var mapped = ledger._contact_components(event)
	note("lake_propeller_binding_gap",{"result":mapped,"qualified_binding":ledger.dossier.contact_components.get("propeller/propulsion_main")},mapped.is_empty() and ledger.dossier.contact_components.has("propeller/propulsion_main"),"Probe of binding lookup fields only; not a complete validated lake event nor proof of blade damage.")
	var jet = AircraftData.load_file("res://data/aircraft/sebart_avanti_s_a200.json")
	if jet.ok:
		var mass = float(jet.model.mass_kg)
		note("jet_translation_energy_example",{"mass_kg":mass,"at_40_kmh_j":0.5*mass*pow(40.0/3.6,2),"at_500_kmh_j":0.5*mass*pow(500.0/3.6,2),"ratio":156.25},true,"Arithmetic from loaded mass. Total translational energy, not component absorbed energy; no asserted survival probability.")
	var out = FileAccess.open("res://audit_probe_results.json",FileAccess.WRITE)
	out.store_string(JSON.stringify({"baseline":"f47d1dc6cccb141936407d0217eafdc465558190","checks":checks,"failures":failures,"observations":observations},"\t"))
	out.close()
	print("AUDIT PROBES: %d checks, %d failed" % [checks,failures])
	quit(1 if failures else 0)
