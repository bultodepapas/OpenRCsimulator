extends SceneTree

const Registry := preload("res://input/controller_registry.gd")

var checks := 0
var failures := 0


func check(label: String, condition: bool, detail: String = "") -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL ", label, " ", detail)


func _initialize() -> void:
	var registry := Registry.new()
	check("starts without implicit device selection", registry.selected_device_id("flight") == -1 and registry.selected_device_id("ui") == -1)
	check("unknown and cleared IDs have no device record", registry.device_for_id(-1).is_empty() and registry.device_for_id(99).is_empty())
	var devices_changed_count: Array[int] = [0]
	var selections: Array = []
	var signal_order: Array[String] = []
	registry.devices_changed.connect(func() -> void:
		devices_changed_count[0] += 1
		signal_order.append("devices")
	)
	registry.selection_changed.connect(func(role: String, id: int) -> void:
		selections.append([role, id])
		signal_order.append("selection:%s:%d" % [role, id])
	)
	var report := registry.update_devices([
		{"id": 5, "name": "Xbox", "raw_name": "Xbox Wireless Controller", "known": true, "guid": "AABB", "vendor_id": "4617", "product_id": "20308", "serial_number": "serial-a", "backend": "SDL", "transport": "usb"},
		{"id": 2, "name": "Radio", "known": false, "guid": "radio-guid", "vendor_id": 0, "product_id": 0},
	])
	check("valid observations are accepted", report.ok)
	check("devices arrive in stable ID order", registry.get_devices().size() == 2 and registry.get_devices()[0].id == 2 and registry.get_devices()[1].id == 5)
	var pad: Dictionary = registry.device_for_id(5)
	check("decimal VID/PID strings become uint metadata", pad.vendor_id == 4617 and pad.product_id == 20308)
	check("device kind and connected status are explicit", pad.kind == "gamepad" and pad.connected and pad.generation == 1)
	check("connect does not emit selection or select automatically", registry.selected_device_id("flight") == -1 and selections.is_empty())
	check("first device snapshot emits devices_changed once", devices_changed_count[0] == 1)
	pad.name = "mutated"
	check("device observations are detached copies", registry.device_for_id(5).name == "Xbox")
	check("cannot select unknown role or unobserved ID", not registry.select_device("helicopter", 5) and not registry.select_device("flight", 99))
	check("explicit role selections work independently", registry.select_device("flight", 5) and registry.select_device("ui", 2) and registry.selected_device_id("flight") == 5 and registry.selected_device_id("ui") == 2)
	check("selection emits explicit role and ID", selections == [["flight", 5], ["ui", 2]])
	check("selecting same device is idempotent", registry.select_device("flight", 5) and selections.size() == 2)
	check("negative ID clears explicit selection", registry.select_device("ui", -1) and registry.selected_device_id("ui") == -1 and selections.back() == ["ui", -1])

	var duplicate_identity := registry.update_devices([
		{"id": 5, "name": "Xbox", "raw_name": "Xbox Wireless Controller", "known": true, "guid": "AABB", "vendor_id": 4617, "product_id": 20308, "serial_number": "serial-a", "backend": "SDL", "transport": "usb"},
		{"id": 7, "name": "Xbox 2", "raw_name": "Xbox Wireless Controller", "known": true, "guid": "aabb", "vendor_id": "4617", "product_id": "20308", "serial_number": "serial-b", "backend": "SDL", "transport": "usb"},
	])
	check("second observation update accepted", duplicate_identity.ok)
	check("matching GUID and VID/PID devices are marked ambiguous", registry.device_for_id(5).ambiguous and registry.device_for_id(7).ambiguous)
	check("new device is not adopted", registry.selected_device_id("flight") == 5 and registry.selected_device_id("ui") == -1)
	var generation_before: int = registry.connection_generation(5)
	registry.update_devices([
		{"id": 5, "name": "Xbox", "raw_name": "Xbox Wireless Controller", "known": true, "guid": "AABB", "vendor_id": "4617", "product_id": "20308", "serial_number": "serial-a", "backend": "SDL", "transport": "usb"},
		{"id": 7, "name": "Xbox 2", "raw_name": "Xbox Wireless Controller", "known": true, "guid": "aabb", "vendor_id": 4617, "product_id": 20308, "serial_number": "serial-b", "backend": "SDL", "transport": "usb"},
	])
	check("unchanged snapshot keeps connection generation", registry.connection_generation(5) == generation_before)

	selections.clear()
	signal_order.clear()
	registry.select_device("flight", 5)
	selections.clear()
	signal_order.clear()
	check("disconnect edge accepted", registry.disconnect_device(5))
	check("disconnect clears selected ownership without takeover", registry.selected_device_id("flight") == -1 and registry.selected_device_id("ui") == -1)
	check("selection loss signal precedes device list signal", signal_order == ["selection:flight:-1", "devices"], str(signal_order))
	check("disconnected record remains visible", not registry.device_for_id(5).connected and registry.connection_generation(5) == 1)
	check("repeated disconnect does not advance generation", registry.disconnect_device(5) and registry.connection_generation(5) == 1)
	registry.update_devices([{"id": 5, "name": "Xbox", "raw_name": "Xbox Wireless Controller", "known": true, "guid": "AABB", "vendor_id": 4617, "product_id": 20308, "serial_number": "serial-a", "backend": "SDL", "transport": "usb"}])
	check("same handle reconnect advances generation and stays unselected", registry.connection_generation(5) == 2 and registry.selected_device_id("flight") == -1)
	registry.select_device("flight", 5)
	registry.update_devices([{"id": 5, "name": "Changed firmware", "raw_name": "Xbox Wireless Controller", "known": true, "guid": "DIFFERENT", "vendor_id": 4617, "product_id": 20308, "serial_number": "serial-a", "backend": "SDL", "transport": "usb"}])
	check("identity change clears selection and advances generation", registry.selected_device_id("flight") == -1 and registry.connection_generation(5) == 3)

	var malformed := registry.update_devices([
		{"id": -1, "name": "invalid"},
		{"id": 8, "name": "first"},
		{"id": 8, "name": "duplicate"},
		"not a device",
	])
	check("malformed observations are reported, not adopted", not malformed.ok and malformed.errors.size() == 3)
	check("first duplicate ID observation wins", registry.device_for_id(8).name == "first")
	print("Controller registry: %d checks, %d failed" % [checks, failures])
	quit(1 if failures else 0)
