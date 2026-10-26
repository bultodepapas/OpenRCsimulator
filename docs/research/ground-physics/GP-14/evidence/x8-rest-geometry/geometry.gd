extends SceneTree
const AD:=preload("res://physics/aircraft_data.gd")
const M:=preload("res://physics/math3d.gd")
func _initialize()->void:
	var path:="res://data/aircraft/skywalker_x8.json"
	var raw:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	var loaded:=AD.load_file(path)
	if not loaded.ok:printerr(loaded.errors);quit(1);return
	var points:Array=[]
	for row:Array in raw.crash_hull.value:points.append(PackedFloat64Array(row))
	var supported:=AD.ground_support(points,loaded.model.cg_le)
	var ids:Array=[]
	for i:int in supported.facet:ids.append(raw.crash_hull_ids[i])
	var a:PackedFloat64Array=points[supported.facet[0]]
	var b:PackedFloat64Array=points[supported.facet[1]]
	var c:PackedFloat64Array=points[supported.facet[2]]
	var n:=M.cross(M.sub(b,a),M.sub(c,a))
	if n[2]<0.0:n=M.scale(n,-1.0)
	n=M.scale(n,1.0/M.norm(n))
	var rows:Array=[]
	for i:int in points.size():rows.append({id=raw.crash_hull_ids[i],point=points[i]})
	var result:={raw_data_sha256=FileAccess.get_sha256(path),support=supported,ids=ids,normal_le=n,cg_le=loaded.model.cg_le,
		roll_rad=M.atan2_(-n[1],n[2]),pitch_rad=M.atan2_(-n[0],M.sqrt_(n[1]*n[1]+n[2]*n[2])),hull=rows}
	var file:=FileAccess.open("res://../tmp/gp-x8-support/geometry.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "));file.close()
	print("X8 hull support geometry: ",JSON.stringify({ids=ids,supported=supported,roll=result.roll_rad,pitch=result.pitch_rad}))
	quit(0)
