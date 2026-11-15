"""Compile the real adapter state transitions against bounded stand-ins.

These controls exercise the patched C++ and do not execute Metal or a display.
"""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import zipfile

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("composition_controls", HERE / "test_engine_composition_patch.py")
COMPOSITION = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(COMPOSITION)
ENGINE, CHECK, ARCHIVE = COMPOSITION.ENGINE, COMPOSITION.CHECK, COMPOSITION.ARCHIVE
PATCHES = [HERE / "patches" / name for name in (
    "0001-metalfx-allocation-fallback.patch", "0002-metalfx-history-reset.patch",
    "0003-metalfx-debug-faults.patch", "0004-metalfx-frame-inputs.patch",
    "0005-metal-triangle-query.patch", "0006-metalfx-gpu-observation.patch",
    "0007-metalfx-denoised-binding.patch", "0008-metal-paired-presentation.patch",
    "0009-metalfx-frame-composition.patch", "0010-metal-empty-submit-fence.patch",
    "0011-metalfx-presentation-adapter.patch")]

SOURCE_HARNESS = r'''
#include <atomic>
#include <cstdlib>
#include <memory>
#include <thread>
#include "servers/rendering/storage/metalfx_presentation.h"
#define CHECK(x) do { if (!(x)) std::_Exit(__LINE__ % 250 + 1); } while (false)
namespace DisplayServerEnums { enum { MAIN_WINDOW_ID=0 }; }
struct RendererViewport { struct Viewport {
    int viewport_to_screen=0;
    std::shared_ptr<OpenRCMetalPresent::SourceGeneration> metal_fx_presentation_source;
}; };
@GLOBALS@
@QUIESCENT@
@NEW_SOURCE@
@CANCEL_MAIN@
@CANCEL@
int main() {
    auto first=mfx_new_source(); CHECK(first && mfx_new_source()==first);
    RendererViewport::Viewport vp; vp.metal_fx_presentation_source=first;
    std::atomic<bool> entered{false},release{false};
    std::thread present([&] {
        auto lock=first->lock_for_presentation(); entered.store(true,std::memory_order_release);
        while (!release.load(std::memory_order_acquire)) std::this_thread::yield();
    });
    while (!entered.load(std::memory_order_acquire)) std::this_thread::yield();
    mfx_cancel_viewport_source(&vp); // Must return without waiting for the presentation lock.
    CHECK(first->is_cancelled() && !mfx_sources_quiescent() && !mfx_new_source());
    release.store(true,std::memory_order_release); present.join();
    CHECK(mfx_sources_quiescent());
    auto second=mfx_new_source(); CHECK(second && second!=first && mfx_new_source()==second);
    RendererViewport::Viewport other; other.viewport_to_screen=1;
    mfx_cancel_viewport_source(&other); CHECK(!second->is_cancelled());
    other.viewport_to_screen=0; mfx_cancel_viewport_source(&other); CHECK(second->is_cancelled());
    CHECK(mfx_sources_quiescent());
}
'''

