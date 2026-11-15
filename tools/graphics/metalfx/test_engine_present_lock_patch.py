"""Source-bound regression for the observed CA callback/state-mutex inversion.

The portable stand-in exercises the actual presented callback and lock ordering;
native rendered retesting remains necessary. No Metal object destructor is modeled.
"""
from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("present_lock_checks", HERE / "test_engine_present_patch.py")
PRESENT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PRESENT)

STUB = r'''
#include <atomic>
#include <chrono>
#include <cstdlib>
#include <future>
#include <mutex>
#include <thread>
#include "drivers/metal/openrc_mfx_present_bridge.h"
#define REQUIRE(x) do { if (!(x)) return __LINE__; } while (false)
double CACurrentMediaTime() { return 100.0; }
namespace OpenRCMetalPresent {
struct Shared {
    std::mutex mutex;
    std::atomic<uint64_t> requested_generation{1};
    Snapshot stats;
    Scheduler scheduler;
    bool stopping=false;
    unsigned in_flight=0;
};
}
struct Drawable { double presentedTime=101.0; };
@BODY@
'''

CYCLE = r'''
int main() {
    auto s=std::make_shared<OpenRCMetalPresent::Shared>();
    std::weak_ptr<OpenRCMetalPresent::Shared> weak=s;
    const uint64_t sample_generation=1,sample_frame=7;
    const bool is_generated=false;
    auto callback=[&](Drawable p_drawable) { @PRESENTED@ };
    std::unique_lock<std::mutex> lock(s->mutex);
    @UNLOCK@
    std::mutex ca_lock;
    std::promise<void> ca_entered;
    auto ready=ca_entered.get_future();
    auto done=std::make_shared<std::atomic<bool>>(false);
    std::thread watchdog([done] {
        std::this_thread::sleep_for(std::chrono::seconds(1));
        if (!done->load()) std::_Exit(77);
    });
    watchdog.detach();
    std::thread ca([&] {
        std::lock_guard<std::mutex> ca_guard(ca_lock);
        ca_entered.set_value();
        callback(Drawable{});
    });
    ready.wait();
    // Stand-in for addPresentedHandler taking CA's lock while an old
    // didPresent callback, under that same lock, needs the app mutex.
    { std::lock_guard<std::mutex> registration(ca_lock); }
    if (lock.owns_lock()) lock.unlock();
    ca.join();
    REQUIRE(s->stats.real_presented==1 && s->stats.last_presented_frame==7);
    done->store(true);
}
'''

ADMISSION = r'''
void admit(const std::shared_ptr<OpenRCMetalPresent::Shared> &s,
        const OpenRCMetalPresent::Choice &choice,double deadline,bool is_generated) {
    @ADMIT@
}
int main() {
    for (int fault=0;fault<6;++fault) {
        auto s=std::make_shared<OpenRCMetalPresent::Shared>();
        OpenRCMetalPresent::Job job;
        job.generation=1;job.frame=1;job.fallback=reinterpret_cast<void *>(1);
        job.proof=std::make_shared<OpenRCMetalPresent::Proof>(0,1,1,1);
        job.source_generation=std::make_shared<OpenRCMetalPresent::SourceGeneration>();
        job.output_lease=std::make_shared<int>(1);
        REQUIRE(s->scheduler.submit(job));
        auto choice=s->scheduler.choose(100,101,100.016,0.016,true);
        REQUIRE(choice.kind==OpenRCMetalPresent::Kind::REAL);
        double deadline=101;
        if (fault==1) deadline=100;
        if (fault==2) choice.proof->request_cancel();
        if (fault==3) choice.source_generation->request_cancel();
        if (fault==4) s->requested_generation.store(2);
        if (fault==5) s->stopping=true;
        admit(s,choice,deadline,false);
        REQUIRE(s->in_flight==(fault==0 ? 1u:0u));
        REQUIRE(s->stats.real_present_requested==(fault==0 ? 1u:0u));
        REQUIRE(s->scheduler.last_real()==(fault==0 ? 1u:0u));
        admit(s,choice,deadline,false);
        REQUIRE(s->in_flight==(fault==0 ? 1u:0u));
    }
}
'''


class PresentCallbackLockTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        PRESENT.PresentPatchTests.setUpClass.__func__(cls)
        patch = HERE / "patches/0014-metal-present-callback-lock.patch"
        PRESENT.ENGINE.git(cls.base, "apply", "--check", str(patch))
        PRESENT.ENGINE.git(cls.base, "apply", "--whitespace=error-all", str(patch))
        cls.bridge = (cls.base / "drivers/metal/openrc_mfx_present_bridge.mm").read_text()

    compile_run = PRESENT.PresentPatchTests.compile_run

    def cycle(self, source):
        body = PRESENT.CHECK.cxx_function(source, "[drawable addPresentedHandler:^")
        body = body[body.index("{") + 1:body.rindex("}")]
        early_unlock = source.index("lock.unlock();") < source.index("id<MTLTexture> dst = drawable.texture;")
        return STUB.replace("@BODY@", CYCLE.replace("@PRESENTED@", body).replace(
            "@UNLOCK@", "lock.unlock();" if early_unlock else ""))

    def test_actual_presented_callback_can_finish_during_registration(self):
        result = self.compile_run(self.cycle(self.bridge), "callback_lock")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_old_lock_order_reproduces_bounded_deadlock_control(self):
        changed = self.bridge.replace("\t\tlock.unlock();\n", "", 1)
        changed = changed.replace("\t\t[command commit];", "\t\tlock.unlock();\n\t\t[command commit];", 1)
        result = self.compile_run(self.cycle(changed), "callback_lock_mutant")
        self.assertEqual(result.returncode, 77, result.stdout + result.stderr)

    def test_admission_rechecks_after_native_registration(self):
        start = self.bridge.index("std::lock_guard<std::mutex> admission(s->mutex);")
        end = self.bridge.index("\n\t\t}\n\t\t[command commit];", start)
        body = self.bridge[start:end]
        self.assertLess(self.bridge.index("[command addCompletedHandler:"), start)
        result = self.compile_run(STUB.replace("@BODY@", ADMISSION.replace("@ADMIT@", body)), "callback_admission")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_native_status_and_drawable_access_do_not_hold_callback_mutex(self):
        callback = PRESENT.CHECK.cxx_function(self.bridge, "[command addCompletedHandler:^")
        self.assertLess(callback.index("p_command.status"), callback.index("guard(shared->mutex)"))
        self.assertLess(self.bridge.index("drawable = p_update.drawable"), self.bridge.index("lock(s->mutex)"))


if __name__ == "__main__":
    unittest.main()
