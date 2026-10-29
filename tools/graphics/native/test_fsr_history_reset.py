"""Offline checks of the native FSR reset state and the ordered engine patch.

These exercise the real dispatch functions with a fake SDK. They do not create a
rendering device or establish rendered, synchronization, or GPU correctness.
The FSR2 and patch-stack checks use the already downloaded pinned engine ZIP.
"""
from __future__ import annotations

import hashlib
import importlib.util
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest
import zipfile


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
OUTPUT = ROOT / "tmp/fsr-history-agent"
SPEC = importlib.util.spec_from_file_location("native_build_fsr_test", HERE / "build.py")
assert SPEC is not None and SPEC.loader is not None
BUILD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILD)


def between(source: str, begin: str, end: str) -> str:
    if source.count(begin) != 1 or source.count(end) != 1:
        raise AssertionError(f"Expected exactly one {begin} / {end} section")
    return source[source.index(begin):source.index(end) + len(end)]


def function(source: str, signature: str) -> str:
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 0
    for pos in range(opening, len(source)):
        if source[pos] == "{":
            depth += 1
        elif source[pos] == "}":
            depth -= 1
            if depth == 0:
                return source[start:pos + 1]
    raise AssertionError(f"Unterminated function {signature}")


def compile_and_run(program: str, directory: Path, name: str) -> None:
    compiler = shutil.which("g++") or shutil.which("clang++")
    if not compiler:
        raise unittest.SkipTest("A C++ compiler is required for the offline SDK mock")
    source = directory / f"{name}.cpp"
    executable = directory / (f"{name}.exe" if os.name == "nt" else name)
    source.write_text(program, encoding="utf-8")
    result = subprocess.run([compiler, "-std=c++17", "-Wall", "-Wextra", "-Werror", "-Wno-unused-parameter", str(source), "-o", str(executable)],
                            capture_output=True)
    if result.returncode:
        raise AssertionError(f"{name} compile failed:\n{result.stderr.decode(errors='replace')}")
    result = subprocess.run([str(executable)], capture_output=True)
    if result.returncode:
        raise AssertionError(f"{name} failed ({result.returncode}):\n{result.stderr.decode(errors='replace')}")


FSR2_STUB = r"""
#include <atomic>
#include <cassert>
#include <cstdint>
#include <map>
#include <string>
#include <vector>
struct RID { uint64_t id = 1; uint64_t get_id() const { return id; } bool is_null() const { return id == 0; } bool is_valid() const { return id != 0; } };
struct Projection {};
struct Size { union { int width = 1; int x; }; union { int height = 1; int y; }; };
struct Vec { float x = 0, y = 0; };
struct Dictionary { std::map<std::string, int64_t> values; int64_t &operator[](const char *key) { return values[key]; } };
struct RendererViewport { static uint64_t get_temporal_history_reset_requests() { return 12; } };
struct RD {
    inline static RD *singleton = nullptr;
    uint64_t invalid_texture = 0;
    std::vector<uint64_t> freed;
    static RD *get_singleton() { return singleton; }
    bool texture_is_valid(RID rid) { return rid.is_valid() && rid.id != invalid_texture; }
    void free_rid(RID rid) { freed.push_back(rid.id); }
};
using RenderingDevice = RD;
struct FfxResource {};
FfxResource get_resource_rd(RID *, const wchar_t *) { return {}; }
struct FfxFsr2DispatchDescription {
    void *commandList = nullptr;
    FfxResource color, depth, motionVectors, reactive, exposure, transparencyAndComposition, output, colorOpaqueOnly;
    Vec jitterOffset, motionVectorScale;
    Size renderSize;
    bool reset = false, enableSharpening = false, enableAutoReactive = false;
    float sharpness = 0, frameTimeDelta = 0, preExposure = 0, cameraNear = 0, cameraFar = 0;
    float cameraFovAngleVertical = 0, viewSpaceToMetersFactor = 0;
    float autoTcThreshold = 0, autoTcScale = 0, autoReactiveScale = 0, autoReactiveMax = 0;
    float reprojectionMatrix[16] = {};
};
using FfxErrorCode = int;
const int FFX_OK = 0;
bool sdk_reset = false;
int sdk_result = FFX_OK;
int sdk_backend_result = FFX_OK, sdk_calls = 0;
const int FFX_ERROR_INVALID_ARGUMENT = 1;
const int FFX_ERROR_INVALID_POINTER = 2, FFX_ERROR_INVALID_SIZE = 3;
using FfxCommandList = void *;
enum { FFX_GPU_JOB_CLEAR_FLOAT, FFX_GPU_JOB_COPY, FFX_GPU_JOB_COMPUTE };
struct FfxGpuJobDescription { int jobType = FFX_GPU_JOB_COMPUTE, clearJobDescriptor = 0, copyJobDescriptor = 0, computeJobDescriptor = 0; };
struct FfxFsr2Interface { void *scratchBuffer = nullptr; };
struct FakeFfxContext { FfxFsr2Interface callbacks; };
#define ERR_FAIL_NULL_V(x, result) do { if (!(x)) return result; } while (false)
#define ERR_FAIL_COND_V(x, result) do { if (x) return result; } while (false)
#define WARN_PRINT(...) do {} while (false)
namespace RendererRD {
"""

FSR2_AFTER_STATE = r"""
struct FSR2Context {
    struct Scratch { std::vector<FfxGpuJobDescription> gpu_jobs; FfxErrorCode dispatch_error = FFX_OK; } scratch;
    FakeFfxContext fsr_context;
    FSR2HistoryResetState history_reset;
    FSR2Context() { fsr_context.callbacks.scratchBuffer = &scratch; }
};
struct MaterialStorage { static void store_camera(const Projection &, float *) {} };
class FSR2Effect {
public:
    struct Parameters {
        FSR2Context *context = nullptr;
        Size internal_size;
        RID color, depth, velocity, reactive, exposure, output;
        float z_near = 0, z_far = 0, fovy = 0;
        Vec jitter;
        float delta_time = 0, sharpness = 0;
        bool reset_accumulation = false;
        uint64_t history_reset_generation = 0;
        RID history_reset_viewport;
        uint32_t history_reset_view = 0;
        Projection reprojection;
    };
    static Dictionary get_status();
    bool upscale(const Parameters &);
};
}
using namespace RendererRD;
FfxErrorCode execute_gpu_job_clear_float_rd(FSR2Context::Scratch &, int) { return sdk_backend_result; }
FfxErrorCode execute_gpu_job_copy_rd(FSR2Context::Scratch &, int) { return sdk_backend_result; }
FfxErrorCode execute_gpu_job_compute_rd(FSR2Context::Scratch &, int) { return sdk_backend_result; }
"""

