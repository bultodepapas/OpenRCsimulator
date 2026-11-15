"""Portable source-bound controls for 0013; these do not run Metal or Godot."""
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

def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    sys.modules[name] = result
    spec.loader.exec_module(result)
    return result

ENGINE = module('real_completion_engine', HERE / 'engine.py')
CHECK = module('real_completion_checks', HERE / 'test_engine_patch.py')
PREVIOUS = module('real_completion_present', HERE / 'test_engine_present_patch.py')
NAMES = PREVIOUS.NAMES + (
    '0009-metalfx-frame-composition.patch', '0010-metal-empty-submit-fence.patch',
    '0011-metalfx-presentation-adapter.patch', '0012-rd-gpu-failure-stop.patch',
    '0013-metalfx-real-completion.patch',
)
PATCHES = tuple(HERE / 'patches' / name for name in NAMES)
PATCH_HASH = '4557e956812dd07a5457763d9f59266520c39f04053ecf2977364c345c4e8cda'
HASHES = PREVIOUS.PREREQUISITES + (PREVIOUS.PATCH_HASH,
    '5ca9396cc846a7f6b72a42f06d1785124e605e4a983e565a31cdf4273dc29333',
    'e72d1d5659213f34b582b2c55e88e2bf50a54c24bc38f3dc3c985130a3c063a4',
    'd6ebee96e1717b7f2d6d5b3b63da82d0c3238582a9bb51bda5a749b70ff55640',
    '55c185f928b9e1d742568f3803d5bec70450177d30ddf976723f8f4197f33fdb',
)

STATE = r'''
#include <servers/rendering/storage/real_gpu_completion.h>
#include <limits>
#define CHECK(x) do { if (!(x)) return __LINE__; } while (0)
int main() {
    RealGPUCompletion s;
    CHECK(s.reset(true,10.0));
    auto a=s.reserve(1,10.0), b=s.reserve(2,10.01), c=s.reserve(3,10.02);
    auto snap=s.snapshot(10.03);
    CHECK(snap.enabled && snap.count==0 && snap.pending==3 && snap.observed_through_seconds==10.0);
    s.complete(c,true,10.09,10.10); snap=s.snapshot(10.11);
    CHECK(snap.count==1 && snap.samples[0].frame==3 && snap.observed_through_seconds==10.0);
    s.complete(a,true,10.03,10.12); snap=s.snapshot(10.13);
    CHECK(snap.count==2 && snap.samples[0].frame==1 && snap.samples[1].frame==3 && snap.observed_through_seconds==10.01);
    s.complete(b,true,10.05,10.14); snap=s.snapshot(10.15);
    CHECK(!snap.failed && snap.count==3 && snap.pending==0 && snap.observed_through_seconds==10.15);
    CHECK(snap.samples[0].frame==1 && snap.samples[1].frame==2 && snap.samples[2].frame==3);
    auto old=s.reserve(4,10.20); CHECK(s.reset(true,11.0));
    auto fresh=s.reserve(1,11.01); s.complete(old,true,10.21,11.02);
    snap=s.snapshot(11.03); CHECK(!snap.failed && snap.count==0 && snap.pending==1 && snap.stale_callbacks==1);
    s.complete(fresh,true,11.02,11.04); snap=s.snapshot(11.05); CHECK(snap.count==1 && snap.samples[0].generation==fresh.generation);
    auto bad=s.reserve(2,11.06); s.complete(bad,false,11.07,11.08); snap=s.snapshot(11.09);
    CHECK(snap.failed && snap.count==1 && !snap.invalid_clock);
    CHECK(s.reset(true,12.0)); auto future=s.reserve(5,12.01); s.complete(future,true,12.5,12.1);
    snap=s.snapshot(12.2); CHECK(snap.invalid_clock && snap.failed && snap.count==0);
    CHECK(s.reset(true,13.0)); auto first=s.reserve(1,13.01), second=s.reserve(2,13.02);
    s.complete(second,true,13.1,13.2); s.complete(first,true,13.11,13.2);
    snap=s.snapshot(13.3); CHECK(snap.failed && snap.invalid_clock);
    CHECK(s.reset(true,14.0)); auto dup=s.reserve(7,14.01); CHECK(!s.reserve(7,14.02).generation);
    snap=s.snapshot(14.03); CHECK(snap.failed && snap.count==0); s.complete(dup,true,14.02,14.03);
    CHECK(s.reset(true,20.0)); auto late=s.reserve(1,20.1); snap=s.snapshot(23.2);
    CHECK(snap.failed && snap.observed_through_seconds==20.1 && snap.coverage_start_seconds>20.1);
    s.complete(late,true,20.2,23.2); snap=s.snapshot(23.3); CHECK(snap.count==0 && snap.coverage_start_seconds>20.2);
    CHECK(s.reset(true,30.0));
    for (size_t i=0; i<RealGPUCompletion::CAPACITY; ++i) {
        double t=30.0+i*0.001; auto r=s.reserve(i+1,t); CHECK(r.generation);
        s.complete(r,true,t+0.0002,t+0.0004);
    }
    auto overflow=s.reserve(RealGPUCompletion::CAPACITY+1,31.2); CHECK(overflow.generation);
    s.complete(overflow,true,31.201,31.202); snap=s.snapshot(31.3);
    CHECK(snap.failed && snap.overflow && snap.count==RealGPUCompletion::CAPACITY);
    CHECK(s.reset(true,40.0));
    for (size_t i=0; i<RealGPUCompletion::CAPACITY; ++i) { CHECK(s.reserve(i+1,40.0+i*0.001).generation); }
    CHECK(s.reset(true,42.0)); CHECK(!s.reserve(1,42.1).generation);
    snap=s.snapshot(42.2); CHECK(snap.failed && snap.overflow);
    CHECK(s.reset(false,0)); snap=s.snapshot(43); CHECK(!snap.enabled && snap.count==0);
    return 0;
}
'''

