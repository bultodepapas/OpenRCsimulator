"""Source-bound checks and an opt-in native runner for Metal triangle queries.

Portable controls compile actual patched validation/packing functions with small
C++ stand-ins. They do not execute Godot, Metal, or a GPU. The native runner
launches each expected-error case in a fresh process and retains its logs.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
import zipfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
from tools.godot.run_checked import ANSI, inspect_log, run_checked
from tools.testqueue.common import require_exclusive
SPEC = importlib.util.spec_from_file_location("metalfx_patch_checks", HERE / "test_engine_patch.py")
CHECKS = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(CHECKS)
PATCHES = [HERE / "patches" / n for n in (
    "0001-metalfx-allocation-fallback.patch", "0002-metalfx-history-reset.patch",
    "0003-metalfx-debug-faults.patch", "0004-metalfx-frame-inputs.patch",
    "0005-metal-triangle-query.patch")]
FROZEN = (
    "f04167e05f452bfc37e85e90d512373d92c3f6ec808cef8431a0705e197d716a",
    "d7570f1b3639616e4e565a920cc4b9caca844bf7d1c8b3ec7d14d6e596c4ecc5",
    "cdacbdf81c80e44b96b200f1890236774225d93d8b54299f8e7db47b9f2c21cd",
    "2cfc1c4b466dfba51ae940d4c0529d290bf5a4502cd562d52edc4c4712e1ce18",
)
PROBE = ROOT / "research/engine-upgrade/metalfx/triangle_query_probe.gd"

GUARD_STUB = r'''
#include <cstdint>
#include <map>
#include <vector>
using RID = int;
namespace RDD { enum { ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL, ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL }; }
struct Driver { std::map<int, bool> valid; bool acceleration_structure_build_is_valid(int id) const {
    auto i = valid.find(id); return i != valid.end() && i->second;
} };
template<class T> struct Owner {
    std::map<int,T> objects;
    T *get_or_null(RID id) { auto it=objects.find(id); return it == objects.end() ? nullptr : &it->second; }
};
class RenderingDevice {
public:
    enum { SUPPORTS_METAL_TRIANGLE_QUERY };
    struct UniformSet { std::vector<RID> acceleration_structures; };
    struct AccelerationStructure { int type=0; bool invalidated=true; int driver_id=0; std::vector<RID> acceleration_structure_dependencies; };
    struct ComputeList {
        struct SetState { uint32_t pipeline_expected_format=0, uniform_set_format=0; RID uniform_set=0; };
        struct State { SetState sets[4]; uint32_t set_count=0; } state;
    } compute_list;
    bool feature=false;
    bool has_feature(int) const { return feature; }
    Owner<UniformSet> uniform_set_owner;
    Owner<AccelerationStructure> acceleration_structure_owner;
    Driver *driver=nullptr;
    bool _compute_list_triangle_query_sets_valid();
};
@GUARD@
#define CHECK(x) do { if (!(x)) return __LINE__; } while (0)
int main() {
    RenderingDevice rd; Driver driver; rd.driver=&driver;
    rd.compute_list.state.set_count=1;
    auto &set=rd.compute_list.state.sets[0];
    set.pipeline_expected_format=7; set.uniform_set_format=7; set.uniform_set=1;
    CHECK(rd._compute_list_triangle_query_sets_valid()); // capability off
    rd.feature=true;
    CHECK(!rd._compute_list_triangle_query_sets_valid()); // missing set
    rd.uniform_set_owner.objects[1].acceleration_structures={2};
    set.uniform_set_format=8; CHECK(!rd._compute_list_triangle_query_sets_valid());
    set.uniform_set_format=7; CHECK(!rd._compute_list_triangle_query_sets_valid()); // missing TLAS
    auto &t=rd.acceleration_structure_owner.objects[2];
    t.type=RDD::ACCELERATION_STRUCTURE_TYPE_BOTTOM_LEVEL; t.driver_id=10; t.invalidated=false;
    driver.valid[10]=true; CHECK(!rd._compute_list_triangle_query_sets_valid());
    t.type=RDD::ACCELERATION_STRUCTURE_TYPE_TOP_LEVEL; t.invalidated=true;
    CHECK(!rd._compute_list_triangle_query_sets_valid());
    t.invalidated=false; driver.valid[10]=false; CHECK(!rd._compute_list_triangle_query_sets_valid());
    driver.valid[10]=true; t.acceleration_structure_dependencies={3};
    CHECK(!rd._compute_list_triangle_query_sets_valid()); // missing BLAS
    auto &b=rd.acceleration_structure_owner.objects[3]; b.invalidated=true; b.driver_id=11;
    driver.valid[11]=true; CHECK(!rd._compute_list_triangle_query_sets_valid());
    b.invalidated=false; driver.valid[11]=false; CHECK(!rd._compute_list_triangle_query_sets_valid());
    driver.valid[11]=true; CHECK(rd._compute_list_triangle_query_sets_valid());
    return 0;
}
'''


GEOMETRY_STUB = r'''
#include <cstdint>
#include <vector>
using RID = int;
#define ERR_FAIL_COND_V_MSG(c,v,m) do { if (c) return false; } while (0)
enum { SUPPORTS_METAL_TRIANGLE_QUERY, ACCELERATION_STRUCTURE_GEOMETRY_OPAQUE_BIT=1,
       DATA_FORMAT_R32G32B32_SFLOAT=2 };
namespace RDD { enum { BUFFER_USAGE_ACCELERATION_STRUCTURE_BUILD_INPUT_READ_ONLY_BIT=1,
                       BUFFER_USAGE_DYNAMIC_PERSISTENT_BIT=2 }; }
struct Flags { uint64_t value=0; bool is_empty() const { return value==0; }
    bool has_flag(int bit) const { return (value & uint64_t(bit)) != 0; }
    explicit operator uint64_t() const { return value; } };
struct Handle { bool valid=false; bool is_valid() const { return valid; } };
struct Geometry { Flags flags; Handle index_buffer; int64_t index_offset=0, index_count=0;
    int vertex_format=DATA_FORMAT_R32G32B32_SFLOAT; int64_t vertex_offset=0, vertex_count=6, vertex_stride=16; };
using AccelerationStructureGeometry = Geometry;
struct Buffer { Flags usage; uint64_t size=0; };
static bool has_feature(int) { return true; }
bool geometry_ok(const std::vector<Geometry> &p_geometries, Flags p_flags, Buffer &buffer) {
@ADMISSION@
    for (uint64_t i=0;i<p_geometries.size();++i) {
@FIELDS@
        Buffer *vertex_buffer=&buffer;
@BOUNDS@
    }
    return true;
}
#define CHECK(x) do { if (!(x)) return __LINE__; } while (0)
int main() {
    Geometry g; g.flags.value=1; g.vertex_offset=4; Buffer buffer; buffer.usage.value=1; buffer.size=96;
    CHECK(geometry_ok({g},{0},buffer)); // last float3 ends exactly at buffer end
    buffer.size=95; CHECK(!geometry_ok({g},{0},buffer)); buffer.size=96;
    auto bad=g; bad.vertex_offset=5; CHECK(!geometry_ok({bad},{0},buffer));
    bad=g; bad.vertex_stride=10; CHECK(!geometry_ok({bad},{0},buffer));
    bad=g; bad.vertex_count=0; CHECK(!geometry_ok({bad},{0},buffer));
    bad=g; bad.vertex_count=7; CHECK(!geometry_ok({bad},{0},buffer));
    bad=g; bad.vertex_count=-3; CHECK(!geometry_ok({bad},{0},buffer));
    bad=g; bad.vertex_offset=4294967296LL; CHECK(!geometry_ok({bad},{0},buffer));
    bad=g; bad.index_buffer.valid=true; CHECK(!geometry_ok({bad},{0},buffer));
    bad=g; bad.flags.value=0; CHECK(!geometry_ok({bad},{0},buffer));
    CHECK(!geometry_ok({g,g},{0},buffer)); CHECK(!geometry_ok({g},{1},buffer));
    buffer.usage.value=0; CHECK(!geometry_ok({g},{0},buffer));
    buffer.usage.value=3; CHECK(!geometry_ok({g},{0},buffer));
    return 0;
}
'''

PACK_STUB = r'''
#include <cstdint>
#include <cstring>
#include <cmath>
#include <cstddef>
#define ERR_FAIL_NULL(x) do { if (!(x)) return; } while (0)
#define ERR_FAIL_COND_MSG(x,m) do { if (x) return; } while (0)
namespace MTL {
struct Matrix { float values[4][3]{}; float *operator[](int i) { return values[i]; } };
struct AccelerationStructureUserIDInstanceDescriptor { Matrix transformationMatrix; uint32_t options=0, mask=0, intersectionFunctionTableOffset=0, accelerationStructureIndex=0, userID=0; };
}
struct MDAccelerationStructure { enum class Type { BLAS, TLAS }; Type type=Type::BLAS; };
@INSTANCE@
namespace RDD {
struct Transform { struct Basis { float rows[3][3]{}; } basis; float origin[3]{}; bool finite=true; bool is_finite() const { return finite; } };
struct Flags { bool empty=true; bool is_empty() const { return empty; } };
struct AccelerationStructureInstance { Transform transform; uint32_t id=0, mask=0, hit_sbt_offset=0; Flags flags; struct { uint64_t id=0; } blas; };
}
class RenderingDeviceDriverMetal { public:
    using AccelerationStructureInstance=RDD::AccelerationStructureInstance;
    void acceleration_structure_instance_write(uint8_t *, const AccelerationStructureInstance &);
};
@PACK@
#define CHECK(x) do { if (!(x)) return __LINE__; } while (0)
int main() {
    RenderingDeviceDriverMetal rd; MDAccelerationStructure blas; RDD::AccelerationStructureInstance input;
    input.blas.id=uint64_t(&blas); input.id=0x123456; input.mask=0xa5;
    for (int r=0;r<3;r++) { input.transform.origin[r]=float(10+r); for (int c=0;c<3;c++) input.transform.basis.rows[r][c]=float(3*r+c+1); }
    alignas(8) uint8_t bytes[128]; std::memset(bytes,0xcd,sizeof bytes);
    rd.acceleration_structure_instance_write(bytes,input);
    MDAccelerationStructureInstance result; std::memcpy(&result,bytes,sizeof result);
    CHECK(result.blas==&blas && result.native.userID==0x123456 && result.native.mask==0xa5);
    for (int c=0;c<3;c++) for (int r=0;r<3;r++) CHECK(result.native.transformationMatrix[c][r]==float(3*r+c+1));
    for (int r=0;r<3;r++) CHECK(result.native.transformationMatrix[3][r]==float(10+r));
    for (int mode=0;mode<5;mode++) {
        std::memset(bytes,0xcd,sizeof bytes); input.id=0x123456; input.flags.empty=true; input.transform.finite=true; input.hit_sbt_offset=0; blas.type=MDAccelerationStructure::Type::BLAS;
        if (mode==0) input.id=0x1000000;
        if (mode==1) input.flags.empty=false;
        if (mode==2) input.transform.finite=false;
        if (mode==3) input.hit_sbt_offset=1;
        if (mode==4) blas.type=MDAccelerationStructure::Type::TLAS;
        rd.acceleration_structure_instance_write(bytes,input);
        for (auto value : bytes) CHECK(value==0xcd);
    }
    return 0;
}
'''


READINESS_STUB = r'''
#include <cstdint>
#include <vector>
#include <climits>
namespace RDD {
enum { SHADER_STAGE_COMPUTE_BIT=1, SHADER_STAGE_FRAGMENT_BIT=2, UNIFORM_TYPE_ACCELERATION_STRUCTURE=3, UNIFORM_TYPE_STORAGE_BUFFER=4 };
struct ID { uint64_t id=0; };
struct AccelerationStructureID { uint64_t id; explicit AccelerationStructureID(uint64_t v):id(v) {} };
struct BoundUniform { int type=0; uint32_t binding=0; std::vector<ID> ids; };
}
namespace MTL { enum DataType { DataTypeNone, DataTypeInstanceAccelerationStructure, DataTypePointer }; }
struct Flags { uint32_t value=0; bool has_flag(uint32_t bit) const { return (value & bit) != 0; } };
struct UniformInfo { uint32_t binding=0; Flags active_stages; MTL::DataType dataType=MTL::DataTypeNone;
    struct Indexes { uint32_t buffer=UINT32_MAX; } slot, arg_buffer; };
struct UniformSet { std::vector<UniformInfo> uniforms; Flags active_stages; };
struct MDShader { bool uses_argument_buffers=false; std::vector<UniformSet> sets; };
struct MDComputeShader : MDShader {};
struct MDComputePipeline { MDComputeShader *shader=nullptr; };
struct MDUniformSet { std::vector<RDD::BoundUniform> uniforms; };
struct MDAccelerationStructure { bool build_encoded=false; bool failed=false; };
struct Driver { bool acceleration_structure_build_is_valid(RDD::AccelerationStructureID id) const {
    auto *value=reinterpret_cast<MDAccelerationStructure *>(id.id); return value && !value->failed;
} };
class MDCommandBuffer { public:
    struct State { MDComputePipeline *pipeline=nullptr; std::vector<MDUniformSet *> uniform_sets; } compute;
    Driver *device_driver=nullptr;
    bool triangle_query_resources_ready() const;
};
@ACTIVE@
@READY@
#define CHECK(x) do { if (!(x)) return __LINE__; } while (0)
int main() {
    Driver driver; MDCommandBuffer cmd; cmd.device_driver=&driver;
    CHECK(!cmd.triangle_query_resources_ready());
    MDComputeShader query, plain, hole; MDComputePipeline pquery{&query}, pplain{&plain}, phole{&hole};
    query.sets.resize(1); query.sets[0].active_stages.value=RDD::SHADER_STAGE_COMPUTE_BIT;
    UniformInfo info; info.binding=7; info.active_stages.value=RDD::SHADER_STAGE_COMPUTE_BIT;
    info.dataType=MTL::DataTypeInstanceAccelerationStructure; info.slot.buffer=2; info.arg_buffer.buffer=3;
    query.sets[0].uniforms.push_back(info);
    MDAccelerationStructure as; as.build_encoded=true;
    RDD::BoundUniform bound; bound.type=RDD::UNIFORM_TYPE_ACCELERATION_STRUCTURE; bound.binding=7; bound.ids.push_back({uint64_t(&as)});
    MDUniformSet set; set.uniforms.push_back(bound);
    cmd.compute.pipeline=&pquery; cmd.compute.uniform_sets={&set};
    CHECK(cmd.triangle_query_resources_ready());
    as.failed=true; CHECK(!cmd.triangle_query_resources_ready());
    as.failed=false; as.build_encoded=false; CHECK(!cmd.triangle_query_resources_ready());
    as.build_encoded=true; as.failed=true;
    cmd.compute.pipeline=&pplain; CHECK(cmd.triangle_query_resources_ready()); // obsolete set
    hole.sets.resize(2); hole.sets[0].active_stages.value=RDD::SHADER_STAGE_FRAGMENT_BIT;
    hole.sets[0].uniforms.push_back(info); hole.sets[1].active_stages.value=RDD::SHADER_STAGE_COMPUTE_BIT;
    UniformInfo other; other.dataType=MTL::DataTypePointer; other.active_stages.value=RDD::SHADER_STAGE_COMPUTE_BIT;
    hole.sets[1].uniforms.push_back(other); cmd.compute.uniform_sets={&set, &set}; cmd.compute.pipeline=&phole;
    CHECK(cmd.triangle_query_resources_ready()); // hole at set zero
    hole.sets[0].active_stages.value=RDD::SHADER_STAGE_COMPUTE_BIT;
    hole.sets[0].uniforms[0].active_stages.value=RDD::SHADER_STAGE_FRAGMENT_BIT;
    CHECK(cmd.triangle_query_resources_ready()); // binding not used by compute
    hole.sets[0].uniforms[0].active_stages.value=RDD::SHADER_STAGE_COMPUTE_BIT;
    hole.sets[0].uniforms[0].slot.buffer=UINT32_MAX;
    CHECK(cmd.triangle_query_resources_ready()); // unused direct binding
    hole.uses_argument_buffers=true; hole.sets[0].uniforms[0].arg_buffer.buffer=UINT32_MAX;
    CHECK(cmd.triangle_query_resources_ready()); // unused argument-buffer binding
    cmd.compute.pipeline=&pquery; as.failed=false;
    cmd.compute.uniform_sets.clear(); CHECK(!cmd.triangle_query_resources_ready());
    cmd.compute.uniform_sets={nullptr}; CHECK(!cmd.triangle_query_resources_ready());
    cmd.compute.uniform_sets={&set}; set.uniforms.clear(); CHECK(!cmd.triangle_query_resources_ready());
    set.uniforms.push_back(bound); set.uniforms[0].binding=8; CHECK(!cmd.triangle_query_resources_ready());
    set.uniforms[0]=bound; set.uniforms[0].type=RDD::UNIFORM_TYPE_STORAGE_BUFFER; CHECK(!cmd.triangle_query_resources_ready());
    set.uniforms[0]=bound; set.uniforms[0].ids.clear(); CHECK(!cmd.triangle_query_resources_ready());
    set.uniforms[0]=bound; set.uniforms[0].ids.push_back({uint64_t(&as)}); CHECK(!cmd.triangle_query_resources_ready());
    set.uniforms[0]=bound; set.uniforms[0].ids[0].id=0; CHECK(!cmd.triangle_query_resources_ready());
    set.uniforms[0]=bound; CHECK(cmd.triangle_query_resources_ready());
    query.uses_argument_buffers=true; CHECK(cmd.triangle_query_resources_ready());
    as.failed=true; CHECK(!cmd.triangle_query_resources_ready()); // both modes fail closed
    return 0;
}
'''

BIND_STUB = r'''
#include <cstdint>
#include <cstdlib>
#include <memory>
#include <vector>
#define DEV_ASSERT(v) do { if (!(v)) std::abort(); } while (0)
namespace RDD { enum { SHADER_STAGE_COMPUTE_BIT=1, SHADER_STAGE_FRAGMENT_BIT=2 }; }
struct Flags { uint32_t value=0; bool has_flag(uint32_t bit) const { return (value & bit) != 0; } void clear_flag(uint32_t bit) { value &= ~bit; } };
struct UniformSet { Flags active_stages; };
struct MDComputeShader { std::vector<UniformSet> sets; bool uses_argument_buffers=true; };
struct MDComputePipeline { MDComputeShader *shader=nullptr; };
struct MDUniformSet {};
struct DirectEncoder { enum Mode { COMPUTE }; DirectEncoder(int *, int &, Mode) {} };
enum class MDCommandBufferStateType { Compute };
class MDCommandBuffer { public:
    struct ComputeState { enum { DIRTY_UNIFORMS=1 }; Flags dirty; uint64_t uniform_set_mask=0; uint32_t dynamic_offsets=0;
        MDComputePipeline *pipeline=nullptr; std::vector<MDUniformSet *> uniform_sets; std::shared_ptr<int> encoder; } compute;
    MDCommandBufferStateType type=MDCommandBufferStateType::Compute;
    int binding_cache=0, arg_calls=0, direct_calls=0; uint32_t last_set=99;
    void _compute_bind_uniform_sets();
    void _bind_uniforms_argument_buffers_compute(MDUniformSet *, MDComputeShader *, uint32_t index, uint32_t) { ++arg_calls; last_set=index; }
    void _bind_uniforms_direct(MDUniformSet *, MDComputeShader *, DirectEncoder, uint32_t index, uint32_t) { ++direct_calls; last_set=index; }
};
@BIND@
#define CHECK(x) do { if (!(x)) return __LINE__; } while (0)
int main() {
    MDCommandBuffer cmd; MDComputeShader query, other; MDComputePipeline first{&query}, second{&other}; MDUniformSet old_set, live_set;
    query.sets.resize(1); query.sets[0].active_stages.value=RDD::SHADER_STAGE_COMPUTE_BIT;
    cmd.compute.pipeline=&first; cmd.compute.encoder=std::make_shared<int>(); cmd.compute.uniform_sets={&old_set};
    cmd.compute.dirty.value=1; cmd.compute.uniform_set_mask=1; cmd._compute_bind_uniform_sets();
    CHECK(cmd.arg_calls==1 && cmd.last_set==0);
    other.sets.resize(2); other.sets[0].active_stages.value=RDD::SHADER_STAGE_FRAGMENT_BIT;
    other.sets[1].active_stages.value=RDD::SHADER_STAGE_COMPUTE_BIT;
    cmd.compute.pipeline=&second; cmd.compute.uniform_sets={&old_set,&live_set}; cmd.compute.dirty.value=1; cmd.compute.uniform_set_mask=3;
    cmd._compute_bind_uniform_sets(); CHECK(cmd.arg_calls==2 && cmd.last_set==1);
    other.uses_argument_buffers=false; cmd.compute.dirty.value=1; cmd.compute.uniform_set_mask=3;
    cmd._compute_bind_uniform_sets(); CHECK(cmd.direct_calls==1 && cmd.last_set==1);
    other.sets.clear(); cmd.compute.dirty.value=1; cmd.compute.uniform_set_mask=3;
    cmd._compute_bind_uniform_sets(); CHECK(cmd.direct_calls==1 && cmd.arg_calls==2);
    return 0;
}
'''


ARGUMENT_BIND_STUB = r'''
#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <vector>
#define DEV_ASSERT(v) do { if (!(v)) std::abort(); } while (0)
#define MIN(a,b) std::min(a,b)
using CFTypeRef=const void *;
template<class T> struct Vec : std::vector<T> {
    using std::vector<T>::vector; bool is_empty() const { return this->empty(); }
    const T *ptr() const { return this->data(); } T *ptr() { return this->data(); }
};
namespace RDD {
enum { SHADER_STAGE_COMPUTE_BIT=1, SHADER_STAGE_FRAGMENT_BIT=2, UNIFORM_TYPE_ACCELERATION_STRUCTURE=3 };
struct ID { uint64_t id=0; };
struct BoundUniform { int type=0; uint32_t binding=0; Vec<ID> ids; };
}
namespace MTL {
enum DataType { DataTypeNone, DataTypeInstanceAccelerationStructure };
enum ResourceUsage { ResourceUsageRead=1 };
struct Resource {};
struct AccelerationStructure : Resource {};
struct Buffer : Resource { uint64_t gpuAddress() const { return 0; } };
struct ComputeCommandEncoder {
    int resources=0, lists=0, bindings=0;
    void useResource(Resource *, ResourceUsage) { ++resources; }
    void noop(Resource *, ResourceUsage) {}
    void useResources(const Resource *const *, size_t count, ResourceUsage) { if (count) ++lists; }
    void setBuffer(Buffer *, uint32_t, uint32_t) { ++bindings; }
};
}
struct Flags { uint32_t value=0; bool has_flag(uint32_t bit) const { return (value & bit) != 0; } };
struct UniformInfo { uint32_t binding=0; Flags active_stages; MTL::DataType dataType=MTL::DataTypeNone;
    struct Indexes { uint32_t buffer=UINT32_MAX; } slot, arg_buffer; };
struct UniformSet { Vec<UniformInfo> uniforms; Vec<uint32_t> dynamic_uniforms; Flags active_stages; };
struct DynamicOffsetLayout { uint32_t get_offset_index_shift(uint32_t, uint32_t) const { return 0; } };
struct MDShader { bool uses_argument_buffers=true; Vec<UniformSet> sets; DynamicOffsetLayout dynamic_offset_layout; };
struct MDUniformSet { Vec<RDD::BoundUniform> uniforms; int usage_to_resources=0; Vec<uint8_t> arg_buffer_data;
    struct { std::shared_ptr<MTL::Buffer> buffer; } arg_buffer; };
struct MDAccelerationStructure { std::shared_ptr<MTL::AccelerationStructure> accel; Vec<MTL::Resource *> resident_blases; };
struct MetalBufferDynamicInfo { std::shared_ptr<MTL::Buffer> buffer; uint64_t size_bytes=0; };
namespace MDRingBuffer { struct Allocation { void *ptr; MTL::Buffer *buffer; uint32_t offset; }; }
struct Tracker { int merges=0; void merge_from(int) { ++merges; } };
class MDCommandBuffer { public:
    struct State { std::shared_ptr<MTL::ComputeCommandEncoder> encoder; Tracker resource_tracker; } compute;
    int retains=0;
    void retain_resource(CFTypeRef) { ++retains; }
    MDRingBuffer::Allocation allocate_arg_buffer(uint32_t) { static uint8_t bytes[32]; static MTL::Buffer buffer; return {bytes, &buffer, 0}; }
    void _bind_uniforms_argument_buffers_compute(MDUniformSet *, MDShader *, uint32_t, uint32_t);
};
@ACTIVE@
@BIND_ARGUMENT@
#define CHECK(x) do { if (!(x)) return __LINE__; } while (0)
int main() {
    MDCommandBuffer cmd; cmd.compute.encoder=std::make_shared<MTL::ComputeCommandEncoder>();
    MDShader shader; shader.sets.resize(1); auto &layout=shader.sets[0];
    MDUniformSet set; set.arg_buffer.buffer=std::make_shared<MTL::Buffer>();
    UniformInfo info; info.binding=7; info.dataType=MTL::DataTypeInstanceAccelerationStructure;
    info.active_stages.value=RDD::SHADER_STAGE_COMPUTE_BIT; info.arg_buffer.buffer=2; layout.uniforms.push_back(info);
    MDAccelerationStructure as; as.accel=std::make_shared<MTL::AccelerationStructure>(); MTL::Resource blas;
    as.resident_blases.push_back(&blas); RDD::BoundUniform bound; bound.type=RDD::UNIFORM_TYPE_ACCELERATION_STRUCTURE;
    bound.binding=7; bound.ids.push_back({uint64_t(&as)}); set.uniforms.push_back(bound);
    cmd._bind_uniforms_argument_buffers_compute(&set,&shader,0,0);
    CHECK(cmd.compute.resource_tracker.merges==0 && cmd.retains==0 && cmd.compute.encoder->bindings==0);
    layout.active_stages.value=RDD::SHADER_STAGE_COMPUTE_BIT;
    layout.uniforms[0].active_stages.value=RDD::SHADER_STAGE_FRAGMENT_BIT;
    cmd._bind_uniforms_argument_buffers_compute(&set,&shader,0,0);
    CHECK(cmd.compute.resource_tracker.merges==1 && cmd.retains==0 && cmd.compute.encoder->resources==0);
    layout.uniforms[0].active_stages.value=RDD::SHADER_STAGE_COMPUTE_BIT;
    cmd._bind_uniforms_argument_buffers_compute(&set,&shader,0,0);
    CHECK(cmd.compute.resource_tracker.merges==2 && cmd.compute.encoder->resources==1 && cmd.compute.encoder->lists==1 && cmd.retains==2);
    CHECK(cmd.compute.encoder->bindings==2);
    return 0;
}
'''

NAMING_STUB = r'''
#include <cstdint>
#include <memory>
#include <string>
#define DEV_ENABLED 1
static int assertions=0;
#define DEV_ASSERT(v) do { if (!(v)) ++assertions; } while (0)
namespace NS { struct String {}; }
using String=std::string;
namespace conv { NS::String *to_nsstring(const String &) { static NS::String label; return &label; } }
struct Resource { int labels=0; void setLabel(NS::String *) { ++labels; } };
struct Library { void set_label(NS::String *) {} };
struct MDShader { virtual ~MDShader()=default; };
struct MDRenderShader : MDShader { std::shared_ptr<Library> vert, frag; };
struct MDComputeShader : MDShader { std::shared_ptr<Library> kernel; };
struct MDUniformSet { struct { std::shared_ptr<Resource> buffer; } arg_buffer; };
struct MDAccelerationStructure { std::shared_ptr<Resource> accel; };
class RenderingDeviceDriverMetal { public:
    enum ObjectType { OBJECT_TYPE_TEXTURE, OBJECT_TYPE_SAMPLER, OBJECT_TYPE_BUFFER, OBJECT_TYPE_SHADER,
        OBJECT_TYPE_UNIFORM_SET, OBJECT_TYPE_ACCELERATION_STRUCTURE, OBJECT_TYPE_PIPELINE, OBJECT_TYPE_UNKNOWN };
    struct ID { uint64_t id=0; template<class T> explicit ID(T *ptr):id(uint64_t(ptr)) {} ID()=default; };
    struct TextureInfo { bool rasterization_rate_map=false; std::shared_ptr<Resource> texture; };
    struct BufferInfo { std::shared_ptr<Resource> buffer; };
    void set_object_name(ObjectType, ID, const String &);
};
@NAME@
#define CHECK(x) do { if (!(x)) return __LINE__; } while (0)
int main() {
    RenderingDeviceDriverMetal driver; MDUniformSet direct, argument;
    argument.arg_buffer.buffer=std::make_shared<Resource>();
    driver.set_object_name(driver.OBJECT_TYPE_UNIFORM_SET, RenderingDeviceDriverMetal::ID(&direct), "direct");
    driver.set_object_name(driver.OBJECT_TYPE_UNIFORM_SET, RenderingDeviceDriverMetal::ID(&argument), "argument");
    CHECK(argument.arg_buffer.buffer->labels==1 && assertions==0);
    MDAccelerationStructure as, empty; as.accel=std::make_shared<Resource>();
    driver.set_object_name(driver.OBJECT_TYPE_ACCELERATION_STRUCTURE, RenderingDeviceDriverMetal::ID(&as), "blas");
    driver.set_object_name(driver.OBJECT_TYPE_ACCELERATION_STRUCTURE, RenderingDeviceDriverMetal::ID(&empty), "empty");
    driver.set_object_name(driver.OBJECT_TYPE_ACCELERATION_STRUCTURE, RenderingDeviceDriverMetal::ID(), "invalid");
    CHECK(as.accel->labels==1 && assertions==0);
    driver.set_object_name(driver.OBJECT_TYPE_UNKNOWN, RenderingDeviceDriverMetal::ID(), "unknown");
    CHECK(assertions==1);
    return 0;
}
'''

class TriangleQueryPatchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if hashlib.sha256(CHECKS.ARCHIVE.read_bytes()).hexdigest() != CHECKS.ARCHIVE_SHA256:
            raise RuntimeError("Pinned source archive differs")
        if tuple(hashlib.sha256(p.read_bytes()).hexdigest() for p in PATCHES[:4]) != FROZEN:
            raise RuntimeError("Frozen prerequisite patches differ")
        cls.temp = tempfile.TemporaryDirectory(prefix="openrc-metal-query-")
        cls.base = Path(cls.temp.name)
        names = set()
        for patch in PATCHES:
            for name in re.findall(r"^(?:---|\+\+\+) ([ab]/[^\r\n]+)$", patch.read_text(encoding="utf-8"), re.M):
                names.add(name[2:])
        with zipfile.ZipFile(CHECKS.ARCHIVE) as archive:
            members = set(archive.namelist())
            for name in names:
                member = f"godot-{CHECKS.COMMIT}/{name}"
                if member in members:
                    target = cls.base / name
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(archive.read(member))
        for patch in PATCHES:
            subprocess.run(["git", "-c", "core.autocrlf=false", "apply", "--check", str(patch)], cwd=cls.base, check=True, capture_output=True)
            subprocess.run(["git", "-c", "core.autocrlf=false", "apply", str(patch)], cwd=cls.base, check=True, capture_output=True)
        cls.rd = (cls.base / "servers/rendering/rendering_device.cpp").read_text(encoding="utf-8")
        cls.shared = (cls.base / "drivers/metal/metal_objects_shared.h").read_text(encoding="utf-8")
        cls.driver = (cls.base / "drivers/metal/rendering_device_driver_metal.cpp").read_text(encoding="utf-8")

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temp.cleanup()

    def compile(self, source: str, name: str) -> subprocess.CompletedProcess[str]:
        compiler = shutil.which("g++") or shutil.which("clang++")
        if not compiler:
            self.fail("A C++17 compiler is required")
        cpp = self.base / (name + ".cpp")
        binary = self.base / (name + (".exe" if os.name == "nt" else ""))
        cpp.write_text(source, encoding="utf-8")
        built = subprocess.run([compiler, "-std=c++17", "-Wall", "-Wextra", "-Werror", "-Wno-unused-parameter", str(cpp), "-o", str(binary)], capture_output=True, text=True)
        self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
        return subprocess.run([str(binary)], cwd=self.base, capture_output=True, text=True)

    def test_prerequisite_stack_and_mutation_rejection(self) -> None:
        subprocess.run(["git", "apply", "--reverse", "--check", str(PATCHES[-1])], cwd=self.base, check=True, capture_output=True)
        target = self.base / "thirdparty/spirv-cross/spirv_msl.cpp"
        original = target.read_bytes()
        try:
            altered = original.replace(b"case SPIRType::AccelerationStructure:\n\t\t\tADD_ARG_IDX_TO_BINDING_NUM_LOOKUP", b"case SPIRType::Unknown:\n\t\t\tADD_ARG_IDX_TO_BINDING_NUM_LOOKUP", 1)
            self.assertNotEqual(original, altered)
            target.write_bytes(altered)
            refused = subprocess.run(["git", "apply", "--reverse", "--check", str(PATCHES[-1])], cwd=self.base, capture_output=True)
            self.assertNotEqual(refused.returncode, 0)
        finally:
            target.write_bytes(original)

    def test_real_dispatch_guard_and_negative_mutation(self) -> None:
        guard = CHECKS.cxx_function(self.rd, "bool RenderingDevice::_compute_list_triangle_query_sets_valid(")
        src = GUARD_STUB.replace("@GUARD@", guard)
        run = self.compile(src, "guard_controls")
        self.assertEqual(run.returncode, 0, run.stderr)
        mutated = src.replace("tlas->invalidated ||", "false ||", 1)
        self.assertNotEqual(mutated, src)
        run = self.compile(mutated, "guard_mutated")
        self.assertNotEqual(run.returncode, 0, "Control failed to detect a stale TLAS")
        for signature in ("void RenderingDevice::compute_list_dispatch(", "void RenderingDevice::compute_list_dispatch_indirect("):
            fn = CHECKS.cxx_function(self.rd, signature)
            self.assertLess(fn.index("_compute_list_triangle_query_sets_valid"), fn.index("draw_graph.add_compute_list_dispatch"))

    def test_real_geometry_admission_and_exact_bounds(self) -> None:
        start = self.rd.index("RID RenderingDevice::blas_create(")
        admission_start = self.rd.index("\tconst bool triangle_query =", start)
        admission_end = self.rd.index("\n\tthread_local", admission_start)
        fields_start = self.rd.index("\t\tconst AccelerationStructureGeometry &rd_geometry", admission_end)
        fields_end = self.rd.index("\n\t\tRDD::AccelerationStructureGeometry &", fields_start)
        bounds_start = self.rd.index("\t\tif (triangle_query) {", fields_end)
        bounds_end = self.rd.index("\n\t\tERR_FAIL_COND_V_MSG(rd_geometry.vertex_format", bounds_start)
        source = (GEOMETRY_STUB.replace("@ADMISSION@", self.rd[admission_start:admission_end])
                  .replace("@FIELDS@", self.rd[fields_start:fields_end])
                  .replace("@BOUNDS@", self.rd[bounds_start:bounds_end]))
        run = self.compile(source, "geometry_controls")
        self.assertEqual(run.returncode, 0, run.stderr)
        mutated = source.replace("end > vertex_buffer->size", "end >= vertex_buffer->size", 1)
        self.assertNotEqual(mutated, source)
        self.assertNotEqual(self.compile(mutated, "geometry_mutated").returncode, 0,
                            "Control failed to detect rejection of an exact-fit buffer")

    def test_real_instance_packing_and_invalid_inputs(self) -> None:
        instance = "struct MDAccelerationStructureInstance " + CHECKS.cxx_block(self.shared, self.shared.index("struct MDAccelerationStructureInstance")) + ";"
        pack = CHECKS.cxx_function(self.driver, "void RenderingDeviceDriverMetal::acceleration_structure_instance_write(")
        run = self.compile(PACK_STUB.replace("@INSTANCE@", instance).replace("@PACK@", pack), "instance_controls")
        self.assertEqual(run.returncode, 0, run.stderr)

    def test_actual_driver_readiness_tracks_current_shader_layout(self) -> None:
        source = (self.base / "drivers/metal/metal3_objects.cpp").read_text(encoding="utf-8")
        active = CHECKS.cxx_function(source, "static bool _triangle_query_binding_active(")
        ready = CHECKS.cxx_function(source, "bool MDCommandBuffer::triangle_query_resources_ready(")
        harness = READINESS_STUB.replace("@ACTIVE@", active).replace("@READY@", ready)
        run = self.compile(harness, "active_layout_controls")
        self.assertEqual(run.returncode, 0, run.stderr)
        mutant = harness.replace("!accel->build_encoded ||", "false ||", 1)
        self.assertNotEqual(mutant, harness)
        self.assertNotEqual(self.compile(mutant, "active_layout_mutated").returncode, 0,
                            "Control failed to catch an unbuilt active TLAS")
        for signature in ("void MDCommandBuffer::compute_dispatch(", "void MDCommandBuffer::compute_dispatch_indirect("):
            fn = CHECKS.cxx_function(source, signature)
            self.assertLess(fn.index("triangle_query_resources_ready()"), fn.index("dispatchThreadgroups"))

    def test_actual_pipeline_switch_ignores_inactive_sets(self) -> None:
        source = (self.base / "drivers/metal/metal3_objects.cpp").read_text(encoding="utf-8")
        bind = CHECKS.cxx_function(source, "void MDCommandBuffer::_compute_bind_uniform_sets(")
        run = self.compile(BIND_STUB.replace("@BIND@", bind), "pipeline_switch_controls")
        self.assertEqual(run.returncode, 0, run.stderr)
        mutant = bind.replace(" || !shader->sets[index].active_stages.has_flag(RDD::SHADER_STAGE_COMPUTE_BIT)", "", 1)
        self.assertNotEqual(mutant, bind)
        self.assertNotEqual(self.compile(BIND_STUB.replace("@BIND@", mutant), "pipeline_switch_mutated").returncode, 0)
        argument = CHECKS.cxx_function(source, "void MDCommandBuffer::_bind_uniforms_argument_buffers_compute(")
        self.assertLess(argument.index("!shader_set.active_stages"), argument.index("merge_from"))
        self.assertLess(argument.index("!shader_set.active_stages"), argument.index("resident_blases"))
        self.assertIn("_triangle_query_binding_active(p_shader, info)", argument)
        direct = CHECKS.cxx_function(source, "void MDCommandBuffer::_bind_uniforms_direct(")
        self.assertIn("_triangle_query_binding_active(p_shader, ui)", direct)

    def test_actual_argument_binding_respects_active_layout_and_residency(self) -> None:
        source = (self.base / "drivers/metal/metal3_objects.cpp").read_text(encoding="utf-8")
        active = CHECKS.cxx_function(source, "static bool _triangle_query_binding_active(")
        bind = CHECKS.cxx_function(source, "void MDCommandBuffer::_bind_uniforms_argument_buffers_compute(")
        harness = ARGUMENT_BIND_STUB.replace("@ACTIVE@", active).replace("@BIND_ARGUMENT@", bind)
        run = self.compile(harness, "argument_residency_controls")
        self.assertEqual(run.returncode, 0, run.stderr)
        mutant = harness.replace("enc->useResource(accel->accel.get(),", "enc->noop(accel->accel.get(),", 1)
        self.assertNotEqual(mutant, harness)
        self.assertNotEqual(self.compile(mutant, "argument_residency_mutated").returncode, 0,
                            "Control failed to detect missing TLAS residency")

    def test_actual_dev_resource_naming_handles_direct_and_as(self) -> None:
        name = CHECKS.cxx_function(self.driver, "void RenderingDeviceDriverMetal::set_object_name(")
        run = self.compile(NAMING_STUB.replace("@NAME@", name), "dev_resource_name_controls")
        self.assertEqual(run.returncode, 0, run.stderr)
        direct_mutant = name.replace("set && set->arg_buffer.buffer", "false", 1)
        self.assertNotEqual(direct_mutant, name)
        self.assertNotEqual(self.compile(NAMING_STUB.replace("@NAME@", direct_mutant), "dev_uniform_name_mutated").returncode, 0)
        mutant = name.replace("case OBJECT_TYPE_ACCELERATION_STRUCTURE:", "case OBJECT_TYPE_UNKNOWN:", 1)
        self.assertNotEqual(mutant, name)
        self.assertNotEqual(self.compile(NAMING_STUB.replace("@NAME@", mutant), "dev_resource_name_mutated").returncode, 0)
        for signature in ("RID RenderingDevice::blas_create(", "RID RenderingDevice::tlas_create("):
            fn = CHECKS.cxx_function(self.rd, signature)
            self.assertIn("#ifdef DEV_ENABLED", fn)
            self.assertIn("set_resource_name(id", fn)

    def test_scope_and_binding_routes(self) -> None:
        metal3 = (self.base / "drivers/metal/rendering_device_driver_metal3.cpp").read_text(encoding="utf-8")
        commands = (self.base / "drivers/metal/metal3_objects.cpp").read_text(encoding="utf-8")
        spirv = (self.base / "thirdparty/spirv-cross/spirv_msl.cpp").read_text(encoding="utf-8")
        self.assertIn('get_environment("GODOT_METAL_TRIANGLE_QUERY") == "1"', metal3)
        self.assertIn("sync_mode = HazardTracking", metal3)
        self.assertIn("setAccelerationStructure(accel->accel.get()", commands)
        self.assertIn("accel->resident_blases", commands)
        self.assertIn("addCompletedHandler", commands)
        self.assertGreaterEqual(spirv.count("case SPIRType::AccelerationStructure:"), 2)
        for sig, create in (("RID RenderingDevice::blas_create(", "driver->blas_create"),
                            ("RID RenderingDevice::tlas_create(", "driver->tlas_create")):
            fn = CHECKS.cxx_function(self.rd, sig)
            self.assertLess(fn.index("!has_feature(SUPPORTS_METAL_TRIANGLE_QUERY)"), fn.index(create))
        for sig in ("RID RenderingDevice::hit_sbt_create(", "RID RenderingDevice::raytracing_pipeline_create("):
            fn = CHECKS.cxx_function(self.rd, sig)
            self.assertIn("!has_feature(SUPPORTS_RAYTRACING_PIPELINE)", fn)
            self.assertNotIn("SUPPORTS_METAL_TRIANGLE_QUERY", fn[:fn.index(";")])

EXPECTED = {
    "off": None,
    "off_blas": "The current rendering device has neither raytracing pipeline nor ray query support.",
    "off_tlas": "The current rendering device has neither raytracing pipeline nor ray query support.",
    "happy": None,
    "bad_bounds": "Metal triangle vertices exceed the vertex buffer.",
    "bad_stride": "Metal triangle queries require non-indexed opaque float3 triangles with aligned offsets and stride.",
    "bad_offset": "Acceleration-structure geometry fields must fit uint32.",
    "bad_capacity": "TLAS capacity must fit uint32.",
    "bad_id": "Invalid Metal triangle-query instance (BLAS, zero SBT, flags, ID, mask, or transform).",
    "bad_mask": "Invalid Metal triangle-query instance (BLAS, zero SBT, flags, ID, mask, or transform).",
    "bad_transform": "Invalid Metal triangle-query instance (singular float32 transform).",
    "bad_sbt": "Invalid Metal triangle-query instance (BLAS, zero SBT, flags, ID, mask, or transform).",
    "bad_flags": "Invalid Metal triangle-query instance (BLAS, zero SBT, flags, ID, mask, or transform).",
    "empty": "Metal triangle-query TLAS is nonempty and can be built only once.",
    "rebuild": "Metal triangle-query TLAS is nonempty and can be built only once.",
    "pipeline": "The current rendering device has no raytracing pipeline support.",
    "sbt": "The current rendering device has no raytracing pipeline support.",
    "ray_list": "The current rendering device has no raytracing pipeline support.",
    "stale_direct": "Metal triangle-query compute dispatch has an invalid or stale TLAS uniform set.",
    "stale_indirect": "Metal triangle-query compute dispatch has an invalid or stale TLAS uniform set.",
    "rebuild_stale": ["Metal triangle-query TLAS is nonempty and can be built only once.", "Metal triangle-query compute dispatch has an invalid or stale TLAS uniform set."],
}

PREFIX = "METAL_TRIANGLE_QUERY "
MAX_LOG_BYTES = 8 * 1024 * 1024
CASE_TIMEOUT_SECONDS = 180
GPU_FAULT = re.compile(r"(?i)(failed assertion|assertion failure|GPU fault|MTLCommandBufferError|shader validation error|metal validation error)")


@contextmanager
def scoped_case_environment(mode: str, case: str):
    """Set only per-process Metal controls; preserve any inherited queue capability."""
    changes = {
        "GODOT_METAL_TRIANGLE_QUERY": None if case.startswith("off") else "1",
        "GODOT_MTL_DISABLE_ARGUMENT_BUFFERS": "1" if mode == "direct" else None,
        "GODOT_MTL_SYNC_MODE": None,
        "MTL_DEBUG_LAYER": "1",
        "MTL_SHADER_VALIDATION": "1",
        "MTL_SHADER_VALIDATION_DEFAULT_STATE": None,
        "MTL_SHADER_VALIDATION_ENABLE_PIPELINES": None,
        "MTL_SHADER_VALIDATION_DISABLE_PIPELINES": None,
        "MTL_SHADER_VALIDATION_REPORT_TO_STDERR": "1",
        "MTL_SHADER_VALIDATION_ABORT_ON_FAULT": "1",
    }
    original = {key: os.environ.get(key) for key in changes}
    try:
        for key, value in changes.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
        yield changes
    finally:
        for key, value in original.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value


def evaluate_checked_case(report: dict, command: list[str], case_dir: Path,
                          mode: str, case: str, expected) -> dict:
    """Evaluate the fixture separately; never rewrite a checked verdict or its evidence."""
    result = {"case": case, "mode": mode, "ok": False, "findings": []}
    findings = result["findings"]
    try:
        if not isinstance(report, dict):
            raise ValueError("checked runner returned an invalid report")
        if report.get("format") != "openrc-godot-check v1" or report.get("command") != command:
            raise ValueError("checked report identity or command differs")
        report_path = Path(report["report"]).resolve(strict=True)
        log_path = Path(report["log"]).resolve(strict=True)
        root = case_dir.resolve(strict=True)
        if (not report_path.is_relative_to(root) or not log_path.is_relative_to(root)
                or report_path.name != "report.json" or log_path.name != "engine.log"
                or report_path.parent != log_path.parent):
            raise ValueError("checked report/log are outside this case's retained evidence directory")
        report_bytes = report_path.read_bytes()
        if json.loads(report_bytes) != report:
            raise ValueError("in-memory and retained checked reports differ")
        if report.get("max_log_bytes") != MAX_LOG_BYTES or report.get("timeout_seconds") != CASE_TIMEOUT_SECONDS \
                or report.get("warnings_as_errors") is not True or report.get("required_text") != [PREFIX]:
            raise ValueError("checked runner policy differs")
        log_bytes = log_path.read_bytes()
        log_hash = hashlib.sha256(log_bytes).hexdigest()
        if len(log_bytes) > MAX_LOG_BYTES or len(log_bytes) != report.get("log_bytes") or log_hash != report.get("log_sha256"):
            raise ValueError("checked log size or digest differs")
        scan = inspect_log(log_path, [PREFIX], max_chars=MAX_LOG_BYTES)
        if any(report.get(key) != scan[key] for key in ("counts", "diagnostics", "missing_required_text")):
            raise ValueError("checked report diagnostics differ from its log")
        if report_path.read_bytes() != report_bytes or hashlib.sha256(log_path.read_bytes()).hexdigest() != log_hash:
            raise ValueError("checked evidence changed while being inspected")
        result["checked"] = {"ok": report.get("ok"), "reason": report.get("reason"),
                             "complete": report.get("complete"), "process_exit": report.get("process_exit"),
                             "report": str(report_path), "report_sha256": hashlib.sha256(report_bytes).hexdigest(),
                             "log": str(log_path), "log_sha256": log_hash}
        if report.get("complete") is not True or report.get("process_exit") != 0:
            findings.append("checked_run_incomplete_or_child_failed")
        if report.get("missing_required_text"):
            findings.append("checked_completion_marker_missing")
        expected_list = expected if isinstance(expected, list) else ([expected] if expected else [])
        counts = report.get("counts", {})
        diagnostics = report.get("diagnostics", [])
        if counts.get("error") != len(expected_list) or counts.get("warning") != 0:
            findings.append("unexpected_diagnostic_count")
        actual = [(d.get("kind"), d.get("message")) for d in diagnostics]
        if actual != [("ERROR", message) for message in expected_list]:
            findings.append("unexpected_diagnostics")
        if expected_list:
            if report.get("ok") is not False or report.get("reason") != "engine_error" or report.get("exit_code") != 1:
                findings.append("intentional_rejection_lost_checked_failure")
        elif report.get("ok") is not True or report.get("reason") != "passed" or report.get("exit_code") != 0:
            findings.append("checked_run_not_ok")
        log = ANSI.sub("", log_bytes.decode("utf-8", errors="replace"))
        lines = [line for line in log.splitlines() if line.startswith(PREFIX)]
        try:
            verdict = json.loads(lines[0][len(PREFIX):]) if len(lines) == 1 else {}
        except (ValueError, IndexError):
            verdict = {}
        result["fixture"] = verdict
        if (not isinstance(verdict, dict) or verdict.get("ok") is not True or verdict.get("case") != case
                or verdict.get("scope") != "local_rendering_device_compute_query" or verdict.get("failures") != []):
            findings.append("fixture_verdict_missing_or_failed")
        binding_modes = re.findall(r"Metal triangle query binding mode: (argument|direct)", log)
        binding_observed = not binding_modes if case.startswith("off") else bool(binding_modes) and set(binding_modes) == {mode}
        result["binding_observed"] = binding_observed
        if not binding_observed:
            findings.append("binding_mode_not_observed")
        if GPU_FAULT.search(log):
            findings.append("gpu_validation_fault")
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
        findings.append("checked_evidence_invalid: " + str(error))
    result["ok"] = not findings
    return result


def run_native_case(command: list[str], output: Path, mode: str, case: str, expected,
                    *, runner=run_checked, admission=None) -> dict:
    """Delegate bounded process ownership and normal host admission to run_checked."""
    case_dir = output / "cases" / (mode + "-" + case)
    try:
        # The queue's generic checked adapter does not admit this custom GPU
        # command. An enrolled host must supply an exclusive rendered grant.
        (admission or require_exclusive)("rendered")
        with scoped_case_environment(mode, case) as controlled:
            report = runner(command, out_dir=case_dir / "checked", timeout=CASE_TIMEOUT_SECONDS,
                            max_log_bytes=MAX_LOG_BYTES, warnings_as_errors=True,
                            required=[PREFIX], label=mode + "-" + case)
        result = evaluate_checked_case(report, command, case_dir, mode, case, expected)
        result["environment"] = controlled
        result["command"] = command
        return result
    except (OSError, ValueError, RuntimeError) as error:
        # Admission/configuration failure has no invented checked verdict and must stop the campaign.
        return {"mode": mode, "case": case, "ok": False,
                "runner_exception": f"{type(error).__name__}: {error}", "command": command}


def native_runner(binary: Path, output: Path, *, runner=run_checked) -> int:
    if sys.platform != "darwin":
        raise SystemExit("Native Metal fixture requires macOS")
    binary = binary.resolve(strict=True)
    output.mkdir(parents=True, exist_ok=False)
    records = []
    fixture = PROBE.read_bytes()
    project = output / "project"
    project.mkdir()
    (project / "project.godot").write_text('config_version=5\n[application]\nconfig/name="Metal Triangle Query"\n[rendering]\nrenderer/rendering_method="mobile"\n', encoding="utf-8")
    (project / "triangle_query_probe.gd").write_bytes(fixture)
    stop = False
    for mode in ("argument", "direct"):
        for case, expected in EXPECTED.items():
            if case.startswith("off") and mode == "direct":
                continue
            command = [str(binary), "--path", str(project.resolve()), "--rendering-method", "mobile", "--rendering-driver", "metal", "--verbose", "--script", "res://triangle_query_probe.gd", "--", f"--case={case}"]
            record = run_native_case(command, output, mode, case, expected, runner=runner)
            records.append(record)
            print(f"{mode}-{case}: {'PASS' if record['ok'] else 'FAIL'}", flush=True)
            if record.get("runner_exception"):
                stop = True
                break
        if stop:
            break
    planned = sum(1 for mode in ("argument", "direct") for case in EXPECTED if not (mode == "direct" and case.startswith("off")))
    manifest = {"binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
                "fixture_sha256": hashlib.sha256(fixture).hexdigest(),
                "patch_sha256": hashlib.sha256(PATCHES[-1].read_bytes()).hexdigest(),
                "checked_runner_sha256": hashlib.sha256((ROOT / "tools/godot/run_checked.py").read_bytes()).hexdigest(),
                "planned_cases": planned, "cases": records,
                "ok": len(records) == planned and all(r["ok"] for r in records)}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return 0 if manifest["ok"] else 1


class NativeRunnerControlTests(unittest.TestCase):
    """Fake checked-runner reports; these tests never start Godot or alter admission."""

    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="openrc-query-runner-")
        self.addCleanup(self.temp.cleanup)
        self.output = Path(self.temp.name)
        self.command = ["fake-godot", "--script", "res://triangle_query_probe.gd"]
        self.environment = {}
        self.report = None
        self.admission_scopes = []

    def fake_admission(self, scope: str) -> None:
        self.admission_scopes.append(scope)

    @staticmethod
    def fixture_log(case: str, mode: str, diagnostics=(), *, marker=True, suffix="") -> str:
        parts = [] if case.startswith("off") else ["Metal triangle query binding mode: " + mode]
        parts.extend(kind + ": " + message for kind, message in diagnostics)
        if marker:
            value = {"case": case, "ok": True, "scope": "local_rendering_device_compute_query", "failures": []}
            parts.append(PREFIX + json.dumps(value))
        if suffix:
            parts.append(suffix)
        return "\n".join(parts) + "\n"

    def fake_runner(self, log: str, *, incomplete=False, change_after_report=False):
        def run(command, *, out_dir, timeout, max_log_bytes, warnings_as_errors, required, label):
            self.assertEqual(timeout, CASE_TIMEOUT_SECONDS)
            self.assertEqual(max_log_bytes, MAX_LOG_BYTES)
            self.assertTrue(warnings_as_errors)
            self.assertEqual(required, [PREFIX])
            self.environment = {k: os.environ.get(k) for k in (
                "OPENRC_TESTQUEUE_CONTEXT", "OPENRC_TESTQUEUE_ROOT", "GODOT_METAL_TRIANGLE_QUERY",
                "GODOT_MTL_DISABLE_ARGUMENT_BUFFERS", "MTL_SHADER_VALIDATION_DEFAULT_STATE", "MTL_SHADER_VALIDATION")}
            directory = Path(out_dir) / "fake-checked"
            directory.mkdir(parents=True)
            log_path = (directory / "engine.log").resolve()
            report_path = (directory / "report.json").resolve()
            log_path.write_text(log, encoding="utf-8")
            raw = log_path.read_bytes()
            scan = inspect_log(log_path, required, max_chars=MAX_LOG_BYTES)
            reason = "timeout" if incomplete else "engine_error" if scan["counts"]["error"] else "warning" if scan["counts"]["warning"] else "missing_required_text" if scan["missing_required_text"] else "passed"
            report = {"format": "openrc-godot-check v1", "command": command, "log": str(log_path),
                      "report": str(report_path), "timeout_seconds": timeout, "max_log_bytes": max_log_bytes,
                      "warnings_as_errors": warnings_as_errors, "required_text": required, "label": label,
                      "process_exit": -9 if incomplete else 0, "complete": not incomplete,
                      "reason": reason, "exit_code": 124 if incomplete else 0 if reason == "passed" else 1,
                      "ok": reason == "passed", "log_bytes": len(raw), "log_sha256": hashlib.sha256(raw).hexdigest(), **scan}
            report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
            self.report = report
            if change_after_report:
                with log_path.open("a", encoding="utf-8") as stream:
                    stream.write("altered\n")
            return report
        return run

    def test_happy_and_off_use_checked_and_restore_environment(self) -> None:
        with mock.patch.dict(os.environ, {"OPENRC_TESTQUEUE_CONTEXT": "fake-capability",
                                         "OPENRC_TESTQUEUE_ROOT": "fake-root",
                                         "GODOT_METAL_TRIANGLE_QUERY": "original",
                                         "MTL_SHADER_VALIDATION_DEFAULT_STATE": "none"}):
            result = run_native_case(self.command, self.output, "argument", "happy", None,
                                     runner=self.fake_runner(self.fixture_log("happy", "argument")), admission=self.fake_admission)
            self.assertTrue(result["ok"], result)
            self.assertTrue(result["checked"]["ok"])
            self.assertEqual(result["checked"]["reason"], "passed")
            self.assertEqual(self.environment["OPENRC_TESTQUEUE_CONTEXT"], "fake-capability")
            self.assertEqual(self.environment["OPENRC_TESTQUEUE_ROOT"], "fake-root")
            self.assertEqual(self.environment["GODOT_METAL_TRIANGLE_QUERY"], "1")
            self.assertIsNone(self.environment["GODOT_MTL_DISABLE_ARGUMENT_BUFFERS"])
            self.assertIsNone(self.environment["MTL_SHADER_VALIDATION_DEFAULT_STATE"])
            self.assertEqual(os.environ["GODOT_METAL_TRIANGLE_QUERY"], "original")
            self.assertEqual(os.environ["MTL_SHADER_VALIDATION_DEFAULT_STATE"], "none")
            result = run_native_case(self.command, self.output, "argument", "off", None,
                                     runner=self.fake_runner(self.fixture_log("off", "argument")), admission=self.fake_admission)
            self.assertTrue(result["ok"], result)
            self.assertTrue(result["checked"]["ok"])
            self.assertIsNone(self.environment["GODOT_METAL_TRIANGLE_QUERY"])
            self.assertEqual(self.admission_scopes, ["rendered", "rendered"])

    def test_expected_rejection_preserves_failing_checked_verdict(self) -> None:
        case = "bad_stride"
        log = self.fixture_log(case, "direct", [("ERROR", EXPECTED[case])])
        result = run_native_case(self.command, self.output, "direct", case, EXPECTED[case], runner=self.fake_runner(log), admission=self.fake_admission)
        self.assertTrue(result["ok"], result)
        self.assertFalse(result["checked"]["ok"])
        self.assertEqual(result["checked"]["reason"], "engine_error")
        self.assertEqual(self.environment["GODOT_MTL_DISABLE_ARGUMENT_BUFFERS"], "1")
        retained = json.loads(Path(result["checked"]["report"]).read_text(encoding="utf-8"))
        self.assertFalse(retained["ok"])
        self.assertEqual(retained["reason"], "engine_error")
        self.assertEqual(retained, self.report)

    def test_extra_script_or_shader_errors_cannot_pass(self) -> None:
        case = "bad_stride"
        for kind in ("SCRIPT ERROR", "SHADER ERROR"):
            with self.subTest(kind=kind):
                output = self.output / kind.replace(" ", "_")
                log = self.fixture_log(case, "direct", [("ERROR", EXPECTED[case]), (kind, "unexpected")])
                result = run_native_case(self.command, output, "direct", case, EXPECTED[case], runner=self.fake_runner(log), admission=self.fake_admission)
                self.assertFalse(result["ok"])
                self.assertEqual(result["checked"]["reason"], "engine_error")
                self.assertIn("unexpected_diagnostic_count", result["findings"])
        log = self.fixture_log(case, "direct", [("SCRIPT ERROR", EXPECTED[case])])
        result = run_native_case(self.command, self.output / "wrong-kind", "direct", case, EXPECTED[case], runner=self.fake_runner(log), admission=self.fake_admission)
        self.assertFalse(result["ok"])
        self.assertIn("unexpected_diagnostics", result["findings"])

    def test_timeout_and_incomplete_capture_fail_even_with_expected_marker(self) -> None:
        case = "bad_stride"
        log = self.fixture_log(case, "direct", [("ERROR", EXPECTED[case])])
        result = run_native_case(self.command, self.output, "direct", case, EXPECTED[case], runner=self.fake_runner(log, incomplete=True), admission=self.fake_admission)
        self.assertFalse(result["ok"])
        self.assertEqual(result["checked"]["reason"], "timeout")
        self.assertFalse(result["checked"]["complete"])
        self.assertIn("checked_run_incomplete_or_child_failed", result["findings"])

    def test_changed_evidence_wrong_mode_and_gpu_fault_fail(self) -> None:
        log = self.fixture_log("happy", "argument")
        result = run_native_case(self.command, self.output / "changed", "argument", "happy", None,
                                 runner=self.fake_runner(log, change_after_report=True), admission=self.fake_admission)
        self.assertFalse(result["ok"])
        self.assertTrue(any("checked log size or digest differs" in item for item in result["findings"]))
        wrong_mode = self.fixture_log("happy", "direct")
        result = run_native_case(self.command, self.output / "mode", "argument", "happy", None,
                                 runner=self.fake_runner(wrong_mode), admission=self.fake_admission)
        self.assertFalse(result["ok"])
        self.assertIn("binding_mode_not_observed", result["findings"])
        gpu_fault = self.fixture_log("happy", "argument", suffix="GPU fault: injected")
        result = run_native_case(self.command, self.output / "gpu", "argument", "happy", None,
                                 runner=self.fake_runner(gpu_fault), admission=self.fake_admission)
        self.assertFalse(result["ok"])
        self.assertIn("gpu_validation_fault", result["findings"])

    def test_admission_failure_is_not_a_fixture_verdict(self) -> None:
        def reject(scope):
            self.assertEqual(scope, "rendered")
            raise ValueError("admission refused")
        result = run_native_case(self.command, self.output, "argument", "happy", None,
                                 runner=self.fake_runner(self.fixture_log("happy", "argument")), admission=reject)
        self.assertFalse(result["ok"])
        self.assertIn("admission refused", result["runner_exception"])
        self.assertNotIn("checked", result)
        self.assertIsNone(self.report, "runner must not launch after admission refusal")

    def test_default_admission_checks_exclusive_grant(self) -> None:
        log = self.fixture_log("happy", "argument")
        with mock.patch("tools.testqueue.common.enabled", return_value=True), \
                mock.patch("tools.testqueue.common.inherited", side_effect=lambda scope: scope == "rendered") as inherited:
            result = run_native_case(self.command, self.output / "refused", "argument", "happy", None,
                                     runner=self.fake_runner(log))
        self.assertFalse(result["ok"])
        self.assertIn("exclusive inherited", result["runner_exception"])
        self.assertEqual(inherited.call_args_list, [mock.call("rendered"), mock.call("performance")])
        self.assertIsNone(self.report, "a nonexclusive grant must not launch the runner")
        with mock.patch("tools.testqueue.common.enabled", return_value=True), \
                mock.patch("tools.testqueue.common.inherited", return_value=True) as inherited:
            result = run_native_case(self.command, self.output / "admitted", "argument", "happy", None,
                                     runner=self.fake_runner(log))
        self.assertTrue(result["ok"], result)
        self.assertEqual(inherited.call_args_list, [mock.call("rendered"), mock.call("performance")])

if __name__ == "__main__":
    if "--native" in sys.argv:
        parser = argparse.ArgumentParser(description="Run each query case in a fresh native Metal process")
        parser.add_argument("--native", type=Path, required=True, help="Source-bound patched Godot editor binary")
        parser.add_argument("--out", type=Path, required=True, help="New evidence directory")
        args = parser.parse_args()
        raise SystemExit(native_runner(args.native, args.out))
    unittest.main()
