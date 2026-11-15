"""Source-bound composition controls; these are not native GPU evidence."""
from __future__ import annotations

import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import zipfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


ENGINE = module("composition_engine", HERE / "engine.py")
CHECK = module("composition_check", HERE / "test_engine_patch.py")
ARCHIVE = Path(os.environ.get("OPENRC_METALFX_SOURCE_ARCHIVE", ROOT / ".tools/apple-metalfx-cache/godot-cafc17a192acf67903910a68aeb3c076c0907a4b.zip"))
PATCHES = [HERE / "patches" / name for name in (
    "0001-metalfx-allocation-fallback.patch", "0002-metalfx-history-reset.patch",
    "0003-metalfx-debug-faults.patch", "0004-metalfx-frame-inputs.patch",
    "0005-metal-triangle-query.patch", "0006-metalfx-gpu-observation.patch",
    "0007-metalfx-denoised-binding.patch", "0009-metalfx-frame-composition.patch")]

FRAME_HARNESS = r'''
#include <atomic>
#include <cassert>
#include <chrono>
#include <cstdlib>
#include <functional>
#include <memory>
#include <vector>
#include "servers/rendering/storage/metalfx_gpu_observation.h"
#undef assert
#define assert(x) do { if (!(x)) std::_Exit(1); } while (false)
@FRAME@
@HISTORY@
namespace NS { struct Error { int64_t value=3; int64_t code() const { return value; } }; }
namespace MTL {
enum CommandBufferStatus { CommandBufferStatusScheduled=3, CommandBufferStatusCompleted=4, CommandBufferStatusError=5 };
struct CommandBuffer {
    CommandBufferStatus state=CommandBufferStatusCompleted;
    NS::Error *failure=nullptr;
    std::vector<std::function<void(CommandBuffer *)>> handlers;
    CommandBufferStatus status() const { return state; }
    NS::Error *error() const { return failure; }
    double GPUStartTime() const { return 1.0; }
    double GPUEndTime() const { return 1.1; }
    void addCompletedHandler(std::function<void(CommandBuffer *)> fn) { handlers.push_back(fn); }
    void finish() { auto all=std::move(handlers); for (auto &f:all) f(this); }
}; }
@OBSERVER@
struct RDD { struct CommandBufferID { uintptr_t id; }; struct TextureID { uintptr_t id=0; }; };
using CFTypeRef=void *;
struct MDCommandBufferBase {
    void end() {} void *external_pass_fence() { return nullptr; }
    void retain_resource(CFTypeRef) {}
};
namespace MTL3 { struct MDCommandBuffer : MDCommandBufferBase {
    MTL::CommandBuffer command;
    MTL::CommandBuffer *get_command_buffer() { return &command; }
    MTL::CommandBuffer *ensure_command_buffer() { return &command; }
}; }
static int encode_return=0;
template<class... T> int mfx_frame_encode(T...) { return encode_return; }
static void mfx_frame_release(void *) {}
#define memdelete(x) delete (x)
enum { MFX_FRAME_OK=0, MFX_FRAME_INPUT_MISMATCH=5 };
class MFXFrameEffect { public:
    struct CallbackArgs {
        void *effect=nullptr;
        RDD::TextureID color, previous, depth, motion, output;
        std::shared_ptr<MetalFXFrameHistoryState> history;
        uint64_t serial=0, epoch=0;
        std::shared_ptr<MetalFXGPUObservation> gpu;
        uint64_t frame=0;
        std::shared_ptr<MetalFXCompositionFrame> composition;
        float scale_x=0,scale_y=0,jitter_x=0,jitter_y=0,delta=0,fov=0,z_near=0,z_far=0,aspect=0;
        bool reset=false;
    };
    static void callback(RDD *, RDD::CommandBufferID, CallbackArgs *);
};
class MFXCompositionEffect { public:
    struct CallbackArgs { std::shared_ptr<MetalFXCompositionFrame> state; };
    static void callback(RDD *, RDD::CommandBufferID, CallbackArgs *);
};
@SDK_CALLBACK@
@COMPOSE_CALLBACK@

static MFXFrameEffect::CallbackArgs *args(const std::shared_ptr<MetalFXCompositionFrame> &pair,
        const std::shared_ptr<MetalFXFrameHistoryState> &history) {
    auto *a=new MFXFrameEffect::CallbackArgs;
    a->composition=pair; a->history=history; a->serial=pair->serial; a->frame=pair->frame; a->epoch=pair->epoch;
    return a;
}
int main() {
    auto p=std::make_shared<MetalFXCompositionFrame>();
    p->frame=72; p->epoch=8; p->serial=9;
    auto h=std::make_shared<MetalFXFrameHistoryState>();
    h->encoded_epoch.store(8); h->encoded_in_epoch.store(4);
    MTL3::MDCommandBuffer sdk, composed;
    MFXFrameEffect::callback(nullptr,{uintptr_t(&sdk)},args(p,h));
    assert(p->encode_result.load()==1 && p->warm_count.load()==5);
    MFXCompositionEffect::callback(nullptr,{uintptr_t(&composed)},new MFXCompositionEffect::CallbackArgs{p});
    assert(!p->ready(72,8));
    composed.command.finish(); assert(!p->ready(72,8));
    sdk.command.finish(); assert(p->ready(72,8));
    assert(!p->ready(71,8) && !p->ready(72,7));
    p->warm_count.store(4); assert(!p->ready(72,8)); p->warm_count.store(5);

    // A separate SDK command failure must defeat a successful later pair write.
    auto failed=std::make_shared<MetalFXCompositionFrame>();
    failed->frame=73; failed->epoch=8; failed->serial=10;
    MTL3::MDCommandBuffer sdk_bad, pair_ok;
    MFXFrameEffect::callback(nullptr,{uintptr_t(&sdk_bad)},args(failed,h));
    MFXCompositionEffect::callback(nullptr,{uintptr_t(&pair_ok)},new MFXCompositionEffect::CallbackArgs{failed});
    NS::Error error; sdk_bad.command.state=MTL::CommandBufferStatusError; sdk_bad.command.failure=&error;
    pair_ok.command.finish(); sdk_bad.command.finish(); assert(!failed->ready(73,8));

    // SDK encode failure cannot be disguised by a successful composition callback.
    auto rejected=std::make_shared<MetalFXCompositionFrame>();
    rejected->frame=74; rejected->epoch=8; rejected->serial=11;
    MTL3::MDCommandBuffer reject_sdk, reject_pair; encode_return=7;
    MFXFrameEffect::callback(nullptr,{uintptr_t(&reject_sdk)},args(rejected,h));
    assert(rejected->encode_result.load()==-1 && reject_sdk.command.handlers.empty());
    MFXCompositionEffect::callback(nullptr,{uintptr_t(&reject_pair)},new MFXCompositionEffect::CallbackArgs{rejected});
    reject_pair.command.finish(); assert(!rejected->ready(74,8));

    // Queued callbacks retain only value state, and retired state cannot revive a new pair.
    auto old=std::make_shared<MetalFXCompositionFrame>(); old->frame=80; old->epoch=9; old->serial=1;
    std::weak_ptr<MetalFXCompositionFrame> weak=old;
    auto *queued=new MFXCompositionEffect::CallbackArgs{old}; old.reset(); assert(!weak.expired());
    MTL3::MDCommandBuffer late; MFXCompositionEffect::callback(nullptr,{uintptr_t(&late)},queued);
    assert(weak.expired()); late.command.finish();
    auto replacement=std::make_shared<MetalFXCompositionFrame>();
    replacement->frame=81; replacement->epoch=10; replacement->serial=1;
    assert(!replacement->ready(81,10));
}
'''

