extends RefCounted
## Shared authoring setup; importing this fixture never imports another test suite.
const Authoring := preload("res://workshop/creator/authoring.gd")
const Definition := preload("res://workshop/creator/definition.gd")


static func populated(source: RefCounted) -> RefCounted:
	var doc := Authoring.new()
	doc.name = "Reference trainer"
	doc.set_source(source)
	var template: Dictionary = Definition.template()
	var values := {}
	for entry: Dictionary in Authoring.FIELDS:
		values[entry.path] = Authoring._lookup(template, entry.path.split("/"))
	doc.apply_values(values, true)
	doc.propose_inventory()
	doc.set_axis("nose_axis", "+x")
	doc.set_axis("up_axis", "+z")
	doc.set_units("m")
	doc.set_datum([0.0, 0.0, 0.0])
	return doc