FSR2_AFTER_EXECUTION = r"""
FfxErrorCode ffxFsr2ContextDispatch(FakeFfxContext *context, FfxFsr2DispatchDescription *description) {
    ++sdk_calls;
    sdk_reset = description->reset;
    auto *scratch = static_cast<FSR2Context::Scratch *>(context->callbacks.scratchBuffer);
    scratch->gpu_jobs.push_back({});
    // The bundled SDK discards this backend return and reports sdk_result instead.
    (void)execute_gpu_jobs_rd(&context->callbacks, nullptr);
    return sdk_result;
}
"""

FSR2_MAIN = r"""
int main() {
    RD rd; RD::singleton = &rd;
    FSR2Effect effect;
    FSR2Context left, right;
    FSR2Effect::Parameters p;
    p.context = &left; p.history_reset_viewport.id = 42;
    assert(effect.upscale(p) && sdk_reset);
    assert(effect.upscale(p) && !sdk_reset);
    p.context = &right; p.history_reset_view = 1;
    assert(effect.upscale(p) && sdk_reset);
    p.context = &left; p.history_reset_view = 0; p.history_reset_generation = 3;
    sdk_result = 7;
    auto before = fsr2_reset_dispatches.load();
    assert(!effect.upscale(p) && sdk_reset);
    assert(fsr2_reset_dispatches.load() == before);
    Dictionary failed_status = FSR2Effect::get_status();
    assert(failed_status["backend_failed"] && failed_status["last_return_code"] == 7);
    sdk_result = FFX_OK;
    int calls_before_retry = sdk_calls;
    assert(!effect.upscale(p) && sdk_calls == calls_before_retry); // Failure is latched.
    fsr2_backend_failed.store(false); // Simulate a fresh process for independent cases.
    sdk_backend_result = 5; // SDK returns OK despite a failed backend job.
    assert(!effect.upscale(p) && sdk_reset);
    assert(fsr2_reset_dispatches.load() == before);
    failed_status = FSR2Effect::get_status();
    assert(failed_status["backend_failed"] && failed_status["last_return_code"] == 5);
    calls_before_retry = sdk_calls;
    sdk_backend_result = FFX_OK;
    assert(!effect.upscale(p) && sdk_calls == calls_before_retry);
    fsr2_backend_failed.store(false);
    p.color.id = 0;
    auto calls_before_invalid = sdk_calls;
    assert(!effect.upscale(p) && sdk_calls == calls_before_invalid);
    assert(FSR2Effect::get_status()["backend_failed"] && FSR2Effect::get_status()["last_return_code"] == FFX_ERROR_INVALID_ARGUMENT);
    fsr2_backend_failed.store(false);
    p.color.id = 1;
    rd.invalid_texture = 1;
    assert(!effect.upscale(p) && sdk_calls == calls_before_invalid && fsr2_backend_failed.load());
    rd.invalid_texture = 0; fsr2_backend_failed.store(false);
    p.context = &right; p.history_reset_view = 1;
    assert(effect.upscale(p) && sdk_reset);
    assert(fsr2_last_reset_viewport.load() == 42 && fsr2_last_reset_view.load() == 1);
    assert(effect.upscale(p) && !sdk_reset);
    p.context = &left; p.history_reset_view = 0;
    assert(effect.upscale(p) && sdk_reset);
    assert(effect.upscale(p) && !sdk_reset);
    p.history_reset_generation = 2; // A stale completion cannot roll history backward.
    assert(effect.upscale(p) && !sdk_reset);
    p.history_reset_generation = 3; p.reset_accumulation = true;
    assert(effect.upscale(p) && sdk_reset);
    p.reset_accumulation = false;
    assert(effect.upscale(p) && !sdk_reset);
    FSR2Context replacement;
    p.context = &replacement;
    assert(effect.upscale(p) && sdk_reset);
    assert(fsr2_dispatches_succeeded.load() == uint64_t(sdk_calls - 2));
}
"""

FSR2_RESOURCE_STUB = r"""
#include <cassert>
#include <cstdint>
#include <vector>
using FfxErrorCode = int;
constexpr int FFX_OK = 0, FFX_ERROR_INVALID_ARGUMENT = 1, FFX_ERROR_BACKEND_API_ERROR = 2;
constexpr int FFX_RESOURCE_TYPE_BUFFER = 0, OK = 0;
struct RID {};
struct Color { Color(float, float, float, float) {} };
struct Vector3 { Vector3(int, int, int) {} };
struct FfxResourceDescription { int type = 1; uint32_t mipCount = 2, width = 4, height = 4, depth = 1; };
struct ResourceIndex { int internalIndex = 0; };
struct FfxClearFloatJobDescription { ResourceIndex target; float color[4] = {}; };
struct FfxCopyJobDescription { ResourceIndex src, dst; };
struct FSR2Context {
    struct Scratch { struct { std::vector<RID> rids = std::vector<RID>(2); std::vector<FfxResourceDescription> descriptions = std::vector<FfxResourceDescription>(2); } resources; };
};
struct RD {
    int clear_result = OK, copy_result = OK, copy_calls = 0;
    static RD *get_singleton() { static RD rd; return &rd; }
    int texture_clear(RID, Color, int, uint32_t, int, int) { return clear_result; }
    int texture_copy(RID, RID, Vector3, Vector3, Vector3, uint32_t, uint32_t, int, int) { ++copy_calls; return copy_result; }
};
#define ERR_FAIL_COND_V(x, result) do { if (x) return result; } while (false)
"""

