extends RefCounted
static var stack:Array=[]
static var totals:Dictionary={}
static var counts:Dictionary={}
static var exclusive:Dictionary={}
static var serial_bytes:Dictionary={}
static func enter(label:String)->void:
	stack.append({label=label,start=Time.get_ticks_usec(),child=0})
static func leave()->void:
	var row:Dictionary=stack.pop_back()
	var elapsed:int=Time.get_ticks_usec()-row.start
	totals[row.label]=int(totals.get(row.label,0))+elapsed
	exclusive[row.label]=int(exclusive.get(row.label,0))+elapsed-int(row.child)
	counts[row.label]=int(counts.get(row.label,0))+1
	if not stack.is_empty():stack[-1].child+=elapsed
static func serialize(value:Variant)->PackedByteArray:
	var caller:String=stack[-1].label if not stack.is_empty() else "outside"
	var label:="serialize@"+caller
	enter(label)
	var bytes:=var_to_bytes(value)
	leave()
	serial_bytes[label]=int(serial_bytes.get(label,0))+bytes.size()
	return bytes
static func clear()->void:
	stack.clear();totals.clear();exclusive.clear();counts.clear();serial_bytes.clear()
