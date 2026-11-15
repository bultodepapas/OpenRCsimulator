"""Portable 0007 admission/lifetime checks and opt-in native Metal witness.

The compiled fakes execute the patched contract and callback, not Metal or Godot.
Native execution is a separate source-bound build and real GPU qualification gate.
"""
from __future__ import annotations

import argparse
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
import zipfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SPEC = importlib.util.spec_from_file_location("metalfx_checks", HERE / "test_engine_patch.py")
CHECK = importlib.util.module_from_spec(SPEC)
assert SPEC.loader
SPEC.loader.exec_module(CHECK)
ENGINE_SPEC = importlib.util.spec_from_file_location("metalfx_engine", HERE / "engine.py")
ENGINE = importlib.util.module_from_spec(ENGINE_SPEC)
assert ENGINE_SPEC.loader
ENGINE_SPEC.loader.exec_module(ENGINE)
PATCHES = [HERE / "patches" / p for p in (
    "0001-metalfx-allocation-fallback.patch", "0002-metalfx-history-reset.patch",
    "0003-metalfx-debug-faults.patch", "0004-metalfx-frame-inputs.patch",
    "0005-metal-triangle-query.patch", "0006-metalfx-gpu-observation.patch",
    "0007-metalfx-denoised-binding.patch")]
FROZEN_FIRST_FOUR = (
    "f04167e05f452bfc37e85e90d512373d92c3f6ec808cef8431a0705e197d716a",
    "d7570f1b3639616e4e565a920cc4b9caca844bf7d1c8b3ec7d14d6e596c4ecc5",
    "cdacbdf81c80e44b96b200f1890236774225d93d8b54299f8e7db47b9f2c21cd",
    "2cfc1c4b466dfba51ae940d4c0529d290bf5a4502cd562d52edc4c4712e1ce18")
PROBE = ROOT / "research/engine-upgrade/metalfx/denoised_query_probe.gd"
COMPILER = Path("C:/Users/bulto/scoop/apps/gcc/current/bin/g++.exe")

CONTRACT_TEST = r'''
#include <servers/rendering/storage/metalfx_denoised_contract.h>
#include <limits>
using namespace MFXDenoisedContract;
#define CHECK(x) do { if (!(x)) return __LINE__; } while (0)
int main() {
    CHECK(!dimensions(0,720,1920,1080)); CHECK(!dimensions(1,1,16385,1));
    CHECK(dimensions(1280,720,1920,1080));
    Image v[COUNT]; Format f[COUNT]={RGBA16F,D32F,RG16F,RGBA16F,RGBA16F,RGBA16F,R16F,R16F,RGBA16F};
    for (int i=0;i<COUNT;i++) { v[i].identity=100+i; v[i].width=i==EXPOSURE ? 1 : (i==OUTPUT ? 1920 : 1280);
        v[i].height=i==EXPOSURE ? 1 : (i==OUTPUT ? 1080 : 720); v[i].format=f[i];
        v[i].regular=true; v[i].sampled=true; v[i].writable=i==OUTPUT; }
    CHECK(images(v,1280,720,1920,1080));
    v[OUTPUT].external=true; CHECK(!images(v,1280,720,1920,1080)); v[OUTPUT].external=false; // distinct imported view of same backing
    v[COLOR].shared=true; CHECK(!images(v,1280,720,1920,1080)); v[COLOR].shared=false;
    auto original=v[OUTPUT]; v[OUTPUT].width=1280; CHECK(!images(v,1280,720,1920,1080)); v[OUTPUT]=original;
    v[OUTPUT].writable=false; CHECK(!images(v,1280,720,1920,1080)); v[OUTPUT]=original;
    auto saved=v[DEPTH]; v[DEPTH].format=R16F; CHECK(!images(v,1280,720,1920,1080)); v[DEPTH]=saved;
    v[DEPTH].sampled=false; CHECK(!images(v,1280,720,1920,1080)); v[DEPTH]=saved;
    v[DEPTH].regular=false; CHECK(!images(v,1280,720,1920,1080)); v[DEPTH]=saved;
    auto exposure=v[EXPOSURE]; v[EXPOSURE].width=2; CHECK(!images(v,1280,720,1920,1080)); v[EXPOSURE]=exposure;
    auto spec=v[SPECULAR]; v[SPECULAR].identity=v[DIFFUSE].identity; CHECK(!images(v,1280,720,1920,1080)); v[SPECULAR]=spec;
    float world[16]={}, clip[16]={};
    CHECK(!frame(1,0,0,world,clip,false,0)); CHECK(frame(1,0,0,world,clip,true,0));
    CHECK(frame(1,0,0,world,clip,false,1)); CHECK(!frame(0,0,0,world,clip,true,0));
    CHECK(!frame(-1,0,0,world,clip,true,0));
    CHECK(!frame(1,std::numeric_limits<float>::infinity(),0,world,clip,true,0));
    clip[7]=std::numeric_limits<float>::quiet_NaN(); CHECK(!frame(1,0,0,world,clip,true,0)); clip[7]=0;
    CHECK(!frame(1,0,0,world,clip,true,UINT64_MAX));
    CHECK(!frame(1,0,0,nullptr,clip,true,0));
    return 0;
}
'''

