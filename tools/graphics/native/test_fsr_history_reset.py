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
#include <vector>
struct RID { uint64_t id = 1; uint64_t get_id() const { return id; } bool is_null() const { return id == 0; } };
struct Projection {};
struct Size { int width = 1, height = 1; };
struct Vec { float x = 0, y = 0; };
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
using FfxCommandList = void *;
enum { FFX_GPU_JOB_CLEAR_FLOAT, FFX_GPU_JOB_COPY, FFX_GPU_JOB_COMPUTE };
struct FfxGpuJobDescription { int jobType = FFX_GPU_JOB_COMPUTE, clearJobDescriptor = 0, copyJobDescriptor = 0, computeJobDescriptor = 0; };
struct FfxFsr2Interface { void *scratchBuffer = nullptr; };
struct FakeFfxContext { FfxFsr2Interface callbacks; };
#define ERR_FAIL_NULL_V(x, result) do { if (!(x)) return result; } while (false)
#define ERR_FAIL_COND_V(x, result) do { if (x) return result; } while (false)
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
    bool upscale(const Parameters &);
};
}
using namespace RendererRD;
static std::atomic<uint64_t> fsr2_dispatches_succeeded{0}, fsr2_reset_dispatches{0}, fsr2_last_reset_viewport{0};
static std::atomic<uint32_t> fsr2_last_reset_view{0};
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
    sdk_result = FFX_OK;
    sdk_backend_result = 5; // SDK returns OK despite a failed backend job.
    assert(!effect.upscale(p) && sdk_reset);
    assert(fsr2_reset_dispatches.load() == before);
    sdk_backend_result = FFX_OK;
    p.color.id = 0;
    auto calls_before_invalid = sdk_calls;
    assert(!effect.upscale(p) && sdk_calls == calls_before_invalid);
    p.color.id = 1;
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
        execute_jobs = function(source, "static FfxErrorCode execute_gpu_jobs_rd(")
        dispatch = function(source, "bool FSR2Effect::upscale(")
        compile_and_run(FSR2_STUB + state + FSR2_AFTER_STATE + execute_jobs + FSR2_AFTER_EXECUTION + dispatch + FSR2_MAIN,
                        self.directory, "fsr2")
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
