"""Source-bound portable controls for 0016; no Metal, display, or Godot execution."""
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
ENGINE=module('pacing_engine', HERE/'engine.py')
CHECK=module('pacing_checks', HERE/'test_engine_patch.py')
BASE=module('pacing_real', HERE/'test_engine_real_completion_patch.py')
NAMES=BASE.NAMES+('0014-metal-present-callback-lock.patch','0015-metal-present-decision-observation.patch','0016-metal-present-pacing.patch')
PATCHES=tuple(HERE/'patches'/name for name in NAMES)
PATCH_HASH='6592562afd4208d211e924cd1330b6fb58a05d88b0161f43a51d133d6863efbe'
HASHES=BASE.HASHES+(BASE.PATCH_HASH,
    'a15caae49bb4d543043e009fd63a63f88c433e8d8ccbbc139ade6acf6a991468',
    '5e1b25dc8e3296423dae24489cd8b936a6cfbaf32a0fc6b006c6bec0b1971b9d')

STATE = r'''
#include <drivers/metal/openrc_mfx_present_state.h>
#include <cmath>
#include <memory>
#include <mutex>
#include <thread>
#define CHECK(x) do { if (!(x)) return __LINE__; } while (0)
using namespace OpenRCMetalPresent;
struct ReleaseProbe {
    std::mutex &gate; bool &released; bool &under_lock;
    ReleaseProbe(std::mutex &m, bool &r, bool &l) : gate(m), released(r), under_lock(l) {}
    ~ReleaseProbe() { std::thread t([&] { if (gate.try_lock()) { gate.unlock(); } else { under_lock=true; } }); t.join(); released=true; }
};
static void *ptr(uint64_t n) { return reinterpret_cast<void *>(uintptr_t(n)); }
static Job job(Scheduler &s, uint64_t frame, uint64_t previous, double reserved, double interval, uint64_t epoch=7) {
    Job j; j.generation=s.current_generation(); j.frame=frame; j.epoch=epoch; j.serial=frame;
    j.reserved_at=reserved; j.generated_deadline=reserved+interval; j.real_deadline=reserved+interval*2.0; j.real_interval=interval;
    j.fallback=ptr(frame*10+1); j.generated=ptr(frame*10+2); j.paired_real=ptr(frame*10+3);
    j.output_lease=std::make_shared<int>(42); j.proof=std::make_shared<Proof>(previous,frame,epoch,frame);
    j.proof->warm_count.store(5); j.proof->encode_result.store(1); j.proof->sdk_completion.store(1);
    return j;
}
static bool put(Scheduler &s, Job j, double now) { Retired r; return s.submit(j,now,r); }
static Choice pick(Scheduler &s,double now,double deadline,double target,double period,bool drawable=true) { Retired r; return s.choose(now,deadline,target,period,drawable,r); }
static bool commit(Scheduler &s,const Choice &c,double now) { Retired r; return s.commit(c,now,r); }
static bool initial(Scheduler &s,double now,double target,double period) {
    Job j=job(s,1,0,now-0.005,period*2); j.generated=nullptr; j.paired_real=nullptr; j.proof.reset();
    if(!put(s,j,now)) { return false; }
    auto c=pick(s,now,now+0.01,target,period); return c.kind==Kind::REAL && commit(s,c,now+0.001);
}
int main() {
    constexpr double P=0.016666625, R=0.033584667, B=479646.0;
    Scheduler s; CHECK(initial(s,B+0.05,B+0.105649625,P));
    auto second=job(s,2,1,B+0.081439917,R); CHECK(put(s,second,B+0.089127583));
    auto g=pick(s,B+0.089127583,B+0.120,B+0.138982875,P);
    CHECK(g.kind==Kind::GENERATED && g.texture==ptr(22)); CHECK(commit(s,g,B+0.0893)); CHECK(!s.cadence_is_primed());
    auto real=pick(s,B+0.1058,B+0.135,B+0.1556495,P); CHECK(real.kind==Kind::REAL && real.frame==2 && real.texture==ptr(23));
    CHECK(commit(s,real,B+0.106)); CHECK(s.cadence_is_primed());
    auto third=job(s,3,2,B+0.1148,R); CHECK(put(s,third,B+0.1224));
    g=pick(s,B+0.1224,B+0.150,B+0.172316125,P); CHECK(g.kind==Kind::GENERATED && commit(s,g,B+0.1225));
    real=pick(s,B+0.1391,B+0.170,B+0.18898275,P); CHECK(real.kind==Kind::REAL && real.frame==3 && commit(s,real,B+0.1392)); CHECK(s.cadence_is_primed());
    auto fourth=job(s,4,3,B+0.148,R); CHECK(put(s,fourth,B+0.156));
    auto missed=pick(s,B+0.172,B+0.190,B+0.222316,P); CHECK(missed.kind==Kind::REAL && missed.frame==4); CHECK(commit(s,missed,B+0.1721)); CHECK(!s.cadence_is_primed());
    {
        Scheduler x; CHECK(initial(x,10.05,10.105,P));
        auto bad=job(x,2,1,10.08,1.9*P); CHECK(put(x,bad,10.089));
        auto c=pick(x,10.089,10.12,10.105+2*P,P); CHECK(c.kind==Kind::REAL);
    }
    {
        Scheduler x; CHECK(initial(x,20.05,20.105,P));
        auto bad=job(x,2,1,20.08,R); CHECK(put(x,bad,20.089));
        auto c=pick(x,20.089,20.12,20.239,P); CHECK(c.kind==Kind::REAL && c.frame==2);
        CHECK(commit(x,c,20.090));
    }
    {
        Scheduler x; CHECK(initial(x,30.05,30.105,P));
        auto pending=job(x,2,1,30.08,R); CHECK(put(x,pending,30.089));
        auto c=pick(x,30.089,30.12,30.105+2*P,P); CHECK(c.kind==Kind::GENERATED);
        auto newer=job(x,3,2,30.090,R); CHECK(put(x,newer,30.091));
        CHECK(!commit(x,c,30.092)); CHECK(!x.cadence_is_primed());
        c=pick(x,30.093,30.12,30.105+2*P,P); CHECK(c.kind==Kind::REAL && c.frame==3);
    }
    {
        Scheduler x; CHECK(initial(x,40.05,40.105,P));
        auto j=job(x,2,1,40.08,R); CHECK(put(x,j,40.089));
        auto c=pick(x,40.089,40.12,40.105+2*P,P); CHECK(c.kind==Kind::GENERATED);
        CHECK(!commit(x,c,40.114));
        c=pick(x,40.115,40.14,40.105+3*P,P); CHECK(c.kind==Kind::REAL);
    }
    {
        Scheduler x; CHECK(initial(x,50.05,50.105,P));
        auto j=job(x,2,1,50.08,R); CHECK(put(x,j,50.089));
        auto c=pick(x,50.089,50.12,50.105+2*P,P); CHECK(c.kind==Kind::GENERATED && commit(x,c,50.09));
        c=pick(x,50.149,50.17,50.105+3*P,P); CHECK(c.kind==Kind::REAL && c.frame==2 && c.texture==ptr(21));
        CHECK(x.blocked_source_epoch()==7 && !x.cadence_is_primed()); CHECK(commit(x,c,50.15));
    }
    {
        Scheduler x; constexpr double Q=1.0/120.0, T=0.0167;
        CHECK(initial(x,60.05,60.10,Q)); auto j=job(x,2,1,60.061,T); CHECK(put(x,j,60.066));
        auto c=pick(x,60.066,60.075,60.10+2*Q,Q); CHECK(c.kind==Kind::GENERATED); CHECK(commit(x,c,60.067));
        c=pick(x,60.074,60.08,60.10+3*Q,Q); CHECK(c.kind==Kind::REAL && commit(x,c,60.075));
    }
    {
        Scheduler x; CHECK(initial(x,70.05,70.105,P));
        auto j=job(x,2,1,70.08,R); j.generated=nullptr; j.paired_real=nullptr; j.proof.reset(); CHECK(put(x,j,70.089));
        auto real_old=pick(x,70.089,70.12,70.105+2*P,P); CHECK(real_old.kind==Kind::REAL);
        auto fresh=job(x,3,2,70.09,R); CHECK(put(x,fresh,70.091));
        CHECK(commit(x,real_old,70.092));
        auto next=pick(x,70.095,70.12,70.105+3*P,P); CHECK(next.kind==Kind::GENERATED && next.frame==3);
    }
    {
        Scheduler x; CHECK(initial(x,80.05,80.105,P));
        auto j=job(x,2,1,80.08,R); auto source=j.source_generation=std::make_shared<SourceGeneration>(); CHECK(put(x,j,80.089));
        auto c=pick(x,80.089,80.12,80.105+2*P,P); CHECK(c.kind==Kind::GENERATED && commit(x,c,80.09));
        source->request_cancel(); c=pick(x,80.105,80.12,80.105+3*P,P);
        CHECK(c.kind==Kind::NONE && !x.cadence_is_primed() && x.blocked_source_epoch()==7);
    }
    {
        Scheduler x; CHECK(initial(x,90.05,90.105,P));
        auto j=job(x,2,1,90.08,P); CHECK(put(x,j,90.089));
        auto c=pick(x,90.089,90.12,90.105+2*P,P); CHECK(c.kind==Kind::REAL);
    }
    {
        Scheduler x; CHECK(initial(x,100.05,100.105,P));
        auto j=job(x,2,1,100.08,R); CHECK(put(x,j,100.089));
        auto c=pick(x,100.089,100.12,100.105+2*P,P); CHECK(c.kind==Kind::GENERATED);
        Retired r; x.reset(r); r.clear(); CHECK(!x.recover_failed(c,100.09,r)); CHECK(!x.cadence_is_primed());
        CHECK(!put(x,j,100.09));
    }
    {
        std::mutex gate; bool released=false, under_lock=false;
        Scheduler x; CHECK(initial(x,110.05,110.105,P));
        auto j=job(x,2,1,110.08,R); j.output_lease=std::make_shared<ReleaseProbe>(gate,released,under_lock);
        CHECK(put(x,j,110.089)); j.output_lease.reset();
        auto c=pick(x,110.089,110.12,110.105+2*P,P); CHECK(c.kind==Kind::GENERATED && commit(x,c,110.09)); c=Choice();
        Retired retired;
        { std::lock_guard<std::mutex> lock(gate); x.expire(110.30,retired); CHECK(!released); }
        retired.clear(); CHECK(released && !under_lock && !x.cadence_is_primed());
    }
    {
        Scheduler x; CHECK(initial(x,120.05,120.105,P));
        auto j=job(x,2,1,120.08,R); CHECK(put(x,j,120.089));
        auto c=pick(x,120.089,120.12,120.105+2*P,P); CHECK(c.kind==Kind::GENERATED && commit(x,c,120.09));
        auto next=job(x,3,2,120.09,R); CHECK(put(x,next,120.091));
        c=pick(x,120.105,120.12,120.105+4*P,P);
        CHECK(c.kind==Kind::REAL && c.frame==3 && x.blocked_source_epoch()==7 && !x.cadence_is_primed());
    }
    {
        Scheduler x; CHECK(initial(x,130.05,130.20566675,P));
        auto j=job(x,2,1,130.081,R); CHECK(put(x,j,130.089));
        auto c=pick(x,130.089,130.12,130.20566675+2*P,P);
        CHECK(c.kind==Kind::REAL && c.frame==2);
    }
    {
        Scheduler x; CHECK(initial(x,140.05,140.105,P));
        auto j=job(x,3,2,140.08,R); CHECK(put(x,j,140.089));
        auto c=pick(x,140.089,140.12,140.105+2*P,P); CHECK(c.kind==Kind::REAL);
    }
    {
        Scheduler x; CHECK(initial(x,150.05,150.105,P));
        auto j=job(x,2,1,150.08,R); j.proof->sdk_completion.store(-1); CHECK(put(x,j,150.089));
        auto c=pick(x,150.089,150.12,150.105+2*P,P); CHECK(c.kind==Kind::REAL);
    }
    {
        Scheduler x; CHECK(initial(x,160.05,160.105,P));
        auto future=job(x,2,1,160.10,R); CHECK(!put(x,future,160.09));
        auto c=pick(x,160.09,160.12,160.105+2*P,P); CHECK(c.kind==Kind::NONE);
    }
    {
        Scheduler x; CHECK(initial(x,170.05,170.105,P));
        auto newer=job(x,2,1,170.090,R); CHECK(put(x,newer,170.091));
        Retired r; x.expire(170.089,r); r.clear();
        auto c=pick(x,170.089,170.12,170.105+2*P,P); CHECK(c.kind==Kind::NONE);
        c=pick(x,170.092,170.12,170.105+2*P,P); CHECK(c.kind==Kind::GENERATED && c.frame==2);
    }
    {
        Scheduler x; CHECK(initial(x,180.05,180.105,P));
        auto older=job(x,2,1,180.080,R); CHECK(put(x,older,180.089));
        auto newer=job(x,3,2,180.090,R); CHECK(put(x,newer,180.091));
        auto c=pick(x,180.089,180.12,180.105+2*P,P); CHECK(c.kind==Kind::GENERATED && c.frame==2);
        c=pick(x,180.092,180.12,180.105+2*P,P); CHECK(c.kind==Kind::REAL && c.frame==3);
    }
    {
        Scheduler x; CHECK(initial(x,190.05,190.105,P));
        auto newer=job(x,4,3,190.090,R); CHECK(put(x,newer,190.091));
        auto older=job(x,3,2,190.080,R); CHECK(put(x,older,190.089));
        auto c=pick(x,190.092,190.12,190.105+2*P,P); CHECK(c.kind==Kind::REAL && c.frame==4);
    }
    {
        Scheduler x; CHECK(initial(x,200.05,200.105,P));
        auto j=job(x,2,1,200.090,R); CHECK(put(x,j,200.091));
        auto g=pick(x,200.092,200.12,200.105+2*P,P); CHECK(g.kind==Kind::GENERATED && commit(x,g,200.093));
        auto stale=pick(x,200.089,200.12,200.105+3*P,P); CHECK(stale.kind==Kind::NONE);
        auto real=pick(x,200.105,200.13,200.105+3*P,P); CHECK(real.kind==Kind::REAL && real.texture==ptr(23) && x.blocked_source_epoch()==0);
    }
    return 0;
}
'''


