// Isolated allocation counts for the unmodified nk_tick.hpp, no engine or aircraft data.
// Build: g++ -std=c++17 -O2 -fno-fast-math -ffp-contract=off -I <repo>/research/native-kernel/src this.cpp -o probe
#include "nk_tick.hpp"
#include "nk_prop.hpp"
#include <array>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <new>

static bool measuring;
static size_t allocations, bytes;
void *operator new(size_t n) {
    if (measuring) { ++allocations; bytes += n; }
    if (auto p = std::malloc(n ? n : 1)) return p;
    throw std::bad_alloc();
}
void operator delete(void *p) noexcept { std::free(p); }
void operator delete(void *p, size_t) noexcept { std::free(p); }

using nk::R;
constexpr int n = 32, rpm = 13, fuel = 14, line = 30, mode = 31;
constexpr double dt = 1.0 / 240.0;
enum class Case { Plain, Eight, DeclaredClear, DeclaredEight, DeclaredCross, GlowClear, GlowCross };
struct Row { size_t alloc, bytes; int rhs, events; bool ok; double event_t; uint64_t hash; };

static Row observe(Case test) {
    const bool glow = test == Case::GlowClear || test == Case::GlowCross;
    std::array<R,n> initial{}, first{};
    initial[nk::kTickAtt] = 1.0;
    initial[rpm] = test == Case::DeclaredCross ? dt * 0.5 : 3500.0;
    initial[line] = 0.125;
    initial[fuel] = test == Case::GlowCross ? initial[line].v + dt * 0.5 : 1.0;
    initial[mode] = 1.0;
    std::vector<R> output(n), dates;
    std::vector<nk::ResourceReport> reports;
    nk::TickRk4Scratch scratch;
    scratch.size(n);
    std::vector<nk::ResourceEvent> surfaces(3);
    surfaces[0].surface = nk::ResourceSurface::RotorStop; surfaces[0].id = "rotor";
    surfaces[1].surface = nk::ResourceSurface::MainTankUnusable; surfaces[1].id = "tank"; surfaces[1].has_enabled = true;
    surfaces[2].surface = nk::ResourceSurface::FeedLineEmpty; surfaces[2].id = "line"; surfaces[2].has_enabled = true;
    const nk::ResourceGlowLayout layout{};
    int rhs = 0;
    auto f = [&](const R *s, R, R *out) {
        ++rhs;
        for (int i = 0; i < n; ++i) out[i] = 0.0;
        out[0] = 1.0;
        out[rpm] = s[rpm].v != 0.0 ? -1.0 : 0.0; // Continue smoothly on negative locator trials.
        out[fuel] = glow && s[mode].v == 1.0 ? -1.0 : 0.0;
        return true;
    };
    auto project = [](const R *in, int count, int index, std::vector<R> &out) {
        out.assign(in, in + count); out[index] = 0.0; return true;
    };
    auto transition = [](const nk::ResourceEvent &event, const std::vector<R> &in, R, std::vector<R> &out, int &detail) {
        if (event.surface != nk::ResourceSurface::MainTankUnusable) return false;
        out = in; out[fuel] = out[line]; out[mode] = 2.0; detail = 0; return true;
    };
    f(initial.data(), 0.0, first.data());
    rhs = 0; // k1 is supplied by the caller.
    bool accepted = true;
    allocations = bytes = 0;
    measuring = true;
    nk::TickStatus status;
    if (test == Case::Plain) {
        status = nk::tick_rk4_step_at(initial.data(), n, 0.0, dt, f, first.data(), output.data(), scratch);
    } else if (test == Case::Eight) {
        status = nk::tick_rk4_substeps(initial.data(), n, 0.0, dt, f, first.data(), 8, output, scratch);
    } else if (glow) {
        status = nk::resource_advance(initial.data(), n, 0.0, dt, f, first.data(), surfaces, layout,
                                      transition, accepted, output, reports, scratch);
    } else {
        int pieces = test == Case::DeclaredEight ? 8 : 1;
        status = nk::tick_locate_substeps(initial.data(), n, 0.0, dt, f, first.data(), rpm, project,
                                          true, pieces, accepted, output, dates, scratch);
    }
    measuring = false;
    const double at = !dates.empty() ? dates.front().v : (!reports.empty() ? reports.front().time_s.v : -1.0);
    const int events = int(dates.size() + reports.size());
    const bool crossing = test == Case::DeclaredCross || test == Case::GlowCross;
    const bool correct = status == nk::TickStatus::Ok && accepted && events == int(crossing) &&
        std::abs(output[0].v - dt) < 2e-12 && (!crossing || std::abs(at - 0.5 * dt) < 2e-12);
    uint64_t hash = 14695981039346656037ULL;
    for (R value : output) {
        uint64_t bits;
        std::memcpy(&bits, &value.v, sizeof bits);
        for (unsigned i=0; i<8; ++i) { hash ^= (bits >> (8*i)) & 255; hash *= 1099511628211ULL; }
    }
    return {allocations, bytes, rhs, events, correct, at, hash};
}

static bool compare_torque_rounding() {
    nk::PropModel prop;
    prop.ct = {0.0, 0.13, 0.5, 0.09, 1.2, 0.00};
    prop.cp = {0.0, 0.075, 0.5, 0.065, 1.2, 0.006};
    uint32_t state = 9517531;
    auto draw = [&]() { state = state * 1664525u + 1013904223u; return state / 4294967296.0; };
    int different = 0;
    double blade_example = 0, shaft_example = 0;
    for (int i = 0; i < 4096; ++i) {
        prop.diameter = 0.23 + draw() * 0.23;
        const R speed[3] = {5.0 + draw() * 30.0, 0.0, 0.0};
        const R rotation = 2500.0 + draw() * 15500.0;
        const R density = 0.8 + draw() * 0.55;
        const R blade = nk::prop_thrust_torque(speed, rotation, prop, density)[1];
        const R shaft = nk::prop_torque(rotation, speed[0], prop, density);
        if (std::memcmp(&blade.v, &shaft.v, sizeof(double)) != 0) {
            if (different == 0) { blade_example = blade.v; shaft_example = shaft.v; }
            ++different;
        }
    }
    std::printf("blade_vs_shaft_different_bits=%d/4096 first=%a,%a\n", different, blade_example, shaft_example);
    return different > 0;
}

int main() {
    const char *names[] = {"rk4_one","rk4_eight","declared_clear","declared_clear_eight","declared_cross","resource_clear","resource_cross"};
    bool passed = true;
    for (int i=0; i<7; ++i) {
        const auto a = observe(static_cast<Case>(i)), b = observe(static_cast<Case>(i));
        const bool ok = a.ok && b.ok && a.alloc == b.alloc && a.bytes == b.bytes && a.rhs == b.rhs &&
            a.events == b.events && a.event_t == b.event_t && a.hash == b.hash;
        passed = passed && ok;
        std::printf("%s alloc=%zu bytes=%zu rhs_after_k1=%d events=%d event_t=%.17g hash=%016llx pass=%d\n",
            names[i],a.alloc,a.bytes,a.rhs,a.events,a.event_t,(unsigned long long)a.hash,int(ok));
    }
    return !passed || !compare_torque_rounding();
}