RING_HARNESS = r'''
#define METAL_ENABLED
#define MACOS_ENABLED
#include <atomic>
#include <cstdint>
#include <cstdlib>
#include <map>
#include <memory>
#include <string>
#include "servers/rendering/storage/metalfx_gpu_observation.h"
#define CHECK(x) do { if (!(x)) std::_Exit(__LINE__ % 250 + 1); } while (false)
@FRAME@
@HISTORY@
struct RID {
    int id=0;
    bool is_valid() const { return id!=0; }
    bool operator==(RID other) const { return id==other.id; }
};
struct Size2i { int x=0,y=0; bool operator!=(Size2i other) const { return x!=other.x || y!=other.y; } };
struct Point2i {};
struct Rect2i { Rect2i(Point2i,Size2i) {} };
using String=std::string;
namespace RendererRD {
struct MFXFrameContext { std::shared_ptr<MetalFXFrameHistoryState> history; };
struct TextureStorage {
    struct Info { Size2i size; bool hdr=false, debanding=false; };
    std::map<int,Info> targets;
    int next=200,created=0,freed=0,fail_on=0;
    static TextureStorage *get_singleton() { static TextureStorage t; return &t; }
    RID render_target_create() { ++created; if (created==fail_on) return {}; int id=++next; targets[id]=Info{}; return {id}; }
    void render_target_free(RID r) { targets.erase(r.id); ++freed; }
    Size2i render_target_get_size(RID r) const { return targets.at(r.id).size; }
    bool render_target_is_using_hdr(RID r) const { return targets.at(r.id).hdr; }
    bool render_target_is_using_debanding(RID r) const { return targets.at(r.id).debanding; }
    void render_target_set_use_hdr(RID r,bool x) { targets[r.id].hdr=x; }
    void render_target_set_use_debanding(RID r,bool x) { targets[r.id].debanding=x; }
    void render_target_set_size(RID r,int x,int y,int) { targets[r.id].size={x,y}; }
    RID render_target_get_rd_texture(RID r) const { return r.is_valid() && targets.count(r.id) ? RID{r.id+1000} : RID{}; }
};
struct CopyEffects {
    bool succeeds=true; RID src,dst; bool eight_bit=false;
    static CopyEffects *get_singleton() { static CopyEffects t; return &t; }
    bool copy_to_rect_checked(RID a,RID b,Rect2i,bool,bool,bool,bool c) {
        src=a; dst=b; eight_bit=c; return succeeds;
    }
};
struct MFXCompositionEffect {
    static bool accepted;
    static RID generated,real;
    bool observe_completion(RID g,RID r,const std::shared_ptr<MetalFXCompositionFrame> &p) {
        generated=g; real=r;
        if (!accepted) return false;
        return p->completion->encoded(p->frame,p->epoch).ticket==1;
    }
};
bool MFXCompositionEffect::accepted=true;
RID MFXCompositionEffect::generated, MFXCompositionEffect::real;
}
struct RenderSceneBuffersRD {
    struct MFXCompositionSlot {
        RID generated_target,real_target;
        std::shared_ptr<MetalFXCompositionFrame> state;
        bool submitted=false,encode_enqueued=false,tonemapped=false,eligible=false;
    } mfx_composition_slots[2];
    int mfx_composition_active=-1;
    uint64_t mfx_composition_invalid_through=0,mfx_composition_current_frame=0;
    bool mfx_composition_faulted=false,requested=false,frame_requested=true;
    String mfx_composition_reason="not_attempted";
    RID render_target{100}; Size2i target_size{1920,1080};
    RendererRD::MFXFrameContext *mfx_frame_context=nullptr;
    bool is_metalfx_frame_composition_requested() const { return requested; }
    bool is_metalfx_frame_requested() const { return frame_requested; }
    int _metalfx_composition_ready_slot() const;
    void clear_metalfx_frame_composition();
    void begin_metalfx_frame_composition(uint64_t,bool);
    RID get_metalfx_frame_composition_target() const;
    void finish_metalfx_frame_composition(bool);
};
@CLEAR@
@READY@
@BEGIN@
@TARGET@
@FINISH@

static void done(const std::shared_ptr<MetalFXGPUObservation> &observer,bool success=true) {
    auto s=observer->snapshot().encoded;
    CHECK(s.ticket==1);
    CHECK(observer->completed(s,true,success,success?4:5,!success,success?0:3,1,2,1));
}
static std::shared_ptr<MetalFXCompositionFrame> submit(RenderSceneBuffersRD &b,uint64_t frame,bool sdk_complete) {
    b.begin_metalfx_frame_composition(frame,true);
    CHECK(b.mfx_composition_active>=0);
    auto &slot=b.mfx_composition_slots[b.mfx_composition_active];
    auto state=slot.state; state->epoch=8; state->serial=frame;
    state->warm_count.store(5); state->encode_result.store(1);
    CHECK(state->sdk_completion->encoded(frame,8).ticket==1);
    if (sdk_complete) done(state->sdk_completion);
    slot.tonemapped=true; slot.encode_enqueued=true;
    b.finish_metalfx_frame_composition(true);
    return state;
}
int main() {
    auto *storage=RendererRD::TextureStorage::get_singleton();
    storage->targets[100]={{1920,1080},false,true};
    auto history=std::make_shared<MetalFXFrameHistoryState>(); history->requested_epoch.store(8);
    RendererRD::MFXFrameContext context{history};
    RenderSceneBuffersRD b; b.mfx_frame_context=&context;
    b.begin_metalfx_frame_composition(9,true); CHECK(storage->created==0); // Off allocates nothing.
    b.requested=true;
    auto first=submit(b,10,false);
    CHECK(b._metalfx_composition_ready_slot()==-1);
    CHECK(RendererRD::MFXCompositionEffect::generated.is_valid());
    CHECK(!(RendererRD::MFXCompositionEffect::generated==RendererRD::MFXCompositionEffect::real));
    CHECK(RendererRD::CopyEffects::get_singleton()->eight_bit);
    done(first->completion); CHECK(b._metalfx_composition_ready_slot()==-1);
    done(first->sdk_completion); CHECK(b._metalfx_composition_ready_slot()==0);
    b.begin_metalfx_frame_composition(11,true);
    CHECK(b.mfx_composition_active==1 && b._metalfx_composition_ready_slot()==0);
    auto second=b.mfx_composition_slots[1].state; second->epoch=8; second->serial=11;
    second->warm_count.store(5); second->encode_result.store(1);
    CHECK(second->sdk_completion->encoded(11,8).ticket==1);
    b.mfx_composition_slots[1].tonemapped=true;
    b.finish_metalfx_frame_composition(true);
    done(second->sdk_completion); done(second->completion);
    CHECK(b._metalfx_composition_ready_slot()==1);
    b.begin_metalfx_frame_composition(12,false); CHECK(b._metalfx_composition_ready_slot()==-1);
    b.clear_metalfx_frame_composition();

    RenderSceneBuffersRD busy; busy.requested=true; busy.mfx_frame_context=&context;
    auto one=submit(busy,20,false), two=submit(busy,21,false);
    int created=storage->created;
    busy.begin_metalfx_frame_composition(22,true);
    CHECK(busy.mfx_composition_active==-1 && busy.mfx_composition_reason=="both_slots_pending");
    CHECK(storage->created==created);
    // Retirement frees the owned RIDs using RD's deferred-free path; callbacks retain only state.
    busy.clear_metalfx_frame_composition();
    done(one->sdk_completion); done(one->completion);
    CHECK(busy._metalfx_composition_ready_slot()==-1);
    done(two->sdk_completion); done(two->completion);

    RenderSceneBuffersRD copy_failed; copy_failed.requested=true; copy_failed.mfx_frame_context=&context;
    RendererRD::CopyEffects::get_singleton()->succeeds=false;
    auto bad=submit(copy_failed,30,true); done(bad->completion);
    CHECK(copy_failed._metalfx_composition_ready_slot()==-1 && copy_failed.mfx_composition_reason=="copy_record_failed");
    RendererRD::CopyEffects::get_singleton()->succeeds=true;
    copy_failed.clear_metalfx_frame_composition();

    RenderSceneBuffersRD failed; failed.requested=true; failed.mfx_frame_context=&context;
    auto gpu_bad=submit(failed,40,false); done(gpu_bad->completion); done(gpu_bad->sdk_completion,false);
    CHECK(failed._metalfx_composition_ready_slot()==-1);
    failed.begin_metalfx_frame_composition(41,true);
    CHECK(failed.mfx_composition_active==-1 && failed.mfx_composition_faulted);
    failed.clear_metalfx_frame_composition();

    RenderSceneBuffersRD allocation; allocation.requested=true; allocation.mfx_frame_context=&context;
    int freed=storage->freed; storage->fail_on=storage->created+2;
    allocation.begin_metalfx_frame_composition(50,true);
    CHECK(allocation.mfx_composition_active==-1 && allocation.mfx_composition_reason=="render_target_allocation_failed");
    CHECK(storage->freed==freed+1 && !allocation.mfx_composition_slots[0].generated_target.is_valid());
    storage->fail_on=0;

    RenderSceneBuffersRD observer_rejected; observer_rejected.requested=true; observer_rejected.mfx_frame_context=&context;
    RendererRD::MFXCompositionEffect::accepted=false;
    auto rejected=submit(observer_rejected,60,true);
    CHECK(rejected && observer_rejected.mfx_composition_faulted && observer_rejected._metalfx_composition_ready_slot()==-1);
    observer_rejected.begin_metalfx_frame_composition(61,true);
    CHECK(observer_rejected.mfx_composition_active==-1);
    RendererRD::MFXCompositionEffect::accepted=true;
    observer_rejected.clear_metalfx_frame_composition();
}
'''

