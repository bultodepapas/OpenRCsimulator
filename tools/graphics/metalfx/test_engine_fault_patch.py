"""Debug-only fault-injection checks on the pinned Godot MetalFX patch chain.

Tests compile the actual patched factory and enqueue functions with fake SDK/RD
objects. They do not execute Metal, a Godot binary, or GPU fallback behavior.
"""
from __future__ import annotations

import hashlib
import importlib.util
from pathlib import Path
import subprocess
import unittest

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("metalfx_history_checks", HERE / "test_engine_history_patch.py")
HISTORY = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(HISTORY)
CHECKS = HISTORY.CHECKS
PATCH2_SHA256 = "d7570f1b3639616e4e565a920cc4b9caca844bf7d1c8b3ec7d14d6e596c4ecc5"
PATCH3 = HERE / "patches/0003-metalfx-debug-faults.patch"


class MetalFXDebugFaultTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if hashlib.sha256(HISTORY.PATCH2.read_bytes()).hexdigest() != PATCH2_SHA256:
            raise RuntimeError("Frozen MetalFX history patch differs")
        HISTORY.TemporalHistoryPatchTests.setUpClass.__func__(cls)
        subprocess.run(["git", "apply", "--check", str(PATCH3)], cwd=cls.base, check=True, capture_output=True)
        subprocess.run(["git", "apply", str(PATCH3)], cwd=cls.base, check=True, capture_output=True)
        cls.metal = (cls.base / "servers/rendering/renderer_rd/effects/metal_fx.cpp").read_text(encoding="utf-8")

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temp.cleanup()

    def compile_and_run(self, source: str, name: str) -> str:
        return CHECKS.MetalFXPatchTests.compile_and_run(self, source, name)

    def contexts(self) -> str:
        start = self.header.index("// Synchronous factory outcome")
        spatial_end = self.header.index("class MFXSpatialEffect", start)
        temporal_start = self.header.index("struct MFXTemporalContext")
        temporal_end = self.header.index("class MFXTemporalEffect", temporal_start)
        return self.header[start:spatial_end] + self.header[temporal_start:temporal_end]

    @staticmethod
    def injection_support(debug: bool) -> str:
        define = "#define DEBUG_ENABLED 1\n" if debug else ""
        return define + r'''
#include <string>
[[maybe_unused]] static std::string injection;
[[maybe_unused]] static int injected_warnings = 0;
[[maybe_unused]] static bool mfx_debug_failure(const char *name) { return injection == name; }
#define WARN_PRINT_ONCE(message) (++injected_warnings)
'''

    def test_applies_only_after_frozen_chain(self) -> None:
        subprocess.run(["git", "apply", "--reverse", "--check", str(PATCH3)], cwd=self.base, check=True, capture_output=True)
        self.assertEqual(hashlib.sha256(HISTORY.PATCH2.read_bytes()).hexdigest(), PATCH2_SHA256)

    def test_debug_option_is_latched_on_first_lookup(self) -> None:
        helper = CHECKS.cxx_function(self.metal, "static bool mfx_debug_failure(")
        src = r'''
#include <cassert>
#include <string>
using String = std::string;
struct OS {
    std::string setting; int reads = 0;
    static OS *get_singleton() { static OS os; return &os; }
    String get_environment(const String &name) { assert(name == "OPENRC_METALFX_TEST_FAILURE"); ++reads; return setting; }
};
''' + helper + r'''
int main() {
    OS::get_singleton()->setting = "spatial_factory";
    assert(mfx_debug_failure("spatial_factory"));
    OS::get_singleton()->setting = "temporal_factory";
    assert(mfx_debug_failure("spatial_factory") && !mfx_debug_failure("temporal_factory"));
    assert(OS::get_singleton()->reads == 1);
}
'''
        self.compile_and_run(src, "debug_option")

    def test_fault_controls_are_removed_by_non_debug_preprocessor(self) -> None:
        import shutil
        compiler = shutil.which("g++") or shutil.which("clang++")
        self.assertIsNotNone(compiler)
        helper_at = self.metal.index("static bool mfx_debug_failure(")
        start = self.metal.rindex("#ifdef DEBUG_ENABLED", 0, helper_at)
        end = self.metal.index("#endif", helper_at) + len("#endif")
        src = self.metal[start:end] + "\n" + "\n".join(CHECKS.cxx_function(self.metal, signature) for signature in (
            "MFXSpatialContext *MFXSpatialEffect::create_context(", "MFXTemporalContext *MFXTemporalEffect::create_context(",
            "bool MFXSpatialEffect::try_process(", "bool MFXTemporalEffect::process("))
        path = self.base / "fault_preprocess.cpp"
        path.write_text(src, encoding="utf-8")
        for enabled in (False, True):
            args = [compiler, "-E", "-P", "-std=c++17"] + (["-DDEBUG_ENABLED"] if enabled else []) + [str(path)]
            processed = subprocess.run(args, capture_output=True, text=True, check=True).stdout
            for name in ("OPENRC_METALFX_TEST_FAILURE", "spatial_factory", "temporal_factory", "spatial_enqueue", "temporal_enqueue"):
                self.assertEqual(name in processed, enabled, name)

    def test_factory_faults_and_non_debug_preprocessing(self) -> None:
        spatial = CHECKS.cxx_function(self.metal, "MFXSpatialContext *MFXSpatialEffect::create_context(")
        temporal = CHECKS.cxx_function(self.metal, "MFXTemporalContext *MFXTemporalEffect::create_context(")
        body = CHECKS.FACTORY_STUB.split("int main() {")[0]
        body = body.replace("@CONTEXTS@", self.contexts()).replace("@SPATIAL_FACTORY@", spatial).replace("@TEMPORAL_FACTORY@", temporal)
        body += r'''
int main() {
    MFXSpatialEffect spatial; MFXTemporalEffect temporal; failure = Failure::NONE;
    injection = "spatial_factory";
    auto *a = spatial.create_context({}); auto *b = temporal.create_context({});
#ifdef DEBUG_ENABLED
    assert(!a->is_usable() && a->allocation_status == MFXAllocationStatus::SCALER_UNAVAILABLE && b->is_usable());
#else
    assert(a->is_usable() && b->is_usable());
#endif
    delete a; delete b;
    injection = "temporal_factory";
    a = spatial.create_context({}); b = temporal.create_context({});
#ifdef DEBUG_ENABLED
    assert(a->is_usable() && !b->is_usable() && b->allocation_status == MFXAllocationStatus::SCALER_UNAVAILABLE);
    assert(injected_warnings == 2);
#else
    assert(a->is_usable() && b->is_usable() && injected_warnings == 0);
#endif
    delete a; delete b;
    injection = ""; a = spatial.create_context({}); b = temporal.create_context({});
    assert(a->is_usable() && b->is_usable()); delete a; delete b;
}
'''
        for enabled in (False, True):
            self.compile_and_run(self.injection_support(enabled) + body, "fault_factory_" + str(enabled))

    def test_enqueue_faults_release_args_and_are_debug_only(self) -> None:
        start = self.header.index("class MFXSpatialEffect")
        temporal_start = self.header.index("class MFXTemporalEffect")
        args1 = CHECKS.cxx_block(self.header, self.header.index("struct CallbackArgs", start))
        args2 = CHECKS.cxx_block(self.header, self.header.index("struct CallbackArgs", temporal_start))
        history = "struct MetalFXTemporalHistoryState " + CHECKS.cxx_block(
            self.buffers, self.buffers.index("struct MetalFXTemporalHistoryState")) + ";"
        body = CHECKS.CALLBACK_STUB.split("int main() {")[0]
        body = body.replace("#include <cassert>", "#include <cassert>\n#include <atomic>\n#include <memory>")
        body = body.replace("constexpr Error OK = 0;", "constexpr Error OK = 0; [[maybe_unused]] constexpr Error ERR_CANT_CREATE = 2;")
        body = body.replace("bool fail = false; RDD::DriverCallback pending", "bool fail = false; int calls = 0; RDD::DriverCallback pending")
        body = body.replace("if (fail) return 1;", "++calls; if (fail) return 1;")
        body = body.replace("namespace RendererRD {\n@CONTEXTS@", history + "\nnamespace RendererRD {\n@CONTEXTS@")
        body = body.replace("struct Params { RID src, depth, motion, exposure, dst; Vector2 jitter_offset; bool reset = false; };",
                            "struct Params { RID src, depth, motion, exposure, dst; Vector2 jitter_offset; bool reset = false; std::shared_ptr<MetalFXTemporalHistoryState> history; uint64_t reset_serial = 0; };")
        replacements = {"@CONTEXTS@": self.contexts(), "@SPATIAL_ARGS@": args1, "@TEMPORAL_ARGS@": args2,
                        "@SPATIAL_DESTRUCTOR@": CHECKS.cxx_function(self.metal, "MFXSpatialContext::~MFXSpatialContext("),
                        "@TEMPORAL_DESTRUCTOR@": CHECKS.cxx_function(self.metal, "MFXTemporalContext::~MFXTemporalContext("),
                        "@SPATIAL_PROCESS@": CHECKS.cxx_function(self.metal, "bool MFXSpatialEffect::try_process("),
                        "@TEMPORAL_PROCESS@": CHECKS.cxx_function(self.metal, "bool MFXTemporalEffect::process("),
                        "@SPATIAL_CALLBACK@": CHECKS.cxx_function(self.metal, "void MFXSpatialEffect::callback("),
                        "@TEMPORAL_CALLBACK@": CHECKS.cxx_function(self.metal, "void MFXTemporalEffect::callback(")}
        for key, value in replacements.items():
            body = body.replace(key, value)
        body += r'''
int main() {
    RD *rd = RD::get_singleton(); [[maybe_unused]] MTL3::MDCommandBuffer cmd;
    MTLFX::SpatialScaler s; MFXSpatialContext cs; cs.scaler = &s; cs.allocation_status = MFXAllocationStatus::SCALER_CREATED;
    RenderSceneBuffersRD rb; rb.context = &cs; MFXSpatialEffect se;
    injection = "spatial_enqueue";
    bool spatial_ok = se.try_process({&rb}, {1}, {2});
#ifdef DEBUG_ENABLED
    assert(!spatial_ok && cs.submission_status == MFXSubmissionStatus::ENQUEUE_FAILED && s.refs == 1 && allocations == 0 && rd->calls == 0 && !rd->pending);
#else
    assert(spatial_ok && rd->calls == 1 && allocations == 1); rd->run(cmd); cmd.release_resource();
#endif
    MTLFX::TemporalScaler t; MFXTemporalContext ct; ct.scaler = &t; ct.allocation_status = MFXAllocationStatus::SCALER_CREATED;
    MFXTemporalEffect te; MFXTemporalEffect::Params p; p.src={1}; p.depth={2}; p.motion={3}; p.dst={4};
    p.reset = true; p.reset_serial = 1; p.history = std::make_shared<MetalFXTemporalHistoryState>();
    injection = "temporal_enqueue";
    bool temporal_ok = te.process(&ct, p);
#ifdef DEBUG_ENABLED
    assert(!temporal_ok && ct.submission_status == MFXSubmissionStatus::ENQUEUE_FAILED && t.refs == 1 && allocations == 0 && rd->calls == 0 && !rd->pending);
    assert(p.history->submitted.load() == 0 && p.history->encoded.load() == 0 && injected_warnings == 2);
#else
    assert(temporal_ok && rd->calls == 2 && allocations == 1); rd->run(cmd); cmd.release_resource(); assert(injected_warnings == 0);
#endif
}
'''
        for enabled in (False, True):
            self.compile_and_run(self.injection_support(enabled) + body, "fault_enqueue_" + str(enabled))


if __name__ == "__main__":
    unittest.main()