CALLBACK_TEST = r'''
#include <atomic>
#include <cstdint>
#include <memory>
#define memdelete(p) delete (p)
struct Effect { int refs=2; }; // context + retained queued callback
struct Driver {
    using CommandBufferID=int;
    struct DenoisedFrame { bool reset=false; };
    int code=0, calls=0;
    int denoised_encode(void *p, CommandBufferID, const DenoisedFrame &) {
        ++calls; if (!code) ++static_cast<Effect *>(p)->refs; return code; // GPU command holds successful effect
    }
    void denoised_release(void *p) { --static_cast<Effect *>(p)->refs; }
};
using RDD=Driver;
class RenderingDevice {
public:
    struct DenoisedProgress { std::atomic<uint64_t> encoded{0}; std::atomic<int> callback_error{0}; };
    struct DenoisedCallback { void *effect=nullptr; RDD::DenoisedFrame frame;
        std::shared_ptr<DenoisedProgress> progress; uint64_t serial=0; };
    static void _denoised_callback(RDD *, RDD::CommandBufferID, void *);
};
@CALLBACK@
#define CHECK(x) do { if (!(x)) return __LINE__; } while (0)
int main() {
    Driver d; Effect old;
    auto state=std::make_shared<RenderingDevice::DenoisedProgress>();
    auto *queued=new RenderingDevice::DenoisedCallback; queued->effect=&old; queued->progress=state; queued->serial=1;
    d.denoised_release(&old); CHECK(old.refs==1); // destroy context before callback
    RenderingDevice::_denoised_callback(&d,0,queued);
    CHECK(old.refs==1 && d.calls==1 && state->encoded==1 && state->callback_error==0);
    d.denoised_release(&old); CHECK(old.refs==0); // GPU completes
    auto fresh=std::make_shared<RenderingDevice::DenoisedProgress>(); Effect next;
    d.code=4; auto *bad=new RenderingDevice::DenoisedCallback; bad->effect=&next; bad->progress=fresh; bad->serial=1;
    RenderingDevice::_denoised_callback(&d,0,bad);
    CHECK(next.refs==1 && fresh->callback_error==4 && fresh->encoded==0 && state->encoded==1);
    ++next.refs; auto *later=new RenderingDevice::DenoisedCallback; later->effect=&next; later->progress=fresh; later->serial=2;
    d.code=0; RenderingDevice::_denoised_callback(&d,0,later);
    CHECK(next.refs==1 && d.calls==2 && fresh->callback_error==4 && fresh->encoded==0); // sticky failure, no encode
    d.denoised_release(&next); CHECK(next.refs==0);
    return 0;
}
'''