NATIVE = r'''
#include <servers/rendering/storage/real_gpu_completion.h>
#include <functional>
#include <memory>
#include <cstdint>
#define CHECK(x) do { if (!(x)) return __LINE__; } while (0)
static double clock_value=10; double mfx_real_gpu_now() { return clock_value; }
namespace MTL {
enum CommandBufferStatus { CommandBufferStatusCompleted, CommandBufferStatusError };
struct CommandBuffer {
    CommandBufferStatus current=CommandBufferStatusCompleted; bool has_error=false; double gpu_end=0;
    std::function<void(CommandBuffer*)> callback;
    CommandBufferStatus status() { return current; }
    void *error() { return has_error ? this : nullptr; }
    double GPUEndTime() { return gpu_end; }
    template<class F> void addCompletedHandler(F f) { callback=f; }
    void finish() { callback(this); }
};
}
namespace MTL3 {
struct MDCommandBuffer { MTL::CommandBuffer *native=nullptr; bool ended=false; void end() { ended=true; } MTL::CommandBuffer *ensure_command_buffer() { return native; } };
struct CommandBufferID { uintptr_t id=0; };
struct RenderingDeviceDriverMetal {
    bool real_gpu_completion_register(CommandBufferID, const std::shared_ptr<RealGPUCompletion>&, const RealGPUCompletion::Reservation&);
};
@REGISTER@
}
int main() {
    auto state=std::make_shared<RealGPUCompletion>(); CHECK(state->reset(true,10));
    MTL::CommandBuffer native; MTL3::MDCommandBuffer cmd{&native}; MTL3::RenderingDeviceDriverMetal driver;
    auto first=state->reserve(1,10.01); clock_value=10.03;
    CHECK(driver.real_gpu_completion_register({uintptr_t(&cmd)},state,first)); CHECK(cmd.ended);
    auto snap=state->snapshot(10.03); CHECK(snap.pending==1 && snap.count==0);
    native.gpu_end=10.02; native.finish(); snap=state->snapshot(10.04);
    CHECK(snap.count==1 && snap.samples[0].frame==1 && !snap.failed);
    auto failed=state->reserve(2,10.05); CHECK(driver.real_gpu_completion_register({uintptr_t(&cmd)},state,failed));
    native.current=MTL::CommandBufferStatusError; native.gpu_end=10.06; clock_value=10.07; native.finish();
    snap=state->snapshot(10.08); CHECK(snap.failed && snap.count==1);
    CHECK(state->reset(true,11)); auto error=state->reserve(1,11.01);
    CHECK(driver.real_gpu_completion_register({uintptr_t(&cmd)},state,error));
    native.current=MTL::CommandBufferStatusCompleted; native.has_error=true; native.gpu_end=11.02; clock_value=11.03; native.finish();
    snap=state->snapshot(11.04); CHECK(snap.failed && snap.count==0);
    CHECK(state->reset(true,12)); auto missing=state->reserve(1,12.01); cmd.native=nullptr;
    CHECK(!driver.real_gpu_completion_register({uintptr_t(&cmd)},state,missing));
    state->fail(missing,"registration_failed"); snap=state->snapshot(12.02); CHECK(snap.failed && snap.pending==0);
    return 0;
}
'''