SETTER_HARNESS = r'''
#include <cstdlib>
#define CHECK(x) do { if (!(x)) std::_Exit(__LINE__ % 250 + 1); } while (false)
#define ERR_FAIL_NULL(x) do { if (!(x)) return; } while (false)
using RID=int;
namespace RSE { enum ViewportUpdateMode { VIEWPORT_UPDATE_DISABLED,VIEWPORT_UPDATE_ALWAYS }; }
struct Buffers { bool enabled=false; void set_metalfx_frame_composition_requested(bool v) { enabled=v; } };
struct Ref { Buffers *value=nullptr; bool is_valid() const { return value; } Buffers *operator->() const { return value; } };
struct RendererViewport {
    struct Viewport { bool metal_fx_frame_composition_requested=false; RSE::ViewportUpdateMode update_mode=RSE::VIEWPORT_UPDATE_DISABLED; Ref render_buffers; };
    struct Owner { Viewport *value=nullptr; Viewport *get_or_null(RID) { return value; } } viewport_owner;
    void viewport_set_metalfx_frame_composition_requested(RID,bool);
    void viewport_set_update_mode(RID,RSE::ViewportUpdateMode);
};
static int cancellations=0;
static void mfx_cancel_viewport_source(RendererViewport::Viewport *) { ++cancellations; }
@COMPOSITION_SETTER@
@UPDATE_SETTER@
int main() {
    RendererViewport renderer; RendererViewport::Viewport vp; Buffers buffers;
    vp.render_buffers.value=&buffers; renderer.viewport_owner.value=&vp;
    renderer.viewport_set_metalfx_frame_composition_requested(0,false); CHECK(cancellations==0);
    renderer.viewport_set_metalfx_frame_composition_requested(0,true); CHECK(cancellations==0 && buffers.enabled);
    renderer.viewport_set_metalfx_frame_composition_requested(0,false); CHECK(cancellations==1 && !buffers.enabled);
    renderer.viewport_set_metalfx_frame_composition_requested(0,false); CHECK(cancellations==1);
    renderer.viewport_set_update_mode(0,RSE::VIEWPORT_UPDATE_DISABLED); CHECK(cancellations==1);
    renderer.viewport_set_update_mode(0,RSE::VIEWPORT_UPDATE_ALWAYS); CHECK(cancellations==2);
    renderer.viewport_set_update_mode(0,RSE::VIEWPORT_UPDATE_ALWAYS); CHECK(cancellations==2);
    renderer.viewport_set_update_mode(0,RSE::VIEWPORT_UPDATE_DISABLED); CHECK(cancellations==3);
}
'''

