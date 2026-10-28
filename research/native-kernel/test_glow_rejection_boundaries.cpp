// Small numeric controls for the native stopped-glow rejection witness.
// Built with the locked compiler and floating-point flags, without Godot.
#include <cmath>
#include <cstdio>
#include <limits>

#include "src/nk_glow_stage.hpp"

namespace {

int failures = 0;
int checks = 0;

void check(bool condition, const char *name) {
	++checks;
	if (!condition) {
		++failures;
		std::fprintf(stderr, "FAIL %s\n", name);
	}
}

struct Fixture {
	std::array<nk::R, 13> body{};
	std::array<nk::R, 6> external{};
	std::array<nk::R, 19> values{};
	nk::PropModel prop;
	nk::GlowLifecycleModel lifecycle;
	nk::GlowLifecycleState state;
	nk::GlowLifecyclePoint life;
	nk::GlowBladePoint blade;
	nk::LiquidMassProperties mass;

	Fixture() {
		body[6] = 1.0;
		values[12] = 1.0;
		prop.rotor_inertia = 0.125;
		lifecycle.throttle_capacity_m3_s = 1.0;
		auto &source = lifecycle.source;
		source.max_rpm = 100.0;
		source.displacement_m3 = 1.0e-6;
		source.oil_fraction = 0.0;
		source.stoich_air_fuel_ratio = 14.7;
		source.fuel_lhv_j_kg = 4.0e7;
		source.breathing = {0.0, 1.0, 100.0, 1.0};
		source.trapping_efficiency = {0.0, 1.0, 100.0, 1.0};
		source.pumping_pressure = {0.0, 0.0, 100.0, 0.0};
		source.mechanical_torque_nm = {0.0, 0.125, 100.0, 0.125};
		source.combustion_efficiency = {0.0, 1.0, 2.0, 1.0};
		source.indicated_efficiency = {0.0, 1.0, 100.0, 1.0};
		state.air_fraction = 1.0;
		life.ok = true;
		life.source.shaft_torque_nm = 0.0;
		blade.ok = true;
		mass.ok = true;
		mass.mass_kg = 1.0;
		mass.inertia = {1.0, 1.0, 1.0, 0.0, 0.0, 0.0};
		mass.inverse = mass.inertia;
	}

	nk::GlowCoupledStage run(nk::GlowStageRejection *rejection) const {
		return nk::glow_coupled_stage(body.data(), external.data(), values.data(), prop, lifecycle, state,
				life, blade, mass, 1.0, 9.80665, rejection);
	}
};

enum class FeedCase { BothReverse, LowReverse, HighReverse, MixedFailure, InvalidTarget, InteriorReverse,
		SpeculativeOnly, SpeculativeThenOther };

struct FeedObservation {
	bool solved = false;
	nk::GlowStageRejection diagnostic;
};

FeedObservation exercise_feed(FeedCase which, const nk::GlowStageRejection &actual_reverse) {
	nk::GlowFeedRejectionWitness witness;
	// A speculative factor=1 base is intentionally not passed to the witness.
	const nk::GlowStageRejection speculative = actual_reverse;
	(void)speculative;
	auto result = nk::glow_feed_solve<int>([&](nk::R factor) {
		nk::GlowFeedProbe<int> probe;
		const bool low = factor.v == 0.0;
		const bool high = factor.v == 2.0;
		const bool interior = !low && !high;
		const bool reverse = (which == FeedCase::BothReverse && (low || high)) ||
				(which == FeedCase::LowReverse && low) || (which == FeedCase::HighReverse && high) ||
				((which == FeedCase::MixedFailure || which == FeedCase::InvalidTarget) && low) ||
				(which == FeedCase::InteriorReverse && interior);
		if (reverse) {
			witness.rejected_probe(factor, actual_reverse);
			return probe;
		}
		if ((which == FeedCase::MixedFailure && high) || which == FeedCase::SpeculativeThenOther) {
			witness.other_failure();
			return probe;
		}
		probe.ok = true;
		probe.target_factor = which == FeedCase::InvalidTarget && high ? 3.0 : 1.0;
		if (probe.target_factor.v < 0.0 || probe.target_factor.v > 2.0) witness.other_failure();
		return probe;
	}, 1.0);
	FeedObservation out;
	out.solved = result.ok;
	if (!result.ok) witness.publish_on_failure(&out.diagnostic);
	return out;
}

} // namespace