FRESH_COMMAND_TEST = r"""
#include <cstdint>
namespace MTL { struct CommandBuffer {}; }
using CFTypeRef=const void *;
enum { MFX_DENOISED_OK=0, MFX_DENOISED_HAZARD_REQUIRED=6 };
struct MDCommandBuffer {
    bool created=false; int allocations=0, retains=0; MTL::CommandBuffer object;
    void end() {}
    MTL::CommandBuffer *command_buffer() { if (!created) { created=true; ++allocations; } return &object; }
    MTL::CommandBuffer *ensure_command_buffer() @ENSURE@
    void retain_resource(CFTypeRef) {++retains;}
};
static int native_result=0; static bool saw_command=false;
int mfx_denoised_encode(void *, void *command, void *, void *const *, float,float,float,const float *,const float *,bool) {
    saw_command=command!=nullptr; return native_result;
}
class RenderingDeviceDriverMetal {
public:
    enum { HazardTracking, Barriers };
    int sync_mode=Barriers;
    struct CommandBufferID { uint64_t id=0; };
    struct DenoisedFrame { uint64_t textures[9]={}; float exposure=1,jitter_x=0,jitter_y=0,world[16]={},clip[16]={}; bool reset=false; };
    int denoised_encode(void *,CommandBufferID,const DenoisedFrame &);
};
@ENCODE@
#define CHECK(x) do { if (!(x)) return __LINE__; } while (0)
int main() {
    MDCommandBuffer cmd; RenderingDeviceDriverMetal driver; RenderingDeviceDriverMetal::DenoisedFrame frame;
    RenderingDeviceDriverMetal::CommandBufferID id{uint64_t(&cmd)}; int effect=0;
    CHECK(driver.denoised_encode(&effect,id,frame)==MFX_DENOISED_HAZARD_REQUIRED && !cmd.created);
    driver.sync_mode=driver.HazardTracking;
    CHECK(driver.denoised_encode(&effect,id,frame)==0 && saw_command && cmd.allocations==1 && cmd.retains==1);
    CHECK(driver.denoised_encode(&effect,id,frame)==0 && cmd.allocations==1 && cmd.retains==2);
    native_result=4; CHECK(driver.denoised_encode(&effect,id,frame)==4 && cmd.retains==2);
    return 0;
}
"""

TRANSFER_TEST = r"""
#include <cstdint>
struct Texture { int transfer_worker_index=-1; uint64_t transfer_worker_operation=0; };
struct Owner { Texture textures[9]; Texture *get_or_null(int i) { return &textures[i]; } };
enum { COUNT=9, EXPOSURE=7 };
class RenderingDevice {
public:
    Owner texture_owner; int marked=-1, cleared=0; uint64_t operation=0;
    void _check_transfer_worker_operation(int index, uint64_t op) { marked=index; operation=op; }
    void _texture_check_pending_clear(int,Texture *) { ++cleared; }
    void _check_transfer_worker_texture(Texture *);
    void prepare(int *ids);
};
@CHECKER@
void RenderingDevice::prepare(int *ids) {
@LOOP@
}
#define CHECK(x) do { if (!(x)) return __LINE__; } while (0)
int main() {
    RenderingDevice rd; int ids[COUNT]; for (int i=0;i<COUNT;++i) ids[i]=i;
    // Exposure is the only texture with a pending upload and no other consumer.
    rd.texture_owner.textures[EXPOSURE].transfer_worker_index=3;
    rd.texture_owner.textures[EXPOSURE].transfer_worker_operation=42;
    rd.prepare(ids);
    CHECK(rd.marked==3 && rd.operation==42 && rd.cleared==COUNT);
    CHECK(rd.texture_owner.textures[EXPOSURE].transfer_worker_index==-1);
    return 0;
}
"""