COPY_HARNESS = r'''
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <vector>
#define CHECK(x) do { if (!(x)) std::_Exit(__LINE__ % 250 + 1); } while (false)
#define ERR_FAIL_NULL_V(p,v) do { if (!(p)) return v; } while (false)
#define ERR_FAIL_COND_V(c,v) do { if (c) return v; } while (false)
struct RID { int id=0; bool is_null() const { return id==0; } };
struct Point { int x=0,y=0; }; struct Size { int width=0,height=0; };
struct Rect2i { Point position; Size size; };
template<class T> using Vector=std::vector<T>;
namespace RSE { enum { CANVAS_ITEM_TEXTURE_FILTER_LINEAR, CANVAS_ITEM_TEXTURE_REPEAT_DISABLED }; }
struct RD {
    using ComputeListID=int;
    static constexpr int INVALID_ID=-1, UNIFORM_TYPE_SAMPLER_WITH_TEXTURE=1,UNIFORM_TYPE_IMAGE=2;
    struct Uniform { Uniform(int,int,const Vector<RID> &) {} Uniform(int,int,RID) {} };
    bool pipeline_ok=true,set_ok=true,list_ok=true; int checks=0,dispatches=0;
    static RD *get_singleton() { static RD rd; return &rd; }
    bool compute_pipeline_is_valid(RID) { ++checks; return pipeline_ok; }
    bool uniform_set_is_valid(RID) { ++checks; return set_ok; }
    int compute_list_begin() { return list_ok?1:INVALID_ID; }
    void compute_list_bind_compute_pipeline(int,RID) {}
    void compute_list_bind_uniform_set(int,RID,int) {}
    void compute_list_set_push_constant(int,const void *,unsigned) {}
    void compute_list_dispatch_threads(int,int,int,int) { ++dispatches; }
    void compute_list_end() {}
};
struct UniformSetCacheRD {
    static bool present;
    static UniformSetCacheRD *get_singleton() { static UniformSetCacheRD x; return present?&x:nullptr; }
    RID get_cache(RID,int,const RD::Uniform &) { return {1}; }
}; bool UniformSetCacheRD::present=true;
struct MaterialStorage {
    static bool present;
    static MaterialStorage *get_singleton() { static MaterialStorage x; return present?&x:nullptr; }
    RID sampler_rd_get_default(int,int) { return {1}; }
}; bool MaterialStorage::present=true;
enum { COPY_FLAG_FLIP_Y=1,COPY_FLAG_FORCE_LUMINANCE=2,COPY_FLAG_ALL_SOURCE=4,
       COPY_FLAG_ALPHA_TO_ONE=8,COPY_FLAG_SANITIZE_INF_NAN=16,
       COPY_MODE_SIMPLY_COPY_8BIT=0,COPY_MODE_SIMPLY_COPY=1 };
using CopyMode=int;
struct CopyPushConstant { int flags,section[4],target[2]; };
struct Shader { bool valid=true; RID version_get_shader(RID,int) { return {valid?1:0}; } };
struct Pipeline { RID get_rid() { return {1}; } };
struct CopyEffects {
    struct Copy { CopyPushConstant push_constant; Shader shader; RID shader_version{1}; Pipeline pipelines[2]; } copy;
    template<bool p_checked> bool copy_to_rect_impl(RID,RID,const Rect2i &,bool,bool,bool,bool,bool,bool);
};
@COPY@
int main() {
    CopyEffects e; Rect2i rect{{0,0},{1920,1080}}; auto *rd=RD::get_singleton();
    CHECK(e.copy_to_rect_impl<true>({1},{2},rect,false,false,false,true,false,false));
    CHECK(rd->dispatches==1 && rd->checks==3);
    rd->dispatches=0; rd->pipeline_ok=false;
    CHECK(!e.copy_to_rect_impl<true>({1},{2},rect,false,false,false,true,false,false)); CHECK(rd->dispatches==0);
    rd->checks=0;
    CHECK(e.copy_to_rect_impl<false>({1},{2},rect,false,false,false,true,false,false));
    CHECK(rd->checks==0 && rd->dispatches==1); // Normal route performs no checked-only queries.
    rd->dispatches=0; rd->pipeline_ok=true; rd->set_ok=false;
    CHECK(!e.copy_to_rect_impl<true>({1},{2},rect,false,false,false,true,false,false)); CHECK(rd->dispatches==0);
    rd->set_ok=true; rd->list_ok=false;
    CHECK(!e.copy_to_rect_impl<true>({1},{2},rect,false,false,false,true,false,false)); CHECK(rd->dispatches==0);
    rd->list_ok=true; e.copy.shader.valid=false;
    CHECK(!e.copy_to_rect_impl<true>({1},{2},rect,false,false,false,true,false,false));
    e.copy.shader.valid=true; UniformSetCacheRD::present=false;
    CHECK(!e.copy_to_rect_impl<true>({1},{2},rect,false,false,false,true,false,false));
    UniformSetCacheRD::present=true; MaterialStorage::present=false;
    CHECK(!e.copy_to_rect_impl<true>({1},{2},rect,false,false,false,true,false,false));
}
'''

