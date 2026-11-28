#include "nk_stage.hpp"

#include <cinttypes>
#include <cstdio>
#include <cstdlib>
#include <new>

static std::uint64_t allocations = 0, bytes = 0;
void *operator new(std::size_t size) {
    ++allocations; bytes += size;
    if (void *ret = std::malloc(size ? size : 1)) return ret;
    throw std::bad_alloc();
}
void operator delete(void *p) noexcept { std::free(p); }
void operator delete(void *p, std::size_t) noexcept { std::free(p); }

static nk::StageModel model(int wheels) {
    nk::StageModel m;
    m.layout.wheel_index = 1; m.layout.wheel_count = wheels;
    m.aero.S = 0.5; m.aero.b = 1.5; m.aero.c = 0.3; m.aero.CLa = 5; m.aero.CD0 = 0.03;
    m.aero.k_induced = 0.06; m.aero.ys = {-0.4, 0.4};
    m.aero.a1 = m.aero.n1 = 0.20; m.aero.a2 = m.aero.n2 = 0.40;
    m.aero.b1 = 0.20; m.aero.b2 = 0.40; m.aero.attached_limit = 0.12;
    m.aero.tail_local_limit = 0.20; m.aero.tail_stall_end = 0.4;
    m.ground.gear.empty = wheels == 0; m.ground.gear.contacts.resize(wheels);
    m.ground.surfaces.valid = true; m.ground.lake_valid = true;
    m.density = 1.225; m.gravity = 9.81; m.liquid.ready = true; m.liquid.capacity_kg = 0.5;
    m.liquid.mass.reference_mass_kg = 2.0;
    m.liquid.mass.reference_inertia = {0.3,0.5,0.8,0,0,0};
    nk::LiquidMassResource r;
    r.reference_kg = 0.3; r.capacity_kg = 0.5; r.center = {0.02, 0.0, -0.08};
    m.liquid.mass.resources.push_back(r);
    auto &t = m.liquid.turbine;
    t.max_rpm = 100000; t.installed_factor = 0.9; t.governor_tau = 0.25;
    t.throttle_map = {0,10000,1,100000};
    t.accel_limit = t.decel_limit = {0,1000,100000,10000};
    t.static_thrust = {0,0,100000,40}; t.mass_flow = {0,0.01,100000,1.0};
    t.fuel_flow = {0,0.001,100000,0.01};
    return m;
}

static void word(nk::R x) { std::printf(" %016" PRIx64, nk::bits(x.v)); }

int main() {
    for (int wheels : {0, 3}) {
        nk::StageModel m = model(wheels);
        nk::TickContext tick;
        tick.ready = tick.power_ready = tick.power_enabled = true;
        tick.throttle = 0.5; tick.wheel_speeds.resize(wheels); tick.aux.resize(4);
        for (double fuel : {0.0, 0.2, 0.51}) for (double rpm : {0.0, 40000.0, 100001.0}) {
            nk::R s[13] = {};
            s[6] = 1.0; s[2] = -30.0; s[3] = 15.0; s[5] = -0.2;
            std::vector<nk::R> v(wheels + 3);
            v[0] = rpm; v[1 + wheels] = fuel; v[2 + wheels] = 1.0;
            const auto warm = nk::stage_evaluate(s,v.data(),v.size(),0.0,m,tick);
            allocations = bytes = 0;
            const auto out = nk::stage_evaluate(s,v.data(),v.size(),0.0,m,tick);
            const auto count = allocations, size = bytes;
            std::printf("%d %g %g %d %zu %d", wheels,fuel,rpm,out.shaped,out.derivative.size(),out.has_body_derivative);
            if (out.shaped) {
                for (auto x:out.loads) word(x);
                for (auto x:out.derivative) word(x);
                for (auto x:out.body_derivative) word(x);
                for (auto x:out.rotor) word(x);
            }
            std::printf(" %" PRIu64 " %" PRIu64 "\n", count, size);
            if (out.shaped != (rpm <= 100000 && fuel <= 0.5)) return 1;
        }
    }
}