FACTORY_TEST = r"""
#include <atomic>
#include <cstdint>
#include <map>
#include <memory>
#include <string>
#include <variant>
#include <servers/rendering/storage/metalfx_denoised_contract.h>
#define ERR_RENDER_THREAD_GUARD_V(v) do {} while (0)
struct RID { int id=0; bool is_valid() const {return id!=0;} bool operator<(const RID &o) const {return id<o.id;} };
struct Size2i { int x=0,y=0; };
using Value = std::variant<std::string,RID,uint64_t,bool>;
using Dictionary = std::map<std::string,Value>;
static int next_id=0;
template<class T, bool> struct Owner {
    std::map<RID,T> objects;
    bool fail=false;
    RID make_rid() { if (fail) return RID(); RID r{++next_id}; objects[r]=T(); return r; }
    T *get_or_null(RID r) { auto it=objects.find(r); return it==objects.end() ? nullptr : &it->second; }
    void free(RID r) { objects.erase(r); }
};
struct Driver {
    int capability=0, code=0, creates=0, releases=0; bool return_effect=true; int effect=0;
    int denoised_capability() const {return capability;}
    void *denoised_create(uint32_t,uint32_t,uint32_t,uint32_t,int &out) {++creates; out=code; return return_effect ? &effect : nullptr;}
    void denoised_release(void *) {++releases;}
};
class RenderingDevice {
public:
    struct DenoisedProgress {std::atomic<uint64_t> encoded{0}; std::atomic<int> callback_error{0};};
    struct DenoisedContext {void *effect=nullptr; Size2i input,output; uint64_t accepted=0; std::shared_ptr<DenoisedProgress> progress;};
    Owner<DenoisedContext,true> denoised_owner; Driver *driver=nullptr;
    Dictionary metalfx_denoised_capability() const;
    Dictionary metalfx_denoised_create(Size2i,Size2i);
    Dictionary metalfx_denoised_status(RID);
};
@REASON@
@RESULT@
@CAPABILITY@
@CREATE@
@STATUS@
#define CHECK(x) do { if (!(x)) return __LINE__; } while (0)
std::string status(Dictionary d) {return std::get<std::string>(d.at("status"));}
int main() {
    Driver d; RenderingDevice a,b; a.driver=&d; b.driver=&d;
    CHECK(status(a.metalfx_denoised_create({0,720},{1920,1080}))=="invalid_dimensions" && d.creates==0);
    d.capability=1; CHECK(status(a.metalfx_denoised_capability())=="sdk_os_or_driver_unavailable");
    CHECK(status(a.metalfx_denoised_create({1280,720},{1920,1080}))=="sdk_os_or_driver_unavailable" && d.creates==0);
    d.capability=2; CHECK(status(a.metalfx_denoised_create({1280,720},{1920,1080}))=="device_unsupported" && d.creates==0);
    d.capability=6; CHECK(status(a.metalfx_denoised_create({1280,720},{1920,1080}))=="native_hazard_tracking_required" && d.creates==0);
    d.capability=0; d.code=3; d.return_effect=false;
    CHECK(status(a.metalfx_denoised_create({1280,720},{1920,1080}))=="factory_failed" && d.creates==1 && d.releases==0);
    d.return_effect=true; CHECK(status(a.metalfx_denoised_create({1280,720},{1920,1080}))=="factory_failed" && d.releases==1);
    d.code=0; a.denoised_owner.fail=true;
    CHECK(status(a.metalfx_denoised_create({1280,720},{1920,1080}))=="allocation_failed" && d.releases==2);
    a.denoised_owner.fail=false;
    Dictionary created=a.metalfx_denoised_create({1280,720},{1920,1080});
    CHECK(status(created)=="created"); RID first=std::get<RID>(created.at("context"));
    CHECK(status(b.metalfx_denoised_status(first))=="invalid_context");
    auto info=a.metalfx_denoised_status(first); CHECK(status(info)=="created" && std::get<uint64_t>(info.at("accepted"))==0);
    CHECK(!std::get<bool>(info.at("gpu_completion_observed")));
    a.denoised_owner.free(first); CHECK(status(a.metalfx_denoised_status(first))=="invalid_context");
    Dictionary resized=a.metalfx_denoised_create({640,360},{1920,1080});
    RID second=std::get<RID>(resized.at("context")); CHECK(first.id!=second.id);
    CHECK(status(a.metalfx_denoised_status(first))=="invalid_context" && status(a.metalfx_denoised_status(second))=="created");
    CHECK(a.denoised_owner.get_or_null(second)->input.x==640);
    return 0;
}
"""

class DenoisedPatchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not CHECK.ARCHIVE.is_file() or ENGINE.sha256(CHECK.ARCHIVE) != CHECK.ARCHIVE_SHA256:
            raise RuntimeError("Pinned source archive missing or differs")
        if tuple(ENGINE.sha256(p) for p in PATCHES[:4]) != FROZEN_FIRST_FOUR:
            raise RuntimeError("Frozen prerequisites differ")
        cls.temp = tempfile.TemporaryDirectory(prefix="openrc-denoised-")
        cls.addClassCleanup(cls.temp.cleanup)
        cls.base = Path(cls.temp.name)
        paths = ENGINE.patch_paths(PATCHES)
        with zipfile.ZipFile(CHECK.ARCHIVE) as archive:
            members = set(archive.namelist())
            for name in paths:
                member = f"{ENGINE.SOURCE_PREFIX}/{name}"
                if member in members:
                    target = cls.base / name
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(archive.read(member))
        for patch in PATCHES:
            ENGINE.git(cls.base, "apply", "--check", str(patch.resolve()))
            ENGINE.git(cls.base, "apply", str(patch.resolve()))
        cls.rd = (cls.base / "servers/rendering/rendering_device.cpp").read_text(encoding="utf-8")
        cls.bridge = (cls.base / "drivers/metal/metalfx_denoised_bridge.mm").read_text(encoding="utf-8")
        cls.driver = (cls.base / "drivers/metal/rendering_device_driver_metal3.cpp").read_text(encoding="utf-8")

    def compile_run(self, source: str, name: str, include: Path | None = None) -> subprocess.CompletedProcess:
        compiler = str(COMPILER) if sys.platform == "win32" and COMPILER.is_file() else shutil.which("g++") or shutil.which("clang++")
        self.assertTrue(compiler, "C++17 compiler required")
        cpp = self.base / (name + ".cpp")
        exe = self.base / (name + (".exe" if sys.platform == "win32" else ""))
        cpp.write_text(source, encoding="utf-8")
        command = [compiler, "-std=c++17", "-Wall", "-Wextra", "-Werror", "-I", str(include or self.base), str(cpp), "-o", str(exe)]
        built = subprocess.run(command, capture_output=True, text=True, timeout=90)
        self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
        return subprocess.run([str(exe)], capture_output=True, text=True, timeout=20)

    def test_real_contract_accepts_and_rejects(self):
        result = self.compile_run(CONTRACT_TEST, "contract")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_alias_negative_control_detects_mutation(self):
        altered = self.base / "mutated/servers/rendering/storage/metalfx_denoised_contract.h"
        altered.parent.mkdir(parents=True, exist_ok=True)
        original = (self.base / "servers/rendering/storage/metalfx_denoised_contract.h").read_text(encoding="utf-8")
        mutated = original.replace("if (v[i].identity == v[j].identity) return false;", "if (false) return false;")
        self.assertNotEqual(original, mutated)
        altered.write_text(mutated, encoding="utf-8")
        result = self.compile_run(CONTRACT_TEST, "mutation", self.base / "mutated")
        self.assertNotEqual(result.returncode, 0, "negative control failed to detect aliased resources")

    def test_external_pass_creates_command_buffer_on_fresh_graph(self):
        header = (self.base / "drivers/metal/metal3_objects.h").read_text(encoding="utf-8")
        ensure = CHECK.cxx_block(header, header.index("MTL::CommandBuffer *ensure_command_buffer()"))
        encode = CHECK.cxx_function(self.driver, "int RenderingDeviceDriverMetal::denoised_encode(")
        source = FRESH_COMMAND_TEST.replace("@ENSURE@", ensure).replace("@ENCODE@", encode)
        result = self.compile_run(source, "fresh_command")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_isolated_exposure_upload_is_registered_before_enqueue(self):
        encode = CHECK.cxx_function(self.rd, "Dictionary RenderingDevice::metalfx_denoised_encode(")
        anchor = "if (code) return denoised_result(denoised_reason(code));"
        begin = encode.index("for (unsigned i=0; i<COUNT; ++i) {", encode.index(anchor))
        end = encode.index("\n\tDenoisedCallback *args", begin)
        loop = encode[begin:end]
        checker = CHECK.cxx_function(self.rd, "void RenderingDevice::_check_transfer_worker_texture(")
        source = TRANSFER_TEST.replace("@CHECKER@", checker).replace("@LOOP@", loop)
        result = self.compile_run(source, "transfer")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        broken = source.replace("_check_transfer_worker_texture(tex);", "/* intentionally omitted */")
        self.assertNotEqual(broken, source)
        mutated = self.compile_run(broken, "transfer_mutation")
        self.assertNotEqual(mutated.returncode, 0, "isolated upload regression did not detect missing mark")

    def test_real_factory_rejects_failures_cross_device_and_retired_generations(self):
        source = FACTORY_TEST
        functions = {
            "@REASON@": "static const char *denoised_reason(",
            "@RESULT@": "static Dictionary denoised_result(",
            "@CAPABILITY@": "Dictionary RenderingDevice::metalfx_denoised_capability(",
            "@CREATE@": "Dictionary RenderingDevice::metalfx_denoised_create(",
            "@STATUS@": "Dictionary RenderingDevice::metalfx_denoised_status(",
        }
        for key, signature in functions.items():
            source = source.replace(key, CHECK.cxx_function(self.rd, signature))
        result = self.compile_run(source, "factory")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_real_callback_owns_retired_context_and_latches_failure(self):
        callback = CHECK.cxx_function(self.rd, "void RenderingDevice::_denoised_callback(")
        result = self.compile_run(CALLBACK_TEST.replace("@CALLBACK@", callback), "callback")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_factory_guards_and_native_texture_contract(self):
        b = self.bridge
        for text in ("__MAC_OS_X_VERSION_MAX_ALLOWED >= 260000", "@available(macOS 26.0, *)",
                     "[MTLFXTemporalDenoisedScalerDescriptor supportsDevice:device]",
                     "newTemporalDenoisedScalerWithDevice:device", "MFX_DENOISED_FACTORY_FAILED",
                     "fx.colorTextureUsage", "fx.depthTextureUsage", "fx.motionTextureUsage",
                     "fx.diffuseAlbedoTextureUsage", "fx.specularAlbedoTextureUsage", "fx.normalTextureUsage",
                     "fx.roughnessTextureUsage", "fx.outputTextureUsage", "texture.storageMode != MTLStorageModePrivate",
                     "fx.exposureTexture", "fx.worldToViewMatrix", "fx.viewToClipMatrix", "fx.shouldResetHistory",
                     "[fx encodeToCommandBuffer:command]"):
            self.assertIn(text, b)
        self.assertNotIn("MTLCreateSystemDefaultDevice", b)
        self.assertIn("cmd->retain_resource((CFTypeRef)p)", self.driver)
        self.assertIn("sync_mode == HazardTracking", self.driver)
        encode = CHECK.cxx_function(self.driver, "int RenderingDeviceDriverMetal::denoised_encode(")
        self.assertIn("sync_mode != HazardTracking", encode)
        self.assertNotIn("external_pass_fence", encode)
        self.assertIn("cmd->ensure_command_buffer(), nullptr", encode)

    def test_rd_checks_and_graph_lifetime(self):
        encode = CHECK.cxx_function(self.rd, "Dictionary RenderingDevice::metalfx_denoised_encode(")
        self.assertLess(encode.index("images(info"), encode.index("driver_callback_add("))
        self.assertLess(encode.index("denoised_validate("), encode.index("driver_callback_add("))
        self.assertIn("draw_graph.add_synchronization()", encode)
        self.assertIn("_texture_check_pending_clear", encode)
        self.assertIn("info[i].external = tex->is_external", encode)
        self.assertIn("info[i].shared = tex->owner.is_valid()", encode)
        external = CHECK.cxx_function(self.rd, "RID RenderingDevice::texture_create_from_extension(")
        self.assertIn("texture.is_external = true", external)
        self.assertIn("denoised_retain(args->effect)", encode)
        self.assertIn("CALLBACK_RESOURCE_USAGE_STORAGE_IMAGE_READ_WRITE", encode)
        self.assertIn("CALLBACK_RESOURCE_USAGE_TEXTURE_SAMPLE", encode)
        self.assertIn('denoised_owner.owns(p_id)', self.rd)
        self.assertIn('_free_rids(denoised_owner, "MetalFXDenoised")', self.rd)
        self.assertIn('result["gpu_completion_observed"] = false', self.rd)

    def test_fixture_requires_ray_producer_and_depth_pass(self):
        source = PROBE.read_text(encoding="utf-8")
        for term in ("rayQueryProceedEXT", "rayQueryGetIntersectionTEXT", "gl_FragDepth", "framebuffer_create([depth])",
                     "1920", "1080", "decode_half", "sentinel_rgb", "roi_mean_absolute_error", "rd.free_rid(next)",
                     "fresh_graph_enqueue_", "func _near", "is_finite(value)"):
            self.assertIn(term, source)