GRAPH = r'''
#include <servers/rendering/storage/real_gpu_completion.h>
#include <memory>
#include <cstdint>
#define CHECK(x) do { if (!(x)) return __LINE__; } while (0)
#define ERR_RENDER_THREAD_GUARD_V(x) do {} while (0)
#define memnew(T) new T
#define memdelete(x) delete (x)
enum Error { OK=0, ERR_UNAVAILABLE=1, ERR_INVALID_PARAMETER=2 };
struct RID { int id=0; };
template<class T> struct VectorView { T *ptr; int size; VectorView(T *p,int n) : ptr(p),size(n) {} };
struct RenderingDeviceDriver {
    struct CommandBufferID { int id=0; };
    using Callback = void (*)(RenderingDeviceDriver*, CommandBufferID, void*);
    std::shared_ptr<RealGPUCompletion> retained; RealGPUCompletion::Reservation reservation;
    bool real_gpu_completion_register(CommandBufferID, const std::shared_ptr<RealGPUCompletion>&s, const RealGPUCompletion::Reservation&r) { retained=s; reservation=r; return true; }
};
class RenderingDevice {
public:
    enum Usage { CALLBACK_RESOURCE_USAGE_TEXTURE_SAMPLE };
    struct CallbackResource { RID rid; Usage usage; };
    bool supports=true, reject=false; double now=10.0;
    RenderingDeviceDriver::Callback callback=nullptr; void *userdata=nullptr;
    bool real_gpu_completion_supported() const { return supports; }
    double real_gpu_completion_now() const { return now; }
    Error driver_callback_add(RenderingDeviceDriver::Callback c, void *d, VectorView<CallbackResource> resources) {
        if (reject) return ERR_INVALID_PARAMETER;
        if (resources.size!=1 || resources.ptr[0].rid.id!=7 || resources.ptr[0].usage!=CALLBACK_RESOURCE_USAGE_TEXTURE_SAMPLE) return ERR_INVALID_PARAMETER;
        callback=c; userdata=d; return OK;
    }
    Error real_gpu_completion_observe(RID,const std::shared_ptr<RealGPUCompletion>&,uint64_t);
};
struct RealGPUCompletionCallback { std::shared_ptr<RealGPUCompletion> state; RealGPUCompletion::Reservation reservation; };
@CALLBACK@
@OBSERVE@
int main() {
    auto state=std::make_shared<RealGPUCompletion>(); CHECK(state->reset(true,10));
    RenderingDevice rd; int scene_output=1987;
    CHECK(rd.real_gpu_completion_observe({7},state,1)==OK);
    auto snap=state->snapshot(10.01); CHECK(scene_output==1987 && snap.pending==1 && snap.count==0);
    RenderingDeviceDriver driver; rd.callback(&driver,{1},rd.userdata);
    snap=state->snapshot(10.02); CHECK(scene_output==1987 && snap.pending==1 && snap.count==0);
    driver.retained->complete(driver.reservation,true,10.03,10.04);
    snap=state->snapshot(10.05); CHECK(scene_output==1987 && snap.pending==0 && snap.count==1);
    CHECK(state->reset(true,11)); rd.now=11.01; rd.reject=true;
    CHECK(rd.real_gpu_completion_observe({7},state,2)==ERR_INVALID_PARAMETER);
    snap=state->snapshot(11.02); CHECK(snap.failed && snap.pending==0 && snap.count==0 && scene_output==1987);
    return 0;
}
'''