RING_CLASS = r'''
#include <vector>
template<class T> struct Vector {
    std::vector<T> values;
    struct Proxy { Vector *self; T &operator[](int i) { return self->values.at(i); } } write{this};
    int size() const { return int(values.size()); }
    bool is_empty() const { return values.empty(); }
    void push_back(T x) { values.push_back(std::move(x)); }
    void remove_at(int i) { values.erase(values.begin()+i); }
};
struct MetalFXPendingPair {
    RID generated_texture,real_texture; double real_interval=0;
    std::shared_ptr<OpenRCMetalPresent::Proof> proof;
    std::shared_ptr<OpenRCMetalPresent::Ticket> ticket;
};
struct OS { static OS *get_singleton() { static OS o; return &o; } void delay_usec(int) {} };
#define CRASH_COND_MSG(c,m) do { if (c) std::_Exit(99); } while (false)
struct RenderSceneBuffersRD {
    struct MFXCompositionSlot {
        RID generated_target,real_target;
        std::shared_ptr<MetalFXCompositionFrame> state;
        std::shared_ptr<OpenRCMetalPresent::Lease> lease;
        bool submitted=false,encode_enqueued=false,tonemapped=false,eligible=false;
    } mfx_composition_slots[2];
    struct MFXRetiredCompositionSlot {
        RID generated_target,real_target;
        std::shared_ptr<OpenRCMetalPresent::Lease> lease;
    };
    static Vector<MFXRetiredCompositionSlot> mfx_retired_composition_slots;
    static uint32_t mfx_live_composition_slots;
    static constexpr uint32_t MFX_MAX_LIVE_COMPOSITION_SLOTS=4;
    int mfx_composition_active=-1,mfx_composition_handoff=-1;
    std::weak_ptr<OpenRCMetalPresent::Proof> mfx_presentation_proofs[8];
    uint64_t mfx_composition_invalid_through=0,mfx_composition_current_frame=0;
    bool mfx_composition_faulted=false,mfx_presentation_incompatible=false,requested=true,frame_requested=true;
    String mfx_composition_reason="not_attempted";
    RID render_target{100}; Size2i target_size{1920,1080};
    RendererRD::MFXFrameContext *mfx_frame_context=nullptr;
    std::shared_ptr<OpenRCMetalPresent::SourceGeneration> source;
    bool is_metalfx_frame_composition_requested() const { return requested; }
    bool is_metalfx_frame_requested() const { return frame_requested; }
    auto get_metalfx_presentation_source() const { return source; }
    void cancel_metalfx_presentation_source() { if (source) source->request_cancel(); }
    void invalidate_metalfx_presentation_once() {
        if (!mfx_presentation_incompatible) { cancel_metalfx_presentation_source(); mfx_presentation_incompatible=true; }
    }
    static void collect_metalfx_retired_slots();
    static void finalize_metalfx_retirements();
    int _metalfx_composition_ready_slot() const;
    void clear_metalfx_frame_composition();
    void begin_metalfx_frame_composition(uint64_t,bool);
    RID get_metalfx_frame_composition_target() const;
    void finish_metalfx_frame_composition(bool);
    bool acquire_metalfx_pending_pair(uint64_t,MetalFXPendingPair &);
};
Vector<RenderSceneBuffersRD::MFXRetiredCompositionSlot> RenderSceneBuffersRD::mfx_retired_composition_slots;
uint32_t RenderSceneBuffersRD::mfx_live_composition_slots=0;
@COLLECT@
@FINALIZE@
@CLEAR@
@READY@
@BEGIN@
@TARGET@
@FINISH@
@ACQUIRE@
static void done(const std::shared_ptr<MetalFXGPUObservation> &observer) {
    auto s=observer->snapshot().encoded;
    CHECK(s.ticket==1 && observer->completed(s,true,true,4,false,0,1,2,1));
}
static std::shared_ptr<MetalFXCompositionFrame> submit(RenderSceneBuffersRD &b,uint64_t frame) {
    b.begin_metalfx_frame_composition(frame,true); CHECK(b.mfx_composition_active>=0);
    auto &slot=b.mfx_composition_slots[b.mfx_composition_active]; auto p=slot.state;
    p->epoch=8; p->serial=frame; p->previous_frame=frame-1; p->real_interval=1.0/60.0;
    p->presentation_proof=std::make_shared<OpenRCMetalPresent::Proof>(frame-1,frame,8,frame);
    p->warm_count.store(5); p->encode_result.store(1);
    CHECK(p->sdk_completion->encoded(frame,8).ticket==1); done(p->sdk_completion);
    slot.tonemapped=true; slot.encode_enqueued=true;
    b.finish_metalfx_frame_composition(true); return p;
}
int main(int argc,char **argv) {
    (void)argv;
    auto *storage=RendererRD::TextureStorage::get_singleton(); storage->targets[100]={{1920,1080},false,true};
    auto history=std::make_shared<MetalFXFrameHistoryState>(); history->requested_epoch.store(8);
    RendererRD::MFXFrameContext context{history};
    RenderSceneBuffersRD b; b.mfx_frame_context=&context; b.source=std::make_shared<OpenRCMetalPresent::SourceGeneration>();
    auto state=submit(b,10); done(state->completion);
    MetalFXPendingPair pair; CHECK(!b.acquire_metalfx_pending_pair(9,pair));
    CHECK(b.acquire_metalfx_pending_pair(10,pair) && pair.ticket && pair.proof && pair.proof->frame==10);
    CHECK(!b.acquire_metalfx_pending_pair(10,pair)); // one ticket per source slot.
    b.begin_metalfx_frame_composition(11,true); CHECK(b.mfx_composition_active==1); // Held slot 0 cannot be reused.
    auto proof=pair.proof; b.clear_metalfx_frame_composition();
    CHECK(proof->is_cancelled() && b.source->is_cancelled());
    CHECK(b.mfx_retired_composition_slots.size()==1 && b.mfx_live_composition_slots==1);
    int freed=storage->freed; b.collect_metalfx_retired_slots(); CHECK(storage->freed==freed);
    if (argc>1) { b.finalize_metalfx_retirements(); return 0; } // held ticket must fail-stop.
    pair.ticket.reset(); b.collect_metalfx_retired_slots();
    CHECK(storage->freed==freed+2 && b.mfx_live_composition_slots==0);
    b.finalize_metalfx_retirements();

    RenderSceneBuffersRD many; many.mfx_frame_context=&context; many.source=std::make_shared<OpenRCMetalPresent::SourceGeneration>();
    std::vector<std::shared_ptr<OpenRCMetalPresent::Proof>> held;
    for (uint64_t frame=20;frame<28;++frame) {
        auto p=submit(many,frame); done(p->completion);
        MetalFXPendingPair next; CHECK(many.acquire_metalfx_pending_pair(frame,next));
        held.push_back(next.proof); next.ticket.reset();
    }
    auto last=submit(many,28); done(last->completion);
    MetalFXPendingPair full; CHECK(!many.acquire_metalfx_pending_pair(28,full));
    many.clear_metalfx_frame_composition();
    for (auto &item : held) CHECK(item->is_cancelled());
    many.finalize_metalfx_retirements();

    std::vector<MetalFXPendingPair> leases;
    for (uint64_t frame=40;frame<44;++frame) {
        RenderSceneBuffersRD v; v.mfx_frame_context=&context; v.source=std::make_shared<OpenRCMetalPresent::SourceGeneration>();
        auto p=submit(v,frame); done(p->completion);
        MetalFXPendingPair ticket; CHECK(v.acquire_metalfx_pending_pair(frame,ticket));
        leases.push_back(ticket); ticket.ticket.reset(); v.clear_metalfx_frame_composition();
    }
    CHECK(RenderSceneBuffersRD::mfx_live_composition_slots==4);
    RenderSceneBuffersRD saturated; saturated.mfx_frame_context=&context; saturated.source=std::make_shared<OpenRCMetalPresent::SourceGeneration>();
    int created=storage->created; saturated.begin_metalfx_frame_composition(44,true);
    CHECK(saturated.mfx_composition_active==-1 && storage->created==created);
    for (auto &item : leases) item.ticket.reset();
    saturated.collect_metalfx_retired_slots(); CHECK(RenderSceneBuffersRD::mfx_live_composition_slots==0);
    saturated.finalize_metalfx_retirements();
}
'''


class AdapterPatchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.compiler = shutil.which("g++") or shutil.which("clang++")
        if not cls.compiler or not ARCHIVE.is_file():
            raise unittest.SkipTest("C++17 compiler or pinned engine archive unavailable")
        if ENGINE.sha256(ARCHIVE) != ENGINE.SOURCE_SHA256:
            raise RuntimeError("Godot source archive differs from independent pin")
        cls.temp = tempfile.TemporaryDirectory(prefix="openrc-metalfx-adapter-")
        cls.addClassCleanup(cls.temp.cleanup)
        cls.base = Path(cls.temp.name)
        with zipfile.ZipFile(ARCHIVE) as archive:
            members = set(archive.namelist())
            for name in ENGINE.patch_paths(PATCHES):
                member = f"{ENGINE.SOURCE_PREFIX}/{name}"
                if member in members:
                    target = cls.base / name
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(archive.read(member))
        for patch in PATCHES:
            ENGINE.git(cls.base, "apply", "--check", str(patch.resolve()))
            ENGINE.git(cls.base, "apply", str(patch.resolve()))
        cls.buffers = (cls.base / "servers/rendering/storage/render_scene_buffers.h").read_text(encoding="utf-8")
        cls.viewport = (cls.base / "servers/rendering/renderer_viewport.cpp").read_text(encoding="utf-8")
        cls.effects = (cls.base / "servers/rendering/renderer_rd/effects/metal_fx.cpp").read_text(encoding="utf-8")
        cls.rd_buffers = (cls.base / "servers/rendering/renderer_rd/storage_rd/render_scene_buffers_rd.cpp").read_text(encoding="utf-8")
        cls.frame = "struct MetalFXCompositionFrame " + CHECK.cxx_block(cls.buffers, cls.buffers.index("struct MetalFXCompositionFrame")) + ";"
        cls.history = "struct MetalFXFrameHistoryState " + CHECK.cxx_block(cls.buffers, cls.buffers.index("struct MetalFXFrameHistoryState")) + ";"

    def compile_run(self, source: str, name: str) -> subprocess.CompletedProcess:
        cpp = self.base / f"{name}.cpp"
        binary = self.base / (name + (".exe" if os.name == "nt" else ""))
        cpp.write_text(source, encoding="utf-8")
        built = subprocess.run([self.compiler, "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror", "-pthread", "-I", str(self.base), str(cpp), "-o", str(binary)], capture_output=True, text=True, timeout=90)
        self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
        return subprocess.run([str(binary)], capture_output=True, text=True, timeout=20)

    def test_actual_source_barrier_does_not_wait_or_publish_before_quiescence(self):
        source = SOURCE_HARNESS.replace("@GLOBALS@", "static std::shared_ptr<OpenRCMetalPresent::SourceGeneration> mfx_sources[4];")
        source = source.replace("@QUIESCENT@", CHECK.cxx_function(self.viewport, "static bool mfx_sources_quiescent("))
        source = source.replace("@NEW_SOURCE@", CHECK.cxx_function(self.viewport, "static std::shared_ptr<OpenRCMetalPresent::SourceGeneration> mfx_new_source("))
        source = source.replace("@CANCEL_MAIN@", CHECK.cxx_function(self.viewport, "static void mfx_cancel_main_sources("))
        source = source.replace("@CANCEL@", CHECK.cxx_function(self.viewport, "static void mfx_cancel_viewport_source("))
        source = "#define METAL_ENABLED\n#define MACOS_ENABLED\n" + source
        result = self.compile_run(source, "source_barrier")
        self.assertEqual(result.returncode, 0, f"source barrier returned {result.returncode}: {result.stdout}{result.stderr}")

    def test_source_barrier_mutation_is_caught(self):
        quiet = CHECK.cxx_function(self.viewport, "static bool mfx_sources_quiescent(")
        self.assertIn("!source->try_cancel_complete()", quiet)
        quiet = quiet.replace("!source->try_cancel_complete()", "false && !source->try_cancel_complete()")
        source = SOURCE_HARNESS.replace("@GLOBALS@", "static std::shared_ptr<OpenRCMetalPresent::SourceGeneration> mfx_sources[4];")
        source = source.replace("@QUIESCENT@", quiet)
        source = source.replace("@NEW_SOURCE@", CHECK.cxx_function(self.viewport, "static std::shared_ptr<OpenRCMetalPresent::SourceGeneration> mfx_new_source("))
        source = source.replace("@CANCEL_MAIN@", CHECK.cxx_function(self.viewport, "static void mfx_cancel_main_sources("))
        source = source.replace("@CANCEL@", CHECK.cxx_function(self.viewport, "static void mfx_cancel_viewport_source("))
        result = self.compile_run("#define METAL_ENABLED\n#define MACOS_ENABLED\n" + source, "mutant_barrier")
        self.assertNotEqual(result.returncode, 0, "quiescence mutant escaped the behavioral control")

    def test_actual_setters_do_not_cancel_for_unchanged_values(self):
        source = SETTER_HARNESS.replace("@COMPOSITION_SETTER@", CHECK.cxx_function(self.viewport, "void RendererViewport::viewport_set_metalfx_frame_composition_requested("))
        source = source.replace("@UPDATE_SETTER@", CHECK.cxx_function(self.viewport, "void RendererViewport::viewport_set_update_mode("))
        result = self.compile_run(source, "setters")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_exact_sdk_callback_updates_presenter_proof_only_after_completion(self):
        source = COMPOSITION.FRAME_HARNESS.replace("@FRAME@", self.frame).replace("@HISTORY@", self.history)
        source = source.replace('#include "servers/rendering/storage/metalfx_gpu_observation.h"', '#include "servers/rendering/storage/metalfx_gpu_observation.h"\n#include "servers/rendering/storage/metalfx_presentation.h"')
        source = source.replace("@OBSERVER@", CHECK.cxx_function(self.effects, "static void mfx_observe_gpu("))
        source = source.replace("@SDK_CALLBACK@", CHECK.cxx_function(self.effects, "void MFXFrameEffect::callback("))
        source = source.replace("@COMPOSE_CALLBACK@", CHECK.cxx_function(self.effects, "void MFXCompositionEffect::callback("))
        source = source.replace("p->frame=72; p->epoch=8; p->serial=9;", "p->frame=72; p->epoch=8; p->serial=9; p->presentation_proof=std::make_shared<OpenRCMetalPresent::Proof>(71,72,8,9);")
        source = source.replace("failed->frame=73; failed->epoch=8; failed->serial=10;", "failed->frame=73; failed->epoch=8; failed->serial=10; failed->presentation_proof=std::make_shared<OpenRCMetalPresent::Proof>(72,73,8,10);")
        source = source.replace("rejected->frame=74; rejected->epoch=8; rejected->serial=11;", "rejected->frame=74; rejected->epoch=8; rejected->serial=11; rejected->presentation_proof=std::make_shared<OpenRCMetalPresent::Proof>(73,74,8,11);")
        source = source.replace("composed.command.finish(); assert(!p->ready(72,8));", "composed.command.finish(); assert(!p->ready(72,8)); assert(p->presentation_proof->encode_result.load()==1 && p->presentation_proof->warm_count.load()==5 && p->presentation_proof->sdk_completion.load()==0);")
        source = source.replace("sdk.command.finish(); assert(p->ready(72,8));", "sdk.command.finish(); assert(p->ready(72,8)); assert(p->presentation_proof->sdk_completion.load()==1);")
        source = source.replace("pair_ok.command.finish(); sdk_bad.command.finish(); assert(!failed->ready(73,8));", "pair_ok.command.finish(); sdk_bad.command.finish(); assert(!failed->ready(73,8)); assert(failed->presentation_proof->sdk_completion.load()==-1);")
        source = source.replace("assert(rejected->encode_result.load()==-1 && reject_sdk.command.handlers.empty());", "assert(rejected->encode_result.load()==-1 && reject_sdk.command.handlers.empty()); assert(rejected->presentation_proof->encode_result.load()==-1 && rejected->presentation_proof->sdk_completion.load()==-1);")
        result = self.compile_run(source, "sdk_proof")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_current_pair_leases_retirement_and_registry_cap(self):
        prefix = COMPOSITION.RING_HARNESS[:COMPOSITION.RING_HARNESS.index("struct RenderSceneBuffersRD {")]
        prefix = prefix.replace('#include "servers/rendering/storage/metalfx_gpu_observation.h"', '#include "servers/rendering/storage/metalfx_gpu_observation.h"\n#include "servers/rendering/storage/metalfx_presentation.h"')
        source = (prefix + RING_CLASS).replace("@FRAME@", self.frame).replace("@HISTORY@", self.history)
        for marker, signature in (
            ("@COLLECT@", "void RenderSceneBuffersRD::collect_metalfx_retired_slots("),
            ("@FINALIZE@", "void RenderSceneBuffersRD::finalize_metalfx_retirements("),
            ("@CLEAR@", "void RenderSceneBuffersRD::clear_metalfx_frame_composition("),
            ("@READY@", "int RenderSceneBuffersRD::_metalfx_composition_ready_slot("),
            ("@BEGIN@", "void RenderSceneBuffersRD::begin_metalfx_frame_composition("),
            ("@TARGET@", "RID RenderSceneBuffersRD::get_metalfx_frame_composition_target("),
            ("@FINISH@", "void RenderSceneBuffersRD::finish_metalfx_frame_composition("),
            ("@ACQUIRE@", "bool RenderSceneBuffersRD::acquire_metalfx_pending_pair("),
        ):
            source = source.replace(marker, CHECK.cxx_function(self.rd_buffers, signature))
        cpp = self.base / "leases.cpp"
        binary = self.base / ("leases.exe" if os.name == "nt" else "leases")
        cpp.write_text(source, encoding="utf-8")
        built = subprocess.run([self.compiler, "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror", "-pthread", "-I", str(self.base), str(cpp), "-o", str(binary)], capture_output=True, text=True, timeout=90)
        self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
        normal = subprocess.run([str(binary)], capture_output=True, text=True, timeout=20)
        self.assertEqual(normal.returncode, 0, f"lease check returned {normal.returncode}: {normal.stdout}{normal.stderr}")
        held = subprocess.run([str(binary), "held"], capture_output=True, text=True, timeout=20)
        self.assertEqual(held.returncode, 99, f"held lease was not fail-stopped: {held.returncode}")


if __name__ == "__main__":
    unittest.main()