FSR2_RESOURCE_MAIN = r"""
int main() {
    FSR2Context::Scratch scratch;
    FfxClearFloatJobDescription clear;
    FfxCopyJobDescription copy; copy.dst.internalIndex = 1;
    RD *rd = RD::get_singleton();
    assert(execute_gpu_job_clear_float_rd(scratch, clear) == FFX_OK);
    rd->clear_result = 7;
    assert(execute_gpu_job_clear_float_rd(scratch, clear) == FFX_ERROR_BACKEND_API_ERROR);
    rd->copy_result = 7;
    assert(execute_gpu_job_copy_rd(scratch, copy) == FFX_ERROR_BACKEND_API_ERROR && rd->copy_calls == 1);
    rd->copy_result = OK; rd->copy_calls = 0;
    assert(execute_gpu_job_copy_rd(scratch, copy) == FFX_OK && rd->copy_calls == 2);
}
"""

FSR2_CREATE_STUB = r"""
#include <atomic>
#include <cassert>
#include <cstdint>
#include <map>
#include <string>
#include <vector>
struct RID { uint64_t id = 0; bool is_valid() const { return id != 0; } };
struct Size2i { int x = 100, y = 80; };
struct Dictionary { std::map<std::string, int64_t> values; int64_t &operator[](const char *key) { return values[key]; } };
struct RendererViewport { static uint64_t get_temporal_history_reset_requests() { return 0; } };
struct RD {
    inline static RD *singleton = nullptr;
    std::vector<uint64_t> freed;
    static RD *get_singleton() { return singleton; }
    void free_rid(RID rid) { freed.push_back(rid.id); }
};
using RenderingDevice = RD;
using FfxErrorCode = int;
constexpr int FFX_OK = 0, FFX_ERROR_INVALID_SIZE = 3;
constexpr int FFX_FSR2_ENABLE_HIGH_DYNAMIC_RANGE = 1, FFX_FSR2_ENABLE_DEPTH_INVERTED = 2;
struct FakeFfxContext {};
struct FfxFsr2Interface {
    void (*fpCreateBackendContext)() = nullptr, (*fpGetDeviceCapabilities)() = nullptr, (*fpDestroyBackendContext)() = nullptr;
    void (*fpCreateResource)() = nullptr, (*fpRegisterResource)() = nullptr, (*fpUnregisterResources)() = nullptr;
    void (*fpGetResourceDescription)() = nullptr, (*fpDestroyResource)() = nullptr, (*fpCreatePipeline)() = nullptr;
    void (*fpDestroyPipeline)() = nullptr, (*fpScheduleGpuJob)() = nullptr, (*fpExecuteGpuJobs)() = nullptr;
    void *scratchBuffer = nullptr; size_t scratchBufferSize = 0;
};
struct FfxFsr2ContextDescription {
    int flags = 0;
    struct { int width = 0, height = 0; } maxRenderSize, displaySize;
    void *device = nullptr;
    FfxFsr2Interface callbacks;
};
void create_backend_context_rd() {} void get_device_capabilities_rd() {} void destroy_backend_context_rd() {}
void create_resource_rd() {} void register_resource_rd() {} void unregister_resources_rd() {}
void get_resource_description_rd() {} void destroy_resource_rd() {} void create_pipeline_rd() {}
void destroy_pipeline_rd() {} void schedule_gpu_job_rd() {} void execute_gpu_jobs_rd() {}
#define WARN_PRINT(...) do {} while (false)
#define memnew(T) new T
#define memdelete(T) delete (T)
namespace RendererRD {
struct FSR2Context {
    struct Scratch { struct { std::vector<RID> rids; } resources; RID ubo_ring_buffer[4] = {}; } scratch;
    FakeFfxContext fsr_context = {};
    FfxFsr2ContextDescription fsr_desc = {};
    bool fsr_context_created = false;
    ~FSR2Context();
};
class FSR2Effect {
    int device = 0;
public:
    static Dictionary get_status();
    FSR2Context *create_context(Size2i, Size2i);
};
}
using namespace RendererRD;
int create_calls = 0, destroy_calls = 0;
bool fail_create = true;
FfxErrorCode ffxFsr2ContextCreate(FakeFfxContext *, FfxFsr2ContextDescription *description) {
    ++create_calls;
    auto *scratch = static_cast<FSR2Context::Scratch *>(description->callbacks.scratchBuffer);
    scratch->ubo_ring_buffer[0] = RID{101}; scratch->ubo_ring_buffer[1] = RID{102};
    scratch->resources.rids = {RID{201}, RID{}, RID{202}};
    return fail_create ? 9 : FFX_OK;
}
void ffxFsr2ContextDestroy(FakeFfxContext *) { ++destroy_calls; }
"""

FSR2_CREATE_MAIN = r"""
int main() {
    RD rd; RD::singleton = &rd;
    FSR2Effect effect;
    assert(effect.create_context({}, {}) == nullptr);
    assert(FSR2Effect::get_status()["backend_failed"] && FSR2Effect::get_status()["last_return_code"] == 9);
    assert(create_calls == 1 && destroy_calls == 0);
    assert((rd.freed == std::vector<uint64_t>{201, 202, 101, 102}));
    fail_create = false;
    assert(effect.create_context({}, {}) == nullptr && create_calls == 1); // No retry after failure.
    fsr2_backend_failed.store(false); // Simulate a new process for the success path.
    FSR2Context *context = effect.create_context({}, {});
    assert(context && context->fsr_context_created && create_calls == 2);
    delete context;
    assert(destroy_calls == 1 && rd.freed.size() == 4); // Successful contexts use SDK destruction.
    fsr2_backend_failed.store(false);
    assert(effect.create_context({0, 80}, {}) == nullptr && create_calls == 2);
    assert(FSR2Effect::get_status()["backend_failed"] && FSR2Effect::get_status()["last_return_code"] == FFX_ERROR_INVALID_SIZE);
}
"""


