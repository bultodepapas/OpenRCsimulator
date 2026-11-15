"""Portable source-bound controls for 0018; no Godot or Metal execution."""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    sys.modules[name] = result
    spec.loader.exec_module(result)
    return result


ENGINE = module("rt_scene_engine", HERE / "engine.py")
CHECK = module("rt_scene_checks", HERE / "test_engine_patch.py")
PREVIOUS = module("rt_scene_submission", HERE / "test_engine_present_submission_patch.py")
PATCH = HERE / "patches/0018-metal-rt-scene-inputs.patch"
PATCHES = PREVIOUS.PATCHES + (PATCH,)
HASHES = PREVIOUS.HASHES + (PREVIOUS.PATCH_HASH,)
PATCH_HASH = "8339b8978c21a1133b8b6e144de0dc182a9c29a7cb39677fa628b3105dee5c82"

GEOMETRY = r'''
#define OVERFLOW 3 // Apple SDK math.h defines this before Godot headers.
#include <servers/rendering/storage/metalfx_rt_geometry.h>
#include <vector>
#include <limits>
#include <cstring>
#define CHECK(x) do { if (!(x)) return __LINE__; } while (0)
using namespace OpenRCRTGeometry;
int main() {
    // Godot stores the float3 block first, followed by normal bytes.
    const float positions[] = {0,0,0, 1,0,0, 0,1,0, 99,98,97};
    const uint16_t index16[] = {2,0,1};
    Input input{reinterpret_cast<const uint8_t *>(positions),sizeof(positions),3,
        reinterpret_cast<const uint8_t *>(index16),sizeof(index16),3,2};
    uint64_t bytes=0;
    CHECK(validate(input,bytes)==Result::OK && bytes==36);
    std::vector<uint8_t> output(bytes);
    CHECK(expand(input,output.data(),output.size()));
    float first[3]; std::memcpy(first,output.data(),12);
    CHECK(first[0]==0 && first[1]==1 && first[2]==0);
    float third[3]; std::memcpy(third,output.data()+24,12);
    CHECK(third[0]==1 && third[1]==0 && third[2]==0); // winding preserved
    CHECK(!expand(input,output.data(),output.size()-1));
    uint16_t bad16[]={2,0,3}; input.indices=reinterpret_cast<const uint8_t *>(bad16);
    CHECK(validate(input,bytes)==Result::INDEX_OUT_OF_RANGE);
    input.indices=reinterpret_cast<const uint8_t *>(index16); input.index_bytes=5;
    CHECK(validate(input,bytes)==Result::GEOMETRY_OVERFLOW);
    input.index_bytes=sizeof(index16); input.index_count=2;
    CHECK(validate(input,bytes)==Result::INVALID_TOPOLOGY);
    input.index_count=3; input.index_width=1;
    CHECK(validate(input,bytes)==Result::INVALID_ARGUMENT);
    input.index_width=2; input.vertex_count=UINT32_MAX;
    CHECK(validate(input,bytes)==Result::GEOMETRY_OVERFLOW);
    float nonfinite[]={0,0,0, 1,0,0, 0,std::numeric_limits<float>::infinity(),0};
    input.positions=reinterpret_cast<const uint8_t *>(nonfinite); input.position_bytes=sizeof(nonfinite); input.vertex_count=3;
    CHECK(validate(input,bytes)==Result::NONFINITE_POSITION);
    input.positions=reinterpret_cast<const uint8_t *>(positions); input.position_bytes=sizeof(positions);
    input.indices=nullptr; input.index_bytes=0; input.index_count=0; input.index_width=0;
    CHECK(validate(input,bytes)==Result::OK && bytes==36);
    // Exercise the 65536/65537 boundary and uint32 indices without giant fixtures.
    std::vector<float> large(65537*3,0.0f);
    uint16_t top16[]={65535,0,1};
    input={reinterpret_cast<const uint8_t *>(large.data()),large.size()*sizeof(float),65536,
        reinterpret_cast<const uint8_t *>(top16),sizeof(top16),3,2};
    CHECK(validate(input,bytes)==Result::OK);
    uint32_t top32[]={65536,0,1}; input.vertex_count=65537;
    input.indices=reinterpret_cast<const uint8_t *>(top32); input.index_width=4; input.index_bytes=sizeof(top32);
    CHECK(validate(input,bytes)==Result::OK && bytes==36);
    top32[0]=65537; CHECK(validate(input,bytes)==Result::INDEX_OUT_OF_RANGE);
    InputBudget budget{0,64}; CHECK(budget.consume(48)); CHECK(!budget.consume(17));
    CHECK(budget.spent==48 && budget.consume(16) && !budget.consume(1));
    return 0;
}
'''

REENTRY = r'''
@GUARD@;
static int entered=0;
int probe(bool &active, bool simulate_callback, bool early_return=false) {
    RTProbeActiveGuard guard(active);
    if (!guard.acquired) return 1; // probe_busy, before any RD access
    ++entered;
    if (simulate_callback) {
        if (probe(active, false) != 1 || !active) return 2;
    }
    if (early_return) return 3;
    return 0;
}
int main() {
    bool active=false;
    if (probe(active,true)!=0 || active || entered!=1) return 10;
    if (probe(active,false,true)!=3 || active || entered!=2) return 11;
    if (probe(active,false)!=0 || active || entered!=3) return 12;
    return 0;
}
'''

