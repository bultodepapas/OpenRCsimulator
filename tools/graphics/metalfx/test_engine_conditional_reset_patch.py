"""Portable controls for the exact 1–19 conditional Temporal reset source."""
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
spec = importlib.util.spec_from_file_location("conditional_rt18", HERE / "test_engine_rt_scene_patch.py")
PREVIOUS = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = PREVIOUS
spec.loader.exec_module(PREVIOUS)
ENGINE, CHECK = PREVIOUS.ENGINE, PREVIOUS.CHECK
PATCH = HERE / "patches/0019-metalfx-conditional-history-reset.patch"
PATCHES = PREVIOUS.PATCHES + (PATCH,)
HASHES = PREVIOUS.HASHES + (PREVIOUS.PATCH_HASH,)
PATCH_HASH = "6a71e3e6eee7542996f52a318085f892ada178b1800c28a173129e07b500b289"

CONTROL = r'''
#include <atomic>
#include <cstdint>
#include <climits>
#include <map>
#include <memory>
#include <string>
#define CHECK(x) do { if (!(x)) return __LINE__; } while (0)
#define ERR_FAIL_NULL_V(x, y) do { if (!(x)) return y; } while (0)
struct Value {
    int64_t number=0; std::string text;
    Value &operator=(bool x){number=x;return *this;}
    Value &operator=(int64_t x){number=x;return *this;}
    Value &operator=(const char *x){text=x;return *this;}
    explicit operator bool()const{return number!=0;}
    explicit operator int64_t()const{return number;}
};
struct Dictionary {
    std::map<std::string,Value> values;
    Value &operator[](const char *key){return values[key];}
    Value get(const char *key,bool fallback)const {
        auto i=values.find(key); if(i!=values.end())return i->second;
        Value v; v=fallback; return v;
    }
};
struct RID { int value=0; bool operator==(RID other)const{return value==other.value;} };
struct MetalFXTemporalHistoryState {
    std::atomic<uint64_t> requested{0},temporal_attempts{0};
};
struct RenderSceneBuffers {
    bool ready=true; int clears=0;
    std::shared_ptr<MetalFXTemporalHistoryState> history=std::make_shared<MetalFXTemporalHistoryState>();
    bool is_metalfx_temporal_ready()const{return ready && bool(history);}
    std::shared_ptr<MetalFXTemporalHistoryState> get_metalfx_history_state()const{return history;}
    void clear_metalfx_frame(){++clears;}
};
struct Buffers {
    RenderSceneBuffers *ptr=nullptr;
    bool is_valid()const{return ptr!=nullptr;}
    RenderSceneBuffers *operator->()const{return ptr;}
};
struct Viewport {
    uint64_t metal_fx_generation=7,metal_fx_reset_serial=40,metal_fx_frame_generation=10;
    bool disable_3d=false; int view_count=1; Buffers render_buffers;
};
struct RendererViewport {
    struct Owner { Viewport *viewport=nullptr; Viewport *get_or_null(RID id){return id.value==1?viewport:nullptr;} } viewport_owner;
    RID real_gpu_observer_viewport{1}; int observer_resets=0;
    void _real_gpu_reset_main(){++observer_resets;}
    Dictionary viewport_request_temporal_history_reset(RID);
    Dictionary viewport_request_temporal_history_reset_if_current(RID,int64_t,int64_t);
};
@LEGACY@
@CONDITIONAL@
static bool outcome(Dictionary &d,bool accepted,const char *reason,int64_t generation,int64_t previous,int64_t current){
    return d["accepted"].number==int(accepted) && d["reason"].text==reason &&
        d["generation"].number==generation && d["previous_requested_serial"].number==previous &&
        d["requested_serial"].number==current;
}
int main(){
    RendererViewport r; Viewport v; RenderSceneBuffers b;
    r.viewport_owner.viewport=&v; v.render_buffers.ptr=&b;
    b.history->requested.store(4); b.history->temporal_attempts.store(9);
    const RID valid{1};
    auto bad=r.viewport_request_temporal_history_reset_if_current({99},7,4);
    CHECK(outcome(bad,false,"invalid_viewport",-1,-1,-1));
    auto negative=r.viewport_request_temporal_history_reset_if_current(valid,-1,4);
    CHECK(outcome(negative,false,"invalid_expected_scope",7,4,4));
    negative=r.viewport_request_temporal_history_reset_if_current(valid,7,-1);
    CHECK(outcome(negative,false,"invalid_expected_scope",7,4,4));
    auto stale_generation=r.viewport_request_temporal_history_reset_if_current(valid,6,4);
    CHECK(outcome(stale_generation,false,"stale_generation",7,4,4));
    auto stale_serial=r.viewport_request_temporal_history_reset_if_current(valid,7,3);
    CHECK(outcome(stale_serial,false,"stale_serial",7,4,4));
    CHECK(v.metal_fx_reset_serial==40 && v.metal_fx_frame_generation==10 && b.clears==0 && r.observer_resets==0);
    v.render_buffers.ptr=nullptr;
    auto missing=r.viewport_request_temporal_history_reset_if_current(valid,7,4);
    CHECK(outcome(missing,false,"render_buffers_unavailable",7,-1,-1));
    v.render_buffers.ptr=&b; auto saved=b.history; b.history.reset();
    auto no_history=r.viewport_request_temporal_history_reset_if_current(valid,7,4);
    CHECK(outcome(no_history,false,"history_unavailable",7,-1,-1)); b.history=saved;
    v.metal_fx_generation=uint64_t(INT64_MAX)+1;
    auto generation_overflow=r.viewport_request_temporal_history_reset_if_current(valid,7,4);
    CHECK(!bool(generation_overflow["accepted"]) && generation_overflow["reason"].text=="generation_out_of_range" && generation_overflow["generation"].number==-1);
    v.metal_fx_generation=7; b.history->requested.store(uint64_t(INT64_MAX)+1);
    auto serial_overflow=r.viewport_request_temporal_history_reset_if_current(valid,7,4);
    CHECK(!bool(serial_overflow["accepted"]) && serial_overflow["reason"].text=="requested_serial_out_of_range" && serial_overflow["requested_serial"].number==-1);
    b.history->requested.store(4);
    v.metal_fx_reset_serial=uint64_t(INT64_MAX);
    auto exhausted=r.viewport_request_temporal_history_reset_if_current(valid,7,4);
    CHECK(outcome(exhausted,false,"reset_unavailable",7,4,4));
    v.metal_fx_reset_serial=40; b.history->temporal_attempts.store(uint64_t(INT64_MAX)-1);
    exhausted=r.viewport_request_temporal_history_reset_if_current(valid,7,4);
    CHECK(outcome(exhausted,false,"reset_unavailable",7,4,4));
    b.history->temporal_attempts.store(9); v.disable_3d=true;
    auto disabled=r.viewport_request_temporal_history_reset_if_current(valid,7,4);
    CHECK(outcome(disabled,false,"reset_unavailable",7,4,4)); v.disable_3d=false;
    v.view_count=2; auto multiview=r.viewport_request_temporal_history_reset_if_current(valid,7,4);
    CHECK(outcome(multiview,false,"reset_unavailable",7,4,4)); v.view_count=1;
    b.ready=false; auto unready=r.viewport_request_temporal_history_reset_if_current(valid,7,4);
    CHECK(outcome(unready,false,"reset_unavailable",7,4,4)); b.ready=true;
    CHECK(v.metal_fx_reset_serial==40 && v.metal_fx_frame_generation==10 && b.clears==0 && r.observer_resets==0);
    auto accepted=r.viewport_request_temporal_history_reset_if_current(valid,7,4);
    CHECK(outcome(accepted,true,"accepted",7,4,41));
    CHECK(accepted["reset_request_attempt"].number==9 && b.history->requested.load()==41);
    CHECK(v.metal_fx_reset_serial==41 && v.metal_fx_frame_generation==11 && b.clears==1 && r.observer_resets==1);
    auto replay=r.viewport_request_temporal_history_reset_if_current(valid,7,4);
    CHECK(outcome(replay,false,"stale_serial",7,41,41));
    CHECK(v.metal_fx_reset_serial==41 && v.metal_fx_frame_generation==11 && b.clears==1 && r.observer_resets==1);
    // Another reset between the query and conditional call is not repeated.
    auto external=r.viewport_request_temporal_history_reset(valid);
    CHECK(bool(external["accepted"]) && b.history->requested.load()==42);
    auto raced=r.viewport_request_temporal_history_reset_if_current(valid,7,41);
    CHECK(outcome(raced,false,"stale_serial",7,42,42));
    CHECK(v.metal_fx_reset_serial==42 && v.metal_fx_frame_generation==12 && b.clears==2 && r.observer_resets==2);
    // A new history starts at zero even when the viewport-wide serial does not.
    b.history=std::make_shared<MetalFXTemporalHistoryState>(); v.metal_fx_generation=8;
    auto new_history=r.viewport_request_temporal_history_reset_if_current(valid,8,0);
    CHECK(outcome(new_history,true,"accepted",8,0,43));
    CHECK(b.history->requested.load()==43 && b.clears==3 && r.observer_resets==3);
    return 0;
}
'''


class ConditionalResetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if ENGINE.sha256(CHECK.ARCHIVE) != CHECK.ARCHIVE_SHA256:
            raise RuntimeError("Pinned Godot archive differs")
        if tuple(ENGINE.sha256(p) for p in PATCHES[:-1]) != HASHES:
            raise RuntimeError("Frozen 1–18 prerequisites differ")
        if ENGINE.sha256(PATCH) != PATCH_HASH:
            raise RuntimeError("0019 candidate differs")
        parent = (ROOT / "tmp/metalfx-conditional-reset-port").resolve()
        if not parent.is_relative_to(ROOT.resolve()):
            raise RuntimeError("Control directory escaped workspace")
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
        cls.viewport = (cls.base / "servers/rendering/renderer_viewport.cpp").read_text(encoding="utf-8")

    def compile_run(self, code, name):
        compiler = os.environ.get("CXX") or shutil.which("g++") or shutil.which("clang++")
        self.assertTrue(compiler, "A C++17 compiler is required")
        source = self.base / (name + ".cpp")
        executable = self.base / (name + (".exe" if os.name == "nt" else ""))
        source.write_text(code, encoding="utf-8")
        built = subprocess.run([compiler, "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror",
                                str(source), "-o", str(executable)], capture_output=True, text=True, timeout=90)
        self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
        return subprocess.run([str(executable)], capture_output=True, text=True, timeout=30)

    def test_actual_reset_transaction_and_mutations(self):
        legacy = CHECK.cxx_function(self.viewport, "Dictionary RendererViewport::viewport_request_temporal_history_reset(")
        conditional = CHECK.cxx_function(self.viewport, "Dictionary RendererViewport::viewport_request_temporal_history_reset_if_current(")
        control = CONTROL.replace("@LEGACY@", legacy).replace("@CONDITIONAL@", conditional)
        self.assertEqual(self.compile_run(control, "conditional_reset").returncode, 0)
        for name, expression in (("generation", "uint64_t(p_expected_render_buffer_generation) != viewport->metal_fx_generation"),
                                 ("serial", "uint64_t(p_expected_requested_serial) != requested")):
            mutated = control.replace(expression, "false && (" + expression + ")")
            self.assertNotEqual(mutated, control)
            self.assertNotEqual(self.compile_run(mutated, "conditional_reset_mutated_" + name).returncode, 0)

    def test_public_binding_and_single_render_thread_transaction(self):
        headers = self.base / "servers/rendering"
        server = (headers / "rendering_server.h").read_text(encoding="utf-8")
        binding = (headers / "rendering_server.cpp").read_text(encoding="utf-8")
        wrapper = (headers / "rendering_server_default.h").read_text(encoding="utf-8")
        viewport_header = (headers / "renderer_viewport.h").read_text(encoding="utf-8")
        name = "viewport_request_temporal_history_reset_if_current"
        self.assertIn("virtual Dictionary " + name + "(", server)
        self.assertIn("Dictionary " + name + "(", viewport_header)
        self.assertIn('D_METHOD("' + name + '", "viewport", "expected_render_buffer_generation", "expected_requested_serial")', binding)
        self.assertIn("FUNC3R(Dictionary, " + name + ", RID, int64_t, int64_t)", wrapper)
        body = CHECK.cxx_function(self.viewport, "Dictionary RendererViewport::" + name + "(")
        self.assertEqual(body.count("viewport_request_temporal_history_reset(p_viewport)"), 1)
        self.assertNotIn("_real_gpu_reset_main()", body)
        self.assertNotIn("clear_metalfx_frame()", body)
        self.assertLess(body.index("stale_generation"), body.index("viewport_request_temporal_history_reset(p_viewport)"))
        self.assertLess(body.index("stale_serial"), body.index("viewport_request_temporal_history_reset(p_viewport)"))


if __name__ == "__main__":
    unittest.main()
