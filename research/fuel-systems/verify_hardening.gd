## FUEL-12-R2: compare complete same-law tapes against current code and exact-replay new logs.
## Requires --source-dir=<baseline ORFL directory> --out=<new absolute directory>.
extends SceneTree
const Log := preload("res://sim/flight_log.gd")
const Reader := preload("res://tools/flight_log_cli.gd")
var source_directory := ""
var destination := ""
func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--source-dir="): source_directory=argument.trim_prefix("--source-dir=")
		if argument.begins_with("--out="): destination=argument.trim_prefix("--out=")
	if not source_directory.is_absolute_path() or not destination.is_absolute_path() \
		or not DirAccess.dir_exists_absolute(source_directory) or DirAccess.dir_exists_absolute(destination) or FileAccess.file_exists(destination):
		printerr("Require an existing absolute --source-dir and a new absolute --out directory")
		quit(2)
		return
	if DirAccess.make_dir_recursive_absolute(destination)!=OK:
		printerr("Cannot create evidence directory")
		quit(2)
		return
	call_deferred("run")
func run() -> void:
	var results: Array = []
	var failed := false
	for name: String in DirAccess.get_files_at(source_directory):
		if not name.ends_with(".orfl"): continue
		var result: Dictionary=compare(source_directory.path_join(name),destination.path_join(name))
		results.append(result)
		failed=failed or not result.get("ok",false)
		print(name,": ",result.get("ok",false),"; ",result.get("error",""))
	var file := FileAccess.open(destination.path_join("verification.json"),FileAccess.WRITE)
	if file==null: printerr("Cannot write verification report"); quit(2); return
	file.store_string(JSON.stringify({format="openrc-fuel-hardening-replay v1",software_only=true,
		comparison="Same-law candidate experiment with the recorded initial body/internal state and command tape; byte comparison is scoped to these recordings.",
		current_solver_sha256=Log.solver_identity(),failed=failed,results=results},"\t",true,true))
	file.close()
	quit(1 if failed or results.is_empty() else 0)
func compare(source: String, output: String) -> Dictionary:
	var checked: Dictionary=Reader.inspect(source)
	if not checked.get("ok",false) or not checked.get("complete",false): return {ok=false,error="baseline log is incomplete"}
	if checked.get("events_omitted",0)!=0: return {ok=false,error="baseline event list is truncated"}
	var prepared: Dictionary=Reader.prepare_replay(checked.header,str(checked.header.aircraft_path))
	if not prepared.get("ok",false): return {ok=false,error=prepared.get("error","candidate restore failed")}
	var logger := Log.new(prepared.flight)
	if logger.start(output)!=OK:
		prepared.flight.free()
		return {ok=false,error="candidate recording failed to start"}
	var compared: Dictionary=consume(source,prepared.flight,logger,checked.events)
	var stopped: Error=logger.stop()
	prepared.flight.free()
	var exact: Dictionary={ok=false,error="candidate failed"}
	if compared.ok and stopped==OK:
		var candidate: Dictionary=Reader.inspect(output)
		var replay: Dictionary=Reader.prepare_replay(candidate.header) if candidate.get("ok",false) else {ok=false}
		if replay.get("ok",false):
			var observer := Log.new(replay.flight)
			exact=consume(output,replay.flight,observer,[])
			replay.flight.free()
		else: exact={ok=false,error=replay.get("error","exact restore failed")}
	var failure: String=compared.get("error","")
	if failure.is_empty() and stopped!=OK: failure="candidate recording failed to stop"
	if failure.is_empty() and not exact.ok: failure=exact.get("error","candidate exact replay failed")
	return {ok=compared.ok and stopped==OK and exact.ok,source=source.get_file(),candidate=output.get_file(),
		source_sha256=FileAccess.get_sha256(source),candidate_sha256=FileAccess.get_sha256(output),
		baseline_solver_sha256=checked.header.solver_sha256,current_solver_sha256=Log.solver_identity(),
		solver_changed=checked.header.solver_sha256!=Log.solver_identity(),
		complete=compared.complete and stopped==OK and exact.get("complete",false),
		comparison=compared,exact_candidate_replay=exact,error=failure}
func consume(path: String, flight: Node, observer: RefCounted, markers: Array) -> Dictionary:
	var stream := FileAccess.open(path,FileAccess.READ)
	stream.seek(8)
	Log.read_packet(stream)
	var rows := 0
	var error := ""
	var complete := false
	while stream.get_position()<stream.get_length() and error.is_empty():
		var packet: Dictionary=Log.read_packet(stream)
		if not packet.get("ok",false): error="invalid packet"; break
		var block: Dictionary=packet.value
		if block.kind=="footer": complete=true; break
		for row: Dictionary in block.rows:
			if rows>0:
				for key: String in row.intervention: flight.sim.set(key,row.intervention[key].duplicate())
				flight.sim.inputs=row.inputs.duplicate()
				flight.sim.step()
			if not flight.sim.fault_reason.is_empty() or flight.sim.tick!=row.tick:
				error="candidate tick failed: "+flight.sim.fault_reason
				break
			error=Reader.disagreement(row,observer._sample({}))
			rows+=1
			for marker: Dictionary in markers:
				if marker.get("kind")=="marker" and int(marker.tick)==int(row.tick): observer.mark(str(marker.detail))
			if not error.is_empty(): break
	stream.close()
	return {ok=error.is_empty() and complete,rows=rows,complete=complete,byte_exact=error.is_empty() and complete,error=error}
