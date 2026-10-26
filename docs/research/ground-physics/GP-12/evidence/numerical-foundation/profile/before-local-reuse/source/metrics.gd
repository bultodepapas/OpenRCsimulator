extends RefCounted
static var totals:Dictionary={}
static var counts:Dictionary={}
static func record(label:String,elapsed:int)->void:
	totals[label]=int(totals.get(label,0))+elapsed
	counts[label]=int(counts.get(label,0))+1
static func clear()->void:
	totals.clear()
	counts.clear()
