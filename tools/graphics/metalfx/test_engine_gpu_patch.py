"""Compile actual opt-in GPU-observation code against fake Metal commands.

These are source/lifetime controls, not native GPU or presentation evidence.
"""
from __future__ import annotations

import hashlib
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import zipfile

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("gpu_engine", HERE / "engine.py")
ENGINE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(ENGINE)
CHECK_SPEC = importlib.util.spec_from_file_location("gpu_checks", HERE / "test_engine_patch.py")
CHECK = importlib.util.module_from_spec(CHECK_SPEC)
assert CHECK_SPEC.loader is not None
CHECK_SPEC.loader.exec_module(CHECK)
ARCHIVE = Path(os.environ.get("OPENRC_METALFX_SOURCE_ARCHIVE", HERE.parents[2] /
                             ".tools/apple-metalfx-cache/godot-cafc17a192acf67903910a68aeb3c076c0907a4b.zip"))
PATCHES = [HERE / "patches" / name for name in (
    "0001-metalfx-allocation-fallback.patch", "0002-metalfx-history-reset.patch",
    "0003-metalfx-debug-faults.patch", "0004-metalfx-frame-inputs.patch",
    "0006-metalfx-gpu-observation.patch")]


STUB = r'''
#include <any>
#include <atomic>
#include <cassert>
#include <chrono>
#include <functional>
#include <map>
#include <memory>
#include <string>
#include <thread>
#include <type_traits>
#include <utility>
#include <vector>
#include "servers/rendering/storage/metalfx_gpu_observation.h"
struct Variant {
    std::any value;
    Variant() = default;
    Variant(const Variant &) = default;
    Variant(Variant &&) = default;
    Variant &operator=(const Variant &) = default;
    Variant &operator=(Variant &&) = default;
    template<class T> static std::any store(T &&v) {
        if constexpr (std::is_convertible_v<T, std::string>) return std::string(std::forward<T>(v));
        else return std::any(std::forward<T>(v));
    }
    template<class T, std::enable_if_t<!std::is_same_v<std::decay_t<T>, Variant>, int> = 0>
    Variant(T &&v) : value(store(std::forward<T>(v))) {}
    template<class T, std::enable_if_t<!std::is_same_v<std::decay_t<T>, Variant>, int> = 0>
    Variant &operator=(T &&v) { value = store(std::forward<T>(v)); return *this; }
};
struct Dictionary : std::map<std::string, Variant> {
    Variant get(const std::string &name, Variant fallback) const {
        auto it = find(name); return it == end() ? fallback : it->second;
    }
};
template<class T> T field(const Dictionary &d, const char *name) { return std::any_cast<T>(d.at(name).value); }
using String = std::string;
struct RefCounted { virtual ~RefCounted() = default; };
struct RenderSceneBuffersConfiguration {};
namespace RSE { enum { VIEWPORT_SCALING_3D_MODE_METALFX_TEMPORAL = 4 }; enum ViewportAnisotropicFiltering { NONE }; }
#define GDCLASS(...)
#define ERR_FAIL_NULL(p) do { if (!(p)) return; } while (false)
#define ERR_FAIL_NULL_V(p, v) do { if (!(p)) return v; } while (false)
@HISTORY@
@BUFFERS@
struct TestBuffers : RenderSceneBuffers {
    void configure(const RenderSceneBuffersConfiguration *) override { reset_metalfx_status(); }
    void set_fsr_sharpness(float) override {}
    void set_texture_mipmap_bias(float) override {}
    void set_anisotropic_filtering_level(RSE::ViewportAnisotropicFiltering) override {}
    void set_use_debanding(bool) override {}
    void clear_metalfx_frame() override { clear_metalfx_frame_gpu_observation(); }
};
struct RefBuffers {
    RenderSceneBuffers *value = nullptr;
    bool is_valid() const { return value != nullptr; }
    RenderSceneBuffers *operator->() const { return value; }
};
using RID = int;
struct RendererViewport {
    struct Viewport {
        bool metal_fx_gpu_observation_requested = false;
        bool metal_fx_frame_requested = false;
        uint64_t metal_fx_generation = 8, metal_fx_frame_generation = 9;
        RefBuffers render_buffers;
    };
    struct Owner { Viewport *value = nullptr; Viewport *get_or_null(RID) const { return value; } } viewport_owner;
    void viewport_set_metalfx_gpu_observation_requested(RID, bool);
    Dictionary viewport_get_metalfx_gpu_status(RID) const;
};
@VIEWPORT@
namespace NS { struct Error { int64_t number = 0; int64_t code() const { return number; } }; }
namespace MTL {
    enum CommandBufferStatus { CommandBufferStatusScheduled = 3, CommandBufferStatusCompleted = 4, CommandBufferStatusError = 5 };
    struct CommandBuffer {
        CommandBufferStatus state = CommandBufferStatusCompleted;
        NS::Error *failure = nullptr;
        double start = 1.0, end = 1.004;
        std::vector<std::function<void(CommandBuffer *)>> handlers;
        CommandBufferStatus status() const { return state; }
        NS::Error *error() const { return failure; }
        double GPUStartTime() const { return start; }
        double GPUEndTime() const { return end; }
        void addCompletedHandler(const std::function<void(CommandBuffer *)> &fn) { handlers.push_back(fn); }
        void finish() { auto pending = std::move(handlers); for (auto &fn : pending) fn(this); }
    };
}
@OBSERVER@
static void successful(const std::shared_ptr<MetalFXGPUObservation> &state,
                       MetalFXGPUObservation::Sample sample) {
    assert(state->completed(sample, true, true, 4, false, 0, 1, 1.004, 7));
}
int main(int argc, char **argv) {
    assert(argc == 2);
    std::string mode = argv[1];
    if (mode == "disabled") {
        MTL::CommandBuffer command;
        mfx_observe_gpu(&command, nullptr, 7);
        assert(command.handlers.empty());
        auto state = std::make_shared<MetalFXGPUObservation>();
        mfx_observe_gpu(nullptr, state, 7);
        assert(!state->snapshot().encoded.ticket);
    } else if (mode == "completion") {
        auto state = std::make_shared<MetalFXGPUObservation>();
        MTL::CommandBuffer command;
        mfx_observe_gpu(&command, state, 19, 4, 2);
        auto before = state->snapshot();
        assert(before.encoded.ticket == 1 && !before.completed.ticket && !before.reset_completed_serial);
        command.finish();
        auto after = state->snapshot();
        assert(after.completed.ticket == 1 && after.completed.frame == 19 && after.completed.epoch == 4);
        assert(after.completed.succeeded && after.completed.gpu_timing_available && after.reset_completed_serial == 2);
        assert(after.completed.gpu_start_seconds == 1 && after.completed.gpu_end_seconds == 1.004);
        assert(after.completed.callback_observer_usec > 0 && !after.first_observed_failure.ticket);
    } else if (mode == "lifetime") {
        MTL::CommandBuffer command;
        std::weak_ptr<MetalFXGPUObservation> retired;
        { auto state = std::make_shared<MetalFXGPUObservation>(); retired = state; mfx_observe_gpu(&command, state, 1); }
        assert(!retired.expired());
        command.finish();
        assert(retired.expired());
    } else if (mode == "failure") {
        auto state = std::make_shared<MetalFXGPUObservation>();
        MTL::CommandBuffer command; NS::Error error; error.number = 8;
        command.state = MTL::CommandBufferStatusError; command.failure = &error;
        mfx_observe_gpu(&command, state, 4, 0, 7); command.finish();
        auto failed = state->snapshot();
        assert(!failed.completed.succeeded && failed.first_observed_failure.ticket == 1);
        assert(failed.first_observed_failure.error_present && failed.first_observed_failure.error_code == 8);
        assert(!failed.completed.gpu_timing_available && !failed.reset_completed_serial);
        successful(state, state->encoded(5, 0, 8));
        assert(state->snapshot().first_observed_failure.ticket == 1 && state->snapshot().reset_completed_serial == 8);
    } else if (mode == "timing") {
        for (const auto &times : std::vector<std::pair<double, double>>{{0,0}, {-1,2}, {2,1},
             {NAN,2}, {1,INFINITY}, {1,std::numeric_limits<double>::max()}}) {
            auto state = std::make_shared<MetalFXGPUObservation>(); MTL::CommandBuffer command;
            command.start = times.first; command.end = times.second;
            mfx_observe_gpu(&command, state, 1); command.finish();
            auto sample = state->snapshot().completed;
            assert(sample.succeeded && !sample.gpu_timing_available && sample.gpu_start_seconds == 0 && sample.gpu_end_seconds == 0);
        }
    } else if (mode == "nonterminal") {
        auto state = std::make_shared<MetalFXGPUObservation>(); MTL::CommandBuffer command;
        command.state = MTL::CommandBufferStatusScheduled;
        mfx_observe_gpu(&command, state, 1); command.finish();
        assert(state->snapshot().unexpected_callback && !state->snapshot().completed.ticket);
        assert(!state->completed({}, true, true, 4, false, 0, 1, 2, 3));
    } else if (mode == "ordering") {
        auto state = std::make_shared<MetalFXGPUObservation>();
        auto first = state->encoded(11, 1, 3), second = state->encoded(12, 2, 7);
        successful(state, second);
        assert(state->completed(first, true, false, 5, true, 8, 0, 0, 5));
        auto result = state->snapshot();
        assert(result.completed.ticket == 2 && result.completed.frame == 12 && result.completed.epoch == 2);
        assert(result.first_observed_failure.ticket == 1 && result.reset_completed_serial == 7);
    } else if (mode == "generation") {
        TestBuffers buffers; RendererViewport server; RendererViewport::Viewport view;
        server.viewport_owner.value = &view;
        server.viewport_set_metalfx_gpu_observation_requested(0, true);
        assert(view.metal_fx_gpu_observation_requested && view.metal_fx_generation == 8 && view.metal_fx_frame_generation == 9);
        view.render_buffers.value = &buffers;
        auto history = buffers.ensure_metalfx_history_state(); history->requested.store(4); history->encoded.store(3);
        buffers.set_metalfx_gpu_observation_requested(true);
        auto old = buffers.ensure_metalfx_gpu_observation();
        auto old_frame = buffers.ensure_metalfx_gpu_observation(true);
        auto old_sample = old->encoded(4), old_frame_sample = old_frame->encoded(4, 1);
        auto generation = field<int64_t>(buffers.get_metalfx_gpu_status(), "observation_generation");
        buffers.set_metalfx_gpu_observation_requested(true);
        assert(buffers.ensure_metalfx_gpu_observation() == old);
        buffers.set_metalfx_gpu_observation_requested(false);
        assert(!buffers.ensure_metalfx_gpu_observation() && !buffers.ensure_metalfx_gpu_observation(true));
        auto off = buffers.get_metalfx_gpu_status();
        assert(!field<bool>(field<Dictionary>(off, "scaler"), "state_allocated"));
        assert(buffers.get_metalfx_history_state() == history && history->requested.load() == 4 && history->encoded.load() == 3);
        buffers.set_metalfx_gpu_observation_requested(true);
        auto current = buffers.ensure_metalfx_gpu_observation();
        successful(old, old_sample); successful(old_frame, old_frame_sample);
        assert(current != old && !current->snapshot().completed.ticket);
        assert(field<int64_t>(buffers.get_metalfx_gpu_status(), "observation_generation") > generation);
        auto frame = buffers.ensure_metalfx_gpu_observation(true); buffers.clear_metalfx_frame();
        assert(buffers.ensure_metalfx_gpu_observation() == current && buffers.ensure_metalfx_gpu_observation(true) != frame);
        auto report = server.viewport_get_metalfx_gpu_status(0);
        assert(field<int64_t>(report, "viewport_generation") == 8 && field<int64_t>(report, "frame_generation") == 9);
    } else if (mode == "concurrency") {
        auto state = std::make_shared<MetalFXGPUObservation>();
        std::vector<MetalFXGPUObservation::Sample> samples;
        for (int i = 1; i <= 256; ++i) samples.push_back(state->encoded(1000+i, 42, i == 128 ? 7 : 0));
        std::vector<std::thread> workers;
        std::atomic<int> done{0};
        for (int t = 0; t < 4; ++t) workers.emplace_back([&, t] {
            for (int i = t; i < 256; i += 4) state->completed(samples[i], true, i != 4, i == 4 ? 5 : 4,
                i == 4, i == 4 ? 8 : 0, 1, 2, i+1);
            ++done;
        });
        uint64_t previous = 0;
        while (done.load() != 4) {
            auto sample = state->snapshot();
            assert(sample.completed.ticket >= previous && sample.completed.ticket <= sample.encoded.ticket);
            if (sample.completed.ticket) assert(sample.completed.frame == 1000+sample.completed.ticket && sample.completed.epoch == 42);
            previous = sample.completed.ticket;
        }
        for (auto &worker : workers) worker.join();
        auto final = state->snapshot();
        assert(final.completed.ticket == 256 && final.first_observed_failure.ticket == 5 && final.reset_completed_serial == 7);
    } else if (mode == "exhaustion") {
        auto state = std::make_shared<MetalFXGPUObservation>();
        assert(!state->encoded(MetalFXGPUObservation::MAX_COUNTER + 1).ticket);
        MTL::CommandBuffer command; mfx_observe_gpu(&command, state, 1);
        assert(command.handlers.empty() && state->snapshot().counter_exhausted && !state->snapshot().encoded.ticket);
    } else { return 2; }
}
'''


class GPUObservationPatchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        compiler = shutil.which("g++") if os.name == "nt" else shutil.which("clang++") or shutil.which("g++")
        if not compiler:
            raise unittest.SkipTest("No C++17 compiler installed")
        if not ARCHIVE.is_file():
            raise unittest.SkipTest("Pinned Godot source archive unavailable")
        if ENGINE.sha256(ARCHIVE) != ENGINE.SOURCE_SHA256:
            raise RuntimeError("Godot source archive differs from independent pin")
        cls.temp = tempfile.TemporaryDirectory(prefix="openrc-metalfx-gpu-")
        cls.addClassCleanup(cls.temp.cleanup)
        cls.base = Path(cls.temp.name)
        paths = ENGINE.patch_paths(PATCHES)
        with zipfile.ZipFile(ARCHIVE) as archive:
            members = set(archive.namelist())
            for name in paths:
                member = f"{ENGINE.SOURCE_PREFIX}/{name}"
                if member not in members:
                    continue  # New regular source files are supplied by the ordered patches.
                target = cls.base / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(archive.read(member))
        for patch in PATCHES:
            ENGINE.git(cls.base, "apply", "--check", str(patch.resolve()))
            ENGINE.git(cls.base, "apply", str(patch.resolve()))
        buffers = (cls.base / "servers/rendering/storage/render_scene_buffers.h").read_text(encoding="utf-8")
        viewport = (cls.base / "servers/rendering/renderer_viewport.cpp").read_text(encoding="utf-8")
        effects = (cls.base / "servers/rendering/renderer_rd/effects/metal_fx.cpp").read_text(encoding="utf-8")
        history = "\n".join("struct " + name + " " + CHECK.cxx_block(buffers, buffers.index("struct " + name)) + ";"
                            for name in ("MetalFXTemporalHistoryState", "MetalFXFrameHistoryState"))
        source = STUB.replace("@HISTORY@", history)
        source = source.replace("@BUFFERS@", "class RenderSceneBuffers : public RefCounted " +
                                CHECK.cxx_block(buffers, buffers.index("class RenderSceneBuffers :")) + ";")
        source = source.replace("@VIEWPORT@", "\n".join(CHECK.cxx_function(viewport, signature) for signature in (
            "void RendererViewport::viewport_set_metalfx_gpu_observation_requested(",
            "Dictionary RendererViewport::viewport_get_metalfx_gpu_status(")))
        source = source.replace("@OBSERVER@", CHECK.cxx_function(effects, "static void mfx_observe_gpu("))
        cpp = cls.base / "gpu-test.cpp"
        cpp.write_text(source, encoding="utf-8")
        cls.executable = cls.base / ("gpu-test.exe" if os.name == "nt" else "gpu-test")
        compiled = subprocess.run([compiler, "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror", "-pthread",
                                   "-I", str(cls.base), str(cpp), "-o", str(cls.executable)],
                                  capture_output=True, text=True, timeout=90)
        if compiled.returncode:
            raise RuntimeError(compiled.stdout + compiled.stderr)

    def scenario(self, name):
        result = subprocess.run([str(self.executable), name], capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_disabled_observer_registers_nothing(self): self.scenario("disabled")
    def test_actual_hook_requires_completed_command_and_preserves_metadata(self): self.scenario("completion")
    def test_callback_owns_retired_generation_until_completion(self): self.scenario("lifetime")
    def test_gpu_failure_latches_and_does_not_acknowledge_reset(self): self.scenario("failure")
    def test_missing_nonfinite_or_backward_timestamps_stay_unavailable(self): self.scenario("timing")
    def test_nonterminal_or_unissued_callback_cannot_complete(self): self.scenario("nonterminal")
    def test_late_failure_survives_a_later_success(self): self.scenario("ordering")
    def test_opt_in_and_retirement_preserve_temporal_and_viewport_receipts(self): self.scenario("generation")
    def test_concurrent_callbacks_have_coherent_monotonic_snapshots(self): self.scenario("concurrency")
    def test_signed_counter_exhaustion_registers_no_callback(self): self.scenario("exhaustion")


if __name__ == "__main__":
    unittest.main()