ACTIVE = r'''
#define CHECK(x) do { if (!(x)) return __LINE__; } while (0)
namespace DisplayServerEnums { enum WindowID { MAIN_WINDOW_ID, OTHER }; }
struct Viewport { DisplayServerEnums::WindowID viewport_to_screen=DisplayServerEnums::MAIN_WINDOW_ID; };
struct Active { bool value=false; bool has(Viewport *) { return value; } };
int main() {
    Viewport v; Viewport *viewport=&v; Active active_viewports; int resets=0; bool p_active=false;
    if (@CONDITION@) { ++resets; } CHECK(resets==0);
    p_active=true; if (@CONDITION@) { ++resets; } CHECK(resets==1);
    active_viewports.value=true; if (@CONDITION@) { ++resets; } CHECK(resets==1);
    p_active=false; if (@CONDITION@) { ++resets; } CHECK(resets==2);
    return 0;
}
'''

class RealCompletionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not CHECK.ARCHIVE.is_file() or ENGINE.sha256(CHECK.ARCHIVE) != CHECK.ARCHIVE_SHA256:
            raise RuntimeError('Pinned Godot source archive unavailable')
        if tuple(ENGINE.sha256(path) for path in PATCHES[:12]) != HASHES:
            raise RuntimeError('Frozen 1–12 prerequisites differ')
        if ENGINE.sha256(PATCHES[12]) != PATCH_HASH:
            raise RuntimeError('Frozen 0013 candidate differs')
        parent=ROOT/'tmp/metalfx-real-completion-port'; parent.mkdir(parents=True,exist_ok=True)
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
        cls.state=(cls.base/'servers/rendering/storage/real_gpu_completion.h').read_text(encoding='utf-8')
        cls.native=(cls.base/'drivers/metal/rendering_device_driver_metal3.cpp').read_text(encoding='utf-8')
        cls.viewport=(cls.base/'servers/rendering/renderer_viewport.cpp').read_text(encoding='utf-8')
        cls.device=(cls.base/'servers/rendering/rendering_device.cpp').read_text(encoding='utf-8')
        cls.frame_bridge=(cls.base/'drivers/metal/metalfx_frame_bridge.mm').read_text(encoding='utf-8')

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

    def test_actual_state_completed_only_ordering_stale_and_capacity(self):
        result=self.compile_run(STATE,'real_state'); self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_submitted_count_and_generation_mutations_are_detected(self):
        mutations={
            'submitted':('++pending_count; ++outstanding_count; last_frame', 'samples[sample_count++] = { generation, p_frame, p_now }; ++pending_count; ++outstanding_count; last_frame'),
            'stale':('const bool current = enabled && p_reservation.generation == generation;', 'const bool current = enabled;'),
            'watermark':('out.observed_through_seconds = std::min(out.observed_through_seconds, p.reservation.reserved_at);', 'out.observed_through_seconds = p_now;'),
            'failed':('if (!p_success) { fail_locked("gpu_failure"); return; }', 'if (false && !p_success) { fail_locked("gpu_failure"); return; }'),
        }
        for name,(old,new) in mutations.items():
            with self.subTest(name=name):
                self.assertEqual(self.state.count(old),1)
                root=self.base/('mutation-'+name); target=root/'servers/rendering/storage/real_gpu_completion.h'; target.parent.mkdir(parents=True,exist_ok=True)
                target.write_text(self.state.replace(old,new),encoding='utf-8')
                result=self.compile_run(STATE,'real_'+name,root)
                self.assertNotEqual(result.returncode,0,f'{name} mutation escaped control')

    def test_actual_native_completion_registration(self):
        function=CHECK.cxx_function(self.native,'bool RenderingDeviceDriverMetal::real_gpu_completion_register(')
        result=self.compile_run(NATIVE.replace('@REGISTER@',function),'native_register')
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        mutation=function.replace('completed->error() == nullptr','true')
        self.assertNotEqual(mutation,function)
        result=self.compile_run(NATIVE.replace('@REGISTER@',mutation),'native_error_mutation')
        self.assertNotEqual(result.returncode,0,'native error mutation escaped control')

    def test_actual_graph_admission_and_no_render_output_write(self):
        callback=CHECK.cxx_function(self.device,'void real_gpu_completion_callback(')
        observe=CHECK.cxx_function(self.device,'Error RenderingDevice::real_gpu_completion_observe(')
        result=self.compile_run(GRAPH.replace('@CALLBACK@',callback).replace('@OBSERVE@',observe),'real_graph')
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_active_noop_does_not_reset_observer(self):
        function=CHECK.cxx_function(self.viewport,'void RendererViewport::viewport_set_active(')
        condition='active_viewports.has(viewport) != p_active && viewport->viewport_to_screen == DisplayServerEnums::MAIN_WINDOW_ID'
        self.assertIn(condition,function)
        result=self.compile_run(ACTIVE.replace('@CONDITION@',condition),'active_reset')
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)
        mutation='((void)active_viewports.has(viewport), (void)p_active, viewport->viewport_to_screen == DisplayServerEnums::MAIN_WINDOW_ID)'
        result=self.compile_run(ACTIVE.replace('@CONDITION@',mutation),'active_reset_mutation')
        self.assertNotEqual(result.returncode,0,'no-op reset mutation escaped control')

    def test_boundary_and_capability_wiring(self):
        draw=CHECK.cxx_function(self.viewport,'void RendererViewport::draw_viewports(')
        observer=CHECK.cxx_function(self.viewport,'void RendererViewport::_real_gpu_observe_viewport(')
        register=CHECK.cxx_function(self.device,'Error RenderingDevice::real_gpu_completion_observe(')
        self.assertLess(draw.index('_draw_viewport(vp);',draw.index('// render standard mono camera')), draw.index('_real_gpu_observe_viewport(vp);'))
        self.assertIn('p_swap_buffers && vp->real_gpu_observation_requested',draw)
        self.assertIn('render_target_get_override_color',observer)
        self.assertIn('main_count != 1',observer)
        self.assertIn('!p_viewport->render_buffers.is_valid()',observer)
        self.assertIn('!RSG::scene->is_camera(p_viewport->camera)',observer)
        self.assertIn('!RSG::scene->is_scenario(p_viewport->scenario)',observer)
        self.assertIn('CALLBACK_RESOURCE_USAGE_TEXTURE_SAMPLE',register)
        self.assertIn('driver_callback_add(real_gpu_completion_callback',register)
        self.assertIn('reserve(p_frame, real_gpu_completion_now())',register)
        self.assertIn('state->fail(args->reservation, "registration_failed")',self.device)
        capability=CHECK.cxx_function(self.frame_bridge,'int mfx_frame_device_capability(')
        self.assertIn('__MAC_OS_X_VERSION_MAX_ALLOWED >= 260000',capability)
        self.assertIn('@available(macOS 26.0, *)',capability)
        self.assertIn('supportsDevice:device',capability)
        self.assertNotIn('newFrameInterpolator',capability)
        frame_toggle=CHECK.cxx_function(self.viewport,'void RendererViewport::viewport_set_metalfx_frame_requested(')
        self.assertNotIn('_real_gpu_reset_main',frame_toggle)

if __name__ == '__main__':
    unittest.main()
