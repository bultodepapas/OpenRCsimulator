extends SceneTree
const Campaign := preload("servo_arrival_campaign.gd")
const Composite := preload("servo_arrival_campaign_all.gd")
var checks := 0
var failures := 0


func check(label: String, value: bool) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL servo campaign: ",label)


func _initialize() -> void:
	var campaign := Campaign.new()
	var cells: Array = campaign.registered_cells()
	var unique := {}
	for cell: String in cells: unique[cell]=true
	check("exactly 68 unique registered cells",cells.size()==68 and unique.size()==68)
	for index: int in range(1,18):
		for tape: String in Campaign.TAPES:
			var spec := {case_id="C%02d" % index,tape=tape,calibrate=false}
			check("every original fixed cell is admitted",Campaign.valid_specification(spec,cells))
			spec.calibrate=true
			check("only original five diagnostic cells may calibrate",Campaign.valid_specification(spec,cells)==((spec.case_id+"/"+tape) in Campaign.CELLS))
	for id: String in ["C00","C18","N01","X01"]:
		check("unregistered domain extension is refused",not Campaign.valid_specification({case_id=id,tape="pitch_doublet",calibrate=false},cells))
	var original := Campaign.Definition.template()
	var selected: Dictionary = campaign.audited_definition(original)
	check("source definition remains unchanged",not original.has("servo_integration") and original.format==Campaign.Definition.FORMAT)
	check("new definition explicitly selects the versioned law",selected.format==Campaign.Definition.SERVO_FORMAT and selected.servo_integration==Campaign.ServoLaw.LAW)
	selected.erase("servo_integration")
	selected.format=original.format
	check("all other authored physical values are identical",selected==original)
	var context: Dictionary = campaign._source_context()
	check("intermediate campaign module belongs to source identity",Campaign.Bytes.is_sha256(context.sources["servo_arrival_campaign.gd"]) and Campaign.valid_context(context))
	var compiled: Dictionary = Campaign.Compiler.compile_candidate(original)
	check("historical compiler fixture",compiled.ok)
	if compiled.ok:
		check("unselected physical candidate cannot claim the new law",not campaign.candidate_is_admitted(compiled.value,original))
	check("unrecorded replay cannot claim the new law",not campaign.baseline_replay_is_admitted({}))
	check("partial replay declaration refused",not campaign.baseline_replay_is_admitted({servo_integration={checkpoint_migration="none",recorded={law=Campaign.ServoLaw.LAW}}}))
	var composite:=Composite.new()
	for index: int in 68:
		composite.set("_cell",index)
		var spec: Dictionary=composite.specification()
		check("composite preserves the fixed cell order",spec.case_id+"/"+spec.tape==cells[index] and spec.calibrate==false)
	composite.free()
	campaign.free()
	print("SERVO_ARRIVAL_CAMPAIGN_TEST %d checks, %d failures" % [checks,failures])
	quit(0 if failures==0 else 1)