TONEMAP_HARNESS = r'''
#include <cstdint>
#include <cstdlib>
#define CHECK(x) do { if (!(x)) std::_Exit(__LINE__ % 250 + 1); } while (false)
#define ERR_FAIL_COND_V(c,v) do { if (c) return v; } while (false)
struct RID { int id=0; bool is_null() const { return id==0; } };
struct RD {
    using DrawListID=int; struct Uniform {};
    static constexpr int INVALID_ID=-1;
    bool pipeline_ok=true,sets_ok=true,list_ok=true; int checks=0,draws=0,ends=0;
    static RD *get_singleton() { static RD rd; return &rd; }
    int draw_list_begin(RID) { return list_ok?1:INVALID_ID; }
    int framebuffer_get_format(RID) { return 1; }
    int draw_list_get_current_pass() { return 0; }
    bool render_pipeline_is_valid(RID) { ++checks; return pipeline_ok; }
    bool uniform_set_is_valid(RID) { ++checks; return sets_ok; }
    void draw_list_bind_render_pipeline(int,RID) {}
    void draw_list_bind_uniform_set(int,RID,unsigned) {}
    void draw_list_set_push_constant(int,const void *,unsigned) {}
    void draw_list_draw(int,bool,unsigned,unsigned) { ++draws; }
    void draw_list_end() { ++ends; }
};
struct UniformSetCacheRD {
    template<class... T> RID get_cache(RID,int,const T &...) { return {1}; }
};
struct TonemapPushConstant { int value; };
struct Shader { bool valid=true; RID version_get_shader(RID,int) { return {valid?1:0}; } };
struct Pipeline { RID get_render_pipeline(int,int,bool,int) { return {1}; } };
struct Tonemap { Shader shader; RID shader_version{1}; Pipeline pipelines[1]; TonemapPushConstant push_constant{}; } tonemap;
template<bool p_checked> bool record_tonemap(RID p_dst_framebuffer) {
    int mode=0;
    RD::Uniform u_source_color,u_exposure_texture,u_glow_texture,u_glow_map,u_color_correction_texture;
    UniformSetCacheRD cache, *uniform_set_cache=&cache;
@TAIL@
}
int main() {
    auto *rd=RD::get_singleton();
    CHECK(record_tonemap<true>({1}) && rd->draws==1 && rd->checks==5);
    rd->draws=0; rd->checks=0; rd->pipeline_ok=false;
    CHECK(!record_tonemap<true>({1}) && rd->draws==0);
    rd->checks=0; CHECK(record_tonemap<false>({1}) && rd->draws==1 && rd->checks==0);
    rd->draws=0; rd->pipeline_ok=true; rd->sets_ok=false;
    CHECK(!record_tonemap<true>({1}) && rd->draws==0);
    rd->sets_ok=true; rd->list_ok=false;
    CHECK(!record_tonemap<true>({1}) && rd->draws==0);
    rd->list_ok=true; tonemap.shader.valid=false;
    CHECK(!record_tonemap<true>({1}) && rd->draws==0);
}
'''