int main() {
	Fixture fixture;
	const nk::R breathing = nk::glow_source_table_sample(fixture.lifecycle.source.breathing, 0.001);
	const nk::R admission = nk::glow_carb_admission(fixture.state.air_fraction, 0.001, breathing,
			fixture.lifecycle.source.displacement_m3, 1.0, fixture.lifecycle.throttle_capacity_m3_s);
	const auto coast = nk::glow_source_evaluate(fixture.lifecycle.source, 0.001, admission, 1.0, 1.0, false, 1.0);
	check(coast.ok && -coast.shaft_torque_nm.v == 0.125, "fixture has exactly representable static friction");

	fixture.blade.torque_nm = 0.125;
	nk::GlowStageRejection equality;
	const auto at = fixture.run(&equality);
	check(at.ok && equality.code == nk::GlowRejectionCode::None, "demand equals -friction: hold, no refusal");

	fixture.blade.torque_nm = std::nextafter(0.125, 0.0);
	nk::GlowStageRejection above;
	const auto near_above = fixture.run(&above);
	check(near_above.ok && above.code == nk::GlowRejectionCode::None, "adjacent demand above -friction: hold");

	fixture.blade.torque_nm = std::nextafter(0.125, std::numeric_limits<double>::infinity());
	nk::GlowStageRejection reverse;
	const auto near_below = fixture.run(&reverse);
	check(!near_below.ok && reverse.code == nk::GlowRejectionCode::StoppedReverseDrive && reverse.rpm == 0.0 &&
			reverse.demand_nm < -reverse.friction_nm, "adjacent demand below -friction: actual reverse refusal");
	const auto disabled = fixture.run(nullptr);
	check(!disabled.ok, "disabled diagnostic leaves the actual refusal unchanged");

	fixture.values[0] = -0.0;
	nk::GlowStageRejection signed_zero;
	check(!fixture.run(&signed_zero).ok && signed_zero.code == nk::GlowRejectionCode::StoppedReverseDrive &&
			signed_zero.rpm == 0.0 && std::signbit(signed_zero.rpm), "negative zero is stopped and retains its sign");
	fixture.values[0] = -0.001;
	nk::GlowStageRejection negative_rpm;
	const auto moving_left = fixture.run(&negative_rpm);
	check(moving_left.ok && negative_rpm.code == nk::GlowRejectionCode::None, "negative trial RPM is a moving left limit");
	fixture.values[0] = 0.0;
	fixture.external[0] = std::numeric_limits<double>::quiet_NaN();
	nk::GlowStageRejection nonfinite;
	check(!fixture.run(&nonfinite).ok && nonfinite.code == nk::GlowRejectionCode::None,
			"nonfinite external loads cannot acquire a reverse reason");
	fixture.external[0] = 0.0;
	fixture.prop.has_axis = true;
	fixture.prop.axis[0] = 2.0;
	fixture.prop.axis[1] = 0.0;
	fixture.prop.axis[2] = 0.0;
	nk::GlowStageRejection invalid_axis;
	check(!fixture.run(&invalid_axis).ok && invalid_axis.code == nk::GlowRejectionCode::None,
			"invalid propeller axis cannot acquire a reverse reason");
	fixture.prop.axis[0] = 1.0;
	fixture.prop.rotor_inertia = 1.0;
	nk::GlowStageRejection invalid_denominator;
	check(!fixture.run(&invalid_denominator).ok && invalid_denominator.code == nk::GlowRejectionCode::None,
			"singular coupled inertia cannot acquire a reverse reason");

	const auto both = exercise_feed(FeedCase::BothReverse, reverse);
	check(!both.solved && both.diagnostic.code == nk::GlowRejectionCode::StoppedReverseDrive &&
			both.diagnostic.origin == nk::GlowRejectionOrigin::FeedEndpoint && both.diagnostic.feed_factor == 0.0,
			"two actual reverse endpoints retain the first endpoint");
	const auto low = exercise_feed(FeedCase::LowReverse, reverse);
	check(!low.solved && low.diagnostic.code == nk::GlowRejectionCode::StoppedReverseDrive &&
			low.diagnostic.feed_factor == 0.0, "only the low endpoint rejects in reverse");
	const auto high = exercise_feed(FeedCase::HighReverse, reverse);
	check(!high.solved && high.diagnostic.code == nk::GlowRejectionCode::StoppedReverseDrive &&
			high.diagnostic.feed_factor == 2.0, "only the high endpoint rejects in reverse");
	for (FeedCase mode : {FeedCase::MixedFailure, FeedCase::InvalidTarget, FeedCase::InteriorReverse,
			FeedCase::SpeculativeThenOther}) {
		const auto result = exercise_feed(mode, reverse);
		check(!result.solved && result.diagnostic.code == nk::GlowRejectionCode::None,
				"mixed, unrelated or interior failure is not an endpoint refusal");
	}
	const auto speculative = exercise_feed(FeedCase::SpeculativeOnly, reverse);
	check(speculative.solved && speculative.diagnostic.code == nk::GlowRejectionCode::None,
			"speculative base failure cannot label a successful solve");
	std::printf("NK3 glow rejection boundaries: %d checks, %d failed\n", checks, failures);
	return failures == 0 ? 0 : 1;
}
