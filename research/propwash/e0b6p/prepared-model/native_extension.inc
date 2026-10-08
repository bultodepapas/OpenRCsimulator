class OpenRCPreparedWake final : public godot::RefCounted {
	GDCLASS(OpenRCPreparedWake, godot::RefCounted)

protected:
	static void _bind_methods() {
		godot::ClassDB::bind_method(godot::D_METHOD("loads", "state", "velocity", "deflections", "model",
				"thrust_torque", "rho", "fade", "downwash_cl", "transported_dv"), &OpenRCPreparedWake::loads);
		godot::ClassDB::bind_method(godot::D_METHOD("prepare_model", "model"), &OpenRCPreparedWake::prepare_model);
		godot::ClassDB::bind_method(godot::D_METHOD("invalidate_model"), &OpenRCPreparedWake::invalidate_model);
		godot::ClassDB::bind_method(godot::D_METHOD("loads_prepared", "state", "velocity", "deflections", "token",
				"thrust_torque", "rho", "fade", "downwash_cl", "transported_dv"),
				&OpenRCPreparedWake::loads_prepared);
	}

public:
	// Stateless baseline retained with the same API and decoding path.
	godot::PackedFloat64Array loads(const godot::PackedFloat64Array &state_value,
		const godot::PackedFloat64Array &velocity_value, const godot::Dictionary &deflections_value,
			const godot::Dictionary &model_value, const godot::PackedFloat64Array &thrust_torque_value,
			double rho, double fade, double downwash_cl, const godot::PackedFloat64Array &transported_dv_value) {
		if (state_value.size() != 13 || velocity_value.size() != 3 || thrust_torque_value.size() != 2) {
			return godot::PackedFloat64Array();
		}
		State13 state{};
		Vec3 velocity{};
		Pair thrust_torque{};
		for (int64_t i = 0; i < state_value.size(); ++i) {
			state[static_cast<std::size_t>(i)] = state_value[i];
		}
		for (int64_t i = 0; i < velocity_value.size(); ++i) {
			velocity[static_cast<std::size_t>(i)] = velocity_value[i];
		}
		for (int64_t i = 0; i < thrust_torque_value.size(); ++i) {
			thrust_torque[static_cast<std::size_t>(i)] = thrust_torque_value[i];
		}
		Pair deflections{};
		if (!read_number(deflections_value, "elevator", deflections[0]) ||
				!read_number(deflections_value, "rudder", deflections[1])) {
			return godot::PackedFloat64Array();
		}
		Model model;
		if (!read_model(model_value, model)) {
			return godot::PackedFloat64Array();
		}
		if (!transported_dv_value.is_empty() &&
				static_cast<std::size_t>(transported_dv_value.size()) != model.piece_count) {
			return godot::PackedFloat64Array();
		}
		std::vector<double> transported_dv;
		transported_dv.reserve(static_cast<std::size_t>(transported_dv_value.size()));
		for (int64_t i = 0; i < transported_dv_value.size(); ++i) {
			transported_dv.push_back(transported_dv_value[i]);
		}
		Loads6 result{};
		if (!openrc::smooth_wake::loads(state, velocity, deflections, model, thrust_torque, rho, fade,
				downwash_cl, transported_dv, result)) {
			return godot::PackedFloat64Array();
		}
		return pack_loads(result);
	}

	int64_t prepare_model(const godot::Dictionary &model_value) {
		// A failed attempt must make every previously issued token unusable.
		invalidate_active_model();
		if (last_issued_generation_ == std::numeric_limits<int64_t>::max()) {
			return 0;
		}

		Model candidate{};
		if (!read_model(model_value, candidate)) {
			return 0;
		}
		const State13 state{};
		const Vec3 velocity{};
		const Pair deflections{};
		const Pair thrust_torque{};
		const std::vector<double> transported_dv;
		const double downwash_cl = candidate.tails[0].has_free_slope ? 0.0 :
				std::numeric_limits<double>::quiet_NaN();
		if (!validate(state, velocity, deflections, candidate, thrust_torque, 1.225, 1.0, downwash_cl,
				transported_dv)) {
			return 0;
		}

		// Model is copied by value; this object retains no Godot Dictionary or Array references.
		model_ = candidate;
		last_issued_generation_ += 1;
		active_generation_ = last_issued_generation_;
		model_valid_ = true;
		return active_generation_;
	}

	void invalidate_model() {
		invalidate_active_model();
	}

	godot::PackedFloat64Array loads_prepared(const godot::PackedFloat64Array &state_value,
		const godot::PackedFloat64Array &velocity_value, const godot::Dictionary &deflections_value,
			int64_t token, const godot::PackedFloat64Array &thrust_torque_value,
			double rho, double fade, double downwash_cl, const godot::PackedFloat64Array &transported_dv_value) {
		if (!model_valid_ || token <= 0 || token != active_generation_ ||
				state_value.size() != 13 || velocity_value.size() != 3 || thrust_torque_value.size() != 2) {
			return godot::PackedFloat64Array();
		}
		State13 state{};
		Vec3 velocity{};
		Pair thrust_torque{};
		for (int64_t i = 0; i < state_value.size(); ++i) {
			state[static_cast<std::size_t>(i)] = state_value[i];
		}
		for (int64_t i = 0; i < velocity_value.size(); ++i) {
			velocity[static_cast<std::size_t>(i)] = velocity_value[i];
		}
		for (int64_t i = 0; i < thrust_torque_value.size(); ++i) {
			thrust_torque[static_cast<std::size_t>(i)] = thrust_torque_value[i];
		}
		Pair deflections{};
		if (!read_number(deflections_value, "elevator", deflections[0]) ||
				!read_number(deflections_value, "rudder", deflections[1])) {
			return godot::PackedFloat64Array();
		}
		if (!transported_dv_value.is_empty() &&
				static_cast<std::size_t>(transported_dv_value.size()) != model_.piece_count) {
			return godot::PackedFloat64Array();
		}
		std::vector<double> transported_dv;
		transported_dv.reserve(static_cast<std::size_t>(transported_dv_value.size()));
		for (int64_t i = 0; i < transported_dv_value.size(); ++i) {
			transported_dv.push_back(transported_dv_value[i]);
		}
		Loads6 result{};
		if (!openrc::smooth_wake::loads(state, velocity, deflections, model_, thrust_torque, rho, fade,
				downwash_cl, transported_dv, result)) {
			return godot::PackedFloat64Array();
		}
		return pack_loads(result);
	}

private:
	static godot::PackedFloat64Array pack_loads(const Loads6 &result) {
		godot::PackedFloat64Array packed_result;
		packed_result.resize(6);
		for (std::size_t i = 0; i < result.size(); ++i) {
			packed_result[static_cast<int64_t>(i)] = result[i];
		}
		return packed_result;
	}

	void invalidate_active_model() {
		model_valid_ = false;
		active_generation_ = 0;
		model_ = Model{};
	}

	Model model_{};
	int64_t last_issued_generation_ = 0;
	int64_t active_generation_ = 0;
	bool model_valid_ = false;
};

void initialize_openrc_prepared_wake(godot::ModuleInitializationLevel level) {
	if (level == godot::MODULE_INITIALIZATION_LEVEL_SCENE) {
		godot::ClassDB::register_class<OpenRCPreparedWake>();
	}
}

void uninitialize_openrc_prepared_wake(godot::ModuleInitializationLevel) {}

extern "C" GDExtensionBool GDE_EXPORT openrc_prepared_wake_library_init(
		GDExtensionInterfaceGetProcAddress get_proc_address, GDExtensionClassLibraryPtr library,
		GDExtensionInitialization *initialization) {
	godot::GDExtensionBinding::InitObject init_object(get_proc_address, library, initialization);
	init_object.register_initializer(initialize_openrc_prepared_wake);
	init_object.register_terminator(uninitialize_openrc_prepared_wake);
	init_object.set_minimum_library_initialization_level(godot::MODULE_INITIALIZATION_LEVEL_SCENE);
	return init_object.init();
}
