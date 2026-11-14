"""Focused tests for the pinned Godot MetalFX temporal reset patch.

These compile the actual patched request, status and SDK-callback functions
against fake render objects. They do not execute Metal or establish GPU completion.
"""
from __future__ import annotations

import hashlib
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
import zipfile

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("metalfx_patch_checks", HERE / "test_engine_patch.py")
CHECKS = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(CHECKS)
PATCH1 = HERE / "patches/0001-metalfx-allocation-fallback.patch"
PATCH2 = HERE / "patches/0002-metalfx-history-reset.patch"
PATCH1_SHA256 = "f04167e05f452bfc37e85e90d512373d92c3f6ec808cef8431a0705e197d716a"


class TemporalHistoryPatchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        h = hashlib.sha256()
        with CHECKS.ARCHIVE.open("rb") as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                h.update(block)
        if h.hexdigest() != CHECKS.ARCHIVE_SHA256 or hashlib.sha256(PATCH1.read_bytes()).hexdigest() != PATCH1_SHA256:
            raise RuntimeError("Pinned Godot archive or first MetalFX patch differs")
        cls.temp = tempfile.TemporaryDirectory(prefix="openrc-metalfx-history-")
        cls.base = Path(cls.temp.name)
        with zipfile.ZipFile(CHECKS.ARCHIVE) as archive:
            for name in CHECKS.PATHS:
                target = cls.base / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(archive.read(f"godot-{CHECKS.COMMIT}/{name}"))
        for patch in (PATCH1, PATCH2):
            subprocess.run(["git", "apply", "--check", str(patch)], cwd=cls.base, check=True, capture_output=True)
            subprocess.run(["git", "apply", str(patch)], cwd=cls.base, check=True, capture_output=True)
        cls.buffers = (cls.base / "servers/rendering/storage/render_scene_buffers.h").read_text(encoding="utf-8")
        cls.header = (cls.base / "servers/rendering/renderer_rd/effects/metal_fx.h").read_text(encoding="utf-8")
        cls.metal = (cls.base / "servers/rendering/renderer_rd/effects/metal_fx.cpp").read_text(encoding="utf-8")
        cls.viewport = (cls.base / "servers/rendering/renderer_viewport.cpp").read_text(encoding="utf-8")
        cls.forward = (cls.base / "servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp").read_text(encoding="utf-8")

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temp.cleanup()

    def compile_and_run(self, source: str, name: str) -> str:
        return CHECKS.MetalFXPatchTests.compile_and_run(self, source, name)

    def history_declaration(self) -> str:
        return "struct MetalFXTemporalHistoryState " + CHECKS.cxx_block(
            self.buffers, self.buffers.index("struct MetalFXTemporalHistoryState")) + ";"

    def test_apply_order_and_mutation_refusal(self) -> None:
        subprocess.run(["git", "apply", "--reverse", "--check", str(PATCH2)], cwd=self.base, check=True, capture_output=True)
        target = self.base / "servers/rendering/renderer_rd/effects/metal_fx.cpp"
        original = target.read_bytes()
        try:
            target.write_bytes(original.replace(b"p_userdata->history->encoded", b"p_userdata->history->requested", 1))
            refused = subprocess.run(["git", "apply", "--reverse", "--check", str(PATCH2)], cwd=self.base, capture_output=True)
            self.assertNotEqual(refused.returncode, 0)
        finally:
            target.write_bytes(original)

    def test_actual_viewport_request_two_cuts_and_stale_generation(self) -> None:
        src = CHECKS.STATUS_STUB.split("int main() {")[0]
        src = src.replace("#include <cassert>", "#include <cassert>\n#include <atomic>\n#include <memory>\n#include <climits>")
        src = src.replace("enum ViewportAnisotropicFiltering { NONE };", "enum ViewportAnisotropicFiltering { NONE }; enum { VIEWPORT_SCALING_3D_MODE_METALFX_TEMPORAL = 4 };")
        src = src.replace("@RENDER_SCENE_BUFFERS@", self.history_declaration() + "\n" +
                          "class RenderSceneBuffers : public RefCounted " +
                          CHECKS.cxx_block(self.buffers, self.buffers.index("class RenderSceneBuffers :")) + ";")
        src = src.replace("uint64_t metal_fx_generation = 0; int scaling_3d_mode = 3;", 
                          "uint64_t metal_fx_generation = 0, metal_fx_reset_serial = 0; bool disable_3d = false; uint32_t view_count = 1; int scaling_3d_mode = 4;")
        src = src.replace("Dictionary viewport_get_metalfx_status(RID) const;", 
                          "Dictionary viewport_get_metalfx_status(RID) const; Dictionary viewport_request_temporal_history_reset(RID);")
        src = src.replace("@VIEWPORT_GETTER@", CHECKS.cxx_function(self.viewport, "Dictionary RendererViewport::viewport_get_metalfx_status(") + "\n" +
                          CHECKS.cxx_function(self.viewport, "Dictionary RendererViewport::viewport_request_temporal_history_reset("))
        src += r'''
int main() {
    RendererViewport viewport; RendererViewport::Viewport state; state.metal_fx_generation = 7;
    viewport.viewport_owner.viewport = &state;
    assert(!std::get<bool>(viewport.viewport_request_temporal_history_reset({}).at("accepted")));
    TestBuffers buffers; state.render_buffers.value = &buffers; buffers.set_metalfx_configured_mode(4);
    assert(!buffers.get_metalfx_history_state());
    assert(!std::get<bool>(viewport.viewport_request_temporal_history_reset({}).at("accepted")));
    buffers.ensure_metalfx_history_state()->temporal_attempts.store(7); buffers.set_metalfx_status("temporal", "created", "enqueued");
    auto first = viewport.viewport_request_temporal_history_reset({});
    auto second = viewport.viewport_request_temporal_history_reset({});
    assert(std::get<bool>(first.at("accepted")) && std::get<int64_t>(first.at("generation")) == 7);
    assert(std::get<int64_t>(first.at("serial")) == 1 && std::get<int64_t>(second.at("serial")) == 2);
    assert(std::get<int64_t>(first.at("reset_request_attempt")) == 7 && std::get<int64_t>(second.at("reset_request_attempt")) == 7);
    auto old = buffers.get_metalfx_history_state();
    auto status = viewport.viewport_get_metalfx_status({});
    assert(std::get<int64_t>(status.at("reset_requested_serial")) == 2 && std::get<int64_t>(status.at("temporal_attempts")) == 7);
    for (int i = 0; i < 100; ++i) assert(std::get<int64_t>(viewport.viewport_get_metalfx_status({}).at("temporal_attempts")) == 7);
    assert(std::get<int64_t>(status.at("reset_submitted_serial")) == 0 && std::get<int64_t>(status.at("reset_encoded_serial")) == 0);
    MetalFXTemporalHistoryState::advance(old->submitted, 2);
    MetalFXTemporalHistoryState::advance(old->encoded, 2);
    MetalFXTemporalHistoryState::advance(old->encoded, 1);
    status = viewport.viewport_get_metalfx_status({});
    assert(std::get<int64_t>(status.at("reset_submitted_serial")) == 2 && std::get<int64_t>(status.at("reset_encoded_serial")) == 2);
    assert(std::get<String>(status.at("reset_gpu_completion")) == "unobserved");
    auto third = viewport.viewport_request_temporal_history_reset({}); assert(std::get<int64_t>(third.at("serial")) == 3);
    ++state.metal_fx_generation; buffers.reset_metalfx_status(); buffers.set_metalfx_configured_mode(4);
    assert(!buffers.get_metalfx_history_state());
    MetalFXTemporalHistoryState::advance(old->encoded, 3);
    status = viewport.viewport_get_metalfx_status({});
    assert(std::get<int64_t>(status.at("generation")) == 8 && std::get<int64_t>(status.at("reset_encoded_serial")) == 0 && std::get<int64_t>(status.at("temporal_attempts")) == 0);
    assert(!std::get<bool>(viewport.viewport_request_temporal_history_reset({}).at("accepted")));
    buffers.ensure_metalfx_history_state(); buffers.set_metalfx_status("temporal", "created", "enqueued");
    auto fourth = viewport.viewport_request_temporal_history_reset({}); assert(std::get<int64_t>(fourth.at("serial")) == 4);
    auto current = buffers.get_metalfx_history_state(); current->temporal_attempts.store(uint64_t(INT64_MAX) - 2);
    auto boundary = viewport.viewport_request_temporal_history_reset({});
    assert(std::get<bool>(boundary.at("accepted")) && std::get<int64_t>(boundary.at("reset_request_attempt")) == INT64_MAX - 2);
    current->temporal_attempts.store(uint64_t(INT64_MAX) - 1);
    assert(!std::get<bool>(viewport.viewport_request_temporal_history_reset({}).at("accepted")));
    state.view_count = 2; assert(!std::get<bool>(viewport.viewport_request_temporal_history_reset({}).at("accepted")));
    state.view_count = 1; state.disable_3d = true; assert(!std::get<bool>(viewport.viewport_request_temporal_history_reset({}).at("accepted")));
    return 0;
}
'''
        self.compile_and_run(src, "history_viewport")

    def test_camera_and_scenario_changes_invalidate_only_when_changed(self) -> None:
        src = CHECKS.STATUS_STUB.split("int main() {")[0]
        src = src.replace("#include <cassert>", "#include <cassert>\n#include <atomic>\n#include <memory>")
        src = src.replace("#define ERR_FAIL_NULL_V(p, value)", "#define ERR_FAIL_NULL(p) do { if (!(p)) return; } while (false)\n#define ERR_FAIL_NULL_V(p, value)")
        src = src.replace("enum ViewportAnisotropicFiltering { NONE };", "enum ViewportAnisotropicFiltering { NONE }; enum { VIEWPORT_SCALING_3D_MODE_METALFX_TEMPORAL = 4 };")
        src = src.replace("@RENDER_SCENE_BUFFERS@", self.history_declaration() + "\n" +
                          "class RenderSceneBuffers : public RefCounted " +
                          CHECKS.cxx_block(self.buffers, self.buffers.index("class RenderSceneBuffers :")) + ";")
        src = src.replace("struct RID { int id = 0; };", "struct RID { int id = 0; bool is_valid() const { return id != 0; } bool operator!=(RID other) const { return id != other.id; } };")
        src = src.replace("uint64_t metal_fx_generation = 0; int scaling_3d_mode = 3;", "uint64_t metal_fx_generation = 0; int scaling_3d_mode = 3; RID camera, scenario; bool use_occlusion_culling = false;")
        src = src.replace("Dictionary viewport_get_metalfx_status(RID) const;", "Dictionary viewport_get_metalfx_status(RID) const; void viewport_attach_camera(RID, RID); void viewport_set_scenario(RID, RID);")
        extras = r"""
struct DummyScene { void scenario_remove_viewport_visibility_mask(RID, RID) {} };
namespace RSG { DummyScene instance; DummyScene *scene = &instance; }
struct RendererSceneOcclusionCull {
    static RendererSceneOcclusionCull *get_singleton() { static RendererSceneOcclusionCull c; return &c; }
    void buffer_set_scenario(RID, RID) {}
};
"""
        methods = CHECKS.cxx_function(self.viewport, "void RendererViewport::viewport_attach_camera(") + "\n" + \
                  CHECKS.cxx_function(self.viewport, "void RendererViewport::viewport_set_scenario(")
        src = src.replace("@VIEWPORT_GETTER@", CHECKS.cxx_function(self.viewport, "Dictionary RendererViewport::viewport_get_metalfx_status(") + "\n" + extras + methods)
        src += r"""
int main() {
    RendererViewport viewport; RendererViewport::Viewport state; state.metal_fx_generation = 7;
    viewport.viewport_owner.viewport = &state; TestBuffers buffers; state.render_buffers.value = &buffers;
    buffers.set_metalfx_configured_mode(4); buffers.ensure_metalfx_history_state()->initial_reset_encoded.store(true);
    state.camera = {1}; auto original = buffers.get_metalfx_history_state();
    viewport.viewport_attach_camera({}, {1}); assert(state.metal_fx_generation == 7 && buffers.get_metalfx_history_state() == original);
    viewport.viewport_attach_camera({}, {2}); assert(state.metal_fx_generation == 8 && !buffers.get_metalfx_history_state());
    auto camera_state = buffers.ensure_metalfx_history_state(); assert(!camera_state->initial_reset_encoded.load());
    viewport.viewport_attach_camera({}, {2}); assert(state.metal_fx_generation == 8 && buffers.get_metalfx_history_state() == camera_state);
    viewport.viewport_set_scenario({}, {3}); assert(state.metal_fx_generation == 9 && !buffers.get_metalfx_history_state());
    auto scenario_state = buffers.ensure_metalfx_history_state(); assert(!scenario_state->initial_reset_encoded.load());
    viewport.viewport_set_scenario({}, {3}); assert(state.metal_fx_generation == 9 && buffers.get_metalfx_history_state() == scenario_state);
    MetalFXTemporalHistoryState::advance(camera_state->encoded, 42);
    auto status = viewport.viewport_get_metalfx_status({}); assert(std::get<int64_t>(status.at("reset_encoded_serial")) == 0);
    return 0;
}
"""
        self.compile_and_run(src, "history_camera_scenario")

    def test_actual_sdk_callback_ack_and_failed_enqueue(self) -> None:
        start = self.header.index("// Synchronous factory outcome")
        spatial_end = self.header.index("class MFXSpatialEffect", start)
        temporal_start = self.header.index("struct MFXTemporalContext")
        temporal_end = self.header.index("class MFXTemporalEffect", temporal_start)
        contexts = self.header[start:spatial_end] + self.header[temporal_start:temporal_end]
        args1 = CHECKS.cxx_block(self.header, self.header.index("struct CallbackArgs", spatial_end))
        args2 = CHECKS.cxx_block(self.header, self.header.index("struct CallbackArgs", temporal_end))
        src = CHECKS.CALLBACK_STUB.split("int main() {")[0]
        src = src.replace("#include <cassert>", "#include <cassert>\n#include <atomic>\n#include <memory>")
        src = src.replace("void setFence(int) {} void setReset(bool) {} void setColorTexture(MTL::Texture *) {}",
                          "bool last_reset = false; int resets = 0; void setFence(int) {} void setReset(bool value) { last_reset = value; ++resets; } void setColorTexture(MTL::Texture *) {}")
        src = src.replace("struct TemporalScaler : TemporalScalerBase { void encodeToCommandBuffer(int) {} };",
                          "struct TemporalScaler : TemporalScalerBase { int encodes = 0; void encodeToCommandBuffer(int) { ++encodes; } };")
        src = src.replace("namespace RendererRD {\n@CONTEXTS@", self.history_declaration() + "\nnamespace RendererRD {\n@CONTEXTS@")
        src = src.replace("struct Params { RID src, depth, motion, exposure, dst; Vector2 jitter_offset; bool reset = false; };",
                          "struct Params { RID src, depth, motion, exposure, dst; Vector2 jitter_offset; bool reset = false; std::shared_ptr<MetalFXTemporalHistoryState> history; uint64_t reset_serial = 0; };")
        replacements = {"@CONTEXTS@": contexts, "@SPATIAL_ARGS@": args1, "@TEMPORAL_ARGS@": args2,
                        "@SPATIAL_DESTRUCTOR@": CHECKS.cxx_function(self.metal, "MFXSpatialContext::~MFXSpatialContext("),
                        "@TEMPORAL_DESTRUCTOR@": CHECKS.cxx_function(self.metal, "MFXTemporalContext::~MFXTemporalContext("),
                        "@SPATIAL_PROCESS@": CHECKS.cxx_function(self.metal, "bool MFXSpatialEffect::try_process("),
                        "@TEMPORAL_PROCESS@": CHECKS.cxx_function(self.metal, "bool MFXTemporalEffect::process("),
                        "@SPATIAL_CALLBACK@": CHECKS.cxx_function(self.metal, "void MFXSpatialEffect::callback("),
                        "@TEMPORAL_CALLBACK@": CHECKS.cxx_function(self.metal, "void MFXTemporalEffect::callback(")}
        for key, value in replacements.items():
            src = src.replace(key, value)
        src += r'''
int main() {
    RD *rd = RD::get_singleton(); MTL3::MDCommandBuffer cmd;
    MTLFX::TemporalScaler scaler; MFXTemporalContext ctx; ctx.scaler = &scaler; ctx.allocation_status = MFXAllocationStatus::SCALER_CREATED;
    MFXTemporalEffect effect; MFXTemporalEffect::Params p; p.src={1}; p.depth={2}; p.motion={3}; p.dst={4};
    auto old = std::make_shared<MetalFXTemporalHistoryState>(); old->requested.store(2);
    p.history = old; p.reset = true; p.reset_serial = 2; rd->fail = true;
    assert(!effect.process(&ctx, p) && old->submitted.load() == 0 && old->encoded.load() == 0 && allocations == 0 && scaler.refs == 1);
    ctx.submission_status = MFXSubmissionStatus::NOT_ATTEMPTED; rd->fail = false;
    assert(effect.process(&ctx, p));
    assert(old->submitted.load() == 2 && old->encoded.load() == 0 && allocations == 1 && scaler.refs == 2);
    auto next_generation = std::make_shared<MetalFXTemporalHistoryState>();
    scaler.release(); ctx.scaler = nullptr; // Context is destroyed before old callback runs.
    rd->run(cmd);
    assert(old->encoded.load() == 2 && next_generation->encoded.load() == 0 && allocations == 0);
    assert(old->initial_reset_encoded.load() && !next_generation->initial_reset_encoded.load());
    assert(scaler.resets == 1 && scaler.last_reset && scaler.encodes == 1);
    MetalFXTemporalHistoryState::advance(old->encoded, 1); assert(old->encoded.load() == 2);
    cmd.release_resource(); assert(scaler.refs == 0);
    MTLFX::TemporalScaler other; MFXTemporalContext ctx2; ctx2.scaler = &other; ctx2.allocation_status = MFXAllocationStatus::SCALER_CREATED;
    p.reset = false; p.reset_serial = 3; p.history = next_generation;
    assert(effect.process(&ctx2, p) && next_generation->submitted.load() == 0);
    rd->run(cmd); assert(!other.last_reset && other.encodes == 1 && next_generation->encoded.load() == 0 && !next_generation->initial_reset_encoded.load());
    cmd.release_resource();
    auto abandoned = std::make_shared<MetalFXTemporalHistoryState>(); std::weak_ptr<MetalFXTemporalHistoryState> weak = abandoned;
    p.reset = true; p.reset_serial = 5; p.history = abandoned;
    assert(effect.process(&ctx2, p)); p.history.reset(); abandoned.reset();
    assert(!weak.expired()); // The queued callback owns its generation after viewport destruction.
    rd->run(cmd); assert(weak.expired()); cmd.release_resource();
    return 0;
}
'''
        self.compile_and_run(src, "history_callback")

    def test_next_frame_reset_and_coalescing_routing(self) -> None:
        src = CHECKS.TEMPORAL_STUB.split("@ENSURE@")[0]
        src = src.replace("#include <cassert>", "#include <cassert>\n#include <atomic>\n#include <memory>")
        src = src.replace("struct Buffers {", self.history_declaration() + "\nstruct Buffers {")
        src = src.replace("uint32_t views = 2;", "uint32_t views = 1; std::shared_ptr<MetalFXTemporalHistoryState> history = std::make_shared<MetalFXTemporalHistoryState>();\n    std::shared_ptr<MetalFXTemporalHistoryState> ensure_metalfx_history_state() { return history; }")
        src = src.replace("struct Params { RID src, depth, motion, exposure, dst; Vector2 jitter_offset; bool reset = false; };",
                          "struct Params { RID src, depth, motion, exposure, dst; Vector2 jitter_offset; bool reset = false; std::shared_ptr<MetalFXTemporalHistoryState> history; uint64_t reset_serial = 0; };")
        src = src.replace("submitted.push_back(params); return true;",
                          "submitted.push_back(params); if (params.reset && params.history && params.reset_serial) MetalFXTemporalHistoryState::advance(params.history->submitted, params.reset_serial); return true;")
        src += CHECKS.cxx_function(self.forward, "bool RenderForwardClustered::RenderBufferDataForwardClustered::ensure_mfx_temporal(")
        branch = self.forward.index("} else if (scale_type == SCALE_MFX)")
        history = self.forward[self.forward.index("std::shared_ptr<MetalFXTemporalHistoryState> history", branch):self.forward.index("RID exposure;", branch)]
        loop = self.forward[self.forward.index("bool submitted = context", branch):self.forward.index("RD::get_singleton()->draw_command_end_label();", branch)]
        src += r"""
int main() {
    Buffers storage; Buffers *rb = &storage; RendererRD::MFXTemporalContext good; good.usable = true;
    RendererRD::MFXTemporalEffect effect; effect.next = &good; auto *mfx_temporal_effect = &effect;
    RenderForwardClustered::RenderBufferDataForwardClustered data{rb}; CopyEffects copy; CopyEffects *copy_effects = &copy;
    RID exposure; Vector2 jitter;
    auto run = [&]() {
        bool reset = data.ensure_mfx_temporal(&effect);
        RendererRD::MFXTemporalContext *context = data.mfx_temporal_context;
""" + history + loop + r"""
    };
    run(); assert(effect.submitted.size() == 1 && effect.submitted.back().reset && effect.submitted.back().reset_serial == 0 && rb->history->temporal_attempts.load() == 1);
    effect.submitted.clear(); run(); assert(effect.submitted.back().reset && rb->history->temporal_attempts.load() == 2); // no callback returned yet
    rb->history->initial_reset_encoded.store(true);
    effect.submitted.clear(); run(); assert(!effect.submitted.back().reset);
    effect.submitted.clear(); rb->history->requested.store(1); rb->history->requested.store(2);
    run(); assert(effect.submitted.size() == 1 && effect.submitted.back().reset && effect.submitted.back().reset_serial == 2);
    assert(rb->history->submitted.load() == 2 && rb->history->encoded.load() == 0);
    effect.submitted.clear(); run(); assert(!effect.submitted.back().reset && effect.submitted.back().reset_serial == 0);
    effect.submitted.clear(); rb->history = std::make_shared<MetalFXTemporalHistoryState>(); // disable then enable, same scaler
    run(); assert(effect.submitted.back().reset && effect.submitted.back().reset_serial == 0 && effect.allocations == 1 && rb->history->temporal_attempts.load() == 1);
    effect.submitted.clear(); run(); assert(effect.submitted.back().reset);
    rb->history->initial_reset_encoded.store(true); effect.submitted.clear(); run(); assert(!effect.submitted.back().reset);
    effect.submitted.clear(); rb->history->requested.store(3); effect.fail_view = 40;
    run(); assert(effect.submitted.empty() && rb->history->submitted.load() == 0 && rb->history->temporal_attempts.load() == 4 && copy.calls.size() == 1);
    run(); assert(effect.submitted.empty() && rb->history->temporal_attempts.load() == 5 && copy.calls.size() == 2); // failed allocation/context still counts
    good.usable = true; effect.fail_view = -1; rb->history->temporal_attempts.store(uint64_t(INT64_MAX) - 1);
    run(); run(); assert(rb->history->temporal_attempts.load() == uint64_t(INT64_MAX));
    return 0;
}
"""
        self.compile_and_run(src, "history_routing")

    def test_render_routing_and_provider_contract(self) -> None:
        configure = CHECKS.cxx_function(self.viewport, "void RendererViewport::_configure_3d_render_buffers(")
        self.assertIn("p_viewport->view_count != 1", configure)
        self.assertIn("scaling_3d_mode = RSE::VIEWPORT_SCALING_3D_MODE_BILINEAR", configure)
        self.assertIn("requested_serial > submitted_serial ? requested_serial : 0", self.forward)
        self.assertIn("params.reset = reset || reset_generation || reset_serial != 0", self.forward)
        self.assertIn("params.history = history", self.forward)
        server = (self.base / "servers/rendering/rendering_server.cpp").read_text(encoding="utf-8")
        default = (self.base / "servers/rendering/rendering_server_default.h").read_text(encoding="utf-8")
        self.assertIn('D_METHOD("viewport_request_temporal_history_reset", "viewport")', server)
        self.assertIn('D_METHOD("get_temporal_history_reset_providers")', server)
        self.assertIn('providers.push_back("metalfx_temporal")', server)
        self.assertIn("FUNC1R(Dictionary, viewport_request_temporal_history_reset, RID)", default)


if __name__ == "__main__":
    unittest.main()
