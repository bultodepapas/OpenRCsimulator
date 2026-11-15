"""Source-bound portable controls for the experimental Metal presentation seam.

The compiled controls exercise the actual patched scheduler and lease/cancel
types with fake texture handles. They do not run Metal, a display link, Godot,
or the GPU. The native fixture is a separate checked-runner exercise.
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
ROOT = HERE.parents[2]


def module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[name] = result
    spec.loader.exec_module(result)
    return result


ENGINE = module("openrc_present_engine", HERE / "engine.py")
CHECK = module("openrc_present_checks", HERE / "test_engine_patch.py")
NAMES = (
    "0001-metalfx-allocation-fallback.patch", "0002-metalfx-history-reset.patch",
    "0003-metalfx-debug-faults.patch", "0004-metalfx-frame-inputs.patch",
    "0005-metal-triangle-query.patch", "0006-metalfx-gpu-observation.patch",
    "0007-metalfx-denoised-binding.patch", "0008-metal-paired-presentation.patch",
)
PATCHES = tuple(HERE / "patches" / name for name in NAMES)
PREREQUISITES = (
    "f04167e05f452bfc37e85e90d512373d92c3f6ec808cef8431a0705e197d716a",
    "d7570f1b3639616e4e565a920cc4b9caca844bf7d1c8b3ec7d14d6e596c4ecc5",
    "cdacbdf81c80e44b96b200f1890236774225d93d8b54299f8e7db47b9f2c21cd",
    "2cfc1c4b466dfba51ae940d4c0529d290bf5a4502cd562d52edc4c4712e1ce18",
    "825920ed18b56dd3d531eda30d25ffb9da33b6becb29dd849c03073ff375e155",
    "565aec0587e8d5b8895f8e9025be316437a9cda0f7207e5c02214f0bf9cfd272",
    "d3ce4cb242eb311d214535ce695c744c2a15801b1226c940fb707b71bce64166",
)
PATCH_HASH = "e4b73172a8025a1702a04ee818b0e0591d68ec814610d22a6441420ebdfef18a"

STATE_TEST = r'''#include <drivers/metal/openrc_mfx_present_state.h>
#define CHECK(x) do { if (!(x)) return __LINE__; } while (0)
#include <limits>
#include <thread>

using namespace OpenRCMetalPresent;
static void *ptr(unsigned n) { return reinterpret_cast<void *>(uintptr_t(n)); }

static Job job(Scheduler &s, uint64_t frame, bool good = true) {
	Job j;
	j.generation = s.current_generation(); j.frame = frame;
	j.epoch = 7; j.serial = frame; j.reserved_at = 9.99; j.generated_deadline = 10.08; j.real_deadline = 10.12; j.real_interval = 0.04;
	j.fallback = ptr(frame * 10 + 1); j.generated = ptr(frame * 10 + 2); j.paired_real = ptr(frame * 10 + 3);
	j.proof = std::make_shared<Proof>(frame - 1, frame, j.epoch, j.serial);
	j.proof->encode_result.store(good ? 1 : -1);
	j.proof->sdk_completion.store(good ? 1 : -1);
	j.proof->warm_count.store(5);
	j.output_lease = std::make_shared<int>(42);
	return j;
}

int main() {
	Scheduler s;
	CHECK(s.choose(9.98, 9.99, 10.0, 0.02, true).kind == Kind::NONE);
	auto bad = job(s, 1); bad.fallback = nullptr; CHECK(!s.submit(bad));
	CHECK(s.submit(job(s, 1, false)));
	CHECK(s.choose(9.98, 9.99, 10.0, 0.02, false).kind == Kind::NONE);
	CHECK(s.choose(9.99, 9.99, 10.0, 0.02, true).kind == Kind::NONE);
	CHECK(s.choose(9.98, 9.99, std::numeric_limits<double>::quiet_NaN(), 0.02, true).kind == Kind::NONE);
	auto c = s.choose(9.98, 9.99, 10.0, 0.02, true); CHECK(c.kind == Kind::REAL && c.texture == ptr(11));
	CHECK(s.commit(c)); CHECK(!s.commit(c)); CHECK(!s.submit(job(s, 1)));
	CHECK(s.submit(job(s, 2))); c = s.choose(10, 10.01, 10.02, 0.02, true);
	CHECK(c.kind == Kind::GENERATED && c.texture == ptr(22)); CHECK(s.commit(c));
	c = s.choose(10.02, 10.03, 10.04, 0.02, true); CHECK(c.kind == Kind::REAL && c.texture == ptr(23));
	auto hold = std::weak_ptr<void>(c.output_lease); CHECK(s.commit(c)); CHECK(!hold.expired());
	c = {}; CHECK(hold.expired());
	CHECK(s.submit(job(s, 3))); c = s.choose(10.04, 10.05, 10.06, 0.02, true); CHECK(c.kind == Kind::GENERATED); CHECK(s.commit(c));
	CHECK(s.submit(job(s, 4))); c = s.choose(10.06, 10.07, 10.08, 0.02, true);
	CHECK(c.kind == Kind::REAL && c.frame == 3 && c.texture == ptr(33)); CHECK(s.commit(c));
	CHECK(!s.submit(job(s, 3)));
	c = s.choose(10.08, 10.09, 10.10, 0.02, true); CHECK(c.kind == Kind::REAL && c.frame == 4); CHECK(s.commit(c));
	CHECK(s.submit(job(s, 5))); c = s.choose(10.10, 10.11, 10.12, 0.02, true);
	CHECK(c.kind == Kind::REAL && c.texture == ptr(51)); CHECK(s.commit(c));
	Job old = job(s, 6); s.reset(); CHECK(!s.submit(old));
	CHECK(s.submit(job(s, 1))); c = s.choose(9.98, 9.99, 10.0, 0.02, true); CHECK(c.kind == Kind::REAL);
	s.reset(); CHECK(!s.commit(c));
	auto lease = std::make_shared<Lease>();
	{ auto first = Ticket::acquire(lease); CHECK(first); CHECK(!Ticket::acquire(lease)); { auto second = first; first.reset(); CHECK(lease->held.load()); } }
	CHECK(!lease->held.load());
	{
		Scheduler v; CHECK(v.submit(job(v, 1)));
		auto x = v.choose(9.98, 9.99, 10.0, 0.02, true); CHECK(x.kind == Kind::REAL); CHECK(v.commit(x));
		auto skipped = job(v, 3); CHECK(v.submit(skipped));
		x = v.choose(10, 10.01, 10.02, 0.02, true); CHECK(x.kind == Kind::REAL && x.frame == 3); CHECK(v.commit(x));
	}
	{
		Scheduler v; CHECK(v.submit(job(v, 1)));
		auto x = v.choose(9.98, 9.99, 10.0, 0.02, true); CHECK(x.kind == Kind::REAL); CHECK(v.commit(x));
		auto slow = job(v, 2); slow.real_interval = 0.033; CHECK(v.submit(slow));
		x = v.choose(9.999, 10.006, 10.016, 0.02, true); CHECK(x.kind == Kind::REAL); CHECK(v.commit(x));
	}
	{
		Scheduler v; CHECK(v.submit(job(v, 1)));
		auto x = v.choose(9.98, 9.99, 10.0, 0.02, true); CHECK(x.kind == Kind::REAL); CHECK(v.commit(x));
		auto no_sdk = job(v, 2); no_sdk.proof->sdk_completion.store(0); CHECK(v.submit(no_sdk));
		x = v.choose(10, 10.01, 10.02, 0.02, true); CHECK(x.kind == Kind::REAL); CHECK(v.commit(x));
	}
	{
		Scheduler v; CHECK(v.submit(job(v, 1)));
		auto x = v.choose(9.98, 9.99, 10.0, 0.02, true); CHECK(x.kind == Kind::REAL); CHECK(v.commit(x));
		CHECK(v.submit(job(v, 2))); x = v.choose(10, 10.01, 10.02, 0.02, true);
		CHECK(x.kind == Kind::GENERATED); CHECK(v.commit(x));
		auto newest = job(v, 3); newest.reserved_at = 10.49; newest.generated_deadline = 10.57; newest.real_deadline = 10.62;
		CHECK(v.submit(newest)); x = v.choose(10.48, 10.49, 10.50, 0.02, true);
		CHECK(x.kind == Kind::REAL && x.frame == 3 && x.texture == ptr(31) && x.abandoned_epoch == 7); CHECK(v.commit(x));
		CHECK(v.blocked_source_epoch() == 7 && v.discontinuity_count() == 1);
		auto blocked = job(v, 4); blocked.reserved_at = 10.49; blocked.generated_deadline = 10.57; blocked.real_deadline = 10.62;
		CHECK(v.submit(blocked)); x = v.choose(10.5, 10.51, 10.52, 0.02, true); CHECK(x.kind == Kind::REAL); CHECK(v.commit(x));
	}
	{
		Scheduler v; auto forged = job(v, 1); forged.generated_scheduled = true; CHECK(!v.submit(forged));
		CHECK(v.submit(job(v, 1))); v.reset(); CHECK(v.blocked_source_epoch() == 7);
	}
	{
		Scheduler v; CHECK(v.submit(job(v, 1)));
		auto x = v.choose(9.98, 9.99, 10.0, 0.02, true); CHECK(x.kind == Kind::REAL); CHECK(v.commit(x));
		CHECK(v.submit(job(v, 2))); x = v.choose(10, 10.01, 10.02, 0.02, true);
		CHECK(x.kind == Kind::GENERATED); CHECK(v.commit(x));
		CHECK(v.recover_failed(x)); CHECK(v.blocked_source_epoch() == 7);
		auto fallback = v.choose(10.02, 10.03, 10.04, 0.02, true);
		CHECK(fallback.kind == Kind::REAL && fallback.frame == 2 && fallback.texture == ptr(21)); CHECK(v.commit(fallback));
		CHECK(!v.recover_failed(x));
		auto blocked = job(v, 3); CHECK(v.submit(blocked));
		fallback = v.choose(10.04, 10.05, 10.06, 0.02, true); CHECK(fallback.kind == Kind::REAL); CHECK(v.commit(fallback));
	}
	{
		Scheduler v; CHECK(v.submit(job(v, 1)));
		auto x = v.choose(9.98, 9.99, 10.0, 0.02, true); CHECK(x.kind == Kind::REAL); CHECK(v.commit(x));
		auto cancelled = job(v, 2); cancelled.proof->request_cancel(); CHECK(!v.submit(cancelled));
		x = v.choose(10, 10.01, 10.02, 0.02, true); CHECK(x.kind == Kind::NONE);
	}
	{
		Scheduler v; CHECK(v.submit(job(v, 1)));
		auto x = v.choose(9.98, 9.99, 10.0, 0.02, true); CHECK(v.commit(x));
		auto frame = job(v, 2); auto proof = frame.proof; CHECK(v.submit(frame));
		x = v.choose(10, 10.01, 10.02, 0.02, true); CHECK(x.kind == Kind::GENERATED);
		proof->request_cancel(); CHECK(!v.commit(x));
	}
	{
		auto proof = std::make_shared<Proof>(1, 2, 7, 2);
		auto guard = proof->lock_for_presentation();
		std::atomic<bool> started{false};
		std::thread worker([&] { started.store(true); proof->request_cancel(); });
		while (!started.load()) { std::this_thread::yield(); }
		worker.join(); CHECK(proof->is_cancelled()); CHECK(!proof->try_cancel_complete());
		guard.unlock(); CHECK(proof->try_cancel_complete());
	}
	{
		Scheduler v;
		auto real = job(v, 1); real.generated = nullptr; real.paired_real = nullptr; real.proof.reset();
		auto source = std::make_shared<SourceGeneration>(); real.source_generation = source;
		CHECK(v.submit(real));
		auto x = v.choose(9.98, 9.99, 10.0, 0.02, true); CHECK(x.kind == Kind::REAL);
		source->request_cancel(); CHECK(!v.commit(x));
		CHECK(v.choose(9.98, 9.99, 10.0, 0.02, true).kind == Kind::NONE);
	}
	return 0;
}
'''

CAP_TEST = r'''
#include "servers/rendering/storage/metalfx_presentation.h"
#include <cstdint>
#include <memory>
#include <vector>
using namespace OpenRCMetalPresent;
struct OpenRCOutputSlot { std::shared_ptr<Lease> lease; };
struct Model {
    OpenRCOutputSlot openrc_slots[4];
    std::vector<int> openrc_retired_slots;
    bool openrc_resize_pending=false;
    bool reject() {
@CAP@
        return false;
    }
};
#define CHECK(x) do { if (!(x)) return __LINE__; } while (0)
int main() {
    Model m; for (auto &slot : m.openrc_slots) slot.lease = std::make_shared<Lease>();
    m.openrc_retired_slots.resize(4); CHECK(!m.reject());
    m.openrc_slots[0].lease->held.store(true); CHECK(m.reject() && m.openrc_resize_pending);
    m.openrc_retired_slots.resize(3); CHECK(!m.reject());
    m.openrc_slots[1].lease->held.store(true); CHECK(m.reject());
    return 0;
}
'''

PRUNE_TEST = r'''
#include <algorithm>
#include <cstdint>
#include <vector>
using RID = int;
template<class T> struct Vector : std::vector<T> {};
template<class K,class V> struct KeyValue { K key; V value; };
struct Mapping {
    std::vector<KeyValue<RID,RID>> values;
    auto begin() { return values.begin(); }
    auto end() { return values.end(); }
    void erase(RID key) {
        values.erase(std::remove_if(values.begin(), values.end(), [key](auto &v) { return v.key == key; }), values.end());
    }
};
struct FakeRD { bool uniform_set_is_valid(RID id) { return id == 11 || id == 13; } };
struct Model {
    Mapping render_target_descriptors;
    void prune(FakeRD *rd) {
@PRUNE@
    }
};
#define CHECK(x) do { if (!(x)) return __LINE__; } while (0)
int main() {
    Model m; FakeRD rd;
    m.render_target_descriptors.values={{1,11},{2,12},{3,13}};
    for (int i=0; i<1000; ++i) {
        m.render_target_descriptors.values.push_back({100+i,12}); m.prune(&rd);
        CHECK(m.render_target_descriptors.values.size() == 2);
    }
    return 0;
}
'''

RETIRE_TEST = r'''
#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
struct Shared { std::mutex gate; std::atomic<uint64_t> requested_generation{1}; };
struct Presenter { std::shared_ptr<Shared> state=std::make_shared<Shared>(); };
using Handle = std::shared_ptr<Presenter>;
@GENERATION@
@RETIRE@
@QUIESCENCE@
#define CHECK(x) do { if (!(x)) return __LINE__; } while (0)
int main() {
    auto h=std::make_shared<Presenter>();
    {
        std::lock_guard<std::mutex> locked(h->state->gate);
        CHECK(generation(h)==1); retire_generation(h); CHECK(generation(h)==2);
        CHECK(!try_retire_complete(h));
        retire_generation(h); CHECK(generation(h)==3); CHECK(generation({})==0);
        h->state->requested_generation.store(UINT64_MAX); retire_generation(h); CHECK(generation(h)==0);
        retire_generation(h); CHECK(generation(h)==0);
    }
    CHECK(try_retire_complete(h)); CHECK(try_retire_complete({}));
    return 0;
}
'''

MULTI_BLIT_TEST = r'''
#include <memory>
namespace OpenRCMetalPresent { struct SourceGeneration {}; }
struct Blit { std::shared_ptr<OpenRCMetalPresent::SourceGeneration> source_generation; struct { bool requested=false; } paired; };
bool reject(const Blit *p_render_targets, int p_amount) {
@BRANCH@
    return false;
}
#define CHECK(x) do { if (!(x)) return __LINE__; } while (0)
int main() {
    Blit b[2]; CHECK(!reject(b,2));
    auto first=std::make_shared<OpenRCMetalPresent::SourceGeneration>();
    auto second=std::make_shared<OpenRCMetalPresent::SourceGeneration>();
    b[0].source_generation=first; CHECK(reject(b,2));
    b[0].source_generation.reset(); b[1].source_generation=first; CHECK(reject(b,2));
    b[0].source_generation=first; CHECK(!reject(b,2));
    b[1].source_generation=second; CHECK(reject(b,2));
    return 0;
}
'''

SURFACE_IDENTITY_TEST = r'''
#include <cstdint>
#include <memory>
bool needs_replace(uint64_t current_id, uint64_t openrc_surface_id,
        const std::shared_ptr<int> &current_handle, const std::shared_ptr<int> &openrc_presenter) {
    return @CONDITION@;
}
#define CHECK(x) do { if (!(x)) return __LINE__; } while (0)
int main() {
    auto first=std::make_shared<int>(1), second=std::make_shared<int>(2);
    CHECK(!needs_replace(7,7,first,first));
    CHECK(needs_replace(8,7,first,first));
    CHECK(needs_replace(7,7,second,first));
    return 0;
}
'''

SOURCE_TRANSITION_TEST = r'''
#include <memory>
namespace OpenRCMetalPresent {
struct SourceGeneration {
    bool cancelled=false, idle=true;
    void request_cancel() { cancelled=true; }
    bool try_cancel_complete() { return idle; }
    bool is_cancelled() { return cancelled; }
};
struct Presenter { bool idle=true; unsigned generation=1, retired=0; };
using Handle=std::shared_ptr<Presenter>;
void retire_generation(const Handle &h) { ++h->generation; ++h->retired; }
bool try_retire_complete(const Handle &h) { return h->idle; }
}
struct Model {
    std::shared_ptr<OpenRCMetalPresent::SourceGeneration> openrc_source;
    OpenRCMetalPresent::Handle openrc_presenter=std::make_shared<OpenRCMetalPresent::Presenter>();
    bool openrc_source_default=true, openrc_source_transition=false;
    bool enter(std::shared_ptr<OpenRCMetalPresent::SourceGeneration> incoming_source, bool any_tagged) {
@TRANSITION@
        return false;
    }
};
#define CHECK(x) do { if (!(x)) return __LINE__; } while (0)
int main() {
    Model m; auto a=std::make_shared<OpenRCMetalPresent::SourceGeneration>();
    auto b=std::make_shared<OpenRCMetalPresent::SourceGeneration>(); m.openrc_source=a;
    a->idle=false; CHECK(m.enter(b,true)); CHECK(a->cancelled && m.openrc_presenter->retired==1 && m.openrc_source==a);
    CHECK(m.enter(b,true)); CHECK(m.openrc_presenter->retired==1 && m.openrc_source==a);
    a->idle=true; m.openrc_presenter->idle=false; CHECK(m.enter(b,true)); CHECK(m.openrc_source==a);
    m.openrc_presenter->idle=true; CHECK(m.enter(b,true)); CHECK(m.openrc_source==b && !m.openrc_source_default);
    CHECK(!m.enter(b,true));
    b->idle=false; CHECK(m.enter({},false)); CHECK(b->cancelled && m.openrc_source==b);
    b->idle=true; CHECK(m.enter({},false)); CHECK(m.openrc_source!=b && m.openrc_source_default);
    return 0;
}
'''

SUBMIT_RECEIPT_TEST = r'''
#include <atomic>
#include <cstdint>
#include <memory>
#include <mutex>
#include <utility>
struct Job { uint64_t generation=0; void *generated=nullptr; void *paired_real=nullptr; };
struct Scheduler { bool submit(Job job) { return job.generation==2; } };
struct Stats { int real_accepted_jobs=0, pair_accepted_candidates=0; };
struct Shared { std::mutex mutex; bool stopping=false; std::atomic<uint64_t> requested_generation{2}; Scheduler scheduler; Stats stats; };
struct Presenter { std::shared_ptr<Shared> state=std::make_shared<Shared>(); };
using Handle=std::shared_ptr<Presenter>;
void synchronize_generation(Shared &) {}
@SUBMIT@
#define CHECK(x) do { if (!(x)) return __LINE__; } while (0)
int main() {
    auto h=std::make_shared<Presenter>(); Job old; old.generation=1; old.generated=(void*)1; old.paired_real=(void*)2;
    CHECK(!submit(h,old)); CHECK(h->state->stats.real_accepted_jobs==0 && h->state->stats.pair_accepted_candidates==0);
    Job valid=old; valid.generation=2; CHECK(submit(h,valid));
    CHECK(h->state->stats.real_accepted_jobs==1 && h->state->stats.pair_accepted_candidates==1);
    return 0;
}
'''

THREAD_START_TEST = r'''
#include <memory>
struct Shared {};
struct Presenter { std::shared_ptr<Shared> state; int worker=0; bool worker_started=false; };
static bool reject_create=true;
static void *held=nullptr;
void *present_worker(void *) { return nullptr; }
int pthread_create(int *worker, void *, void *(*)(void *), void *arg) {
    held=arg; *worker=9; return reject_create ? 11 : 0;
}
@START@
#define CHECK(x) do { if (!(x)) return __LINE__; } while (0)
int main() {
    Presenter p; p.state=std::make_shared<Shared>();
    CHECK(!start_worker(nullptr)); CHECK(!start_worker(&p)); CHECK(!p.worker_started && p.state.use_count()==1);
    reject_create=false; CHECK(start_worker(&p)); CHECK(p.worker_started && p.state.use_count()==2);
    delete static_cast<std::shared_ptr<Shared> *>(held); held=nullptr;
    CHECK(p.state.use_count()==1); CHECK(!start_worker(&p));
    return 0;
}
'''


class PresentPatchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not CHECK.ARCHIVE.is_file() or ENGINE.sha256(CHECK.ARCHIVE) != CHECK.ARCHIVE_SHA256:
            raise RuntimeError("Pinned Godot source archive is missing or differs")
        if tuple(ENGINE.sha256(path) for path in PATCHES[:7]) != PREREQUISITES:
            raise RuntimeError("Frozen prerequisite patches differ")
        if ENGINE.sha256(PATCHES[7]) != PATCH_HASH:
            raise RuntimeError("Presentation patch differs from its frozen test identity")
        parent = ROOT / "tmp/metalfx-present-port"
        parent.mkdir(parents=True, exist_ok=True)
        cls.temp = tempfile.TemporaryDirectory(prefix="controls-", dir=parent)
        cls.addClassCleanup(cls.temp.cleanup)
        cls.base = Path(cls.temp.name)
        paths = ENGINE.patch_paths(PATCHES)
        with zipfile.ZipFile(CHECK.ARCHIVE) as archive:
            members = set(archive.namelist())
            cls.original_compositor = archive.read(f"{ENGINE.SOURCE_PREFIX}/servers/rendering/renderer_rd/renderer_compositor_rd.cpp").decode("utf-8")
            for path in paths:
                member = f"{ENGINE.SOURCE_PREFIX}/{path}"
                if member in members:
                    target = cls.base / path
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(archive.read(member))
        for patch in PATCHES:
            ENGINE.git(cls.base, "apply", "--check", str(patch.resolve()))
            ENGINE.git(cls.base, "apply", str(patch.resolve()))
        cls.state = (cls.base / "drivers/metal/openrc_mfx_present_state.h").read_text(encoding="utf-8")
        cls.shared = (cls.base / "servers/rendering/storage/metalfx_presentation.h").read_text(encoding="utf-8")
        cls.compositor = (cls.base / "servers/rendering/renderer_rd/renderer_compositor_rd.cpp").read_text(encoding="utf-8")
        cls.bridge = (cls.base / "drivers/metal/openrc_mfx_present_bridge.mm").read_text(encoding="utf-8")
        cls.device = (cls.base / "servers/rendering/rendering_device.cpp").read_text(encoding="utf-8")
        cls.context = (cls.base / "drivers/metal/rendering_context_driver_metal.cpp").read_text(encoding="utf-8")

    def compile_run(self, code: str, name: str, include: Path | None = None):
        compiler = shutil.which("g++") or shutil.which("clang++")
        self.assertTrue(compiler, "C++17 compiler required")
        source = self.base / (name + ".cpp")
        executable = self.base / (name + (".exe" if os.name == "nt" else ""))
        source.write_text(code, encoding="utf-8")
        command = [compiler, "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror", "-pthread"]
        if include:
            command += ["-I", str(include)]
        command += ["-I", str(self.base), str(source), "-o", str(executable)]
        built = subprocess.run(command, capture_output=True, text=True, timeout=90)
        self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
        return subprocess.run([str(executable)], capture_output=True, text=True, timeout=20)

    def test_actual_scheduler_leases_deadlines_and_retirement(self):
        result = self.compile_run(STATE_TEST, "present_state")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_scheduler_mutations_are_detected(self):
        mutations = (
            ("previous", "job.proof->previous_frame == last_real_scheduled", "true"),
            ("sdk", "job.proof->sdk_completion.load(std::memory_order_acquire) == 1", "true"),
            ("cadence", "p_display_period * 2.0 <= job.real_interval * 1.05", "true"),
            ("expiry", "p_target > old_real.real_deadline", "false"),
        )
        for name, before, after in mutations:
            with self.subTest(name=name):
                self.assertEqual(self.state.count(before), 1)
                root = self.base / ("mutation-" + name)
                target = root / "drivers/metal/openrc_mfx_present_state.h"
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(self.state.replace(before, after), encoding="utf-8")
                result = self.compile_run(STATE_TEST, "state_" + name, root)
                self.assertNotEqual(result.returncode, 0, f"{name} mutation escaped control")

    def test_ticket_cannot_be_claimed_twice(self):
        before = "if (!p_lease->held.compare_exchange_strong(expected, true, std::memory_order_acq_rel)) { return {}; }"
        self.assertEqual(self.shared.count(before), 1)
        root = self.base / "mutation-ticket"
        target = root / "servers/rendering/storage/metalfx_presentation.h"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(self.shared.replace(before, before.replace("if (!", "if (false && !")), encoding="utf-8")
        result = self.compile_run(STATE_TEST, "state_ticket", root)
        self.assertNotEqual(result.returncode, 0, "duplicate lease mutation escaped control")

    def test_retired_slot_cap_uses_actual_branch(self):
        begin = self.compositor.index("\t\tunsigned held = 0;")
        end = self.compositor.index("\n\t\tfor (OpenRCOutputSlot &slot : openrc_slots)", begin)
        branch = self.compositor[begin:end]
        code = CAP_TEST.replace("@CAP@", branch)
        result = self.compile_run(code, "retired_cap")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        changed = code.replace("+ held > 4", "+ held > 8")
        self.assertNotEqual(changed, code)
        result = self.compile_run(changed, "retired_cap_mutation")
        self.assertNotEqual(result.returncode, 0, "unbounded-retirement mutation escaped control")

    def test_stale_descriptor_pruning_uses_actual_loop(self):
        begin = self.compositor.index("\tVector<RID> stale_descriptors;")
        end = self.compositor.index("\n\tRenderingContextDriver::SurfaceID current_id", begin)
        loop = self.compositor[begin:end]
        code = PRUNE_TEST.replace("@PRUNE@", loop)
        result = self.compile_run(code, "descriptor_prune")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        changed = code.replace("!rd->uniform_set_is_valid(entry.value)", "false && !rd->uniform_set_is_valid(entry.value)")
        self.assertNotEqual(changed, code)
        result = self.compile_run(changed, "descriptor_prune_mutation")
        self.assertNotEqual(result.returncode, 0, "descriptor-prune mutation escaped control")

    def test_retirement_request_does_not_wait_for_present_gate(self):
        gen = CHECK.cxx_function(self.bridge, "uint64_t generation(const Handle &p_presenter)")
        retire = CHECK.cxx_function(self.bridge, "void retire_generation(const Handle &p_presenter)")
        quiescence = CHECK.cxx_function(self.bridge, "bool try_retire_complete(const Handle &p_presenter)")
        result = self.compile_run(RETIRE_TEST.replace("@GENERATION@", gen).replace("@RETIRE@", retire).replace("@QUIESCENCE@", quiescence), "retire_nonblocking")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_multiblit_requires_one_shared_source(self):
        start = self.compositor.index("\tstd::shared_ptr<OpenRCMetalPresent::SourceGeneration> incoming_source;")
        end = self.compositor.index("\n\tconst auto &pair", start)
        branch = self.compositor[start:end]
        code = MULTI_BLIT_TEST.replace("@BRANCH@", branch)
        result = self.compile_run(code, "multiblit")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        changed = code.replace("if (any_tagged && !all_tagged)", "if (false && any_tagged && !all_tagged)")
        self.assertNotEqual(changed, code)
        result = self.compile_run(changed, "multiblit_mutation")
        self.assertNotEqual(result.returncode, 0, "secondary token mutation escaped control")

    def test_reused_surface_address_does_not_reuse_old_presenter(self):
        condition = "current_id != openrc_surface_id || current_handle != openrc_presenter"
        self.assertEqual(self.compositor.count(condition), 1)
        code = SURFACE_IDENTITY_TEST.replace("@CONDITION@", condition)
        result = self.compile_run(code, "surface_identity")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        changed = code.replace(condition, "current_id != openrc_surface_id || (false && current_handle != openrc_presenter)")
        result = self.compile_run(changed, "surface_identity_mutation")
        self.assertNotEqual(result.returncode, 0, "reused-address mutation escaped control")

    def test_default_and_explicit_source_transitions_wait_without_blocking(self):
        start = self.compositor.index("\tif (!openrc_source || openrc_source_transition")
        end = self.compositor.index("\n\tauto source_generation = openrc_source;", start)
        branch = self.compositor[start:end]
        code = SOURCE_TRANSITION_TEST.replace("@TRANSITION@", branch)
        result = self.compile_run(code, "source_transition")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        changed = code.replace("openrc_source && !openrc_source->try_cancel_complete()", "false && openrc_source && !openrc_source->try_cancel_complete()")
        self.assertNotEqual(changed, code)
        result = self.compile_run(changed, "source_transition_mutation")
        self.assertNotEqual(result.returncode, 0, "missing source quiescence mutation escaped control")

    def test_stale_completion_does_not_increment_ready_receipts(self):
        submit = CHECK.cxx_function(self.bridge, "bool submit(const Handle &p_presenter, Job p_job)")
        code = SUBMIT_RECEIPT_TEST.replace("@SUBMIT@", submit)
        result = self.compile_run(code, "submit_receipt")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        changed = submit.replace("if (!shared->scheduler.submit(std::move(p_job))) { return false; }",
                                 "bool accepted = shared->scheduler.submit(std::move(p_job));")
        changed = changed.replace("\n\treturn true;\n}", "\n\treturn accepted;\n}")
        self.assertNotEqual(changed, submit)
        result = self.compile_run(SUBMIT_RECEIPT_TEST.replace("@SUBMIT@", changed), "submit_receipt_mutation")
        self.assertNotEqual(result.returncode, 0, "stale receipt mutation escaped control")

    def test_worker_creation_failure_falls_back_cleanly(self):
        start = CHECK.cxx_function(self.bridge, "static bool start_worker(Presenter *p_presenter)")
        code = THREAD_START_TEST.replace("@START@", start)
        result = self.compile_run(code, "worker_start")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        changed = code.replace("present_worker, holder) != 0", "present_worker, holder) == 0")
        self.assertNotEqual(changed, code)
        result = self.compile_run(changed, "worker_start_mutation")
        self.assertNotEqual(result.returncode, 0, "thread factory failure mutation escaped control")

    def test_real_integration_invariants(self):
        self.assertIn("device->newTexture(descriptor.get())", self.compositor)
        self.assertIn("texture_create_from_extension(", self.compositor)
        self.assertIn("MTL::ResourceHazardTrackingModeTracked", self.compositor)
        self.assertIn("refs->images[i] = NS::RetainPtr(native)", self.compositor)
        self.assertIn("p_completed->status() == MTL::CommandBufferStatusCompleted", self.compositor)
        self.assertIn("args->source_ticket = pair.ticket", self.compositor)
        self.assertIn("p_render_targets[i].paired.presenter_generation != current_generation", self.compositor)
        self.assertIn("source_generation->is_cancelled()", self.compositor)
        self.assertIn("screen_prepare_for_external_drawing", self.compositor)
        self.assertIn("OPENRC_METALFX_DISPLAY_LINK_PROBE", self.context)
        self.assertIn("#ifdef DEBUG_ENABLED", self.context)
        self.assertIn("if (!s || !p_update || !p_update.drawable)", self.bridge)
        self.assertIn("[command commit];\n\t\t[drawable present];", self.bridge)
        self.assertNotIn("nextDrawable", self.bridge)
        self.assertIn("real_os_presented", self.device)
        self.assertIn("real_unresolved", self.device)

    def test_existing_screen_blit_color_conversion_is_preserved(self):
        original = CHECK.cxx_function(self.original_compositor, "void RendererCompositorRD::blit_render_targets_to_screen(")
        helper = CHECK.cxx_function(self.compositor, "void RendererCompositorRD::_draw_screen_blits(")
        before = original[original.index("\tconst RD::ColorSpace color_space"):original.rindex("\n\tRD::get_singleton()->draw_list_end();")].strip()
        after = helper[helper.index("\tconst RD::ColorSpace color_space"):helper.rindex("\n}")].strip()
        after = after.replace("i == 0 && p_override_texture.is_valid() ? p_override_texture : texture_storage->render_target_get_rd_texture(p_render_targets[i].render_target)",
                              "texture_storage->render_target_get_rd_texture(p_render_targets[i].render_target)")
        self.assertEqual(before, after)
        self.assertIn("if (_openrc_blit(p_screen, p_render_targets, p_amount)) { return; }", self.compositor)
        self.assertIn("screen_prepare_for_drawing(p_screen)", self.compositor)


if __name__ == "__main__":
    unittest.main()
