"""Compile the observed scheduler trace against real scheduling predicates."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("present_decision_lock_checks", HERE / "test_engine_present_lock_patch.py")
LOCK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(LOCK)

TRACE = r'''
#include "drivers/metal/openrc_mfx_present_state.h"
#define REQUIRE(x) do { if (!(x)) return __LINE__; } while (false)
int main() {
    using namespace OpenRCMetalPresent;
    Scheduler scheduler;
    Job job;
    job.generation=1;job.frame=1;job.epoch=1;job.serial=1;
    job.reserved_at=100;job.real_interval=1.0/30.0;
    job.generated_deadline=100.1;job.real_deadline=100.18;
    job.fallback=reinterpret_cast<void *>(1);
    job.generated=reinterpret_cast<void *>(2);
    job.paired_real=reinterpret_cast<void *>(3);
    job.output_lease=std::make_shared<int>(1);
    job.proof=std::make_shared<Proof>(0,1,1,1);
    job.proof->warm_count.store(5);
    job.proof->encode_result.store(1);
    job.proof->sdk_completion.store(1);
    REQUIRE(scheduler.submit(job));
    auto selected=scheduler.choose(100.001,100.01,100.016,0.016,true);
    REQUIRE(selected.kind==Kind::REAL); // There is no previous scheduled real.
    auto trace=scheduler.decision_trace();
    REQUIRE(trace.considered==1 && trace.proof_rejected==0 && trace.cadence_rejected==1 && trace.deadline_rejected==0);
    REQUIRE(trace.paired_candidate && trace.proof_ready && !trace.cadence_ready && trace.deadlines_ready);
    REQUIRE(trace.frame==1 && trace.previous_frame==0 && trace.last_real_frame==0);
    REQUIRE(trace.deadline==100.01 && trace.now==100.001 && trace.target==100.016);
    REQUIRE(trace.warm_count==5 && trace.encode_result==1 && trace.sdk_completion==1);
    job.proof->warm_count.store(0);job.proof->sdk_completion.store(-1);
    trace=scheduler.decision_trace(); // Trace preserves the scalars used by the decision.
    REQUIRE(trace.warm_count==5 && trace.sdk_completion==1);
    scheduler.reset_to(2);
    REQUIRE(scheduler.decision_trace().considered==0);
}
'''


class PresentDecisionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        LOCK.PresentCallbackLockTests.setUpClass.__func__(cls)
        patch = HERE / "patches/0015-metal-present-decision-observation.patch"
        LOCK.PRESENT.ENGINE.git(cls.base, "apply", "--check", str(patch))
        LOCK.PRESENT.ENGINE.git(cls.base, "apply", "--whitespace=error-all", str(patch))

    compile_run = LOCK.PRESENT.PresentPatchTests.compile_run

    def test_decision_retains_the_actual_predicate_inputs(self):
        result = self.compile_run(TRACE, "present_decision")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_observation_preserves_existing_scheduler_controls(self):
        result = self.compile_run(LOCK.PRESENT.STATE_TEST, "present_observed_state")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
