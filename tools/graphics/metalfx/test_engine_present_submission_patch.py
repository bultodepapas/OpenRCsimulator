"""Source-bound portable controls for 0017; no Metal or Godot is run."""
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

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[2]
def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path)
    result=importlib.util.module_from_spec(spec)
    sys.modules[name]=result
    spec.loader.exec_module(result)
    return result
ENGINE=module('submission_engine',HERE/'engine.py')
CHECK=module('submission_checks',HERE/'test_engine_patch.py')
BASE=module('submission_pacing',HERE/'test_engine_present_pacing_patch.py')
NAMES=BASE.NAMES+('0017-metal-present-submission-lifetime.patch',)
PATCHES=tuple(HERE/'patches'/name for name in NAMES)
PATCH_HASH='db0f4aad4eced890cd5a072be1b69aa5ca6331d41c1a700b12a8ed967357b746'
HASHES=BASE.HASHES+(BASE.PATCH_HASH,)

CONTROL=r'''
#include <drivers/metal/openrc_mfx_present_bridge.h>
#include <atomic>
#include <memory>
#include <mutex>
#define CHECK(x) do { if (!(x)) return __LINE__; } while (0)
namespace OpenRCMetalPresent {
struct Shared {
    std::mutex mutex;
    Scheduler scheduler;
    std::atomic<uint64_t> requested_generation{1};
    std::atomic<uint64_t> ignored_unrequested_commands{0};
    std::atomic<uint64_t> aborted_completion_not_enqueued{0}, aborted_completion_other{0};
    Snapshot stats;
    std::shared_ptr<SubmissionReceipt> in_flight_submission;
    double previous_display_target=0.0, display_period=0.0;
};
@RETIRE@
@SYNCHRONIZE@
@HANDLER@
@ABORTED@
@ABANDON@
@COMPLETION@
}
using namespace OpenRCMetalPresent;
static void *ptr(unsigned n) { return reinterpret_cast<void *>(uintptr_t(n)); }
static std::shared_ptr<SubmissionReceipt> token() { return std::make_shared<SubmissionReceipt>(std::make_shared<int>(1)); }
static bool begin(const std::shared_ptr<SubmissionReceipt> &r) { return r->claim() && r->admit() && r->begin_commit(); }
static Choice choice(uint64_t gen, double reserved) {
    Choice c; c.kind=Kind::REAL; c.generation=gen; c.frame=1; c.texture=ptr(1);
    c.fallback_texture=ptr(1); c.output_lease=std::make_shared<int>(7); c.source_reserved_at=reserved;
    return c;
}
int main() {
    auto s=std::make_shared<Shared>(); std::weak_ptr<Shared> weak=s;
    auto active=token(); CHECK(begin(active)); s->in_flight_submission=active;
    auto aborted=token(); CHECK(!handler_ready(weak,aborted,false)); CHECK(!aborted->claim());
    CHECK(!handler_ready(weak,aborted,false)); CHECK(s->ignored_unrequested_commands.load()==1);
    record_aborted_completion(weak,aborted,true); record_aborted_completion(weak,aborted,true);
    CHECK(s->aborted_completion_not_enqueued.load()==1 && s->aborted_completion_other.load()==0);
    CHECK(s->in_flight_submission==active && s->stats.gpu_failed==0);
    {
        auto during=token(); CHECK(during->claim());
        std::lock_guard<std::mutex> locked(s->mutex);
        CHECK(!handler_ready(weak,during,false)); CHECK(!during->admit());
    }
    {
        auto after_admission=token(); CHECK(after_admission->claim() && after_admission->admit());
        CHECK(!handler_ready(weak,after_admission,false)); CHECK(!after_admission->begin_commit());
    }
    {
        auto owner=std::make_shared<Shared>(); std::weak_ptr<Shared> owner_weak=owner;
        auto early=token(); Job j; j.generation=1; j.frame=1; j.reserved_at=9.99; j.fallback=ptr(11); j.output_lease=std::make_shared<int>(1);
        Retired deferred; CHECK(owner->scheduler.submit(j,10.0,deferred));
        auto picked=owner->scheduler.choose(10.0,10.01,10.04,0.0167,true,deferred);
        CHECK(picked.kind==Kind::REAL);
        {
            std::lock_guard<std::mutex> locked(owner->mutex);
            CHECK(early->claim()); CHECK(owner->scheduler.commit(picked,10.001,deferred));
            CHECK(!handler_ready(owner_weak,early,false)); CHECK(!early->admit());
            abandon_admitted_locked(*owner,picked,1,10.002,deferred);
        }
        deferred.clear(); CHECK(owner->scheduler.current_generation()==2 && owner->stats.gpu_failed==0);
    }
    auto c=choice(1,10.0); Retired retired;
    CHECK(handler_ready(weak,active,false));
    completion_locked(*s,active,c,1,10.02,false,false,0,0,retired);
    completion_locked(*s,active,c,1,10.03,false,false,0,0,retired);
    CHECK(s->stats.nonterminal_completion_commands==1 && s->in_flight_submission==active && s->stats.gpu_failed==0);
    CHECK(active->take_terminal(true));
    completion_locked(*s,active,c,1,10.04,true,true,4,0,retired);
    CHECK(!s->in_flight_submission && !active->take_terminal(true));
    CHECK(active->claim_present() && handler_ready(weak,active,true));
    CHECK(active->take_presented() && !active->take_presented());
    CHECK(active->take_scheduled() && !active->take_scheduled());
    {
        auto failure=token(); CHECK(begin(failure)); s->in_flight_submission=failure;
        CHECK(failure->take_terminal(false)); CHECK(!failure->claim_present());
        completion_locked(*s,failure,c,1,10.05,true,false,5,17,retired);
        CHECK(s->stats.gpu_failed==1 && s->stats.last_gpu_status==5 && s->stats.last_gpu_error_code==17);
        CHECK(s->stats.last_gpu_failure_generation==1 && s->scheduler.current_generation()==2 && !s->in_flight_submission);
        retired.clear();
    }
    {
        auto old=token(), newer=token(); CHECK(begin(old) && begin(newer));
        s->in_flight_submission=newer; CHECK(old->take_terminal(false));
        auto old_choice=choice(1,10.0);
        completion_locked(*s,old,old_choice,1,10.06,true,false,5,21,retired);
        CHECK(s->stats.gpu_failed==2 && s->stats.last_gpu_failure_generation==1 && s->stats.last_gpu_error_code==21);
        CHECK(s->in_flight_submission==newer && s->scheduler.current_generation()==2);
    }
    {
        auto token_after_present=token(); CHECK(begin(token_after_present));
        CHECK(token_after_present->claim_present()); CHECK(token_after_present->take_terminal(false));
        CHECK(token_after_present->present_was_requested() && !token_after_present->claim_present());
    }
    {
        SubmissionRetentions registry;
        std::shared_ptr<SubmissionReceipt> holders[5]; std::weak_ptr<void> output;
        for (unsigned i=0;i<5;i++) {
            auto lease=std::make_shared<int>(int(i)); if(i==0) { output=lease; }
            holders[i]=std::make_shared<SubmissionReceipt>(lease);
            CHECK(registry.retain(holders[i])==(i<4));
        }
        CHECK(registry.count()==4 && registry.rejection_count()==1);
        auto terminal=holders[0]; holders[0].reset(); CHECK(!output.expired());
        CHECK(begin(terminal) && terminal->take_terminal(true)); registry.release(terminal); terminal.reset();
        CHECK(output.expired() && registry.count()==3 && registry.retain(holders[4]));
        for (unsigned i=1;i<5;i++) { registry.release(holders[i]); holders[i].reset(); }
        CHECK(registry.count()==0);
    }
    {
        SubmissionRetentions registry;
        auto lease=std::make_shared<int>(9); std::weak_ptr<void> weak_lease=lease;
        auto os_receipt=std::make_shared<SubmissionReceipt>(lease); lease.reset();
        CHECK(registry.retain(os_receipt)); CHECK(begin(os_receipt));
        CHECK(!os_receipt->take_completed_output() && !weak_lease.expired());
        CHECK(os_receipt->take_terminal(true)); auto finished_output=os_receipt->take_completed_output();
        registry.release(os_receipt); CHECK(!weak_lease.expired()); finished_output.reset();
        CHECK(weak_lease.expired()); CHECK(os_receipt->claim_present() && os_receipt->take_presented());
    }
    {
        SubmissionRetentions registry;
        auto lease=std::make_shared<int>(11); std::weak_ptr<void> weak_lease=lease;
        auto outstanding=std::make_shared<SubmissionReceipt>(lease); lease.reset();
        CHECK(registry.retain(outstanding)); CHECK(begin(outstanding));
        auto old_owner=std::make_shared<Shared>(); std::weak_ptr<Shared> dead_owner=old_owner;
        old_owner->in_flight_submission=outstanding; old_owner.reset(); CHECK(dead_owner.expired() && !weak_lease.expired());
        CHECK(outstanding->take_terminal(true)); registry.release(outstanding); outstanding.reset(); CHECK(weak_lease.expired());
    }
    return 0;
}
'''

class SubmissionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not CHECK.ARCHIVE.is_file() or ENGINE.sha256(CHECK.ARCHIVE)!=CHECK.ARCHIVE_SHA256:
            raise RuntimeError('Pinned Godot archive unavailable')
        if tuple(ENGINE.sha256(p) for p in PATCHES[:16])!=HASHES:
            raise RuntimeError('Frozen 1–16 prerequisites differ')
        if ENGINE.sha256(PATCHES[16])!=PATCH_HASH:
            raise RuntimeError('Frozen 0017 candidate differs')
        parent=ROOT/'tmp/metalfx-submission-port'; parent.mkdir(parents=True,exist_ok=True)
        cls.tmp=tempfile.TemporaryDirectory(prefix='controls-',dir=parent); cls.addClassCleanup(cls.tmp.cleanup)
        cls.base=Path(cls.tmp.name)
        with zipfile.ZipFile(CHECK.ARCHIVE) as archive:
            members=set(archive.namelist())
            for path in ENGINE.patch_paths(PATCHES):
                member=f'{ENGINE.SOURCE_PREFIX}/{path}'
                if member in members:
                    target=cls.base/path; target.parent.mkdir(parents=True,exist_ok=True); target.write_bytes(archive.read(member))
        ENGINE.git(cls.base,'init','--quiet')
        for patch in PATCHES:
            ENGINE.git(cls.base,'apply','--check','--whitespace=error',str(patch.resolve()))
            ENGINE.git(cls.base,'apply','--whitespace=error',str(patch.resolve()))
        cls.state=(cls.base/'drivers/metal/openrc_mfx_present_state.h').read_text(encoding='utf-8')
        cls.header=(cls.base/'drivers/metal/openrc_mfx_present_bridge.h').read_text(encoding='utf-8')
        cls.bridge=(cls.base/'drivers/metal/openrc_mfx_present_bridge.mm').read_text(encoding='utf-8')
        cls.device=(cls.base/'servers/rendering/rendering_device.cpp').read_text(encoding='utf-8')
        signatures={'@RETIRE@':'static void retire_stats(', '@SYNCHRONIZE@':'static void synchronize_generation(',
                    '@HANDLER@':'static bool handler_ready(', '@ABORTED@':'static void record_aborted_completion(', '@ABANDON@':'static void abandon_admitted_locked(',
                    '@COMPLETION@':'static void completion_locked('}
        cls.control=CONTROL
        for marker,signature in signatures.items():
            cls.control=cls.control.replace(marker,CHECK.cxx_function(cls.bridge,signature))

    def compile_run(self,code,name,include=None):
        compiler=os.environ.get('CXX') or shutil.which('g++') or shutil.which('clang++')
        self.assertTrue(compiler)
        source=self.base/(name+'.cpp'); exe=self.base/(name+('.exe' if os.name=='nt' else ''))
        source.write_text(code,encoding='utf-8')
        cmd=[compiler,'-std=c++17','-O2','-Wall','-Wextra','-Werror','-pthread']
        if include: cmd+=['-I',str(include)]
        cmd+=['-I',str(self.base),str(source),'-o',str(exe)]
        built=subprocess.run(cmd,capture_output=True,text=True,timeout=90)
        self.assertEqual(built.returncode,0,built.stdout+built.stderr)
        return subprocess.run([str(exe)],capture_output=True,text=True,timeout=30)

    def test_actual_receipt_completion_and_bounded_retention(self):
        result=self.compile_run(self.control,'receipt')
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_mutations_are_detected(self):
        mutations={
            'early_callback':('if (phase.compare_exchange_weak(observed, Phase::ABORTED, std::memory_order_acq_rel)) { return false; }','if (phase.compare_exchange_weak(observed, Phase::ABORTED, std::memory_order_acq_rel)) { phase.store(Phase::PREPARED); return false; }'),
            'duplicate_terminal':('if (observed & COMPLETION_OBSERVED) { return false; }','if (false && (observed & COMPLETION_OBSERVED)) { return false; }'),
            'failure_present':('if (observed & (PRESENT_REQUESTED | TERMINAL_FAILURE)) { return false; }','if (observed & PRESENT_REQUESTED) { return false; }'),
            'retention_bound':('std::array<std::shared_ptr<SubmissionReceipt>, 4> entries;', 'std::array<std::shared_ptr<SubmissionReceipt>, 5> entries;'),
            'terminal_detach':('return std::move(retained_output);', 'return {};'),
        }
        for name,(old,new) in mutations.items():
            with self.subTest(name=name):
                self.assertEqual(self.state.count(old),1)
                root=self.base/('mutation-'+name); target=root/'drivers/metal/openrc_mfx_present_state.h'
                target.parent.mkdir(parents=True,exist_ok=True); target.write_text(self.state.replace(old,new),encoding='utf-8')
                (root/'drivers/metal/openrc_mfx_present_bridge.h').write_text(self.header,encoding='utf-8')
                result=self.compile_run(self.control,'receipt_'+name,root)
                self.assertNotEqual(result.returncode,0,f'{name} mutation escaped control')

    def test_old_completion_cannot_clear_new_command_mutation(self):
        before='const bool active_command = p_state.in_flight_submission == p_receipt;'
        self.assertEqual(self.control.count(before),1)
        changed=self.control.replace(before,'const bool active_command = true;')
        result=self.compile_run(changed,'wrong_inflight_mutation')
        self.assertNotEqual(result.returncode,0,'retired command cleared newer inflight')

    def test_actual_native_status_classification(self):
        delegate=CHECK.cxx_function(self.bridge,'- (void)metalDisplayLink:')
        completed=delegate[delegate.index('[command addCompletedHandler:'):delegate.index('// Handler registration')]
        terminal=next(line.strip() for line in completed.splitlines() if line.strip().startswith('const bool terminal ='))
        success=next(line.strip() for line in completed.splitlines() if line.strip().startswith('const bool succeeded ='))
        code=r'''
#define nil nullptr
#define CHECK(x) do { if (!(x)) return __LINE__; } while (0)
enum { MTLCommandBufferStatusNotEnqueued=0, MTLCommandBufferStatusCompleted=4, MTLCommandBufferStatusError=5 };
struct NativeError {};
static bool classify(int status, NativeError *error, bool expected_terminal, bool expected_success) {
@TERMINAL@
@SUCCESS@
    return terminal == expected_terminal && succeeded == expected_success;
}
int main() {
    NativeError error;
    CHECK(classify(0,nullptr,false,false));
    CHECK(classify(4,nullptr,true,true));
    CHECK(classify(4,&error,true,false));
    CHECK(classify(5,&error,true,false));
    return 0;
}
'''
        code=code.replace('@TERMINAL@',terminal).replace('@SUCCESS@',success)
        result=self.compile_run(code,'native_status')
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        changed=code.replace('status == MTLCommandBufferStatusCompleted && error == nil','status == MTLCommandBufferStatusCompleted && ((void)error, true)')
        self.assertNotEqual(changed,code)
        result=self.compile_run(changed,'native_status_mutation')
        self.assertNotEqual(result.returncode,0,'Completed-with-error mutation escaped control')

    def test_native_handler_and_lifetime_wiring(self):
        delegate=CHECK.cxx_function(self.bridge,'- (void)metalDisplayLink:')
        self.assertLess(delegate.index('handler_ready(weak, receipt, false)'),delegate.index('receipt->claim()'))
        self.assertLess(delegate.index('receipt->claim()'),delegate.index('scheduler.commit(choice, admitted_at, retired_after_choice)'))
        self.assertLess(delegate.index('scheduler.commit(choice, admitted_at, retired_after_choice)'),delegate.index('receipt->admit()'))
        self.assertLess(delegate.index('receipt->begin_commit()'),delegate.index('[command commit]'))
        self.assertLess(delegate.index('retention_guard.retain_until_terminal()'),delegate.index('[command commit]'))
        self.assertLess(delegate.index('[command commit]'),delegate.index('receipt->claim_present()'))
        self.assertLess(delegate.index('receipt->claim_present()'),delegate.index('[drawable present]'))
        completed=delegate[delegate.index('[command addCompletedHandler:'):delegate.index('// Handler registration')]
        self.assertLess(completed.index('take_terminal(succeeded)'),completed.index('submission_retentions().release(receipt)'))
        self.assertLess(completed.index('submission_retentions().release(receipt)'),completed.index('auto shared = weak.lock();',completed.index('take_terminal(succeeded)')))
        self.assertIn('status == MTLCommandBufferStatusCompleted && error == nil',completed)
        self.assertIn('MTLCommandBufferStatusNotEnqueued',completed)
        self.assertIn('record_aborted_completion(weak, receipt',completed)
        self.assertIn('aborted_completion_not_enqueued',self.bridge)
        self.assertLess(completed.index('take_completed_output()'),completed.index('submission_retentions().release(receipt)'))
        self.assertIn('completion_choice.output_lease.reset()',delegate)
        self.assertIn('retired_rollback',delegate)
        for key in ('last_gpu_failure_generation','ignored_unrequested_commands','aborted_completion_not_enqueued',
                    'aborted_completion_other','nonterminal_completion_commands','submission_retained','submission_retention_rejected'):
            self.assertIn(key,self.device)

if __name__=='__main__':
    unittest.main()
