extends "servo_arrival_campaign.gd"
## One exclusive research session: all 68 fixed cells, each with fresh flight sessions/logs.
## This avoids 68 identical source/cache copies on constrained qualification hosts.
var _cell := 0
var _outcomes: Array[Dictionary] = []


func _initialize() -> void:
	if not OS.get_cmdline_user_args().is_empty():
		printerr("The fixed composite campaign accepts no cell/rate/output overrides.")
		quit(1)
		return
	super._initialize()


func specification() -> Dictionary:
	@warning_ignore("integer_division")
	var id: int = _cell/4+1
	return {case_id="C%02d" % id,tape=TAPES[_cell%4],calibrate=false}


func audit_finished(report: Dictionary) -> void:
	_outcomes.append({specification=report.specification.duplicate(true),complete=report.complete,
		legacy_interpretable=report.legacy_interpretable,pass_=report.legacy_rule.get("pass",false),
		audit_path=_out.path_join("audit.json"),audit_sha256=FileAccess.get_sha256(_out.path_join("audit.json"))})
	if not report.complete or not report.legacy_interpretable:
		printerr("SERVO_ARRIVAL_CAMPAIGN_ALL incomplete at cell ",_cell)
		quit(1)
		return
	_cell += 1
	if _cell==68:
		print("SERVO_ARRIVAL_CAMPAIGN_ALL 68 cells complete; flight_qualified=false")
		print("SERVO_ARRIVAL_CAMPAIGN_ALL numerical passes ",_outcomes.filter(func(r: Dictionary) -> bool:return r.pass_).size(),"/68")
		quit(0)
		return
	# The inherited finalizer already restored the engine tick rate. Discard only
	# this cell's local caches; every capture constructs and frees its own Session.
	_out=""
	_first_runs.clear()
	_run_number=0
	_run_audit.call_deferred()