def native_runner(binary: Path, output: Path) -> int:
    if sys.platform != "darwin":
        raise SystemExit("Native Metal fixture requires macOS")
    binary = binary.resolve(strict=True)
    output.mkdir(parents=True, exist_ok=False)
    records = []
    fixture = PROBE.read_bytes()
    with tempfile.TemporaryDirectory(prefix="openrc-denoised-project-") as temporary:
        project = Path(temporary)
        (project / "project.godot").write_text('config_version=5\n[application]\nconfig/name="RD Denoised Witness"\n[rendering]\nrenderer/rendering_method="mobile"\n', encoding="utf-8")
        (project / "denoised_query_probe.gd").write_bytes(fixture)
        for mode in ("argument", "direct"):
            env = os.environ.copy()
            for key in ("GODOT_MTL_SYNC_MODE", "GODOT_MTL_DISABLE_ARGUMENT_BUFFERS", "MTL_SHADER_VALIDATION", "MTL_SHADER_VALIDATION_REPORT_TO_STDERR", "MTL_SHADER_VALIDATION_ABORT_ON_FAULT"):
                env.pop(key, None)
            env.update(GODOT_METAL_TRIANGLE_QUERY="1", MTL_DEBUG_LAYER="1", MTL_SHADER_VALIDATION="0")
            if mode == "direct":
                env["GODOT_MTL_DISABLE_ARGUMENT_BUFFERS"] = "1"
            command = [str(binary), "--path", str(project), "--rendering-method", "mobile", "--rendering-driver", "metal", "--verbose", "--script", "res://denoised_query_probe.gd"]
            # Use the checked runner; on enrolled hosts its normal admission rules apply.
            runner_spec = importlib.util.spec_from_file_location("openrc_run_checked", ROOT / "tools/godot/run_checked.py")
            runner = importlib.util.module_from_spec(runner_spec)
            assert runner_spec.loader
            runner_spec.loader.exec_module(runner)
            previous = {key: os.environ.get(key) for key in set(os.environ) | set(env)}
            try:
                os.environ.clear()
                os.environ.update(env)
                report = runner.run_checked(command, out_dir=output / "checked", timeout=900, label="denoised-" + mode, required=["METAL_DENOISED_RD "])
            finally:
                os.environ.clear()
                os.environ.update({k: v for k, v in previous.items() if v is not None})
            log = Path(report["log"]).read_text(encoding="utf-8", errors="replace")
            (output / (mode + ".log")).write_text(log, encoding="utf-8")
            lines = [line for line in log.splitlines() if line.startswith("METAL_DENOISED_RD ")]
            try:
                verdict = json.loads(lines[0].split(" ", 1)[1]) if len(lines) == 1 else {}
            except (ValueError, IndexError):
                verdict = {}
            gpu_fault = re.search(r"(?i)(failed assertion|GPU fault|MTLCommandBufferError|shader validation error|API validation error)", log) is not None
            binding_observed = "Metal triangle query binding mode: " + mode in log
            ok = report.get("ok") is True and verdict.get("ok") is True and not gpu_fault and binding_observed
            records.append({"mode": mode, "binding_observed": binding_observed, "checked_report": report, "verdict": verdict,
                            "ok": ok, "command": command,
                            "environment": {k: env.get(k) for k in ("GODOT_METAL_TRIANGLE_QUERY", "GODOT_MTL_DISABLE_ARGUMENT_BUFFERS", "MTL_DEBUG_LAYER", "MTL_SHADER_VALIDATION")}})
            print(f"{mode}: {'PASS' if ok else 'FAIL'}", flush=True)
    manifest = {"binary_sha256": ENGINE.sha256(binary), "fixture_sha256": hashlib.sha256(fixture).hexdigest(),
                "patch_sha256": [ENGINE.sha256(p) for p in PATCHES], "cases": records,
                "validation_scope": "Metal API validation only; global SDK shader instrumentation is intentionally disabled; no quality or performance claim",
                "source_identity_note": "binary hash recorded; caller must separately verify its build receipt binds this patch stack",
                "ok": all(r["ok"] for r in records)}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return 0 if manifest["ok"] else 1

if __name__ == "__main__":
    if "--native" in sys.argv:
        parser = argparse.ArgumentParser(description="Run the native RenderingDevice denoiser witness")
        parser.add_argument("--native", type=Path, required=True, help="Source-bound patched Godot editor")
        parser.add_argument("--out", type=Path, required=True, help="New evidence directory")
        args = parser.parse_args()
        raise SystemExit(native_runner(args.native, args.out))
    unittest.main()


