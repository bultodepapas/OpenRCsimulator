// Component reproduction of nk_kernel.cpp set_tick_context's two ground operations.
// Uses production types, retractable_pose, and read-only wheel compression queries.
#include "nk_retractable.hpp"
#include <array>
#include <cstdio>
#include <cstdlib>
#include <cstring>

struct CopyCounter {
    const void *source = nullptr;
    size_t size = 0, calls = 0;
};
static CopyCounter tracked[6];
static bool counting;
static void observe(const void *source, size_t n) {
    if (counting) for (auto &block : tracked)
        if (n && block.source == source && block.size == n) ++block.calls;
}
extern "C" void *__real_memmove(void *, const void *, size_t);
extern "C" void *__real_memcpy(void *, const void *, size_t);
extern "C" void *__wrap_memmove(void *to, const void *from, size_t n) {
    observe(from,n); return __real_memmove(to,from,n);
}
extern "C" void *__wrap_memcpy(void *to, const void *from, size_t n) {
    observe(from,n); return __real_memcpy(to,from,n);
}
template<class T> static void track(int i, const std::vector<T> &v) {
    tracked[i] = {v.data(), v.size()*sizeof(T), 0};
}
static void start(const nk::GroundContext &base) {
    track(0, base.gear.contacts); track(1, base.surfaces.values);
    track(2, base.lake.shoreline); track(3, base.lake.bank);
    track(4, base.lake.profile_inset); track(5, base.lake.profile_depth);
    counting = true;
}
static std::array<size_t,2> stop() {
    counting = false;
    size_t bytes = 0;
    for (int i = 1; i < 6; ++i) bytes += tracked[i].calls * tracked[i].size;
    return {tracked[0].calls * tracked[0].size, bytes};
}
static bool set(bool reused, const nk::GroundContext &base, const nk::RetractableModel &model,
                double extension, nk::GroundContext &out) {
    if (!model.enabled) return true;
    if (!nk::retractable_valid_fraction(extension)) return false;
    if (!reused) out = base;
    return nk::retractable_pose(base.gear, model, extension, out.gear);
}
template<class T> static bool equal(const std::vector<T> &a, const std::vector<T> &b) {
    return a.size() == b.size() && (a.empty() || std::memcmp(a.data(),b.data(),a.size()*sizeof(T)) == 0);
}
static bool equal_outputs(const nk::GroundContext &a,const nk::GroundContext &b) {
    if (!(equal(a.gear.contacts,b.gear.contacts) && equal(a.surfaces.values,b.surfaces.values) &&
          equal(a.lake.shoreline,b.lake.shoreline) && equal(a.lake.bank,b.lake.bank) &&
          equal(a.lake.profile_inset,b.lake.profile_inset) && equal(a.lake.profile_depth,b.lake.profile_depth) &&
          a.lake.present == b.lake.present && a.lake_valid == b.lake_valid &&
          a.lake.water_level_down == b.lake.water_level_down &&
          std::memcmp(a.lake.bank_aabb,b.lake.bank_aabb,sizeof(a.lake.bank_aabb)) == 0)) return false;
    nk::R state[13] = {}; state[6] = 1; state[2] = -0.25;
    std::vector<nk::R> c0,c1;
    return nk::wheels_compressions(state,a,c0) == nk::wheels_compressions(state,b,c1) && equal(c0,c1);
}
int main(int argc, char **args) {
    if (argc != 6) return 1;
    int sizes[5]; for (int i=0;i<5;++i) sizes[i] = std::atoi(args[i+1]);
    // Synthetic values with source-derived stock dimensions. Epoch 2 changes surface properties.
    for (int epoch : {0,1,2}) {
        nk::GroundContext base;
        nk::RetractableModel model;
        model.enabled = true;
        base.gear.empty = false; base.gear.contacts.resize(3); model.paths.resize(3);
        for (int i=0;i<3;++i) {
            base.gear.contacts[i].position[2] = 0.35 + 0.02*i;
            base.gear.contacts[i].stiffness = 2500.0;
            model.paths[i] = {0.0, 0.12*i, 0.01, 0.0, 0.24*i, 0.35+0.02*i};
        }
        base.surfaces.values.resize(sizes[0]);
        for(int i=0;i<sizes[0];i+=6) {
            auto *r = base.surfaces.values.data()+i;
            r[0]=-10-i; r[1]=10+i; r[2]=-10-i; r[3]=10+i;
            r[4]=0.6; r[5]=2.5+0.25*epoch;
        }
        auto &surface=base.surfaces.values;
        auto *outside=surface.data()+surface.size()-6;
        outside[0]=outside[2]=-nk::kInf; outside[1]=outside[3]=nk::kInf;
        if (!nk::surface_table_is_valid(surface)) return 2;
        if (epoch) {
            auto &lake=base.lake;
            lake.present=true;
            lake.shoreline.resize(sizes[1]); lake.bank.resize(sizes[2]);
            lake.profile_inset.resize(sizes[3]); lake.profile_depth.resize(sizes[4]);
            for (size_t i=0; i<lake.shoreline.size()/2; ++i) {
                const double phase = 2*nk::kPi*i/(lake.shoreline.size()/2);
                lake.shoreline[2*i]=100+30*std::cos(phase);
                lake.shoreline[2*i+1]=100+30*std::sin(phase);
                lake.bank[2*i]=100+35*std::cos(phase);
                lake.bank[2*i+1]=100+35*std::sin(phase);
            }
            lake.bank_aabb[0]=lake.bank_aabb[2]=65; lake.bank_aabb[1]=lake.bank_aabb[3]=135;
            for (int i=0;i<sizes[3];++i) {lake.profile_inset[i]=0.5*i; lake.profile_depth[i]=i*0.1;}
            lake.water_level_down=0.4+0.1*epoch;
        }
        nk::GroundContext current, candidate;
        candidate.lake = base.lake; candidate.surfaces = base.surfaces; candidate.lake_valid = base.lake_valid;
        if (!set(false,base,model,1.0,current) || !set(true,base,model,1.0,candidate)) return 3;
        for (int retractable : {1,0}) {
            model.enabled=retractable;
            int accepted=0;
            size_t gear0=0,gear1=0,terrain0=0,terrain1=0;
            for (int i=0;i<240;++i) {
                double extension=std::array<double,6>{1.0,0.5,0.25,0.0,1.0,-0.01}[i%6];
                start(base); bool ok0=set(false,base,model,extension,current); auto copies0=stop();
                start(base); bool ok1=set(true,base,model,extension,candidate); auto copies1=stop();
                if (ok0!=ok1 || !equal_outputs(current,candidate)) return 4;
                accepted+=ok0;
                gear0+=copies0[0]; terrain0+=copies0[1]; gear1+=copies1[0]; terrain1+=copies1[1];
            }
            size_t terrain_words=sizes[0]+(epoch ? sizes[1]+sizes[2]+sizes[3]+sizes[4]:0);
            size_t per_gear=base.gear.contacts.size()*sizeof(nk::WheelContact);
            if (accepted != (retractable ? 200:240)) return 5;
            if (gear0!=size_t(retractable*accepted)*2*per_gear || gear1!=size_t(retractable*accepted)*per_gear ||
                terrain0!=size_t(retractable*accepted)*terrain_words*8 || terrain1) return 6;
            std::printf("%d %d %d %zu %zu %zu %zu\n",epoch,retractable,accepted,gear0,gear1,terrain0,terrain1);
        }
    }
}