GRAPH_HARNESS = r'''
#include <atomic>
#include <cstdlib>
#include <initializer_list>
#include <memory>
#include "servers/rendering/storage/metalfx_gpu_observation.h"
#define CHECK(x) do { if (!(x)) std::_Exit(__LINE__ % 250 + 1); } while (false)
#define memnew(x) new x
#define memdelete(x) delete (x)
@FRAME@
struct RID { int id=0; bool is_valid() const { return id!=0; } bool operator==(RID x) const { return id==x.id; } };
using Error=int; constexpr Error OK=0;
struct RDD { using DriverCallback=void (*)(void *,void *,void *); };
template<class T> struct VectorView { T *data; int count; VectorView(T *p,int n):data(p),count(n) {} };
struct RD {
    static constexpr int CALLBACK_RESOURCE_USAGE_TEXTURE_SAMPLE=1;
    struct CallbackResource { RID rid; int usage; };
    bool accept=true; int calls=0; RID first,second; void *retained=nullptr;
    static RD *get_singleton() { static RD rd; return &rd; }
    Error driver_callback_add(RDD::DriverCallback,void *userdata,VectorView<CallbackResource> resources) {
        ++calls; CHECK(resources.count==2); CHECK(resources.data[0].usage==CALLBACK_RESOURCE_USAGE_TEXTURE_SAMPLE);
        CHECK(resources.data[1].usage==CALLBACK_RESOURCE_USAGE_TEXTURE_SAMPLE);
        first=resources.data[0].rid; second=resources.data[1].rid;
        if (!accept) return 1;
        retained=userdata; return OK;
    }
};
struct MFXCompositionEffect {
    struct CallbackArgs { std::shared_ptr<MetalFXCompositionFrame> state; };
    static void callback(void *,void *,void *) {}
    bool observe_completion(RID,RID,const std::shared_ptr<MetalFXCompositionFrame> &) const;
};
@OBSERVE@
int main() {
    MFXCompositionEffect effect; auto *rd=RD::get_singleton();
    auto pair=std::make_shared<MetalFXCompositionFrame>();
    CHECK(!effect.observe_completion({0},{2},pair)); CHECK(!effect.observe_completion({1},{1},pair));
    CHECK(!effect.observe_completion({1},{2},nullptr) && rd->calls==0);
    rd->accept=false; CHECK(!effect.observe_completion({1},{2},pair)); CHECK(rd->calls==1);
    rd->accept=true; CHECK(effect.observe_completion({11},{12},pair));
    CHECK(rd->first.id==11 && rd->second.id==12 && rd->calls==2);
    auto *args=static_cast<MFXCompositionEffect::CallbackArgs *>(rd->retained);
    std::weak_ptr<MetalFXCompositionFrame> weak=pair; pair.reset(); CHECK(!weak.expired());
    delete args; CHECK(weak.expired());
}
'''

