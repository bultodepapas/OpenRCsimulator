// NK-8a: app/render/projected_shadow.gd _part_pose and _part_visible for every part in one native walk each, exact.
// A part's pose composes the Node3D transforms from the part up to the shadow's source with the engine's own
// Transform3D * Transform3D operator evaluator (the function GDScript calls), so the result is the engine's on every
// platform; visibility is false at the first hidden Node3D, else whether the walk reached the source. A part whose
// node is gone (or never bound) keeps its rest pose and is visible only when it was never bound, as in GDScript.
// Presentation only: nothing here reaches the simulation.
#pragma once

#include <cstdint>
#include <vector>

#include <godot_cpp/core/gdextension_interface_loader.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int64_array.hpp>
#include <godot_cpp/variant/string_name.hpp>
#include <godot_cpp/variant/transform3d.hpp>
#include <godot_cpp/variant/variant.hpp>

namespace nk {
namespace render {

struct WalkBinds {
	GDExtensionMethodBindPtr get_parent = nullptr;
	GDExtensionMethodBindPtr get_transform = nullptr;
	GDExtensionMethodBindPtr is_visible = nullptr;
	void *node3d_tag = nullptr;
	GDExtensionPtrOperatorEvaluator multiply = nullptr;
	bool ok = false;
};

inline const WalkBinds &walk_binds() {
	static const WalkBinds binds = [] {
		WalkBinds b;
		const godot::StringName node("Node"), node3d("Node3D"), parent("get_parent"), transform("get_transform"),
			visible("is_visible");
		b.get_parent = godot::gdextension_interface::classdb_get_method_bind(node._native_ptr(), parent._native_ptr(), 3160264692);
		b.get_transform = godot::gdextension_interface::classdb_get_method_bind(node3d._native_ptr(), transform._native_ptr(),
			3229777777);
		b.is_visible = godot::gdextension_interface::classdb_get_method_bind(node3d._native_ptr(), visible._native_ptr(),
			36873697);
		b.node3d_tag = godot::gdextension_interface::classdb_get_class_tag(node3d._native_ptr());
		b.multiply = godot::gdextension_interface::variant_get_ptr_operator_evaluator(GDEXTENSION_VARIANT_OP_MULTIPLY,
			GDEXTENSION_VARIANT_TYPE_TRANSFORM3D, GDEXTENSION_VARIANT_TYPE_TRANSFORM3D);
		b.ok = b.get_parent && b.get_transform && b.is_visible && b.node3d_tag && b.multiply;
		return b;
	}();
	return binds;
}

class ShadowParts {
public:
	// ids: each part node's instance id (0 when none was found at bind); rests: their rest poses; bound: whether a
	// node was found at bind.
	bool bind(const godot::PackedInt64Array &ids, const godot::Array &rests, const godot::PackedByteArray &bound) {
		bound_ = false;
		if (!walk_binds().ok || rests.size() != ids.size() || bound.size() != ids.size()) return false;
		ids_.assign(ids.ptr(), ids.ptr() + ids.size());
		rests_.clear();
		for (int64_t i = 0; i < rests.size(); ++i) {
			if (rests[i].get_type() != godot::Variant::TRANSFORM3D) return false;
			rests_.push_back(rests[i]);
		}
		was_bound_.assign(bound.ptr(), bound.ptr() + bound.size());
		bound_ = true;
		return true;
	}

	// [poses (Transform3D), visibility (bool)] for every part in bind order; empty when unbound or the source is gone.
	godot::Array poses(int64_t source_id) const {
		godot::Array out;
		const WalkBinds &b = walk_binds();
		if (!bound_ || source_id == 0) return out;
		const GDExtensionObjectPtr source = godot::gdextension_interface::object_get_instance_from_id(GDObjectInstanceID(source_id));
		if (source == nullptr) return out;
		godot::Array poses;
		godot::Array visibility;
		for (size_t i = 0; i < ids_.size(); ++i) {
			const GDExtensionObjectPtr node = ids_[i] != 0
				? godot::gdextension_interface::object_get_instance_from_id(GDObjectInstanceID(ids_[i])) : nullptr;
			if (node == nullptr) {
				poses.push_back(rests_[i]);
				visibility.push_back(!was_bound_[i]);
				continue;
			}
			godot::Transform3D transform;
			bool visible = true;
			GDExtensionObjectPtr walk = node;
			while (walk != source && walk != nullptr) {
				if (godot::gdextension_interface::object_cast_to(walk, b.node3d_tag) != nullptr) {
					godot::Transform3D local;
					godot::gdextension_interface::object_method_bind_ptrcall(b.get_transform, walk, nullptr, &local);
					godot::Transform3D product;
					b.multiply(&local, &transform, &product); // (walk as Node3D).transform * transform
					transform = product;
					GDExtensionBool shown = 1;
					godot::gdextension_interface::object_method_bind_ptrcall(b.is_visible, walk, nullptr, &shown);
					if (!shown) visible = false;
				}
				GDExtensionObjectPtr parent = nullptr;
				godot::gdextension_interface::object_method_bind_ptrcall(b.get_parent, walk, nullptr, &parent);
				walk = parent;
			}
			const bool reached = walk == source;
			poses.push_back(reached ? godot::Variant(transform) : godot::Variant(rests_[i]));
			visibility.push_back(visible && reached);
		}
		out.push_back(poses);
		out.push_back(visibility);
		return out;
	}

private:
	bool bound_ = false;
	std::vector<int64_t> ids_;
	std::vector<godot::Transform3D> rests_;
	std::vector<uint8_t> was_bound_;
};

} // namespace render
} // namespace nk