UPLOAD = r'''
#include <cstdint>
#include <cstring>
#include <vector>
#define CHECK(x) do { if (!(x)) return __LINE__; } while (0)
template<class T> struct Span { const T *p; uint64_t n; uint64_t size() const{return n;} const T *ptr() const{return p;} };
struct RID { int id=0; bool is_valid() const{return id!=0;} };
namespace RDD {
enum { BUFFER_USAGE_TRANSFER_FROM_BIT=1, BUFFER_USAGE_TRANSFER_TO_BIT=2, BUFFER_USAGE_VERTEX_BIT=4,
       BUFFER_USAGE_ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_BIT=8, MEMORY_ALLOCATION_TYPE_GPU_MAPPABLE=7 };
struct BufferID { int id=0; explicit operator bool()const{return id!=0;} };
}
struct Driver {
    bool feature=true, fail_allocate=false, fail_map=false; int allocations=0, frees=0, unmaps=0, type=0; unsigned usage=0;
    std::vector<uint8_t> bytes;
    bool has_feature(int)const{return feature;}
    RDD::BufferID buffer_create(unsigned n,unsigned u,int t,uint64_t) { if(fail_allocate)return {}; ++allocations; usage=u;type=t;bytes.resize(n);return {1}; }
    uint8_t *buffer_map(RDD::BufferID){return fail_map?nullptr:bytes.data();}
    void buffer_unmap(RDD::BufferID){++unmaps;}
    void buffer_free(RDD::BufferID){++frees;}
};
struct RenderingDevice {
    enum { SUPPORTS_METAL_TRIANGLE_QUERY=1, SUPPORTS_GPU_MAPPABLE_BUFFER=2 };
    struct Buffer { RDD::BufferID driver_id; unsigned size=0,usage=0; int alloc_type=0; };
    struct Memory { int bytes=0; void add(int n){bytes+=n;} void sub(int n){bytes-=n;} } buffer_memory;
    struct Owner { bool fail=false; int count=0; RID make_rid(const Buffer&){if(fail)return {}; ++count;return {count};} } vertex_buffer_owner;
    Driver *driver=nullptr; uint64_t frames_drawn=0; bool query=true;
    bool has_feature(int)const{return query;}
    RID vertex_buffer_create_metalfx_rt_input(uint32_t,Span<uint8_t>);
};
@UPLOAD@
int main(){
    Driver d; RenderingDevice rd; rd.driver=&d; const uint8_t value[]={1,2,3,4}; Span<uint8_t> span{value,4};
    rd.query=false; CHECK(!rd.vertex_buffer_create_metalfx_rt_input(4,span).is_valid() && d.allocations==0);
    rd.query=true; d.fail_allocate=true; CHECK(!rd.vertex_buffer_create_metalfx_rt_input(4,span).is_valid());
    d.fail_allocate=false; d.fail_map=true; CHECK(!rd.vertex_buffer_create_metalfx_rt_input(4,span).is_valid());
    CHECK(d.frees==1 && rd.vertex_buffer_owner.count==0 && rd.buffer_memory.bytes==0);
    d.fail_map=false; auto id=rd.vertex_buffer_create_metalfx_rt_input(4,span);
    CHECK(id.is_valid() && d.bytes==std::vector<uint8_t>({1,2,3,4}) && d.unmaps==1);
    CHECK(d.type==RDD::MEMORY_ALLOCATION_TYPE_GPU_MAPPABLE && (d.usage&8) && rd.buffer_memory.bytes==4);
    rd.vertex_buffer_owner.fail=true; CHECK(!rd.vertex_buffer_create_metalfx_rt_input(4,span).is_valid());
    CHECK(rd.buffer_memory.bytes==4 && d.frees==2);
    return 0;
}
'''

IDENTITY = r'''
#include <servers/rendering/storage/real_gpu_completion.h>
#include <atomic>
#include <memory>
#define CHECK(x) do { if (!(x)) return __LINE__; } while (0)
#define memdelete(p) delete (p)
struct RenderingDeviceDriver {
    struct CommandBufferID { uint64_t id=0; };
    bool register_ok=true; int registrations=0;
    uint64_t metalfx_rt_command_buffer_identity(CommandBufferID id){return id.id;}
    bool real_gpu_completion_register(CommandBufferID,const std::shared_ptr<RealGPUCompletion>&,const RealGPUCompletion::Reservation&){++registrations;return register_ok;}
};
struct RTProbeIdentity { std::shared_ptr<RealGPUCompletion> state; RealGPUCompletion::Reservation reservation; std::atomic<uint64_t> first_command{0}; };
struct RTProbeObservation { std::shared_ptr<RTProbeIdentity> identity; };
@MARK@
@OBSERVE@
static std::shared_ptr<RTProbeIdentity> identity() {
    auto i=std::make_shared<RTProbeIdentity>(); i->state=std::make_shared<RealGPUCompletion>();
    i->state->reset(true,10); i->reservation=i->state->reserve(1,10.1); return i;
}
int main(){
    RenderingDeviceDriver driver; auto a=identity();
    rt_probe_mark_command(&driver,{42},new RTProbeObservation{a});
    rt_probe_observe(&driver,{42},new RTProbeObservation{a}); CHECK(driver.registrations==1 && !a->state->snapshot(10.2).failed);
    auto b=identity(); rt_probe_mark_command(&driver,{42},new RTProbeObservation{b});
    rt_probe_observe(&driver,{43},new RTProbeObservation{b}); CHECK(driver.registrations==1 && b->state->snapshot(10.2).failed);
    auto c=identity(); rt_probe_mark_command(&driver,{0},new RTProbeObservation{c});
    rt_probe_observe(&driver,{0},new RTProbeObservation{c}); CHECK(driver.registrations==1 && c->state->snapshot(10.2).failed);
    driver.register_ok=false; auto d=identity(); rt_probe_mark_command(&driver,{9},new RTProbeObservation{d});
    rt_probe_observe(&driver,{9},new RTProbeObservation{d}); CHECK(driver.registrations==2 && d->state->snapshot(10.2).failed);
    return 0;
}
'''