FSR3_STUB = r"""
#include <atomic>
#include <cassert>
#include <cstdint>
struct RID { uint64_t id = 0; uint64_t get_id() const { return id; } };
struct Size { int x = 1, y = 1; };
struct Vec { float x = 0, y = 0; };
struct FfxApiResource {};
namespace RDD { using CommandBufferID = int; }
struct RenderingDeviceDriver { void *command_buffer_get_native_handle(int) { return nullptr; } };
struct Header { int type = 0; };
struct ffxDispatchDescUpscale {
    Header header;
    void *commandList = nullptr;
    FfxApiResource color, depth, motionVectors, exposure, reactive, output;
    Vec jitterOffset, motionVectorScale;
    struct Dims { uint32_t x, y; } renderSize, upscaleSize;
    bool enableSharpening = false, reset = false;
    float sharpness = 0, frameTimeDelta = 0, preExposure = 0;
    float cameraNear = 0, cameraFar = 0, cameraFovAngleVertical = 0, viewSpaceToMetersFactor = 0;
};
constexpr int FFX_API_DISPATCH_DESC_TYPE_UPSCALE = 1;
constexpr uint32_t FFX_API_RETURN_OK = 0;
using ffxReturnCode_t = uint32_t;
struct Math { static float deg_to_rad(float value) { return value; } };
bool sdk_reset = false;
uint32_t sdk_result = 0;
int sdk_calls = 0, released = 0;
uint32_t fake_dispatch(int *, Header *header) {
    ++sdk_calls;
    sdk_reset = reinterpret_cast<ffxDispatchDescUpscale *>(header)->reset;
    return sdk_result;
}
struct FSR3Api { decltype(&fake_dispatch) dispatch = fake_dispatch; };
FSR3Api &get_fsr3_api() { static FSR3Api api; return api; }
static std::atomic<bool> backend_failed{false};
static std::atomic<uint64_t> dispatches_succeeded{0}, reset_dispatches{0}, last_reset_viewport{0};
static std::atomic<uint32_t> last_return_code{0};
void record_backend_failure(uint32_t) { backend_failed.store(true); }
#define WARN_PRINT(...) do {} while (false)
#define memdelete(x) delete (x)
namespace RendererRD {
"""

FSR3_AFTER_STATE = r"""
struct FSR3ContextInternal {
    int context = 0;
    Size target_size;
    std::atomic<bool> failed{false}, has_successful_dispatch{false};
    FSR3HistoryResetState history_reset;
};
struct FSR3Context {
    struct Parameters {
        Size internal_size;
        float z_near = 0, z_far = 0, fovy = 0;
        Vec jitter;
        float delta_time = 0, sharpness = 0;
        bool reset_accumulation = false;
        uint64_t history_reset_generation = 0;
        RID history_reset_viewport;
    };
};
class FSR3Effect {
public:
    struct DispatchPayload;
    static void _dispatch_graph_callback(RenderingDeviceDriver *, RDD::CommandBufferID, void *);
};
struct FSR3Effect::DispatchPayload {
    FSR3ContextInternal *context = nullptr;
    FSR3Context::Parameters parameters;
    FfxApiResource color, depth, velocity, reactive, exposure, output;
};
void release_context_internal(FSR3ContextInternal *, bool) { ++released; }
"""

FSR3_MAIN = r"""
void invoke(FSR3ContextInternal &context, uint64_t generation, uint64_t viewport = 7) {
    auto *payload = new FSR3Effect::DispatchPayload;
    payload->context = &context;
    payload->parameters.history_reset_generation = generation;
    payload->parameters.history_reset_viewport.id = viewport;
    RenderingDeviceDriver driver;
    FSR3Effect::_dispatch_graph_callback(&driver, 0, payload);
}
}
int main() {
    using namespace RendererRD;
    FSR3ContextInternal a, b;
    invoke(a, 0); assert(sdk_reset);
    invoke(a, 0); assert(!sdk_reset);
    invoke(b, 0, 9); assert(sdk_reset && last_reset_viewport.load() == 9);
    // Captured older and newer frame generations are handled in callback order.
    invoke(a, 1); assert(sdk_reset);
    invoke(a, 1); assert(!sdk_reset);
    invoke(a, 2); assert(sdk_reset);
    invoke(a, 1); assert(!sdk_reset);
    auto resets = reset_dispatches.load();
    auto successes = dispatches_succeeded.load();
    sdk_result = 7;
    invoke(a, 3); assert(sdk_reset);
    assert(a.history_reset.should_reset(3));
    assert(reset_dispatches.load() == resets && dispatches_succeeded.load() == successes);
    int calls = sdk_calls;
    sdk_result = 0;
    invoke(a, 3); // Already queued after the failed callback: no SDK call or acknowledgement.
    assert(sdk_calls == calls && a.history_reset.should_reset(3));
    invoke(b, 1); // The backend failure is global, even for another context.
    assert(sdk_calls == calls && b.history_reset.should_reset(1));
    assert(released == 10);
    backend_failed.store(false);
    FSR3ContextInternal replacement;
    invoke(replacement, 3); assert(sdk_reset);
    invoke(replacement, 3); assert(!sdk_reset);
}
"""

