#include <algorithm>
#include <cmath>
#include <iomanip>
#include <iostream>
#include <limits>
#include <stdexcept>

// Independent binary64 component screen. Run with C++17, -O2,
// -fno-fast-math and -ffp-contract=off. No application stage is invoked.
constexpr double outer_step = 1.0 / 240.0;
constexpr int pieces = 16;
constexpr double piece = outer_step / pieces;
constexpr double stiffness = 1e6;
const double mass = 1.225 * std::acos(-1.0) / 3.0;

struct Heave {
    double penetration;
    double speed;
};

Heave derivative(Heave state) {
    return {state.speed, -stiffness * std::max(0.0, state.penetration) / mass};
}

Heave increment(Heave state, Heave rate, double interval) {
    return {state.penetration + interval * rate.penetration,
            state.speed + interval * rate.speed};
}

Heave integrate(Heave state) {
    const auto first = derivative(state);
    const auto second = derivative(increment(state, first, piece / 2));
    const auto third = derivative(increment(state, second, piece / 2));
    const auto fourth = derivative(increment(state, third, piece));
    return increment(state, {first.penetration + 2 * second.penetration + 2 * third.penetration + fourth.penetration,
                             first.speed + 2 * second.speed + 2 * third.speed + fourth.speed}, piece / 6);
}

struct Error {
    double energy_ratio;
    double relative_duration;
};

Error run_contact(double initial_delay) {
    const double exact_duration = std::acos(-1.0) * std::sqrt(mass / stiffness);
    Heave state{-initial_delay, 1.0};
    for (int step = 0; step < 64; ++step) {
        const auto next = integrate(state);
        if (state.penetration > 0 && next.penetration <= 0 && next.speed < 0) {
            // Release time estimated from endpoint depths, independently of energy.
            const double fraction = state.penetration / (state.penetration - next.penetration);
            const double duration = (step + fraction) * piece - initial_delay;
            return {std::abs(next.speed * next.speed - 1.0), std::abs(duration / exact_duration - 1.0)};
        }
        state = next;
    }
    throw std::runtime_error("contact failed to release");
}

void phase_scan(int total, double span) {
    Error worst{};
    for (int i = 0; i < total; ++i) {
        const auto error = run_contact(span * i / total);
        worst.energy_ratio = std::max(worst.energy_ratio, error.energy_ratio);
        worst.relative_duration = std::max(worst.relative_duration, error.relative_duration);
    }
    std::cout << "count=" << total << " span_s=" << span << " max_abs_energy_ratio_error=" << worst.energy_ratio
              << " max_rel_duration_error_linear_release=" << worst.relative_duration << '\n';
}

void shape_probe(double ratio) {
    const double x = (1.0 - ratio) * (1.0 + ratio);
    // Direct positive series for (beta-alpha)/x. Term ratios are < x.
    double d = 0.0;
    double power = 1.0;
    for (int j = 0; j < 100; ++j) {
        d += 6.0 * power / ((2 * j + 3) * (2 * j + 5));
        power *= x;
        if (power < std::numeric_limits<double>::epsilon() * (1 - x)) break;
    }
    const double delta = x * d;
    const double k1_correction = -1.5 * delta / (2.0 + delta);
    const double k2_correction = 1.5 * delta / (4.0 - delta);
    const double scaled_rotation = d / ((2.0 - x) * (2.0 - (2.0 - x) * d));
    std::cout << "shape_ratio=" << ratio << " x=" << x << " k1_minus_half=" << k1_correction
              << " k2_minus_half=" << k2_correction << " krot=" << x * x * scaled_rotation
              << " krot_over_x_squared=" << scaled_rotation << '\n';
}

int main() {
    static_assert(std::numeric_limits<double>::is_iec559 && std::numeric_limits<double>::digits == 53);
    std::cout << std::setprecision(17);
    phase_scan(32, piece);
    phase_scan(32, outer_step);
    phase_scan(512, outer_step);
    for (const auto ratio : {1.0 - 1e-4, 1.0 - 1e-10, 1.0 - 1e-12, std::nextafter(1.0, 0.0)}) {
        shape_probe(ratio);
    }
    const double a = 1.5;
    const double b = std::nextafter(a, 0.0);
    const double quotient = b / a;
    const double quotient_x = (1.0 - quotient) * (1.0 + quotient);
    const double relative_difference = (a - b) / a;
    const double difference_x = relative_difference * (2.0 - relative_difference);
    std::cout << "a=" << a << " adjacent_b=" << b << " quotient_first_x=" << quotient_x
              << " difference_first_x=" << difference_x
              << " leading_rotation_relative_error=" << std::pow(quotient_x / difference_x, 2) - 1.0 << '\n';
}