POLL = r'''
#include <servers/rendering/storage/real_gpu_completion.h>
#include <any>
#include <cmath>
#include <map>
#include <memory>
#include <string>
#include <vector>
#define CHECK(x) do { if (!(x)) return __LINE__; } while (0)
struct Array;
struct Dictionary {
    using Map=std::map<std::string,std::any>;
    std::shared_ptr<Map> data=std::make_shared<Map>();
    struct Value {
        std::any *value;
        Value& operator=(const char *v){*value=std::string(v);return *this;}
        template<class T> Value& operator=(const T &v){*value=v;return *this;}
        template<class T> operator T()const{return std::any_cast<T>(*value);}
    };
    Value operator[](const char *key)const{return {&(*data)[key]};}
    template<class T> T get(const char *key)const{return std::any_cast<T>(data->at(key));}
};
struct Array {
    std::vector<Dictionary> values;
    int64_t size()const{return int64_t(values.size());}
    Dictionary operator[](int64_t i)const{return values[size_t(i)];}
};
namespace Math { bool is_finite(double v){return std::isfinite(v);} }
struct RD {
    static RD *current; double now=100.4;
    static RD *get_singleton(){return current;}
    double real_gpu_completion_now()const{return now;}
};
RD *RD::current=nullptr;
struct RendererSceneCull {
    struct RTProbePending { std::shared_ptr<RealGPUCompletion> completion; Dictionary result; };
    std::unique_ptr<RTProbePending> rt_probe_pending;
    Dictionary scenario_poll_metalfx_rt_probe();
};
@POLL@
static RealGPUCompletion::Reservation prepare(RendererSceneCull &c) {
    c.rt_probe_pending=std::make_unique<RendererSceneCull::RTProbePending>();
    auto &p=*c.rt_probe_pending; p.completion=std::make_shared<RealGPUCompletion>(); p.completion->reset(true,100);
    auto reservation=p.completion->reserve(1,100.1);
    Dictionary entry; entry["triangle_count"]=int64_t(4); Array entries; entries.values.push_back(entry);
    p.result["hit_flag"]=int64_t(1); p.result["instance_id"]=int64_t(1); p.result["primitive"]=int64_t(2);
    p.result["distance"]=double(1); p.result["distance_bits"]=int64_t(0x3f800000);
    p.result["write_marker"]=int64_t(0x52435431); p.result["entries"]=entries;
    p.result["submitted_min_distance"]=double(0.001f); p.result["submitted_max_distance"]=double(10);
    return reservation;
}
static std::string status(const Dictionary &d){return d.get<std::string>("status");}
int main(){
    RD rd; RD::current=&rd; RendererSceneCull c;
    CHECK(status(c.scenario_poll_metalfx_rt_probe())=="no_pending_probe");
    auto r=prepare(c); CHECK(status(c.scenario_poll_metalfx_rt_probe())=="gpu_completion_pending");
    c.rt_probe_pending->completion->complete(r,true,100.2,100.3);
    CHECK(status(c.scenario_poll_metalfx_rt_probe())=="ok" && !c.rt_probe_pending);
    r=prepare(c); c.rt_probe_pending->result["write_marker"]=int64_t(0); c.rt_probe_pending->completion->complete(r,true,100.2,100.3);
    CHECK(status(c.scenario_poll_metalfx_rt_probe())=="invalid_or_missing_gpu_result");
    r=prepare(c); c.rt_probe_pending->result["primitive"]=int64_t(4); c.rt_probe_pending->completion->complete(r,true,100.2,100.3);
    CHECK(status(c.scenario_poll_metalfx_rt_probe())=="invalid_or_missing_gpu_result");
    r=prepare(c); c.rt_probe_pending->result["distance"]=double(0); c.rt_probe_pending->completion->complete(r,true,100.2,100.3);
    CHECK(status(c.scenario_poll_metalfx_rt_probe())=="invalid_or_missing_gpu_result");
    r=prepare(c); c.rt_probe_pending->result["hit_flag"]=int64_t(0); c.rt_probe_pending->result["instance_id"]=int64_t(0);
    c.rt_probe_pending->result["primitive"]=int64_t(0); c.rt_probe_pending->result["distance_bits"]=int64_t(0);
    c.rt_probe_pending->completion->complete(r,true,100.2,100.3); CHECK(status(c.scenario_poll_metalfx_rt_probe())=="ok");
    r=prepare(c); c.rt_probe_pending->result["hit_flag"]=int64_t(0); c.rt_probe_pending->result["instance_id"]=int64_t(1);
    c.rt_probe_pending->completion->complete(r,true,100.2,100.3); CHECK(status(c.scenario_poll_metalfx_rt_probe())=="invalid_or_missing_gpu_result");
    r=prepare(c); c.rt_probe_pending->completion->complete(r,true,100.2,100.3); rd.now=104;
    CHECK(status(c.scenario_poll_metalfx_rt_probe())=="completion_expired" && !c.rt_probe_pending);
    rd.now=100.4; r=prepare(c); c.rt_probe_pending->completion->fail(r,"injected");
    CHECK(status(c.scenario_poll_metalfx_rt_probe())=="gpu_failed" && !c.rt_probe_pending);
    r=prepare(c); rd.now=104; CHECK(status(c.scenario_poll_metalfx_rt_probe())=="gpu_failed" && !c.rt_probe_pending);
    return 0;
}
'''