FSR3_PREP_STUB = r"""
#include <atomic>
#include <cassert>
#include <cstdint>
#include <cstring>
struct RID {
    uint64_t id = 0;
    bool is_null() const { return id == 0; }
    bool operator==(const RID &other) const { return id == other.id; }
};
struct Size {
    int x = 100, y = 80;
    bool operator!=(const Size &other) const { return x != other.x || y != other.y; }
};
struct Projection { struct Column { float x, y, z, w; } columns[4] = {}; };
constexpr int FFX_API_RETURN_ERROR_RUNTIME_ERROR = 1;
constexpr uint64_t FFX_API_QUERY_RESOURCE_INPUT_REACTIVEMASK = 16;
std::atomic<bool> backend_failed{false};
int failures = 0;
void record_backend_failure(uint32_t) { ++failures; backend_failed.store(true); }
void collect_retired_contexts() {}
#define WARN_PRINT(...) do {} while (false)
struct RD {
    using ComputeListID = int;
    static constexpr int INVALID_ID = -1;
    enum { UNIFORM_TYPE_IMAGE, UNIFORM_TYPE_TEXTURE };
    struct Uniform { Uniform(int, int, RID) {} };
    inline static RD *singleton = nullptr;
    uint64_t invalid_texture = 0, invalid_pipeline = 0, invalid_uniform = 0;
    bool fail_begin = false;
    int begins = 0, dispatches = 0, ends = 0, bound_pipeline = 0, bound_sets = 0;
    static RD *get_singleton() { return singleton; }
    bool texture_is_valid(RID rid) { return !rid.is_null() && rid.id != invalid_texture; }
    bool compute_pipeline_is_valid(RID rid) { return !rid.is_null() && rid.id != invalid_pipeline; }
    bool uniform_set_is_valid(RID rid) { return !rid.is_null() && rid.id != invalid_uniform; }
    ComputeListID compute_list_begin() { ++begins; return fail_begin ? INVALID_ID : 1; }
    void compute_list_bind_compute_pipeline(ComputeListID, RID rid) { bound_pipeline = int(rid.id); }
    void compute_list_bind_uniform_set(ComputeListID, RID, int) { ++bound_sets; }
    void compute_list_set_push_constant(ComputeListID, const float *, size_t) {}
    void compute_list_dispatch_threads(ComputeListID, int, int, int) { ++dispatches; }
    void compute_list_end() { ++ends; }
};
using RenderingDevice = RD;
struct UniformSetCacheRD {
    inline static UniformSetCacheRD *singleton = nullptr;
    int null_set = -1;
    static UniformSetCacheRD *get_singleton() { return singleton; }
    template <typename... Args> RID get_cache(RID, int set, const Args &...) {
        return set == null_set ? RID{} : RID{uint64_t(30 + set)};
    }
};
struct FSR3ContextInternal {
    std::atomic<bool> failed{false};
    uint64_t required_resources = 0;
    Size internal_size;
    RID reactive_mask{5};
};
struct FSR3Context {
    FSR3ContextInternal *internal = nullptr;
    struct Parameters {
        FSR3Context *context = nullptr;
        Size internal_size;
        RID color{1}, depth{2}, velocity{3}, output{4}, reactive;
        Projection reprojection;
    };
};
struct FakePrepare {
    bool missing_shader = false;
    RID version_get_shader(RID, uint32_t variant) { return missing_shader ? RID{} : RID{uint64_t(20 + variant)}; }
};
class FSR3Effect {
public:
    struct { RID prepare_version{10}; FakePrepare prepare; RID prepare_pipeline[2] = {{11}, {12}}; } shaders;
    void upscale(const FSR3Context::Parameters &);
};
"""

FSR3_PREP_MAIN = r"""
struct Fixture {
    RD rd;
    UniformSetCacheRD cache;
    FSR3ContextInternal internal;
    FSR3Context context;
    FSR3Context::Parameters params;
    FSR3Effect effect;
    Fixture() {
        backend_failed.store(false); failures = 0;
        RD::singleton = &rd; UniformSetCacheRD::singleton = &cache;
        context.internal = &internal; params.context = &context;
    }
    void failed(bool begin_attempted = false) {
        effect.upscale(params);
        assert(backend_failed.load() && internal.failed.load() && failures == 1);
        assert(rd.begins == int(begin_attempted) && rd.dispatches == 0 && rd.ends == 0);
        effect.upscale(params); // A latched failure never retries preparation.
        assert(failures == 1 && rd.begins == int(begin_attempted));
    }
    void passed(int variant) {
        effect.upscale(params);
        assert(!backend_failed.load() && !internal.failed.load() && failures == 0);
        assert(rd.begins == 1 && rd.dispatches == 1 && rd.ends == 1 && rd.bound_sets == 2);
        assert(rd.bound_pipeline == 11 + variant);
    }
};
int main() {
    { Fixture f; f.params.context = nullptr; f.effect.upscale(f.params); assert(backend_failed.load() && failures == 1 && !f.internal.failed.load()); }
    { Fixture f; f.context.internal = nullptr; f.effect.upscale(f.params); assert(backend_failed.load() && failures == 1); }
    { Fixture f; f.params.color = {}; f.failed(); }
    { Fixture f; f.params.depth = {}; f.failed(); }
    { Fixture f; f.params.velocity = {}; f.failed(); }
    { Fixture f; f.params.output = {}; f.failed(); }
    { Fixture f; f.params.output = f.params.color; f.failed(); }
    { Fixture f; f.params.internal_size.x = 0; f.failed(); }
    { Fixture f; f.params.internal_size.x++; f.failed(); }
    for (uint64_t id = 1; id <= 5; ++id) { Fixture f; f.rd.invalid_texture = id; f.failed(); }
    { Fixture f; f.params.reactive = RID{6}; f.rd.invalid_texture = 6; f.failed(); }
    { Fixture f; RD::singleton = nullptr; f.failed(); }
    { Fixture f; UniformSetCacheRD::singleton = nullptr; f.failed(); }
    { Fixture f; f.effect.shaders.prepare_version = {}; f.failed(); }
    { Fixture f; f.rd.invalid_pipeline = 11; f.failed(); }
    { Fixture f; f.rd.invalid_pipeline = 12; f.failed(); } // Inactive variant still gates readiness.
    { Fixture f; f.effect.shaders.prepare.missing_shader = true; f.failed(); }
    { Fixture f; f.cache.null_set = 0; f.failed(); }
    { Fixture f; f.cache.null_set = 1; f.failed(); }
    { Fixture f; f.params.reactive = RID{6}; f.rd.invalid_uniform = 31; f.failed(); }
    { Fixture f; f.rd.fail_begin = true; f.failed(true); }
#if defined(FFX_UPSCALER_VERSION_MAJOR) && FFX_UPSCALER_VERSION_MAJOR >= 4
    { Fixture f; f.internal.required_resources = FFX_API_QUERY_RESOURCE_INPUT_REACTIVEMASK; f.failed(); }
#endif
    { Fixture f; f.passed(0); }
    { Fixture f; f.params.reactive = RID{6}; f.passed(1); }
}
"""

