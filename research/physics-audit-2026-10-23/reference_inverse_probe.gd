extends SceneTree

const MassInventory := preload("res://physics/mass_inventory.gd")
const RB := preload("res://physics/rigid_body.gd")

func _initialize() -> void:
	var zero := PackedFloat64Array([0.0, 0.0, 0.0])
	var resource := {id = "zero", reference_mass_kg = 0.0, capacity_mass_kg = 0.0,
		center_body_m = zero, size_body_m = zero}
	for item: Dictionary in [
			{label = "huge SPD", inertia = PackedFloat64Array([1.0e150, 2.0e150, 3.0e150, 0.0, 0.0, 0.0])},
			{label = "tiny SPD", inertia = PackedFloat64Array([1.0e-150, 2.0e-150, 3.0e-150, 0.0, 0.0, 0.0])}]:
		var prepared: Dictionary = MassInventory.prepare_reference(1.0, item.inertia, [resource])
		var evaluated: Dictionary = MassInventory.evaluate_reference(prepared,
			PackedFloat64Array([0.0])) if prepared.get("ok", false) else {ok = false, error = "prepare failed"}
		var product := PackedFloat64Array()
		if evaluated.get("ok", false):
			product = RB.inertia_mul(evaluated.inertia, RB.inertia_mul(evaluated.inverse,
				PackedFloat64Array([1.0, 0.0, 0.0])))
		print("%s prepare_ok=%s evaluate_ok=%s inverse=%s J*Jinv*e_x=%s error=%s" % [
			item.label, str(prepared.get("ok", false)), str(evaluated.get("ok", false)),
			str(evaluated.get("inverse", PackedFloat64Array())), str(product), str(evaluated.get("error", ""))])
		var geometry: Dictionary = MassInventory.prepare("datum", [{id = "dry", mass_kg = 1.0,
			center_body_m = zero, inertia_centroid_kgm2 = item.inertia}], [])
		var geometric_eval: Dictionary = MassInventory.evaluate(geometry, {}) if geometry.get("ok", false) else {ok = false}
		var geometric_product := PackedFloat64Array()
		if geometric_eval.get("ok", false):
			geometric_product = RB.inertia_mul(geometric_eval.inertia_cg_kgm2,
				RB.inertia_mul(geometric_eval.inverse_inertia_cg_kgm2, PackedFloat64Array([1.0, 0.0, 0.0])))
		print("%s scaled_path_ok=%s inverse=%s J*Jinv*e_x=%s" % [item.label,
			str(geometric_eval.get("ok", false)), str(geometric_eval.get("inverse_inertia_cg_kgm2", PackedFloat64Array())),
			str(geometric_product)])
	quit()
