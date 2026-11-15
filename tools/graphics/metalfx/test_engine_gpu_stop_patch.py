"""Source-bound controls for synchronous GPU failure stops, without a real fault."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import re
import unittest

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("gpu_stop_empty_checks", HERE / "test_engine_empty_patch.py")
EMPTY = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(EMPTY)
EMPTY.PATCHES.append(HERE / "patches/0012-rd-gpu-failure-stop.patch")

STUB = r'''
#include <cstdint>
#include <string>
#include <vector>
using Error = int;
constexpr Error OK = 0;
struct Fatal {};
// Production uses Godot's fatal trap; the fake exception proves control flow
// stops before the modeled next mutation without opening an OS crash dialog.
#define CRASH_COND_MSG(condition, message) do { if (condition) throw Fatal{}; } while (false)
#define REQUIRE(condition) do { if (!(condition)) return __LINE__; } while (false)
struct ID { int value = 1; explicit operator bool() const { return value != 0; } };
template<class T> struct VectorView {
    VectorView() = default;
    VectorView(T) {}
    VectorView(const std::vector<T> &) {}
};
namespace RDD { using SemaphoreID = ID; }
struct Driver {
    Error result = OK;
    int calls = 0;
    std::string backend = "Metal";
    std::string get_api_name() const { return backend; }
    Error command_queue_execute_and_present(ID, VectorView<ID>, VectorView<ID>, VectorView<ID>, ID, VectorView<ID>) { ++calls; return result; }
    Error fence_wait(ID) { ++calls; return result; }
};
struct Frame { ID semaphore, fence; std::vector<ID> swap_chains_to_present; };
struct Worker { ID command_buffer, command_fence; };
struct Iterator { std::vector<ID> value; };
@FUNCTIONS@
int main() {
    using Function = void (*)(Driver *, int &);
    const Function functions[] = { @CASES@ };
    for (auto function : functions) for (Error result : {OK, 1, 24}) for (bool metal : {false, true}) {
        Driver driver; driver.result = result; driver.backend = metal ? "Metal" : "Vulkan";
        int next_mutations = 0;
        bool stopped = false;
        try { function(&driver, next_mutations); } catch (const Fatal &) { stopped = true; }
        REQUIRE(driver.calls == 1);
        REQUIRE(stopped == (metal && result != OK));
        REQUIRE(next_mutations == (metal && result != OK ? 0 : 1));
    }
}
'''

LOCALS = r'''
    ID main_queue, present_queue, transfer_queue, command_buffer, signal_semaphore, signal_fence;
    std::vector<ID> wait_semaphores, swap_chains, p_signal_semaphores;
    std::vector<Frame> frames(1);
    unsigned frame = 0, p_frame = 0;
    Worker worker;
    Worker *p_transfer_worker = &worker;
    Iterator iterator;
    Iterator *it = &iterator;
'''

class GPUFailureStopTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        EMPTY.EmptySubmissionTests.setUpClass.__func__(cls)
        cls.source = (cls.base / "servers/rendering/rendering_device.cpp").read_text()
        blocks = []
        for match in re.finditer(r"Error gpu_(?:submit|wait)_result = driver->", cls.source):
            end = cls.source.index('");', cls.source.index("CRASH_COND_MSG", match.start())) + 3
            blocks.append(cls.source[match.start():end])
        if len(blocks) != 6:
            raise AssertionError(f"Expected all six guarded call sites, found {len(blocks)}")
        functions = []
        for index, block in enumerate(blocks):
            functions.append(f"void case_{index}(Driver *driver, int &next_mutations) {{\n{LOCALS}\n{block}\n++next_mutations;\n}}")
        cls.harness = STUB.replace("@FUNCTIONS@", "\n".join(functions)).replace("@CASES@", ",".join(f"case_{i}" for i in range(6)))

    def compile_run(self, source, name):
        # The snippets retain each actual call expression. Fixture locals are a
        # superset so the same context can compile all six production sites.
        source = source.replace("void case_", "[[maybe_unused]] void case_")
        source = source.replace("    ID main_queue", "    [[maybe_unused]] ID main_queue")
        source = source.replace("    unsigned frame", "    [[maybe_unused]] unsigned frame")
        source = source.replace("    Worker *p_transfer_worker", "    [[maybe_unused]] Worker *p_transfer_worker")
        source = source.replace("    Iterator *it", "    [[maybe_unused]] Iterator *it")
        return EMPTY.EmptySubmissionTests.compile_run(self, source, name)

    def test_actual_six_call_sites_stop_before_next_mutation(self):
        result = self.compile_run(self.harness, "gpu_stop")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_control_detects_ignored_backend_errors(self):
        mutant = re.sub(r'CRASH_COND_MSG\(gpu_(?:submit|wait)_result != OK && driver->get_api_name\(\) == "Metal",', "CRASH_COND_MSG(false,", self.harness)
        self.assertNotEqual(mutant, self.harness)
        # Keep the actual returned values read in this deliberate mutant.
        mutant = mutant.replace("Error gpu_", "[[maybe_unused]] Error gpu_")
        result = self.compile_run(mutant, "gpu_stop_mutant")
        self.assertNotEqual(result.returncode, 0, "Control allowed resource mutation after backend failure")

    def test_wait_guards_precede_frame_and_transfer_recycling(self):
        for signature, mutation in (
            ("void RenderingDevice::_stall_for_frame(", "frames[p_frame].fence_signaled = false"),
            ("void RenderingDevice::_wait_for_transfer_worker(", "driver->command_pool_reset"),
        ):
            function = EMPTY.CHECK.cxx_function(self.source, signature)
            self.assertLess(function.index("CRASH_COND_MSG"), function.index(mutation))

if __name__ == "__main__":
    unittest.main()
