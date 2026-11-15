"""Compile real Metal queue/fence functions for empty RD submissions.

Fakes verify command creation, signal/commit ordering and allocation failure;
native local-device shutdown remains a separate checked Metal test.
"""
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

def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, HERE / filename)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value

ENGINE = module("empty_engine", "engine.py")
CHECK = module("empty_checks", "test_engine_patch.py")
PATCHES = [HERE / "patches" / name for name in (
    "0001-metalfx-allocation-fallback.patch", "0002-metalfx-history-reset.patch",
    "0003-metalfx-debug-faults.patch", "0004-metalfx-frame-inputs.patch",
    "0005-metal-triangle-query.patch", "0006-metalfx-gpu-observation.patch",
    "0007-metalfx-denoised-binding.patch", "0010-metal-empty-submit-fence.patch")]

STUB = r'''
#define REQUIRE(condition) do { if (!(condition)) return __LINE__; } while (false)
#include <cstdint>
#include <initializer_list>
#include <vector>
using Error = int;
constexpr int OK = 0, ERR_CANT_CREATE = 20;
#define ERR_FAIL_NULL_V(ptr, result) do { if (!(ptr)) return result; } while (false)
#define MTLSTR(s) s
static int commits = 0;
namespace MTL {
struct CommandBuffer {
    uint64_t *event = nullptr;
    uint64_t value = 0;
    void setLabel(const char *) {}
    void encodeWait(uint64_t *, uint64_t) {}
    void encodeSignalEvent(uint64_t *p, uint64_t v) { event = p; value = v; }
    void commit() { ++commits; if (event) *event = value; }
};
}
template<class T> struct Shared {
    T *p;
    T *get() const { return p; }
    T *operator->() const { return p; }
};
template<class T> struct VectorView {
    std::vector<T> values;
    VectorView(std::initializer_list<T> v = {}) : values(v) {}
    uint32_t size() const { return uint32_t(values.size()); }
    const T &operator[](uint32_t i) const { return values[i]; }
};
struct ID { uintptr_t id = 0; };
struct MDCommandBuffer {
    MTL::CommandBuffer native;
    MTL::CommandBuffer *current = nullptr;
    int ensures = 0, allocations = 0;
    bool fail = false;
    void end() {}
    MTL::CommandBuffer *get_command_buffer() const { return current; }
    MTL::CommandBuffer *ensure_command_buffer() {
        ++ensures;
        if (!current && !fail) { current = &native; ++allocations; }
        return current;
    }
    // Fake queue completion is synchronous; this is not GPU timing evidence.
    void commit() { if (current) current->commit(); current = nullptr; }
};
struct RenderingContextDriverMetal {
    struct Surface { void present(MDCommandBuffer *) {} };
};
struct Queue {
    MTL::CommandBuffer buffer;
    MTL::CommandBuffer *commandBuffer() { return &buffer; }
};
struct RenderingDeviceDriverMetal {
    using CommandQueueID = ID;
    using CommandBufferID = ID;
    using SemaphoreID = ID;
    using FenceID = ID;
    using SwapChainID = ID;
    struct Fence {
        uint64_t value = 0;
        uint64_t observed = 0;
        Shared<uint64_t> event{&observed};
        void signal(MTL::CommandBuffer *);
    };
    struct Semaphore { Shared<uint64_t> event; uint64_t value; };
    struct SwapChain { void *surface; };
    Queue queue;
    Shared<Queue> device_queue{&queue};
    Error _execute_and_present(CommandQueueID, VectorView<SemaphoreID>, VectorView<CommandBufferID>, VectorView<SemaphoreID>, FenceID, VectorView<SwapChainID>);
    Error _execute_and_present_barriers(CommandQueueID, VectorView<SemaphoreID>, VectorView<CommandBufferID>, VectorView<SemaphoreID>, FenceID, VectorView<SwapChainID>);
};
@SIGNAL@
@DIRECT@
@BARRIERS@
int main() {
    for (bool barriers : {false, true}) {
        RenderingDeviceDriverMetal driver;
        auto execute = [&](MDCommandBuffer &cmd, RenderingDeviceDriverMetal::Fence *fence) {
            VectorView<ID> buffers{{reinterpret_cast<uintptr_t>(&cmd)}};
            ID f{reinterpret_cast<uintptr_t>(fence)};
            return barriers ? driver._execute_and_present_barriers({}, {}, buffers, {}, f, {}) :
                    driver._execute_and_present({}, {}, buffers, {}, f, {});
        };
        RenderingDeviceDriverMetal::Fence fence;
        MDCommandBuffer empty;
        int before = commits;
        REQUIRE(execute(empty, &fence) == OK);
        REQUIRE(empty.ensures == 1 && empty.allocations == 1);
        REQUIRE(fence.value == 1 && fence.observed == 1 && commits == before + 1);
        // A separately begun command buffer with GPU work is not replaced.
        MDCommandBuffer existing;
        existing.current = &existing.native;
        REQUIRE(execute(existing, &fence) == OK);
        REQUIRE(existing.ensures == 1 && existing.allocations == 0);
        REQUIRE(existing.current == nullptr && fence.value == 2 && fence.observed == 2);
        MDCommandBuffer no_fence;
        before = commits;
        REQUIRE(execute(no_fence, nullptr) == OK);
        REQUIRE(no_fence.ensures == 0 && no_fence.allocations == 0 && commits == before);
        MDCommandBuffer failed;
        failed.fail = true;
        RenderingDeviceDriverMetal::Fence unissued;
        REQUIRE(execute(failed, &unissued) == ERR_CANT_CREATE);
        REQUIRE(unissued.value == 0 && unissued.observed == 0 && commits == before);
        // Earlier commands still commit before the final queue fence.
        MDCommandBuffer first, tail;
        first.current = &first.native;
        before = commits;
        VectorView<ID> batch{{reinterpret_cast<uintptr_t>(&first)}, {reinterpret_cast<uintptr_t>(&tail)}};
        RenderingDeviceDriverMetal::Fence batch_fence;
        auto f = ID{reinterpret_cast<uintptr_t>(&batch_fence)};
        auto result = barriers ? driver._execute_and_present_barriers({}, {}, batch, {}, f, {}) :
                driver._execute_and_present({}, {}, batch, {}, f, {});
        REQUIRE(result == OK && commits == before + 2 && batch_fence.observed == 1);
    }
}
'''

class EmptySubmissionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not CHECK.ARCHIVE.is_file():
            raise unittest.SkipTest("Pinned Godot source ZIP unavailable")
        if ENGINE.sha256(CHECK.ARCHIVE) != ENGINE.SOURCE_SHA256:
            raise ValueError("Godot archive differs from pin")
        cls.temp = tempfile.TemporaryDirectory(prefix="metalfx-empty-submit-")
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
            ENGINE.git(cls.base, "apply", "--whitespace=error-all", str(patch.resolve()))
        source = (cls.base / "drivers/metal/rendering_device_driver_metal3.cpp").read_text()
        cls.harness = STUB.replace("@SIGNAL@", CHECK.cxx_function(source, "void RenderingDeviceDriverMetal::Fence::signal("))
        cls.harness = cls.harness.replace("@DIRECT@", CHECK.cxx_function(source, "Error RenderingDeviceDriverMetal::_execute_and_present("))
        cls.harness = cls.harness.replace("@BARRIERS@", CHECK.cxx_function(source, "Error RenderingDeviceDriverMetal::_execute_and_present_barriers("))

    def compile_run(self, source, name, debug=False):
        win = Path("C:/Users/bulto/scoop/apps/gcc/current/bin/g++.exe")
        compiler = str(win) if os.name == "nt" and win.is_file() else shutil.which("clang++") or shutil.which("g++")
        self.assertTrue(compiler, "C++17 compiler required")
        cpp = self.base / (name + ".cpp")
        exe = self.base / (name + (".exe" if sys.platform == "win32" else ""))
        cpp.write_text(source)
        command = [compiler, "-std=c++17", "-Wall", "-Wextra", "-Werror", "-Wno-unused-parameter"]
        if debug:
            command.append("-DDEV_ENABLED")
        built = subprocess.run([*command, str(cpp), "-o", str(exe)], text=True, capture_output=True, timeout=90)
        self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
        return subprocess.run([str(exe)], text=True, capture_output=True, timeout=20)

    def test_actual_queue_fences_release(self):
        result = self.compile_run(self.harness, "release")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_actual_queue_fences_development(self):
        result = self.compile_run(self.harness, "development", True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_control_detects_missing_native_command_creation(self):
        for index, signature in enumerate(("Error RenderingDeviceDriverMetal::_execute_and_present(",
                                           "Error RenderingDeviceDriverMetal::_execute_and_present_barriers(")):
            original = CHECK.cxx_function(self.harness, signature)
            changed = original.replace("ensure_command_buffer()", "get_command_buffer()")
            self.assertNotEqual(original, changed)
            result = self.compile_run(self.harness.replace(original, changed, 1), "mutant" + str(index))
            self.assertNotEqual(result.returncode, 0, "Control accepted an unissued fence")

if __name__ == "__main__":
    unittest.main()