POLICY_HARNESS = r'''
#include <cstdlib>
#define CHECK(x) do { if (!(x)) std::_Exit(__LINE__ % 250 + 1); } while (false)
struct RID { bool valid=false; bool is_valid() const { return valid; } bool is_null() const { return !valid; } };
struct Settings { int identity=47; };
struct Buffers {
    bool candidate=true,output=true,marked=false;
    RID get_metalfx_composition_candidate() { return {candidate}; }
    RID get_texture(int,int) { return {output}; }
    void mark_metalfx_composition_tonemapped() { marked=true; }
};
enum { RB_SCOPE_METALFX_FRAME, RB_METALFX_FRAME_OUTPUT };
struct TextureStorage { bool framebuffer=true; RID render_target_get_rd_framebuffer(RID) { return {framebuffer}; } };
struct ToneMapper {
    bool succeeds=true; int called=0,settings_identity=0;
    bool tonemapper_checked(RID,RID,const Settings &s) { ++called; settings_identity=s.identity; return succeeds; }
};
struct CameraAttributes { bool automatic=false; bool camera_attributes_uses_auto_exposure(RID) { return automatic; } };
namespace RSG { CameraAttributes *camera_attributes=nullptr; }
struct RenderData { RID compositor,environment,camera_attributes; };
bool glow_enabled=false;
bool environment_get_glow_enabled(RID) { return glow_enabled; }
struct Scenario {
    Buffers buffers; TextureStorage storage; ToneMapper mapper; CameraAttributes camera; RenderData data;
    bool storage_enabled=true,upscaled=true,scaling=false,smaa=false,msaa=false,dof=false;
    bool run() {
        Buffers *rb=&buffers; TextureStorage *texture_storage=&storage; ToneMapper *tone_mapper=&mapper;
        RenderData *p_render_data=&data; RSG::camera_attributes=&camera; Settings tonemap;
        bool can_use_storage=storage_enabled,use_upscaled_texture=upscaled,using_scaling_pass=scaling;
        bool use_smaa=smaa,dest_is_msaa_2d=msaa,using_dof=dof;
@POLICY@
        return buffers.marked;
    }
};
int main() {
    Scenario good; CHECK(good.run() && good.mapper.called==1 && good.mapper.settings_identity==47);
    Scenario no_candidate; no_candidate.buffers.candidate=false; CHECK(!no_candidate.run() && no_candidate.mapper.called==0);
    Scenario compositor; compositor.data.compositor.valid=true; CHECK(!compositor.run());
    Scenario storage; storage.storage_enabled=false; CHECK(!storage.run());
    Scenario no_upscale; no_upscale.upscaled=false; CHECK(!no_upscale.run());
    Scenario scaling; scaling.scaling=true; CHECK(!scaling.run());
    Scenario smaa; smaa.smaa=true; CHECK(!smaa.run());
    Scenario msaa; msaa.msaa=true; CHECK(!msaa.run());
    Scenario dof; dof.dof=true; CHECK(!dof.run());
    Scenario exposure; exposure.camera.automatic=true; CHECK(!exposure.run());
    Scenario glow; glow.data.environment.valid=true; glow_enabled=true; CHECK(!glow.run()); glow_enabled=false;
    Scenario missing_output; missing_output.buffers.output=false; CHECK(!missing_output.run());
    Scenario missing_fb; missing_fb.storage.framebuffer=false; CHECK(!missing_fb.run());
    Scenario record_error; record_error.mapper.succeeds=false; CHECK(!record_error.run() && record_error.mapper.called==1);
}
'''


class CompositionPatchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.compiler = shutil.which("g++") or shutil.which("clang++")
        if not cls.compiler:
            raise unittest.SkipTest("C++17 compiler unavailable")
        if not ARCHIVE.is_file():
            raise unittest.SkipTest("Pinned Godot source archive unavailable")
        if ENGINE.sha256(ARCHIVE) != ENGINE.SOURCE_SHA256:
            raise RuntimeError("Godot source archive differs from independent pin")
        cls.temp = tempfile.TemporaryDirectory(prefix="openrc-metalfx-composition-")
        cls.addClassCleanup(cls.temp.cleanup)
        cls.base = Path(cls.temp.name)
        paths = ENGINE.patch_paths(PATCHES)
        with zipfile.ZipFile(ARCHIVE) as archive:
            members = set(archive.namelist())
            for name in paths:
                member = f"{ENGINE.SOURCE_PREFIX}/{name}"
                if member in members:
                    target = cls.base / name
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(archive.read(member))
        for patch in PATCHES:
            ENGINE.git(cls.base, "apply", "--check", str(patch.resolve()))
            ENGINE.git(cls.base, "apply", str(patch.resolve()))
        cls.buffers = (cls.base / "servers/rendering/storage/render_scene_buffers.h").read_text(encoding="utf-8")
        cls.effects = (cls.base / "servers/rendering/renderer_rd/effects/metal_fx.cpp").read_text(encoding="utf-8")
        cls.rd_buffers = (cls.base / "servers/rendering/renderer_rd/storage_rd/render_scene_buffers_rd.cpp").read_text(encoding="utf-8")
        cls.copy_effects = (cls.base / "servers/rendering/renderer_rd/effects/copy_effects.cpp").read_text(encoding="utf-8")
        cls.tonemap = (cls.base / "servers/rendering/renderer_rd/effects/tone_mapper.cpp").read_text(encoding="utf-8")
        cls.scene = (cls.base / "servers/rendering/renderer_rd/renderer_scene_render_rd.cpp").read_text(encoding="utf-8")
        cls.frame = "struct MetalFXCompositionFrame " + CHECK.cxx_block(cls.buffers, cls.buffers.index("struct MetalFXCompositionFrame")) + ";"
        cls.history = "struct MetalFXFrameHistoryState " + CHECK.cxx_block(cls.buffers, cls.buffers.index("struct MetalFXFrameHistoryState")) + ";"

    def compile_frame(self, frame: str, name: str) -> subprocess.CompletedProcess:
        source = FRAME_HARNESS.replace("@FRAME@", frame).replace("@HISTORY@", self.history)
        source = source.replace("@OBSERVER@", CHECK.cxx_function(self.effects, "static void mfx_observe_gpu("))
        source = source.replace("@SDK_CALLBACK@", CHECK.cxx_function(self.effects, "void MFXFrameEffect::callback("))
        source = source.replace("@COMPOSE_CALLBACK@", CHECK.cxx_function(self.effects, "void MFXCompositionEffect::callback("))
        cpp = self.base / f"{name}.cpp"
        binary = self.base / (name + (".exe" if os.name == "nt" else ""))
        cpp.write_text(source, encoding="utf-8")
        compiled = subprocess.run([self.compiler, "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror", "-pthread", "-I", str(self.base), str(cpp), "-o", str(binary)], capture_output=True, text=True, timeout=90)
        self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
        return subprocess.run([str(binary)], capture_output=True, text=True, timeout=20)

    def test_actual_callbacks_require_exact_successful_sdk_and_pair_completion(self):
        result = self.compile_frame(self.frame, "completion")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_warmup_gate_mutation_is_caught(self):
        self.assertIn("warm_count.load(std::memory_order_acquire) < 5", self.frame)
        mutant = self.frame.replace("warm_count.load(std::memory_order_acquire) < 5", "warm_count.load(std::memory_order_acquire) < 4")
        result = self.compile_frame(mutant, "mutant_warmup")
        self.assertNotEqual(result.returncode, 0, "warmup mutant escaped the behavioral control")

    def test_actual_two_slot_ring_retirement_and_faults(self):
        source = RING_HARNESS.replace("@FRAME@", self.frame).replace("@HISTORY@", self.history)
        for marker, signature in (
            ("@CLEAR@", "void RenderSceneBuffersRD::clear_metalfx_frame_composition("),
            ("@READY@", "int RenderSceneBuffersRD::_metalfx_composition_ready_slot("),
            ("@BEGIN@", "void RenderSceneBuffersRD::begin_metalfx_frame_composition("),
            ("@TARGET@", "RID RenderSceneBuffersRD::get_metalfx_frame_composition_target("),
            ("@FINISH@", "void RenderSceneBuffersRD::finish_metalfx_frame_composition("),
        ):
            source = source.replace(marker, CHECK.cxx_function(self.rd_buffers, signature))
        cpp = self.base / "ring.cpp"
        binary = self.base / ("ring.exe" if os.name == "nt" else "ring")
        cpp.write_text(source, encoding="utf-8")
        compiled = subprocess.run([self.compiler, "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror", "-pthread", "-I", str(self.base), str(cpp), "-o", str(binary)], capture_output=True, text=True, timeout=90)
        self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
        result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, f"ring check returned {result.returncode}: {result.stdout}{result.stderr}")

    def test_actual_checked_copy_refuses_unrecordable_work_and_default_skips_checks(self):
        method = CHECK.cxx_function(self.copy_effects, "bool CopyEffects::copy_to_rect_impl(")
        source = COPY_HARNESS.replace("@COPY@", "template <bool p_checked>\n" + method)
        cpp = self.base / "copy.cpp"
        binary = self.base / ("copy.exe" if os.name == "nt" else "copy")
        cpp.write_text(source, encoding="utf-8")
        compiled = subprocess.run([self.compiler, "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror", str(cpp), "-o", str(binary)], capture_output=True, text=True, timeout=90)
        self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
        result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, f"copy check returned {result.returncode}: {result.stdout}{result.stderr}")

    def test_actual_tonemap_recording_tail_checks_failures_only_for_composition(self):
        method = CHECK.cxx_function(self.tonemap, "bool ToneMapper::tonemapper_impl(")
        tail = method[method.index("\tRID shader ="):method.rfind("}")]
        source = TONEMAP_HARNESS.replace("@TAIL@", tail)
        cpp = self.base / "tonemap.cpp"
        binary = self.base / ("tonemap.exe" if os.name == "nt" else "tonemap")
        cpp.write_text(source, encoding="utf-8")
        compiled = subprocess.run([self.compiler, "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror", str(cpp), "-o", str(binary)], capture_output=True, text=True, timeout=90)
        self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
        result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, f"tonemap check returned {result.returncode}: {result.stdout}{result.stderr}")

    def test_actual_observer_registers_both_distinct_targets_and_retains_state(self):
        method = CHECK.cxx_function(self.effects, "bool MFXCompositionEffect::observe_completion(")
        source = GRAPH_HARNESS.replace("@FRAME@", self.frame).replace("@OBSERVE@", method)
        cpp = self.base / "graph.cpp"
        binary = self.base / ("graph.exe" if os.name == "nt" else "graph")
        cpp.write_text(source, encoding="utf-8")
        compiled = subprocess.run([self.compiler, "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror", "-pthread", "-I", str(self.base), str(cpp), "-o", str(binary)], capture_output=True, text=True, timeout=90)
        self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
        result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, f"graph check returned {result.returncode}: {result.stdout}{result.stderr}")

    def test_actual_postprocess_admission_rejects_unsupported_scenes(self):
        start = self.scene.index("\t\tRID generated_target = rb->get_metalfx_composition_candidate();")
        end = self.scene.index("#endif", start)
        policy = self.scene[start:end]
        source = POLICY_HARNESS.replace("@POLICY@", policy)
        cpp = self.base / "policy.cpp"
        binary = self.base / ("policy.exe" if os.name == "nt" else "policy")
        cpp.write_text(source, encoding="utf-8")
        compiled = subprocess.run([self.compiler, "-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror", str(cpp), "-o", str(binary)], capture_output=True, text=True, timeout=90)
        self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
        result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, f"policy check returned {result.returncode}: {result.stdout}{result.stderr}")


if __name__ == "__main__":
    unittest.main()
