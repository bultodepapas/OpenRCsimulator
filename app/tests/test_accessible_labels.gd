# PT1h-R12 (game findings #12): a Label just before a value control in the same container names it for screen
# readers (AccessKit) and agents, through accessibility_labeled_by_nodes, so a language change keeps it right.
# Run: godot --headless --path . --script res://tests/test_accessible_labels.gd
extends SceneTree

const AccessibleLabels := preload("res://ui/accessible_labels.gd")

var checks := 0
var failures := 0


func check(label: String, ok: bool, detail := "") -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL %s %s" % [label, detail])


func _labelled_by(control: Control) -> String:
	var links: Array = control.accessibility_labeled_by_nodes
	if links.is_empty():
		return ""
	var label := control.get_node_or_null(links[0])
	return str(label.text) if label is Label else "<not a label>"


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# Already in the tree before the linker arrives: the initial sweep covers it.
	var early := GridContainer.new()
	early.columns = 2
	root.add_child(early)
	early.add_child(_label("Text size"))
	var early_picker := OptionButton.new()
	early.add_child(early_picker)
	var linker := AccessibleLabels.new()
	root.add_child(linker)
	check("the first sweep links a control already in the tree", _labelled_by(early_picker) == "Text size", _labelled_by(early_picker))

	# Added later, as screens and tabs build their rows.
	var grid := GridContainer.new()
	grid.columns = 2
	root.add_child(grid)
	grid.add_child(_label("Window resolution"))
	var picker := OptionButton.new()
	picker.add_item("Automatic")
	grid.add_child(picker)
	grid.add_child(_label("Volume"))
	var slider := HSlider.new()
	grid.add_child(slider)
	grid.add_child(_label("Pilot name"))
	var field := LineEdit.new()
	grid.add_child(field)
	grid.add_child(_label("Smoke"))
	var bare_check := CheckBox.new()
	grid.add_child(bare_check)
	check("an OptionButton, a slider and a text field are named by the Label before them",
		_labelled_by(picker) == "Window resolution" and _labelled_by(slider) == "Volume" and _labelled_by(field) == "Pilot name")
	check("a check box without its own text is named by its Label", _labelled_by(bare_check) == "Smoke")

	# A whole subtree built off-tree, then added at once (a screen opening).
	var screen := VBoxContainer.new()
	var row := HBoxContainer.new()
	screen.add_child(row)
	row.add_child(_label("Units"))
	var units := OptionButton.new()
	row.add_child(units)
	root.add_child(screen)
	check("a subtree added at once is linked (parents enter the tree before their children)", _labelled_by(units) == "Units")

	# The link follows the Label: a language change renames the field without any refresh code.
	var label: Label = grid.get_child(0)
	label.text = "Resolución de ventana"
	check("the name follows the Label's current text", _labelled_by(picker) == "Resolución de ventana")

	# What must stay unlinked.
	var box := HBoxContainer.new()
	root.add_child(box)
	box.add_child(_label("Danger zone"))
	var button := Button.new()
	button.text = "Delete"
	box.add_child(button)
	box.add_child(_label("Notes"))
	var labelled_check := CheckBox.new()
	labelled_check.text = "Show trails"
	box.add_child(labelled_check)
	var named := OptionButton.new()
	named.accessibility_name = "Explicit name"
	box.add_child(_label("Ignored caption"))
	box.add_child(named)
	var first := OptionButton.new()
	var empty_row := HBoxContainer.new()
	root.add_child(empty_row)
	empty_row.add_child(first)
	var spacer_row := HBoxContainer.new()
	root.add_child(spacer_row)
	spacer_row.add_child(_label("   "))
	var after_blank := OptionButton.new()
	spacer_row.add_child(after_blank)
	check("buttons and check boxes with their own text keep naming themselves",
		_labelled_by(button) == "" and _labelled_by(labelled_check) == "")
	check("an explicit accessibility_name is never overridden", _labelled_by(named) == "" and named.accessibility_name == "Explicit name")
	check("no Label before (first child) or a blank Label links nothing", _labelled_by(first) == "" and _labelled_by(after_blank) == "")
	var loose := Control.new()
	root.add_child(loose)
	loose.add_child(_label("Not a container row"))
	var loose_picker := OptionButton.new()
	loose.add_child(loose_picker)
	check("only Container rows are read as label/control pairs", _labelled_by(loose_picker) == "")
	# Internal children (a ScrollContainer's scroll bars are Ranges) are skipped; asking their index is an engine error,
	# which the checked runner would report.
	var scroller_row := VBoxContainer.new()
	root.add_child(scroller_row)
	scroller_row.add_child(_label("Log"))
	var scroller := ScrollContainer.new()
	scroller_row.add_child(scroller)
	var internal_bars: Array = scroller.get_children(true).filter(func(n: Node) -> bool: return n is ScrollBar)
	check("internal scroll bars are never linked", not internal_bars.is_empty()
		and internal_bars.all(func(bar: ScrollBar) -> bool: return bar.accessibility_labeled_by_nodes.is_empty()))

	linker.queue_free()
	await process_frame
	var after := GridContainer.new()
	root.add_child(after)
	after.add_child(_label("Late"))
	var late_picker := OptionButton.new()
	after.add_child(late_picker)
	check("removing the linker disconnects it", _labelled_by(late_picker) == "")
	for node: Node in [early, grid, screen, box, empty_row, spacer_row, loose, scroller_row, after]:
		node.queue_free()
	await process_frame
	print("Accessible labels: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
