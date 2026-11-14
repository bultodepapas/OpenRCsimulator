"""Focused source-bound controls for the experimental MetalFX frame producer.

The executable checks compile actual patched policy/callback code against fake
rendering objects. They do not run a Godot engine, Metal, or a GPU.
"""
from __future__ import annotations

import hashlib
import importlib.util
from pathlib import Path
import re
import subprocess
import tempfile
import unittest
import zipfile

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("metalfx_patch_checks", HERE / "test_engine_patch.py")
CHECKS = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(CHECKS)
PATCHES = [HERE / "patches" / name for name in (
    "0001-metalfx-allocation-fallback.patch", "0002-metalfx-history-reset.patch",
    "0003-metalfx-debug-faults.patch", "0004-metalfx-frame-inputs.patch")]
FROZEN = (
    "f04167e05f452bfc37e85e90d512373d92c3f6ec808cef8431a0705e197d716a",
    "d7570f1b3639616e4e565a920cc4b9caca844bf7d1c8b3ec7d14d6e596c4ecc5",
    "cdacbdf81c80e44b96b200f1890236774225d93d8b54299f8e7db47b9f2c21cd",
)


class MetalFXFramePatchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if hashlib.sha256(CHECKS.ARCHIVE.read_bytes()).hexdigest() != CHECKS.ARCHIVE_SHA256:
            raise RuntimeError("Pinned Godot source differs")
        if tuple(hashlib.sha256(path.read_bytes()).hexdigest() for path in PATCHES[:3]) != FROZEN:
            raise RuntimeError("Frozen prerequisite patches differ")
        cls.temp = tempfile.TemporaryDirectory(prefix="openrc-metalfx-frame-")
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
            subprocess.run(["git", "apply", "--check", str(patch)], cwd=cls.base, check=True, capture_output=True)
            subprocess.run(["git", "apply", str(patch)], cwd=cls.base, check=True, capture_output=True)
        cls.header = (cls.base / "servers/rendering/renderer_rd/effects/metal_fx.h").read_text(encoding="utf-8")
        cls.metal = (cls.base / "servers/rendering/renderer_rd/effects/metal_fx.cpp").read_text(encoding="utf-8")
        cls.base_buffers = (cls.base / "servers/rendering/storage/render_scene_buffers.h").read_text(encoding="utf-8")
        cls.forward = (cls.base / "servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp").read_text(encoding="utf-8")
        cls.storage = (cls.base / "servers/rendering/renderer_rd/storage_rd/render_scene_buffers_rd.cpp").read_text(encoding="utf-8")
        cls.bridge = (cls.base / "drivers/metal/metalfx_frame_bridge.mm").read_text(encoding="utf-8")

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temp.cleanup()

    def compile_and_run(self, source: str, name: str) -> str:
        return CHECKS.MetalFXPatchTests.compile_and_run(self, source, name)

    @staticmethod
    def declaration(source: str, marker: str) -> str:
        return marker + " " + CHECKS.cxx_block(source, source.index(marker)) + ";"

    def test_patch_is_bound_to_prerequisite_stack(self) -> None:
        subprocess.run(["git", "apply", "--reverse", "--check", str(PATCHES[-1])], cwd=self.base, check=True, capture_output=True)
        target = self.base / "drivers/metal/metalfx_frame_bridge.mm"
        original = target.read_bytes()
        try:
            target.write_bytes(original.replace(b"fx.shouldResetHistory = p_reset", b"fx.shouldResetHistory = false", 1))
            refused = subprocess.run(["git", "apply", "--reverse", "--check", str(PATCHES[-1])], cwd=self.base, capture_output=True)
            self.assertNotEqual(refused.returncode, 0)
        finally:
            target.write_bytes(original)

    def test_actual_timeline_resets_on_cuts_skips_bad_clock_and_projection(self) -> None:
        src = r'''
#include <cassert>
#include <cmath>
#include <cstdint>
namespace Math { static bool is_finite(float x) { return std::isfinite(x); } }
'''+ self.declaration(self.header, "struct MFXFrameTimeline") + r'''
int main() {
    MFXFrameTimeline t;
    auto decide = [&](uint64_t frame, uint64_t time, bool cut = false, float fov = 60.f) {
        return t.decide(frame, time, cut, fov, 0.1f, 1000.f, 1.777f);
    };
    assert(decide(10, 1000000).reset);
    t.commit(10, 1000000, 60.f, 0.1f, 1000.f, 1.777f);
    auto ordinary = decide(11, 1016667);
    assert(!ordinary.reset && std::fabs(ordinary.delta - 0.016667f) < 1e-6f);
    assert(decide(11, 1016667, true).reset);
    assert(decide(11, 1016667, false, 61.f).reset);
    assert(decide(12, 1033334).reset); // skipped/failed frame: no commit
    assert(decide(11, 999999).reset); // backward clock
    assert(decide(11, 1400000).reset); // large elapsed gap
    t.commit(11, 1016667, 60.f, 0.1f, 1000.f, 1.777f);
    assert(!decide(12, 1033334).reset);
}
'''
        self.compile_and_run(src, "frame_timeline_controls")

    def test_actual_callback_warmup_generation_and_failure_controls(self) -> None:
        history = self.declaration(self.base_buffers, "struct MetalFXFrameHistoryState")
        cls = self.declaration(self.header, "class MFXFrameEffect")
        cls = cls.replace("struct CallbackArgs {", "public:\nstruct CallbackArgs {", 1)
        cls = cls.replace("static void callback(", "public:\nstatic void callback(", 1)
        callback = CHECKS.cxx_function(self.metal, "void MFXFrameEffect::callback(")
        src = r'''
#include <atomic>
#include <cassert>
#include <cstdint>
#include <memory>
using CFTypeRef = const void *;
struct RID {};
struct Vector2 { float x = 0, y = 0; };
struct Vector2i { int x = 0, y = 0; };
struct RDD { using DataFormat = int; struct TextureID { uintptr_t id = 1; }; struct CommandBufferID { uintptr_t id = 0; }; };
struct MFXFrameContext;
struct MDCommandBufferBase {
    int retained = 0; void end() {} void *external_pass_fence() { return nullptr; }
    void retain_resource(CFTypeRef) { ++retained; }
};
namespace MTL3 { struct MDCommandBuffer : MDCommandBufferBase { void *get_command_buffer() { return this; } }; }
enum { MFX_FRAME_OK = 0, MFX_FRAME_INPUT_MISMATCH = 3 };
static int bridge_result = 0, calls = 0, releases = 0;
static int mfx_frame_encode(void *, void *, void *, void *, void *, void *, void *, void *, bool,
                            float, float, float, float, float, float, float, float, float) { ++calls; return bridge_result; }
static void mfx_frame_release(void *) { ++releases; }
#define memdelete(p) delete (p)
'''+ history + "\n" + cls + "\n" + callback + r'''
int main() {
    auto h = std::make_shared<MetalFXFrameHistoryState>();
    MTL3::MDCommandBuffer cmd;
    auto invoke = [&](uint64_t serial, uint64_t epoch, bool reset) {
        auto *a = new MFXFrameEffect::CallbackArgs;
        a->effect = reinterpret_cast<void *>(1); a->history = h;
        a->serial = serial; a->epoch = epoch; a->reset = reset;
        MFXFrameEffect::callback(nullptr, {reinterpret_cast<uintptr_t>(&cmd)}, a);
    };
    h->requested_epoch.store(1);
    for (uint64_t i = 1; i <= 5; ++i) {
        h->submitted.store(i); invoke(i, 1, i == 1);
        assert(h->encoded.load() == i && h->encoded_in_epoch.load() == i);
        assert(h->ready_for_debug_readback() == (i == 5));
    }
    assert(calls == 5 && releases == 5 && cmd.retained == 5);
    h->requested_epoch.store(2); h->submitted.store(6);
    assert(!h->ready_for_debug_readback());
    invoke(6, 2, true);
    assert(h->encoded_epoch.load() == 2 && h->encoded_in_epoch.load() == 1);
    assert(!h->ready_for_debug_readback());
    auto replacement = std::make_shared<MetalFXFrameHistoryState>();
    h->submitted.store(7); bridge_result = MFX_FRAME_INPUT_MISMATCH; invoke(7, 2, false);
    assert(h->callback_error.load() == MFX_FRAME_INPUT_MISMATCH && !h->ready_for_debug_readback());
    int before = calls; h->submitted.store(8); invoke(8, 2, false);
    assert(calls == before && releases == 8 && replacement->encoded.load() == 0);
}
'''
        self.compile_and_run(src, "frame_callback_controls")

    def test_default_off_and_epoch_invalidation_use_actual_methods(self) -> None:
        request = CHECKS.cxx_function(self.base_buffers, "void set_metalfx_frame_requested(")
        reset = CHECKS.cxx_function(self.base_buffers, "void reset_metalfx_observation(")
        src = r'''
#include <cassert>
#include <memory>
#include <string>
struct RenderSceneBuffers {
    bool metal_fx_frame_requested = false; int clears = 0;
    std::shared_ptr<int> metal_fx_history;
    std::string metal_fx_provider, metal_fx_allocation, metal_fx_submission;
    void clear_metalfx_frame() { ++clears; }
'''+ request + "\n" + reset + r'''
};
int main() {
    RenderSceneBuffers b;
    b.set_metalfx_frame_requested(false); assert(b.clears == 0);
    b.set_metalfx_frame_requested(true); assert(b.clears == 1 && b.metal_fx_frame_requested);
    b.set_metalfx_frame_requested(true); assert(b.clears == 1);
    b.metal_fx_history = std::make_shared<int>(1);
    b.reset_metalfx_observation(); assert(b.clears == 2 && !b.metal_fx_history && b.metal_fx_frame_requested);
    b.set_metalfx_frame_requested(false); assert(b.clears == 3 && !b.metal_fx_frame_requested);
}
'''
        self.compile_and_run(src, "frame_default_off_controls")

    def test_source_contract_real_inputs_and_guarded_readback(self) -> None:
        body = CHECKS.cxx_function(self.forward, "void RenderForwardClustered::_process_metalfx_frame(")
        self.assertLess(body.index("if (!p_buffers->is_metalfx_frame_requested())"), body.index("ensure_metalfx_frame_context"))
        for required in ("cam_orthogonal", "get_view_count() != 1", "VIEWPORT_MSAA_DISABLED", "transparent_bg",
                         "get_upscaled_texture(0)", "get_depth_texture(0)", "get_velocity_buffer(false, 0)",
                         "copy_effects->copy_to_rect(source, captures[current]", "texture_clear(output",
                         "params.previous = captures[previous]", "ctx->timeline.commit"):
            self.assertIn(required, body)
        self.assertLess(body.index("effect.process(ctx, params)"), body.index("ctx->timeline.commit"))
        self.assertIn("fx.prevColorTexture = p_reset ? color : prev", self.bridge)
        self.assertIn("fx.outputTextureUsage", self.bridge)
        self.assertIn("get_metalfx_frame_status()", CHECKS.cxx_function(self.storage, "Dictionary RenderSceneBuffersRD::read_metalfx_frame("))
        self.assertIn("texture_get_data(output, 0)", self.storage)
        self.assertIn('result["presentable"] = false', self.base_buffers)


if __name__ == "__main__":
    unittest.main()