FSR3_CREATE_STUB = r"""
#include <atomic>
#include <cassert>
#include <cstdint>
#include <mutex>
#include <string>
#include <vector>
struct RID { uint64_t id = 0; bool is_null() const { return id == 0; } };
struct Size2i { int x = 100, y = 80; };
struct CharString { std::string value; const char *get_data() const { return value.c_str(); } };
struct String {
    std::string value;
    String(const char *s = "") : value(s) {}
    String strip_edges() const { return *this; }
    String to_lower() const { return *this; }
    bool is_empty() const { return value.empty(); }
    bool operator==(const char *s) const { return value == s; }
    bool operator!=(const char *s) const { return value != s; }
    CharString utf8() const { return {value}; }
};
struct OS { static OS *get_singleton() { static OS os; return &os; } String get_environment(const char *) { return "auto"; } };
struct Header { uint64_t type = 0; Header *pNext = nullptr; };
using VkDevice = void *;
using VkPhysicalDevice = void *;
using ffxContext = void *;
using ffxReturnCode_t = uint32_t;
constexpr uint32_t FFX_API_RETURN_OK = 0, FFX_API_RETURN_ERROR_RUNTIME_ERROR = 1;
enum { FFX_API_CREATE_CONTEXT_DESC_TYPE_BACKEND_VK = 1, FFX_API_CREATE_CONTEXT_DESC_TYPE_UPSCALE,
       FFX_API_CREATE_CONTEXT_DESC_TYPE_UPSCALE_VERSION, FFX_API_QUERY_DESC_TYPE_GET_VERSIONS,
       FFX_API_DESC_TYPE_OVERRIDE_VERSION, FFX_API_QUERY_DESC_TYPE_GET_PROVIDER_VERSION,
       FFX_API_QUERY_DESC_TYPE_UPSCALE_GET_RESOURCE_REQUIREMENTS };
constexpr uint32_t FFX_UPSCALER_VERSION = 123;
enum { FFX_UPSCALE_ENABLE_HIGH_DYNAMIC_RANGE = 1, FFX_UPSCALE_ENABLE_DEPTH_INVERTED = 2, FFX_UPSCALE_ENABLE_AUTO_EXPOSURE = 4 };
enum { FFX_API_QUERY_RESOURCE_INPUT_COLOR = 1, FFX_API_QUERY_RESOURCE_INPUT_DEPTH = 2,
       FFX_API_QUERY_RESOURCE_INPUT_MV = 4, FFX_API_QUERY_RESOURCE_INPUT_EXPOSURE = 8,
       FFX_API_QUERY_RESOURCE_INPUT_REACTIVEMASK = 16 };
struct ffxCreateBackendVKDesc {
    Header header;
    struct DeviceContext { VkDevice vkDevice = nullptr; VkPhysicalDevice vkPhysicalDevice = nullptr; void *(*vkDeviceProcAddr)(VkDevice, const char *) = nullptr; } deviceContext;
    VkDevice vkDevice = nullptr; VkPhysicalDevice vkPhysicalDevice = nullptr; void *(*vkDeviceProcAddr)(VkDevice, const char *) = nullptr;
};
struct ffxCreateContextDescUpscale { Header header; uint32_t flags = 0; struct Dimensions { uint32_t width = 0, height = 0; } maxRenderSize, maxUpscaleSize; void *fpMessage = nullptr; };
struct ffxCreateContextDescUpscaleVersion { Header header; uint32_t version = 0; };
struct ffxOverrideVersion { Header header; uint64_t versionId = 0; };
struct ffxQueryDescGetVersions { Header header; uint64_t createDescType = 0; void *device = nullptr; uint64_t *outputCount = nullptr, *versionIds = nullptr; const char **versionNames = nullptr; };
struct ffxQueryGetProviderVersion { Header header; const char *versionName = nullptr; uint64_t versionId = 0; };
struct ffxQueryDescUpscaleGetResourceRequirements { Header header; uint64_t required_resources = 0, optional_resources = 0; };
struct RD {
    inline static RD *singleton = nullptr;
    enum { DRIVER_RESOURCE_LOGICAL_DEVICE, DRIVER_RESOURCE_PHYSICAL_DEVICE, TEXTURE_TYPE_2D, DATA_FORMAT_R8_UNORM,
           TEXTURE_USAGE_SAMPLING_BIT = 1, TEXTURE_USAGE_STORAGE_BIT = 2 };
    struct TextureView {};
    struct TextureFormat { int texture_type = 0, format = 0, width = 0, height = 0, depth = 0, array_layers = 0, mipmaps = 0, usage_bits = 0; bool is_discardable = false; };
    uint64_t logical = 11, physical = 12;
    bool fail_mask = false;
    static RD *get_singleton() { return singleton; }
    uint64_t get_driver_resource(int kind) { return kind == DRIVER_RESOURCE_LOGICAL_DEVICE ? logical : physical; }
    RID texture_create(TextureFormat, TextureView) { return fail_mask ? RID{} : RID{42}; }
};
using RenderingDevice = RD;
void *fsr3_get_device_proc_addr(VkDevice, const char *) { return reinterpret_cast<void *>(1); }
struct FSR3ContextInternal {
    ffxContext context = nullptr;
    ffxCreateBackendVKDesc backend;
    ffxCreateContextDescUpscale description;
    ffxCreateContextDescUpscaleVersion api_version;
    ffxOverrideVersion version_override;
    VkDevice device = nullptr;
    Size2i internal_size, target_size;
    RID reactive_mask;
    uint64_t required_resources = 0;
};
struct FSR3Context { FSR3ContextInternal *internal = nullptr; ~FSR3Context() { delete internal; } };
struct FSR3Api {
    std::mutex mutex;
    ffxReturnCode_t (*create_context)(ffxContext *, Header *, void *) = nullptr;
    ffxReturnCode_t (*query)(ffxContext *, Header *) = nullptr;
    std::string provider_version, requested_implementation;
    uint64_t provider_version_id = 0, required_resources = 0, optional_resources = 0;
};
FSR3Api &get_fsr3_api() { static FSR3Api api; return api; }
std::atomic<bool> backend_failed{false};
std::atomic<uint64_t> contexts_created{0};
std::atomic<uint32_t> last_return_code{0};
bool available = true, fail_create = false, fail_provider_query = false, fail_requirements = false;
const char *provider_name = "old";
uint64_t provider_id = 7, required = 1, optional = 16;
void collect_retired_contexts() {}
void record_backend_failure(uint32_t code) { backend_failed.store(true); last_return_code.store(code); }
bool matches_bundled_version(const std::string &, const char *) { return true; }
template<typename... Args> const char *vformat(const char *s, Args...) { return s; }
#define WARN_PRINT(...) do {} while (false)
#define memnew(T) new T
#define memdelete(T) delete (T)
ffxReturnCode_t fake_create(ffxContext *context, Header *, void *) { if (fail_create) return 7; *context = reinterpret_cast<void *>(1); return FFX_API_RETURN_OK; }
ffxReturnCode_t fake_query(ffxContext *, Header *header) {
    if (header->type == FFX_API_QUERY_DESC_TYPE_GET_PROVIDER_VERSION) {
        if (fail_provider_query) return 3;
        auto *query = reinterpret_cast<ffxQueryGetProviderVersion *>(header);
        query->versionName = provider_name; query->versionId = provider_id;
    } else if (header->type == FFX_API_QUERY_DESC_TYPE_UPSCALE_GET_RESOURCE_REQUIREMENTS) {
        if (fail_requirements) return 4;
        auto *query = reinterpret_cast<ffxQueryDescUpscaleGetResourceRequirements *>(header);
        query->required_resources = required; query->optional_resources = optional;
    } else {
        auto *query = reinterpret_cast<ffxQueryDescGetVersions *>(header);
        if (*query->outputCount == 0) *query->outputCount = 1;
        else { query->versionIds[0] = provider_id; query->versionNames[0] = provider_name; }
    }
    return FFX_API_RETURN_OK;
}
class FSR3Effect {
public:
    static bool is_available() { return available && !backend_failed.load(); }
    FSR3Context *create_context(Size2i, Size2i);
};
"""

