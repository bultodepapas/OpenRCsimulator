#include "nk_stage.hpp"

#include <cerrno>
#include <cfenv>
#include <cinttypes>
#include <cstdio>

static std::uint64_t power_calls;
extern "C" double __real_pow(double, double);
extern "C" double __wrap_pow(double x, double y) {
    ++power_calls;
    return __real_pow(x, y);
}

static nk::StageModel fixture(bool spatial, int wake_mode, bool tilted) {
    nk::StageModel m;
    auto &a = m.aero;
    a.S = 0.5; a.b = 1.5; a.c = 0.3;
    a.a1 = a.n1 = 0.19; a.a2 = a.n2 = 0.48;
    a.b1 = 0.15; a.b2 = 0.40; a.CD0 = 0.03; a.CLa = 5.0; a.CL0 = 0.12;
    a.strip_slope = 5.1; a.k_induced = 0.06; a.CD90 = 1.55;
    a.attached_limit = 0.12; a.tail_stall_end = 0.7; a.tail_local_limit = 0.2;
    a.vertical.area = 0.05; a.vertical.lift_slope = 3.2; a.vertical.position[0] = 0.7;
    a.horizontal = a.vertical; a.horizontal.present = true;
    a.ys = {-0.65, -0.39, -0.13, 0.13, 0.39, 0.65};
    auto &p = m.prop;
    p.diameter = 0.32; p.rotor_inertia = 0.0004;
    p.offset[0] = -0.2; p.offset[1] = 0.025; p.offset[2] = 0.035;
    p.ct = {0,0.12, 0.5,0.11, 0.9,0.06, 1.3,-0.03};
    p.cp = {0,0.082, 0.5,0.070, 0.9,0.040, 1.3,0.005};
    p.has_axis = tilted;
    if (tilted) {
        p.axis[0] = std::cos(0.08); p.axis[2] = std::sin(0.08);
        p.normal_force = {0,0.01, 1,0.02}; p.pfactor_moment = {0,0.02, 1,0.03};
    }
    m.has_weather = true; m.spatial_weather = spatial;
    m.spatial.half_extent_north_m = m.spatial.half_extent_east_m = 1200.0;
    m.spatial.max_height_agl_m = 500; m.spatial.time_horizon_s = 120;
    m.spatial.free_air_ned = {2.0, 1.0, 0.0};
    m.wake.enabled = wake_mode > 0; m.wake.transport = wake_mode == 2;
    if (m.wake.enabled) {
        m.wake.wash_factor[0] = 1.0; m.wake.wash_factor[1] = 0.8;
        m.wake.swirl_factor = 0.1; m.wake.reverse_fade[0] = 0.1;
        m.wake.reverse_fade[1] = 0.9; m.wake.transport_speed_floor = 1.0;
        nk::WakePiece piece;
        piece.area = 0.065; piece.root[0] = 0.7; piece.span_dir[1] = 1;
        piece.span = 0.30; piece.chords[0] = 0.25; piece.chords[1] = 0.15;
        m.wake.pieces.push_back(piece);
    }
    m.layout.rotor_index = m.layout.wheel_index = m.wake.transport ? 1 : 0;
    m.layout.downwash = 4;
    return m;
}

static void word(nk::R x) { std::printf(" %016" PRIx64, nk::bits(x.v)); }

int main() {
    for (int spatial : {0, 1}) for (int wake : {0, 1, 2}) for (int tilted : {0, 1}) {
        auto m = fixture(spatial, wake, tilted);
        nk::TickContext ctx;
        ctx.ready = true; ctx.aux = {0,0,0,0,0.15};
        ctx.deflections.rudder = 0.035; ctx.deflections.elevator = 0.05;
        for (double rpm : {0.0, 0.5, 1.0, 4450.0, 10400.0})
        for (double u : {-13.0, 0.0, 11.0, 34.0})
        for (int domain : {0,1}) {
            ctx.aux[0] = rpm;
            nk::R state[13] = {};
            state[0] = domain ? 1201:0; state[2] = -25; state[3] = u; state[4] = 1.1; state[5] = -0.3;
            state[6] = 1; state[10] = 0.2; state[11] = 0.3; state[12] = -0.15;
            nk::R values[1] = {2.5};
            std::feclearexcept(FE_ALL_EXCEPT); errno = 0; power_calls = 0;
            const auto out = nk::stage_evaluate(state, values, m.layout.wheel_index, 1.25, m, ctx);
            const int flags = std::fetestexcept(FE_ALL_EXCEPT), error = errno;
            bool finite = out.shaped;
            for (auto w: out.loads) finite = finite && nk::is_finite(w);
            for (auto w: out.derivative) finite = finite && nk::is_finite(w);
            std::printf("%d %d %d %g %g %d %d %d %zu %d %d %d %d",
                spatial, wake, tilted, rpm, u, domain, out.shaped, finite, out.derivative.size(),
                out.has_body_derivative, out.has_preview, flags, error);
            for (auto w: out.loads) word(w);
            for (auto w: out.rotor) word(w);
            for (auto w: out.derivative) word(w);
            std::printf(" %" PRIu64 "\n", power_calls);
        }
    }
}
