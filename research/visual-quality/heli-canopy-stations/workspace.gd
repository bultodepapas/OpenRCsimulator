extends SceneTree
const Model=preload("res://aircraft/hx700_model.gd")
var candidate: Script
var output: String
func _initialize() -> void:
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--candidate="): candidate=load(arg.trim_prefix("--candidate="))
  if arg.begins_with("--out="): output=arg.trim_prefix("--out=")
 _run.call_deferred()
func _run() -> void:
 var model: Dictionary=Model.build()
 var canopy:=model.root.find_child("Carenado",true,false) as MeshInstance3D
 var triangles: PackedVector3Array=candidate._triangles(model.root,canopy)
 var stations:=PackedFloat64Array()
 for index: int in 17: stations.append(lerpf(-.355,.045,float(index)/16.0))
 var visits:=0
 for index: int in range(0,triangles.size()-2,3):
  var lo: float=minf(triangles[index].z,minf(triangles[index+1].z,triangles[index+2].z))
  var hi: float=maxf(triangles[index].z,maxf(triangles[index+1].z,triangles[index+2].z))
  visits+=stations.bsearch(hi,false)-stations.bsearch(lo)
 var samples: Array=[]
 for iteration: int in 4:
  var before:=OS.get_static_memory_usage()
  var sections: Array=candidate._canopy_sections(triangles,stations)
  var retained:=OS.get_static_memory_usage()-before
  var segments:=0
  var points:=0
  for section: Dictionary in sections:
   segments+=section.segments.size()
   for segment: PackedVector3Array in section.segments: points+=segment.size()
  sections.clear()
  samples.append({retained_bytes=retained,after_clear_bytes=OS.get_static_memory_usage()-before,segments=segments,points=points})
 var result: Dictionary={exhaustive_triangle_plane_visits=triangles.size()/3*17,bounded_triangle_plane_visits=visits,samples=samples}
 FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
 print(JSON.stringify(result))
 model.root.free()
 await process_frame
 quit()