FSR3_CREATE_MAIN = r"""
int main() {
    RD rd; RD::singleton = &rd;
    auto &api = get_fsr3_api(); api.create_context = fake_create; api.query = fake_query;
    FSR3Effect effect;
    auto reset_failure = [&]() { backend_failed.store(false); last_return_code.store(0); };
    available = false; assert(!effect.create_context({}, {}) && backend_failed.load()); available = true; reset_failure();
    assert(!effect.create_context({0, 80}, {}) && backend_failed.load()); reset_failure();
    assert(!effect.create_context({}, {100, 0}) && backend_failed.load()); reset_failure();
    RD::singleton = nullptr; assert(!effect.create_context({}, {}) && backend_failed.load()); RD::singleton = &rd; reset_failure();
    rd.logical = 0; assert(!effect.create_context({}, {}) && backend_failed.load()); rd.logical = 11; reset_failure();
    rd.physical = 0; assert(!effect.create_context({}, {}) && backend_failed.load()); rd.physical = 12; reset_failure();
    FSR3Context *first = effect.create_context({}, {});
    assert(first && api.provider_version == "old" && api.provider_version_id == 7 && contexts_created.load() == 1);
#if defined(FFX_UPSCALER_VERSION_MAJOR) && FFX_UPSCALER_VERSION_MAJOR >= 4
    assert(api.required_resources == 1 && api.optional_resources == 16 && api.requested_implementation == "auto");
#endif
    delete first;
    provider_name = "new"; provider_id = 9; required = 2; optional = 8;
    fail_create = true; assert(!effect.create_context({}, {}) && backend_failed.load());
    assert(api.provider_version == "old" && api.provider_version_id == 7 && contexts_created.load() == 1);
    fail_create = false; reset_failure();
    rd.fail_mask = true; assert(!effect.create_context({}, {}) && backend_failed.load());
    assert(api.provider_version == "old" && api.provider_version_id == 7 && contexts_created.load() == 1);
    rd.fail_mask = false; reset_failure();
#if defined(FFX_UPSCALER_VERSION_MAJOR) && FFX_UPSCALER_VERSION_MAJOR >= 4
    fail_provider_query = true; assert(!effect.create_context({}, {}) && backend_failed.load());
    assert(api.provider_version == "old" && api.required_resources == 1 && api.optional_resources == 16);
    fail_provider_query = false; reset_failure();
    fail_requirements = true; assert(!effect.create_context({}, {}) && backend_failed.load());
    assert(api.provider_version == "old" && api.required_resources == 1 && api.optional_resources == 16);
    fail_requirements = false; reset_failure();
#endif
    FSR3Context *next = effect.create_context({}, {});
    assert(next && api.provider_version == "new" && api.provider_version_id == 9 && contexts_created.load() == 2);
#if defined(FFX_UPSCALER_VERSION_MAJOR) && FFX_UPSCALER_VERSION_MAJOR >= 4
    assert(api.required_resources == 2 && api.optional_resources == 8 && api.requested_implementation == "auto");
#endif
    delete next;
}
"""


class FSRHistoryResetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        OUTPUT.mkdir(parents=True, exist_ok=True)
        cls.temporary = tempfile.TemporaryDirectory(prefix="offline-", dir=OUTPUT)
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.directory = Path(cls.temporary.name)

    def test_fsr3_actual_callback_success_failure_and_queued_generations(self) -> None:
        source = (HERE / "fsr3.cpp").read_text(encoding="utf-8")
        state = between(source, "// BEGIN FSR3 HISTORY RESET STATE", "// END FSR3 HISTORY RESET STATE")
        callback = function(source, "void FSR3Effect::_dispatch_graph_callback(")
        compile_and_run(FSR3_STUB + state + FSR3_AFTER_STATE + callback + FSR3_MAIN, self.directory, "fsr3")

    def test_fsr3_preparation_failures_latch_before_dispatch(self) -> None:
        source = (HERE / "fsr3.cpp").read_text(encoding="utf-8")
        upscale = function(source, "void FSR3Effect::upscale(")
        # The real setup is tested up to graph payload creation. Callback success,
        # failure and ownership are covered separately above.
        prepare = upscale[:upscale.index("\n\tDispatchPayload *payload =")] + "\n}\n"
        for name, defines in (("fsr3_prepare_legacy", ""), ("fsr3_prepare_sdk24", "#define FFX_UPSCALER_VERSION_MAJOR 4\n")):
            compile_and_run(defines + FSR3_PREP_STUB + prepare + FSR3_PREP_MAIN, self.directory, name)

    def test_fsr3_creation_failures_and_provider_status_are_transactional(self) -> None:
        source = (HERE / "fsr3.cpp").read_text(encoding="utf-8")
        create = function(source, "FSR3Context *FSR3Effect::create_context(")
        self.assertIn('status["provider_scope"] = "last_successful_context";', source)
        for name, defines in (("fsr3_create_legacy", ""), ("fsr3_create_sdk24", "#define FFX_UPSCALER_VERSION_MAJOR 4\n")):
            compile_and_run(defines + FSR3_CREATE_STUB + create + FSR3_CREATE_MAIN, self.directory, name)

    def test_fsr2_dispatch_and_ordered_patch_against_pinned_archive(self) -> None:
        if not shutil.which("git"):
            self.skipTest("Git is required to apply the engine patch")
        archive = ROOT / ".tools/advanced-rendering" / BUILD.ARCHIVES[0][0]
        if not archive.is_file():
            self.skipTest("Pinned engine ZIP is not present in the local native cache")
        with archive.open("rb") as stream:
            self.assertEqual(hashlib.file_digest(stream, "sha256").hexdigest(), BUILD.ARCHIVES[0][2])
        prefix = BUILD.ENGINE_PATCHES[:BUILD.ENGINE_PATCHES.index("dlss_history_reset.patch") + 1]
        patches = [HERE / name for name in (*prefix, "fsr_history_reset.patch")]
        paths = {name for patch in patches for name in
                 re.findall(r"^\+\+\+ b/(.+)$", patch.read_text(encoding="utf-8"), re.MULTILINE)}
        engine = self.directory / "engine"
        engine.mkdir()
        with zipfile.ZipFile(archive) as package:
            for name in paths:
                path = engine / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(package.read(f"godot-{BUILD.COMMIT}/{name}").replace(b"\r\n", b"\n"))
        env = dict(os.environ, GIT_CEILING_DIRECTORIES=str(engine.parent))
        for patch in patches:
            result = subprocess.run(["git", "apply", "--whitespace=nowarn", "-"], cwd=engine, env=env,
                                    input=patch.read_bytes().replace(b"\r\n", b"\n"), capture_output=True)
            self.assertEqual(result.returncode, 0, f"{patch.name}: {result.stderr.decode(errors='replace')}")
        header = (engine / "servers/rendering/renderer_rd/effects/fsr2.h").read_text(encoding="utf-8")
        source = (engine / "servers/rendering/renderer_rd/effects/fsr2.cpp").read_text(encoding="utf-8")
        forward = (engine / "servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp").read_text(encoding="utf-8")
        server = (engine / "servers/rendering/rendering_server.cpp").read_text(encoding="utf-8")
        self.assertIn("params.context = rb_data->get_fsr2_context(v);", forward)
        self.assertIn("memdelete_notnull(context);", forward)
        self.assertEqual(forward.count("params.history_reset_generation = rb->get_temporal_history_reset_generation();"), 3)
        self.assertIn('D_METHOD("get_temporal_history_reset_providers")', server)
        state = between(header, "// BEGIN FSR2 HISTORY RESET STATE", "// END FSR2 HISTORY RESET STATE")
        diagnostic_state = between(source, "// BEGIN FSR2 DIAGNOSTIC STATE", "// END FSR2 DIAGNOSTIC STATE")
        status = function(source, "Dictionary FSR2Effect::get_status(")
        execute_jobs = function(source, "static FfxErrorCode execute_gpu_jobs_rd(")
        dispatch = function(source, "bool FSR2Effect::upscale(")
        compile_and_run(FSR2_STUB + state + FSR2_AFTER_STATE + diagnostic_state + "\n" + status + "\n" + execute_jobs + FSR2_AFTER_EXECUTION + dispatch + FSR2_MAIN,
                        self.directory, "fsr2")
        destroy_context = function(source, "FSR2Context::~FSR2Context(")
        create_context = function(source, "FSR2Context *FSR2Effect::create_context(")
        compile_and_run(FSR2_CREATE_STUB + diagnostic_state + "\n" + status + "\n" + destroy_context + "\n" + create_context + FSR2_CREATE_MAIN,
                        self.directory, "fsr2_create")
        clear_job = function(source, "static FfxErrorCode execute_gpu_job_clear_float_rd(")
        copy_job = function(source, "static FfxErrorCode execute_gpu_job_copy_rd(")
        compile_and_run(FSR2_RESOURCE_STUB + clear_job + copy_job + FSR2_RESOURCE_MAIN, self.directory, "fsr2_resources")
        query = function(server, "PackedStringArray RenderingServer::get_temporal_history_reset_providers(")
        query_stub = """#include <cassert>
#include <string>
#include <vector>
using PackedStringArray = std::vector<std::string>;
class RenderingServer { public: PackedStringArray get_temporal_history_reset_providers() const; };
"""
        variants = (
            ("#define RD_ENABLED\n#define STREAMLINE_ENABLED\n#define WINDOWS_ENABLED\n#define VULKAN_ENABLED\n",
             'assert((items == PackedStringArray{"dlss", "fsr2", "fsr3"}));'),
            ("#define RD_ENABLED\n", 'assert((items == PackedStringArray{"fsr2"}));'),
            ("", "assert(items.empty());"),
        )
        for index, (defines, assertion) in enumerate(variants):
            main = f"int main() {{ auto items = RenderingServer().get_temporal_history_reset_providers(); {assertion} }}"
            compile_and_run(defines + query_stub + query + main, self.directory, f"providers_{index}")


if __name__ == "__main__":
    unittest.main()