BUDGET = r'''
#include <atomic>
#include <cstdint>
#include <string>
#include <thread>
#include <vector>
#define CHECK(x) do { if (!(x)) return __LINE__; } while (0)
#define ERR_FAIL_COND_V_MSG(c,v,m) do { if(c) return v; } while(0)
#define ERR_FAIL_NULL_V_MSG(c,v,m) do { if(!(c)) return v; } while(0)
#define memnew(x) new x
namespace MTL {
struct AccelerationStructureDescriptor{};
struct AccelerationStructureSizes { uint64_t accelerationStructureSize=0,buildScratchBufferSize=0; };
struct AccelerationStructure{};
}
struct MDAccelerationStructure {
    enum class Type { BLAS, TLAS };
    MDAccelerationStructure(Type,MTL::AccelerationStructureDescriptor*,MTL::AccelerationStructure*,uint32_t,uint32_t){}
};
namespace RDD { struct AccelerationStructureID { uintptr_t id=0; AccelerationStructureID()=default; template<class T> explicit AccelerationStructureID(T *p):id(reinterpret_cast<uintptr_t>(p)){} }; }
struct OS { static OS object; std::string value="1"; static OS *get_singleton(){return &object;} std::string get_environment(const char*){return value;} };
OS OS::object;
struct Device { MTL::AccelerationStructureSizes sizes; std::atomic<int> allocations{0}; bool fail=false;
    MTL::AccelerationStructureSizes accelerationStructureSizes(MTL::AccelerationStructureDescriptor*){return sizes;}
    MTL::AccelerationStructure *newAccelerationStructure(uint64_t){++allocations;return fail?nullptr:new MTL::AccelerationStructure;}
};
struct RenderingDeviceDriverMetal {
    using AccelerationStructureID=RDD::AccelerationStructureID;
    bool triangle_query_enabled=true; enum { HazardTracking=1 }; int sync_mode=HazardTracking; Device *device=nullptr;
    RDD::AccelerationStructureID _triangle_query_create(MDAccelerationStructure::Type,MTL::AccelerationStructureDescriptor*,uint32_t);
};
@BUDGET@
int main(int argc,char **argv){
    CHECK(argc==2); Device d; RenderingDeviceDriverMetal driver; driver.device=&d; MTL::AccelerationStructureDescriptor desc;
    if(std::string(argv[1])=="off") {
        OS::object.value="0"; d.sizes={300ull*1024*1024,1};
        CHECK(driver._triangle_query_create(MDAccelerationStructure::Type::BLAS,&desc,0).id && d.allocations==1); return 0;
    }
    d.sizes={100ull*1024*1024,50ull*1024*1024};
    CHECK(driver._triangle_query_create(MDAccelerationStructure::Type::BLAS,&desc,0).id && d.allocations==1);
    d.sizes={70ull*1024*1024,40ull*1024*1024};
    CHECK(!driver._triangle_query_create(MDAccelerationStructure::Type::TLAS,&desc,2).id && d.allocations==1);
    d.sizes={UINT64_MAX,1}; CHECK(!driver._triangle_query_create(MDAccelerationStructure::Type::BLAS,&desc,0).id && d.allocations==1);
    d.sizes={10ull*1024*1024,10ull*1024*1024}; d.fail=true;
    CHECK(!driver._triangle_query_create(MDAccelerationStructure::Type::BLAS,&desc,0).id && d.allocations==2);
    d.fail=false; d.sizes={80ull*1024*1024,10ull*1024*1024};
    CHECK(!driver._triangle_query_create(MDAccelerationStructure::Type::BLAS,&desc,0).id && d.allocations==2);
    return 0;
}
'''