WORKER = r"""
struct Shared { std::mutex mutex; bool stopping=false, valid=true; Scheduler scheduler; };
static double fake_clock=0;
static double CACurrentMediaTime() { return fake_clock; }
int main() {
    constexpr double P=0.016666625, R=0.033584667;
    auto shared=std::make_shared<Shared>(); Scheduler &x=shared->scheduler;
    CHECK(initial(x,200.05,200.105,P));
    auto j=job(x,2,1,200.08,R); std::weak_ptr<void> held=j.output_lease;
    CHECK(put(x,j,200.089)); j.output_lease.reset();
    auto c=pick(x,200.089,200.12,200.105+2*P,P); CHECK(c.kind==Kind::GENERATED && commit(x,c,200.09));
    c=Choice(); CHECK(!held.expired()); fake_clock=200.30;
    do {
@MAINTENANCE@
    } while(false);
    CHECK(held.expired()); CHECK(x.blocked_source_epoch()==7 && !x.cadence_is_primed());
    return 0;
}
"""

class PresentPacingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not CHECK.ARCHIVE.is_file() or ENGINE.sha256(CHECK.ARCHIVE)!=CHECK.ARCHIVE_SHA256:
            raise RuntimeError('Pinned Godot archive unavailable')
        if tuple(ENGINE.sha256(p) for p in PATCHES[:15])!=HASHES:
            raise RuntimeError('Frozen 1–15 prerequisites differ')
        if ENGINE.sha256(PATCHES[15])!=PATCH_HASH:
            raise RuntimeError('Frozen 0016 candidate differs')
        parent=ROOT/'tmp/metalfx-pacing-port'; parent.mkdir(parents=True,exist_ok=True)
        cls.tmp=tempfile.TemporaryDirectory(prefix='controls-',dir=parent); cls.addClassCleanup(cls.tmp.cleanup)
        cls.base=Path(cls.tmp.name)
        with zipfile.ZipFile(CHECK.ARCHIVE) as archive:
            members=set(archive.namelist())
            for path in ENGINE.patch_paths(PATCHES):
                member=f'{ENGINE.SOURCE_PREFIX}/{path}'
                if member in members:
                    target=cls.base/path; target.parent.mkdir(parents=True,exist_ok=True); target.write_bytes(archive.read(member))
        # Isolate Git from any parent repository so no patch can be skipped.
        ENGINE.git(cls.base, 'init', '--quiet')
        for patch in PATCHES:
            ENGINE.git(cls.base,'apply','--check','--whitespace=error',str(patch.resolve()))
            ENGINE.git(cls.base,'apply','--whitespace=error',str(patch.resolve()))
        cls.state=(cls.base/'drivers/metal/openrc_mfx_present_state.h').read_text(encoding='utf-8')
        cls.bridge=(cls.base/'drivers/metal/openrc_mfx_present_bridge.mm').read_text(encoding='utf-8')
        cls.device=(cls.base/'servers/rendering/rendering_device.cpp').read_text(encoding='utf-8')
        cls.header=(cls.base/'drivers/metal/openrc_mfx_present_bridge.h').read_text(encoding='utf-8')

    def compile_run(self,code,name,include=None):
        compiler=os.environ.get('CXX') or shutil.which('g++') or shutil.which('clang++')
        self.assertTrue(compiler)
        source=self.base/(name+'.cpp'); executable=self.base/(name+('.exe' if os.name=='nt' else ''))
        source.write_text(code,encoding='utf-8')
        cmd=[compiler,'-std=c++17','-O2','-Wall','-Wextra','-Werror','-pthread']
        if include: cmd+=['-I',str(include)]
        cmd+=['-I',str(self.base),str(source),'-o',str(executable)]
        built=subprocess.run(cmd,capture_output=True,text=True,timeout=90)
        self.assertEqual(built.returncode,0,built.stdout+built.stderr)
        return subprocess.run([str(executable)],capture_output=True,text=True,timeout=30)

    def test_actual_scheduler_native_trace_fallback_lifecycle_and_release(self):
        result=self.compile_run(STATE,'pacing')
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_scheduler_mutations_are_detected(self):
        changes={
            'repeated_prime':('const bool initial_gap = !primed && gap >=', 'const bool initial_gap = gap >='),
            'overspeed':('p_job.real_interval < 2.0 * p_period', 'p_job.real_interval < 1.8 * p_period'),
            'commit_expiry':('p_now > job.generated_deadline', '(false && p_now > job.generated_deadline)'),
            'target_as_deadline':('p_now <= job.generated_deadline', 'p_target <= job.generated_deadline'),
            'lookahead':('p_target - p_now <= MAX_TARGET_LOOKAHEAD', 'p_target - p_now <= 1.0'),
            'predecessor':('job.proof->previous_frame == last_real_scheduled', 'true'),
            'sdk':('decision_completion == 1', 'true'),
            'late_endpoint':('gap > reservation_period * 1.25 || !pair_target_bounded(real', '(false && gap > reservation_period * 1.25) || !pair_target_bounded(real'),
            'future_reservation':('p_now >= p_job.reserved_at', 'true'),
            'stale_clock':('if (!cancelled && std::isfinite(job.reserved_at) && p_now < job.reserved_at) { continue; }', 'if (false && !cancelled && std::isfinite(job.reserved_at) && p_now < job.reserved_at) { continue; }'),
            'stale_reserved':('if (p_now < real.reserved_at) { return {}; }', 'if (false && p_now < real.reserved_at) { return {}; }'),
            'newer_real':('slots[i].frame > job.frame && source_fresh(slots[i], p_now)', 'false && slots[i].frame > job.frame && source_fresh(slots[i], p_now)'),
            'locked_release':('r_retired.keep(slots[p_index].output_lease);', '(void)r_retired;'),
        }
        for name,(old,new) in changes.items():
            with self.subTest(name=name):
                self.assertEqual(self.state.count(old),1)
                root=self.base/('mutation-'+name); target=root/'drivers/metal/openrc_mfx_present_state.h'
                target.parent.mkdir(parents=True,exist_ok=True); target.write_text(self.state.replace(old,new),encoding='utf-8')
                result=self.compile_run(STATE,'pacing_'+name,root)
                self.assertNotEqual(result.returncode,0,f'{name} mutation escaped control')

    def test_worker_idle_timeout_releases_expired_reserved_slot(self):
        worker=CHECK.cxx_function(self.bridge,'static void *present_worker(')
        start=worker.index('Retired retired;',worker.index('for (;;)'))
        end=worker.index('retired.clear();',start)+len('retired.clear();')
        actual=worker[start:end]
        self.assertIn('scheduler.expire(cleanup_now, retired)',actual)
        prefix=STATE[:STATE.index('int main()')]
        result=self.compile_run(prefix+WORKER.replace('@MAINTENANCE@',actual),'idle_expiry')
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        changed=actual.replace('shared->scheduler.expire(cleanup_now, retired);','(void)cleanup_now;')
        self.assertNotEqual(changed,actual)
        result=self.compile_run(prefix+WORKER.replace('@MAINTENANCE@',changed),'idle_expiry_mutation')
        self.assertNotEqual(result.returncode,0,'idle-expiry mutation escaped control')

    def test_bridge_revalidates_commit_and_drawable_identity_outside_lock(self):
        delegate=CHECK.cxx_function(self.bridge,'- (void)metalDisplayLink:')
        self.assertIn('s->scheduler.commit(choice, admitted_at, retired_after_choice)',delegate)
        self.assertLess(delegate.index('const uint64_t drawable_width = uint64_t(dst.width);'),delegate.index('std::lock_guard<std::mutex> admission'))
        self.assertLess(delegate.index('const MTLPixelFormat drawable_format = dst.pixelFormat;'),delegate.index('std::lock_guard<std::mutex> admission'))
        self.assertLess(delegate.index('scheduler.commit(choice, admitted_at, retired_after_choice)'),delegate.index('last_admitted_drawable_width = drawable_width'))
        for key in ('width','height','pixel_format','frame','generated'):
            self.assertIn('last_admitted_drawable_'+key,self.header)
            self.assertIn('last_admitted_drawable_'+key,self.device)
        self.assertLess(delegate.index('Retired retired_before_choice;'),delegate.index('std::unique_lock<std::mutex> gate'))
        self.assertLess(delegate.index('Retired retired_after_choice;'),delegate.index('std::unique_lock<std::mutex> gate'))
        self.assertEqual(ENGINE.patch_paths([PATCHES[-1]]),{
            'drivers/metal/openrc_mfx_present_bridge.h','drivers/metal/openrc_mfx_present_bridge.mm',
            'drivers/metal/openrc_mfx_present_state.h','servers/rendering/rendering_device.cpp'})

if __name__=='__main__':
    unittest.main()
