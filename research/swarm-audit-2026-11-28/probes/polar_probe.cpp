#include "nk_aero.hpp"

#include <cerrno>
#include <cfenv>
#include <cinttypes>
#include <cstdio>
#include <limits>
#include <vector>

static std::uint64_t pow_calls = 0, sin_calls = 0;
extern "C" double __real_pow(double, double);
extern "C" double __real_sin(double);
extern "C" double __wrap_pow(double x, double y) { ++pow_calls; return __real_pow(x, y); }
extern "C" double __wrap_sin(double x) { ++sin_calls; return __real_sin(x); }

static nk::AeroModel fixture() {
    nk::AeroModel m;
    m.S = 0.5; m.b = 1.5; m.c = 0.3;
    m.a1 = m.n1 = 0.19; m.a2 = m.n2 = 0.48;
    m.b1 = 0.15; m.b2 = 0.40; m.CD0 = 0.03; m.CLa = 5.0; m.CL0 = 0.12;
    m.strip_slope = 5.1; m.k_induced = 0.06; m.CL_minD = 0.08; m.CD90 = 1.55;
    m.tail_stall_end = 0.7; m.tail_local_limit = 0.2;
    m.vertical.area = 0.05; m.vertical.lift_slope = 3.2; m.vertical.position[0] = 0.7;
    m.horizontal = m.vertical; m.horizontal.present = true;
    m.ys = {-0.65, -0.39, -0.13, 0.13, 0.39, 0.65};
    m.wing_aileron_effectiveness = 0.41; m.strip_cl0.assign(6, nk::R(0.10));
    m.induced_map.assign(36, nk::R(-0.05));
    for (int i = 0; i < 6; ++i) m.induced_map[7 * i] = 0.99;
    m.polar.cd0 = m.CD0; m.polar.cd90 = m.CD90; m.polar.slope = m.CLa; m.polar.offset = m.CL0;
    m.polar.positive.angles = {0.15, 0.45, nk::kPi / 2.0};
    m.polar.positive.values = {0.85, 0.03, 1.0, 1.05, 0.31, 0.6, 0.0, 1.58, 0.0};
    m.polar.positive.tangents.assign(9, nk::R(0.0));
    m.polar.negative = m.polar.positive;
    m.polar.strip_factor = {0.9, 1.0, 1.1, 1.1, 1.0, 0.9};
    m.flaps.enabled = true; m.flaps.station_coverage = {0.0, 0.5, 1.0, 1.0, 0.5, 0.0};
    m.flaps.effective_angle_limit_deg = 30; m.flaps.lift_effectiveness = 0.55;
    m.flaps.aerodynamic_gain = 0.9; m.flaps.hinge_fraction = 0.7; m.flaps.chord_fraction = 0.3;
    m.flaps.profile_drag_coefficient = 0.025; m.flaps.thin_airfoil_moment_per_cl = -0.3;
    return m;
}

int main() {
    auto m = fixture();
    const double nan = std::numeric_limits<double>::quiet_NaN();
    const std::vector<double> speeds = {-9.0, -0.0, +0.0, 4.0, 18.0};
    const std::vector<double> verticals = {-19.0, -6.2, -0.0, +0.0, 0.3, 4.2, 18.0, nan};
    const std::vector<nk::R> scaled = {0.5, 0.62, 0.8, 0.8, 0.62, 0.5, 0.72, 0.68};
    const std::vector<nk::R> no_ground;
    for (int polar = 0; polar <= 1; ++polar) for (int ground = 0; ground <= 1; ++ground)
    for (int flap = 0; flap <= 1; ++flap) for (double speed : speeds) for (double vertical : verticals) {
        m.polar.enabled = polar;
        nk::R s[13] = {};
        s[3] = speed; s[4] = 0.21; s[5] = vertical; s[6] = 1.0; s[10] = 0.22; s[11] = 0.11; s[12] = -0.04;
        const nk::R wind[3] = {};
        nk::Deflections deflections;
        deflections.aileron_right = -0.018; deflections.aileron_left = 0.018; deflections.flap = flap ? 0.3 : 0.0;
        const nk::Air air = nk::air_compute(s, wind, 1.225);
        std::feclearexcept(FE_ALL_EXCEPT);
        errno = 0; pow_calls = 0; sin_calls = 0;
        const auto o = nk::local_loads(s, air, deflections, m, 1.225, 0.1, ground ? scaled : no_ground);
        const int err = errno, flags = std::fetestexcept(FE_ALL_EXCEPT);
        std::printf("%d %d %d %a %a", polar, ground, flap, speed, vertical);
        for (const auto &v : o) std::printf(" %016" PRIx64, nk::bits(v.v));
        std::printf(" %d %d %" PRIu64 " %" PRIu64 "\n", err, flags, pow_calls, sin_calls);
    }
}
