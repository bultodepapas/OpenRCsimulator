extends SceneTree
const Loader = preload("res://data/lake_loader.gd")
const Before = preload("res://physics/lake_surface.gd")
const After = preload("C:/DEVELOPMENT/OpenRCsimulator/tmp/perf-pass3-20261019/candidate/physics/lake_surface.gd")
func _initialize() -> void:
 var lake: Dictionary = Loader.load_from(Loader.DEFAULT_PATH).lake
 var report := {complete = true, cases = [], iterations = 1000, repeats = 6, scope = "Direct lake sampler only; not full-session cost"}
 for point: Array in [["runway",0.0,0.0],["bed",110.0,125.0],["bank",110.0,174.0],["bank edge",110.0,176.0],["outside near bank",110.0,176.01]]:
  var row := {label = point[0], before_usec = [], after_usec = [], covered = false}
  var reference: Dictionary = Before.sample_terrain_validated(lake,point[1],point[2])
  var candidate: Dictionary = After.sample_covered_terrain_validated(lake,point[1],point[2])
  row.covered = reference.covered
  if reference.covered != candidate.covered or (reference.covered and var_to_bytes(reference) != var_to_bytes(candidate)):
   report.complete = false
  for warm in 100:
   Before.sample_terrain_validated(lake,point[1],point[2])
   After.sample_covered_terrain_validated(lake,point[1],point[2])
  for pair in 6:
   for mode: int in ([0,1] if pair % 2 == 0 else [1,0]):
    var start := Time.get_ticks_usec()
    if mode == 0:
     for i in 1000: Before.sample_terrain_validated(lake,point[1],point[2])
    else:
     for i in 1000: After.sample_covered_terrain_validated(lake,point[1],point[2])
    row["before_usec" if mode == 0 else "after_usec"].append(Time.get_ticks_usec()-start)
  report.cases.append(row)
 var output := OS.get_cmdline_user_args()[0]
 if FileAccess.file_exists(output):
  quit(2)
  return
 FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
 print("covered component ","PASS" if report.complete else "FAIL")
 quit(0 if report.complete else 1)