SOURCES = r'''
#include <servers/rendering/storage/metalfx_rt_geometry.h>
#include <cassert>
#include <cstdint>
#include <cstring>
#include <memory>
#include <mutex>
#include <unordered_map>
#include <vector>
#define CHECK(x) do { if (!(x)) return __LINE__; } while (0)
#define DEV_ASSERT(x) assert(x)
constexpr int OK=0;
template<class T> struct Vector {
    std::vector<T> v;
    bool is_empty()const{return v.empty();} size_t size()const{return v.size();}
    const T *ptr()const{return v.empty()?nullptr:v.data();} T *ptrw(){return v.data();}
    int resize(size_t n){v.resize(n);return OK;}
};
struct RID { int value=0; bool is_valid()const{return value!=0;} };
struct Mutex { mutable std::recursive_mutex m; };
struct MutexLock { std::lock_guard<std::recursive_mutex> l; explicit MutexLock(const Mutex &m):l(m.m){} };
template<class K,class V> struct HashMap {
    std::unordered_map<K,V> m;
    size_t size()const{return m.size();}
    V *getptr(K k){auto i=m.find(k);return i==m.end()?nullptr:&i->second;}
    void insert(K k,const V &v){m.emplace(k,v);} void erase(K k){m.erase(k);}
};
namespace RSE {
enum { PRIMITIVE_TRIANGLES=1, ARRAY_FORMAT_VERTEX=1, ARRAY_FLAG_USE_2D_VERTICES=2,
       ARRAY_FLAG_COMPRESS_ATTRIBUTES=4, ARRAY_FORMAT_BONES=8, ARRAY_FORMAT_WEIGHTS=16 };
}
namespace RenderingServerTypes {
struct SurfaceData {
    int primitive=RSE::PRIMITIVE_TRIANGLES; uint64_t format=RSE::ARRAY_FORMAT_VERTEX;
    Vector<uint8_t> vertex_data,index_data,skin_data; Vector<int> lods;
    uint32_t vertex_count=0,index_count=0;
};
}
struct RD {
    static RD instance; bool fail=false; int allocations=0, frees=0; std::vector<uint8_t> last;
    static RD *get_singleton(){return &instance;}
    RID vertex_buffer_create_metalfx_rt_input(uint32_t size,const Vector<uint8_t> &v){++allocations;if(fail)return {};last.assign(v.ptr(),v.ptr()+size);return {allocations};}
    void free_rid(RID r){if(r.is_valid())++frees;}
};
RD RD::instance;
struct MeshStorage {
    struct Mesh { struct Surface{}; int blend_shape_count=0; Surface **surfaces=nullptr; uint32_t surface_count=0; };
    struct RTSource { RID vertices; uint32_t vertex_count=0; uint64_t serial=0; };
    struct RTSourceCache { static constexpr uint32_t SOURCE_LIMIT=1024; Mutex mutex; HashMap<const Mesh::Surface*,RTSource> sources; OpenRCRTGeometry::InputBudget budget{0,64*1024*1024}; uint64_t next_serial=1; RID deferred_sources[SOURCE_LIMIT]; uint32_t deferred_count=0; bool probe_active=false, probe_changed=false; };
    std::unique_ptr<RTSourceCache> rt_sources;
    struct Owner { Mesh *mesh=nullptr; Mesh *get_or_null(RID id){return id.value?mesh:nullptr;} } mesh_owner;
    void _rt_source_create(Mesh*,Mesh::Surface*,const RenderingServerTypes::SurfaceData&);
    void _rt_source_invalidate(Mesh::Surface*);
    bool rt_source_get(RID,int,RID&,uint32_t&,uint64_t&);
    uint64_t rt_input_budget_spent()const;
    bool rt_probe_source_begin();
    bool rt_probe_source_changed()const;
    void rt_probe_source_end();
};
@CREATE@
@INVALIDATE@
@GET@
@SPENT@
@BEGIN@
@CHANGED@
@END@
int main(){
    float positions[]={0,0,0, 1,0,0, 0,1,0, 99,98,97}; uint16_t indices[]={2,0,1};
    RenderingServerTypes::SurfaceData data; data.vertex_count=3; data.index_count=3;
    data.vertex_data.v.assign(reinterpret_cast<uint8_t*>(positions),reinterpret_cast<uint8_t*>(positions)+sizeof(positions));
    data.index_data.v.assign(reinterpret_cast<uint8_t*>(indices),reinterpret_cast<uint8_t*>(indices)+sizeof(indices));
    MeshStorage storage; MeshStorage::Mesh::Surface surface; MeshStorage::Mesh::Surface *surfaces[]={&surface};
    MeshStorage::Mesh mesh; mesh.surfaces=surfaces;mesh.surface_count=1;storage.mesh_owner.mesh=&mesh;
    storage._rt_source_create(&mesh,&surface,data); CHECK(RD::instance.allocations==0);
    storage.rt_sources=std::make_unique<MeshStorage::RTSourceCache>();
    storage._rt_source_create(&mesh,&surface,data);
    RID input; uint32_t count=0; uint64_t serial=0;
    CHECK(storage.rt_source_get({1},0,input,count,serial) && count==3 && serial==1);
    float first[3];std::memcpy(first,RD::instance.last.data(),12);CHECK(first[1]==1 && storage.rt_input_budget_spent()==36);
    storage._rt_source_invalidate(&surface); CHECK(!storage.rt_source_get({1},0,input,count,serial));
    CHECK(RD::instance.frees==1 && storage.rt_input_budget_spent()==36);
    storage._rt_source_create(&mesh,&surface,data); CHECK(storage.rt_source_get({1},0,input,count,serial) && serial==2);
    // A synchronous RD flush callback mutates the mesh on the same thread.
    CHECK(storage.rt_probe_source_begin() && !storage.rt_probe_source_changed());
    CHECK(!storage.rt_probe_source_begin());
    storage._rt_source_invalidate(&surface);
    CHECK(!storage.rt_source_get({1},0,input,count,serial));
    CHECK(storage.rt_probe_source_changed() && RD::instance.frees==1);
    int allocations=RD::instance.allocations;
    storage._rt_source_create(&mesh,&surface,data);
    CHECK(RD::instance.allocations==allocations && RD::instance.frees==1);
    // A consumer's BLAS is retired first; only then may its source be freed.
    storage.rt_probe_source_end(); CHECK(RD::instance.frees==2);
    CHECK(storage.rt_probe_source_changed()); // Outside a transaction is not a valid snapshot.
    indices[0]=9;
    std::memcpy(data.index_data.ptrw(),indices,sizeof(indices)); auto spent=storage.rt_input_budget_spent();
    storage._rt_source_create(&mesh,&surface,data); CHECK(!storage.rt_source_get({1},0,input,count,serial) && storage.rt_input_budget_spent()==spent);
    indices[0]=2;std::memcpy(data.index_data.ptrw(),indices,sizeof(indices)); RD::instance.fail=true;
    storage._rt_source_create(&mesh,&surface,data); CHECK(!storage.rt_source_get({1},0,input,count,serial));
    CHECK(storage.rt_input_budget_spent()==spent+36);
    RD::instance.fail=false; data.format|=RSE::ARRAY_FLAG_COMPRESS_ATTRIBUTES; spent=storage.rt_input_budget_spent();
    storage._rt_source_create(&mesh,&surface,data); CHECK(storage.rt_input_budget_spent()==spent);
    CHECK(!storage.rt_source_get({1},-1,input,count,serial) && !storage.rt_source_get({1},1,input,count,serial));
    data.format=RSE::ARRAY_FORMAT_VERTEX;
    std::vector<MeshStorage::Mesh::Surface> many(1025);
    for (int i=0;i<1024;++i) storage._rt_source_create(&mesh,&many[i],data);
    CHECK(storage.rt_sources->sources.size()==1024);
    CHECK(storage.rt_probe_source_begin());
    int before_frees=RD::instance.frees;
    for (int i=0;i<1024;++i) storage._rt_source_invalidate(&many[i]);
    CHECK(storage.rt_sources->deferred_count==1024 && RD::instance.frees==before_frees);
    storage._rt_source_create(&mesh,&many[1024],data); // Cannot refill while deferred.
    CHECK(storage.rt_sources->sources.size()==0 && storage.rt_probe_source_changed());
    storage.rt_probe_source_end();
    CHECK(RD::instance.frees==before_frees+1024 && storage.rt_sources->deferred_count==0);
    return 0;
}
'''


class RTSceneTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not CHECK.ARCHIVE.is_file() or ENGINE.sha256(CHECK.ARCHIVE) != CHECK.ARCHIVE_SHA256:
            raise RuntimeError("Pinned Godot archive unavailable")
        if tuple(ENGINE.sha256(p) for p in PATCHES[:-1]) != HASHES:
            raise RuntimeError("Frozen 1–17 prerequisites differ")
        if ENGINE.sha256(PATCH) != PATCH_HASH:
            raise RuntimeError("0018 candidate differs")
        parent = (ROOT / "tmp/metalfx-rt-scene-port").resolve()
        if not parent.is_relative_to(ROOT.resolve()):
            raise RuntimeError("Control directory escaped the workspace")
        parent.mkdir(parents=True, exist_ok=True)
        cls.tmp = tempfile.TemporaryDirectory(prefix="controls-", dir=parent)
        cls.addClassCleanup(cls.tmp.cleanup)
        cls.base = Path(cls.tmp.name)
        with zipfile.ZipFile(CHECK.ARCHIVE) as archive:
            members = set(archive.namelist())
            for path in ENGINE.patch_paths(PATCHES):
                member = f"{ENGINE.SOURCE_PREFIX}/{path}"
                if member in members:
                    target = cls.base / path
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(archive.read(member))
        ENGINE.git(cls.base, "init", "--quiet")
        for patch in PATCHES:
            ENGINE.git(cls.base, "apply", "--check", "--whitespace=error", str(patch.resolve()))
            ENGINE.git(cls.base, "apply", "--whitespace=error", str(patch.resolve()))
        cls.mesh = (cls.base / "servers/rendering/renderer_rd/storage_rd/mesh_storage.cpp").read_text(encoding="utf-8")
        cls.scene = (cls.base / "servers/rendering/renderer_scene_cull.cpp").read_text(encoding="utf-8")
        cls.device = (cls.base / "servers/rendering/rendering_device.cpp").read_text(encoding="utf-8")
        cls.driver = (cls.base / "drivers/metal/rendering_device_driver_metal.cpp").read_text(encoding="utf-8")

    def compile_run(self, code, name, *args, include=None):
        compiler = os.environ.get("CXX") or shutil.which("g++") or shutil.which("clang++")
        self.assertTrue(compiler, "A C++17 compiler is required")
        source = self.base / (name + ".cpp")
        exe = self.base / (name + (".exe" if os.name == "nt" else ""))
        source.write_text(code, encoding="utf-8")
        cmd = [compiler, "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror", "-pthread",
               "-DFORWARD_RD_ENABLED", "-DMETAL_ENABLED", "-DMACOS_ENABLED"]
        if include:
            cmd += ["-I", str(include)]
        cmd += ["-I", str(self.base), str(source), "-o", str(exe)]
        built = subprocess.run(cmd, capture_output=True, text=True, timeout=90)
        self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
        return subprocess.run([str(exe), *args], capture_output=True, text=True, timeout=30)

    def test_actual_index_expansion_and_bounded_budget(self):
        self.assertEqual(self.compile_run(GEOMETRY, "geometry").returncode, 0)
        header = self.base / "servers/rendering/storage/metalfx_rt_geometry.h"
        mutated = header.read_text(encoding="utf-8").replace("index >= p_input.vertex_count", "false && index >= p_input.vertex_count")
        self.assertNotEqual(mutated, header.read_text(encoding="utf-8"))
        overlay = self.base / "mutation_geometry/servers/rendering/storage"
        overlay.mkdir(parents=True)
        (overlay / header.name).write_text(mutated, encoding="utf-8")
        self.assertNotEqual(self.compile_run(GEOMETRY, "geometry_mutation", include=overlay.parents[2]).returncode, 0)

        # Reintroducing the Apple SDK macro collision must fail compilation.
        collision = header.read_text(encoding="utf-8").replace("GEOMETRY_OVERFLOW", "OVERFLOW")
        self.assertNotEqual(collision, header.read_text(encoding="utf-8"))
        macro_overlay = self.base / "mutation_macro/servers/rendering/storage"
        macro_overlay.mkdir(parents=True)
        (macro_overlay / header.name).write_text(collision, encoding="utf-8")
        with self.assertRaises(AssertionError) as failure:
            self.compile_run(GEOMETRY, "geometry_macro_mutation", include=macro_overlay.parents[2])
        self.assertIn("OVERFLOW", str(failure.exception))

    def test_actual_probe_reentry_guard(self):
        guard = CHECK.cxx_function(self.scene, "struct RTProbeActiveGuard")
        control = REENTRY.replace("@GUARD@", guard)
        self.assertEqual(self.compile_run(control, "rt_reentry").returncode, 0)
        changed = control.replace("acquired(!p_active)", "acquired(true)")
        self.assertNotEqual(changed, control)
        self.assertNotEqual(self.compile_run(changed, "rt_reentry_mutation").returncode, 0)
        probe = CHECK.cxx_function(self.scene, "Dictionary RendererSceneCull::scenario_probe_metalfx_rt(")
        self.assertLess(probe.index("RTProbeActiveGuard active_guard(rt_probe_active)"), probe.index("RD *rd ="))
        self.assertLess(probe.index('result["status"] = "probe_busy"'), probe.index("metalfx_rt_probe_begin()"))

    def test_actual_checked_upload_and_failed_map(self):
        body = CHECK.cxx_function(self.device, "RID RenderingDevice::vertex_buffer_create_metalfx_rt_input(")
        control = UPLOAD.replace("@UPLOAD@", body)
        self.assertEqual(self.compile_run(control, "checked_upload").returncode, 0)
        changed = control.replace("memcpy(mapped, p_data.ptr(), p_size_bytes);", "memset(mapped, 0, p_size_bytes);")
        self.assertNotEqual(changed, control)
        self.assertNotEqual(self.compile_run(changed, "checked_upload_mutation").returncode, 0)

    def test_actual_source_creation_invalidation_and_no_refund(self):
        signatures = {
            "@CREATE@": "void MeshStorage::_rt_source_create(",
            "@INVALIDATE@": "void MeshStorage::_rt_source_invalidate(",
            "@GET@": "bool MeshStorage::rt_source_get(",
            "@SPENT@": "uint64_t MeshStorage::rt_input_budget_spent(",
            "@BEGIN@": "bool MeshStorage::rt_probe_source_begin(",
            "@CHANGED@": "bool MeshStorage::rt_probe_source_changed(",
            "@END@": "void MeshStorage::rt_probe_source_end(",
        }
        control = SOURCES
        for marker, signature in signatures.items():
            control = control.replace(marker, CHECK.cxx_function(self.mesh, signature))
        self.assertEqual(self.compile_run(control, "rt_sources").returncode, 0)
        changed = control.replace("rt_sources->sources.erase(p_surface);", "/* deliberately retain stale source */")
        self.assertNotEqual(changed, control)
        self.assertNotEqual(self.compile_run(changed, "rt_sources_mutation").returncode, 0)
        premature = control.replace("rt_sources->deferred_sources[rt_sources->deferred_count++] = vertices;", "RD::get_singleton()->free_rid(vertices);")
        self.assertNotEqual(premature, control)
        self.assertNotEqual(self.compile_run(premature, "rt_sources_premature_free").returncode, 0)

    def test_actual_native_command_identity_callbacks(self):
        control = IDENTITY.replace("@MARK@", CHECK.cxx_function(self.scene, "void rt_probe_mark_command("))
        control = control.replace("@OBSERVE@", CHECK.cxx_function(self.scene, "void rt_probe_observe("))
        self.assertEqual(self.compile_run(control, "identity").returncode, 0)
        changed = control.replace("first != last", "(first == 0 && last == 0)")
        self.assertNotEqual(changed, control)
        self.assertNotEqual(self.compile_run(changed, "identity_mutation").returncode, 0)

    def test_actual_poll_rejects_unwritten_stale_and_invalid_results(self):
        body = CHECK.cxx_function(self.scene, "Dictionary RendererSceneCull::scenario_poll_metalfx_rt_probe(")
        control = POLL.replace("@POLL@", body)
        self.assertEqual(self.compile_run(control, "poll").returncode, 0)
        changed = control.replace("write_marker != 0x52435431", "(write_marker == -1)")
        self.assertNotEqual(changed, control)
        self.assertNotEqual(self.compile_run(changed, "poll_mutation").returncode, 0)

    def test_actual_metal_preallocation_budget(self):
        body = CHECK.cxx_function(self.driver, "RDD::AccelerationStructureID RenderingDeviceDriverMetal::_triangle_query_create(")
        control = BUDGET.replace("@BUDGET@", body)
        self.assertEqual(self.compile_run(control, "as_budget", "on").returncode, 0)
        self.assertEqual(self.compile_run(control, "as_budget_off", "off").returncode, 0)
        changed = control.replace("constexpr uint64_t limit = 256u * 1024u * 1024u", "constexpr uint64_t limit = 1024u * 1024u * 1024u")
        self.assertNotEqual(changed, control)
        self.assertNotEqual(self.compile_run(changed, "as_budget_mutation", "on").returncode, 0)

    def test_scene_scope_and_recording_boundaries(self):
        create = CHECK.cxx_function(self.mesh, "void MeshStorage::mesh_add_surface(")
        self.assertLess(create.index("mesh->surface_count++;"), create.index("_rt_source_create(mesh, s, new_surface);"))
        prepare = CHECK.cxx_function(self.mesh, "void MeshStorage::_rt_source_create(")
        self.assertNotIn("ERR_FAIL", prepare)
        self.assertIn("vertex_buffer_create_metalfx_rt_input", prepare)
        for name in ("vertex", "attribute", "skin", "index"):
            body = CHECK.cxx_function(self.mesh, f"void {'RendererRD::' if name == 'index' else ''}MeshStorage::mesh_surface_update_{name}_region(")
            self.assertLess(body.index("_rt_source_invalidate"), body.index("buffer_update"))
            getter = CHECK.cxx_function(self.mesh, f"RID MeshStorage::mesh_surface_get_{name}_buffer_rd_rid(")
            self.assertLess(getter.index("ScopedRTSourceLock"), getter.index("_rt_source_invalidate"))
            self.assertLess(getter.index("_rt_source_invalidate"), getter.index("return mesh->surfaces"))
        scene = CHECK.cxx_function(self.scene, "Dictionary RendererSceneCull::scenario_probe_metalfx_rt(")
        self.assertIn("scenario->instances.first()", scene)
        self.assertIn("scenario_scan_limit", scene)
        self.assertNotIn("p_domain.intersects", scene)
        self.assertIn("unsupported_material", scene)
        self.assertIn("shader_data->uses_skip_vertex_transform", scene)
        shader = (self.base / "servers/rendering/renderer_rd/forward_clustered/scene_shader_forward_clustered.cpp").read_text(encoding="utf-8")
        self.assertIn('actions.render_mode_flags["skip_vertex_transform"] = &uses_skip_vertex_transform;', shader)
        self.assertIn("uses_skip_vertex_transform = false;", shader)
        self.assertLess(scene.index("metalfx_rt_probe_begin()"), scene.index("rt_probe_mark_command"))
        self.assertLess(scene.index("rt_probe_mark_command"), scene.index("metalfx_rt_probe_barrier()"))
        self.assertLess(scene.index("metalfx_rt_probe_barrier()"), scene.index("blas_create("))
        self.assertLess(scene.index("compute_list_dispatch("), scene.index("rt_probe_observe"))
        self.assertLess(scene.index("rt_probe_observe"), scene.index("buffer_get_data("))
        self.assertLess(scene.index("MutexLock lock("), scene.index("RTProbeResources resources"))
        self.assertLess(scene.index("RTProbeSourceGuard source_guard"), scene.index("RTProbeResources resources"))
        self.assertLess(scene.index("metalfx_rt_probe_begin()"), scene.index("source_guard.changed()"))
        self.assertGreater(scene.rindex("source_guard.changed()"), scene.index("buffer_get_data("))
        self.assertNotIn('entry["vertices"]', scene)
        self.assertNotIn('entry["blas"]', scene)
        self.assertIn("witness.marker=0x52435431u", self.scene)
        self.assertIn("_flush_and_stall_for_all_frames();", CHECK.cxx_function(self.device, "Error RenderingDevice::metalfx_rt_probe_begin("))


if __name__ == "__main__":
    unittest.main()
