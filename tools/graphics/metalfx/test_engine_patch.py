"""Focused checks for the pinned Godot MetalFX allocation-failure patch.

The executable checks compile selected *patched engine functions* against small
fake SDK/rendering objects. They do not exercise Metal, GPU execution or output
images. The real engine build and native fault-injection checks remain separate.
"""

from __future__ import annotations

import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import zipfile


ROOT = Path(__file__).resolve().parents[3]
COMMIT = "cafc17a192acf67903910a68aeb3c076c0907a4b"
ARCHIVE_SHA256 = "83cf257bc53427f2b1ea07015dbad298252c20546e916c5daa30a1cf78c45c1e"
ARCHIVE = Path(os.environ.get("OPENRC_METALFX_SOURCE_ARCHIVE", ROOT / ".tools/apple-metalfx-cache" / f"godot-{COMMIT}.zip"))
PATCH = ROOT / "tools/graphics/metalfx/patches/0001-metalfx-allocation-fallback.patch"
PATHS = (
    "servers/rendering/renderer_rd/effects/metal_fx.h",
    "servers/rendering/renderer_rd/effects/metal_fx.cpp",
    "servers/rendering/renderer_rd/renderer_scene_render_rd.cpp",
    "servers/rendering/renderer_rd/forward_clustered/render_forward_clustered.cpp",
    "servers/rendering/renderer_rd/storage_rd/render_scene_buffers_rd.cpp",
    "servers/rendering/renderer_viewport.cpp",
    "servers/rendering/renderer_viewport.h",
    "servers/rendering/rendering_server.cpp",
    "servers/rendering/rendering_server.h",
    "servers/rendering/rendering_server_default.h",
    "servers/rendering/storage/render_scene_buffers.h",
)


def cxx_block(source: str, start: int) -> str:
    """Return a balanced C++ brace block, ignoring strings and comments."""
    opening = source.index("{", start)
    index = opening
    depth = 0
    state = "code"
    while index < len(source):
        char = source[index]
        following = source[index + 1:index + 2]
        if state == "code":
            if char == "/" and following == "/":
                state = "line"
                index += 1
            elif char == "/" and following == "*":
                state = "block"
                index += 1
            elif char in ('"', "'"):
                state = char
            elif char == "{":
                depth += 1
            elif char == "}":
                depth -= 1
                if depth == 0:
                    return source[opening:index + 1]
        elif state == "line":
            if char == "\n":
                state = "code"
        elif state == "block":
            if char == "*" and following == "/":
                state = "code"
                index += 1
        elif char == "\\":
            index += 1
        elif char == state:
            state = "code"
        index += 1
    raise ValueError("unclosed C++ block")


def cxx_function(source: str, signature: str) -> str:
    start = source.index(signature)
    opening = source.index("{", start)
    return source[start:opening] + cxx_block(source, opening)


FACTORY_STUB = r'''
#include <cassert>
#include <cstdio>
#include <initializer_list>
#define DEV_ASSERT(x) assert(x)
#define memnew(x) new x
enum class Failure { NONE, ALLOC, INIT, SCALER };
static Failure failure = Failure::NONE;
static int temporal_setters = 0;
namespace NS {
using UInteger = unsigned long;
template<class T> struct SharedPtr {
    T *value;
    explicit SharedPtr(T *p) : value(p) {}
    ~SharedPtr() { delete value; }
    explicit operator bool() const { return value != nullptr; }
    T *operator->() const { return value; }
};
template<class T> SharedPtr<T> TransferPtr(T *p) { return SharedPtr<T>(p); }
}
namespace MTL { struct Device {}; using PixelFormat = int; }
namespace MTLFX {
struct SpatialScalerBase { virtual ~SpatialScalerBase() = default; };
struct TemporalScalerBase {
    virtual ~TemporalScalerBase() = default;
    void setMotionVectorScaleX(double) { ++temporal_setters; }
    void setMotionVectorScaleY(double) { ++temporal_setters; }
    void setDepthReversed(bool value) { assert(value); ++temporal_setters; }
};
constexpr int SpatialScalerColorProcessingModeLinear = 1;
struct SpatialScalerDescriptor {
    static SpatialScalerDescriptor *alloc() { return failure == Failure::ALLOC ? nullptr : new SpatialScalerDescriptor; }
    SpatialScalerDescriptor *init() { if (failure == Failure::INIT) { delete this; return nullptr; } return this; }
    void setInputWidth(NS::UInteger) {} void setInputHeight(NS::UInteger) {}
    void setOutputWidth(NS::UInteger) {} void setOutputHeight(NS::UInteger) {}
    void setColorTextureFormat(int) {} void setOutputTextureFormat(int) {} void setColorProcessingMode(int) {}
    SpatialScalerBase *newSpatialScaler(MTL::Device *) { return failure == Failure::SCALER ? nullptr : new SpatialScalerBase; }
};
struct TemporalScalerDescriptor {
    static TemporalScalerDescriptor *alloc() { return failure == Failure::ALLOC ? nullptr : new TemporalScalerDescriptor; }
    TemporalScalerDescriptor *init() { if (failure == Failure::INIT) { delete this; return nullptr; } return this; }
    void setInputWidth(NS::UInteger) {} void setInputHeight(NS::UInteger) {}
    void setOutputWidth(NS::UInteger) {} void setOutputHeight(NS::UInteger) {}
    void setColorTextureFormat(int) {} void setDepthTextureFormat(int) {} void setMotionTextureFormat(int) {}
    void setAutoExposureEnabled(bool) {} void setOutputTextureFormat(int) {}
    TemporalScalerBase *newTemporalScaler(MTL::Device *) { return failure == Failure::SCALER ? nullptr : new TemporalScalerBase; }
};
}
struct PixelFormats { int getMTLPixelFormat(int value) { return value; } };
struct RenderingDeviceDriverMetal {
    PixelFormats formats; MTL::Device device;
    PixelFormats &get_pixel_formats() { return formats; }
    MTL::Device *get_device() { return &device; }
};
struct RD {
    enum { SUPPORTS_METALFX_SPATIAL, SUPPORTS_METALFX_TEMPORAL };
    static RD *get_singleton() { static RD value; return &value; }
    bool has_feature(int) { return true; }
    void *get_device_driver() { static RenderingDeviceDriverMetal driver; return &driver; }
};
struct Extent { int width = 960; int height = 540; };
struct Scale { double x = 960; double y = 540; };
namespace RendererRD {
@CONTEXTS@
class MFXSpatialEffect {
public:
    struct CreateParams { Extent input_size, output_size; int input_format = 0, output_format = 0; };
    MFXSpatialContext *create_context(CreateParams) const;
};
class MFXTemporalEffect {
public:
    struct CreateParams { Extent input_size, output_size; int input_format = 0, depth_format = 0;
        int motion_format = 0, output_format = 0; Scale motion_vector_scale; };
    MFXTemporalContext *create_context(CreateParams) const;
};
MFXSpatialContext::~MFXSpatialContext() { delete scaler; }
MFXTemporalContext::~MFXTemporalContext() { delete scaler; }
}
using namespace RendererRD;
@SPATIAL_FACTORY@
@TEMPORAL_FACTORY@
int main() {
    MFXSpatialEffect spatial; MFXTemporalEffect temporal;
    for (Failure f : {Failure::ALLOC, Failure::INIT, Failure::SCALER, Failure::NONE}) {
        failure = f; temporal_setters = 0;
        auto *s = spatial.create_context({});
        auto *t = temporal.create_context({});
        auto expected = f == Failure::NONE ? MFXAllocationStatus::SCALER_CREATED :
                        f == Failure::SCALER ? MFXAllocationStatus::SCALER_UNAVAILABLE : MFXAllocationStatus::DESCRIPTOR_UNAVAILABLE;
        assert(s && t && s->allocation_status == expected && t->allocation_status == expected);
        assert(s->is_usable() == (f == Failure::NONE));
        assert(t->is_usable() == (f == Failure::NONE));
        assert(temporal_setters == (f == Failure::NONE ? 3 : 0));
        delete s; delete t;
    }
    std::puts("factory allocation controls passed");
}
'''


TEMPORAL_STUB = r'''
#include <cassert>
#include <cstdint>
#include <cstdio>
#include <vector>
#define WARN_PRINT_ONCE(message) ((void)0)
struct RID { int value = 0; };
struct Size { int width = 960, height = 540; };
struct Point2i {};
struct Rect2i { Size size; Rect2i(Point2i, Size p_size) : size(p_size) {} };
struct Vector2 { float x = 0, y = 0; };
struct Buffers {
    uint32_t views = 2;
    uint32_t get_view_count() const { return views; }
    Size get_internal_size() const { return {960, 540}; }
    Size get_target_size() const { return {1920, 1080}; }
    int get_base_data_format() const { return 1; }
    int get_depth_format(bool, bool, bool) const { return 2; }
    int get_velocity_format() const { return 3; }
    bool get_can_be_storage() const { return true; }
    RID get_internal_texture(uint32_t view) const { return {int(10 + view)}; }
    RID get_depth_texture(uint32_t view) const { return {int(20 + view)}; }
    RID get_velocity_buffer(bool, uint32_t view) const { return {int(30 + view)}; }
    RID get_upscaled_texture(uint32_t view) const { return {int(40 + view)}; }
    void set_metalfx_status(const char *provider, const char *, const char *) { assert(provider); }
};
namespace RendererRD {
struct MFXTemporalContext { bool usable = false; int allocation_status = 0, submission_status = 0; bool is_usable() const { return usable; } };
inline const char *mfx_allocation_status_name(int) { return "status"; }
inline const char *mfx_submission_status_name(int) { return "status"; }
class MFXTemporalEffect {
public:
    struct CreateParams { Size input_size, output_size; int input_format = 0, depth_format = 0;
        int motion_format = 0, reactive_format = 0, output_format = 0; Size motion_vector_scale; };
    struct Params { RID src, depth, motion, exposure, dst; Vector2 jitter_offset; bool reset = false; };
    mutable int allocations = 0; MFXTemporalContext *next = nullptr;
    std::vector<Params> submitted; int fail_view = -1;
    MFXTemporalContext *create_context(CreateParams) const { ++allocations; return next; }
    bool process(MFXTemporalContext *context, Params params) {
        assert(context && context->is_usable());
        if (params.dst.value == fail_view) { context->usable = false; return false; }
        submitted.push_back(params); return true;
    }
};
}
class RenderForwardClustered {
public:
    struct RenderBufferDataForwardClustered {
        Buffers *render_buffers;
        RendererRD::MFXTemporalContext *mfx_temporal_context = nullptr;
        bool ensure_mfx_temporal(RendererRD::MFXTemporalEffect *p_effect);
    };
};
struct FramebufferCacheRD {
    static FramebufferCacheRD *get_singleton() { static FramebufferCacheRD cache; return &cache; }
    RID get_cache(RID target) { return {target.value + 100}; }
};
struct CopyEffects {
    struct Call { RID src, target; Rect2i rect; };
    std::vector<Call> calls;
    void copy_to_fb_rect(RID src, RID target, Rect2i rect) { calls.push_back({src, target, rect}); }
};
@ENSURE@
int main() {
    Buffers storage; Buffers *rb = &storage;
    RendererRD::MFXTemporalContext failed, good; good.usable = true;
    RendererRD::MFXTemporalEffect effect; RendererRD::MFXTemporalEffect *mfx_temporal_effect = &effect;
    RenderForwardClustered::RenderBufferDataForwardClustered data{rb};
    effect.next = &failed;
    bool reset = data.ensure_mfx_temporal(&effect);
    assert(reset && !data.mfx_temporal_context->is_usable() && effect.allocations == 1);
    assert(!data.ensure_mfx_temporal(&effect) && effect.allocations == 1);
    CopyEffects copy; CopyEffects *copy_effects = &copy;
    RID exposure; Vector2 jitter;
    auto run = [&](RendererRD::MFXTemporalContext *context) {
@TEMPORAL_LOOP@
    };
    run(data.mfx_temporal_context);
    assert(effect.submitted.empty() && copy.calls.size() == 2);
    for (int view = 0; view < 2; ++view) {
        assert(copy.calls[view].src.value == 10 + view && copy.calls[view].target.value == 140 + view);
        assert(copy.calls[view].rect.size.width == 1920 && copy.calls[view].rect.size.height == 1080);
    }
    copy.calls.clear(); run(nullptr);
    assert(effect.submitted.empty() && copy.calls.size() == 2);
    copy.calls.clear(); data.mfx_temporal_context = nullptr; effect.next = &good;
    reset = data.ensure_mfx_temporal(&effect); assert(reset && effect.allocations == 2);
    run(data.mfx_temporal_context);
    assert(copy.calls.empty() && effect.submitted.size() == 2);
    assert(effect.submitted[0].reset && effect.submitted[1].reset);
    assert(effect.submitted[0].dst.value == 40 && effect.submitted[1].dst.value == 41);
    effect.submitted.clear(); reset = data.ensure_mfx_temporal(&effect); assert(!reset);
    run(data.mfx_temporal_context); assert(!effect.submitted[0].reset && !effect.submitted[1].reset);
    effect.submitted.clear(); effect.fail_view = 41; run(&good);
    assert(effect.submitted.size() == 1 && copy.calls.size() == 2 && !good.usable);
    std::puts("temporal fallback and reset controls passed");
}
'''


SPATIAL_STUB = r'''
#include <cassert>
#include <cstdint>
#include <cstdio>
#include <string>
#include <vector>
#define METAL_ENABLED 1
#define SNAME(value) value
#define WARN_PRINT_ONCE(message) ((void)0)
template<class T> using Vector = std::vector<T>;
struct RID { int value = 0; };
struct Size2i { int width = 1920, height = 1080; };
struct Point2i {};
struct Rect2 {};
struct Rect2i { Size2i size; Rect2i(Point2i, Size2i p_size) : size(p_size) {} };
namespace RSE { enum { VIEWPORT_SCALING_3D_MODE_NEAREST = 1, VIEWPORT_SCALING_3D_MODE_METALFX_SPATIAL = 2 }; }
namespace RendererRD {
struct MFXSpatialContext { bool usable = false; int allocation_status = 0, submission_status = 0; bool is_usable() const { return usable; } };
inline const char *mfx_allocation_status_name(int) { return "status"; }
inline const char *mfx_submission_status_name(int) { return "status"; }
}
struct Buffers {
    bool valid = true; uint32_t views = 2; RendererRD::MFXSpatialContext *context = nullptr;
    bool is_valid() const { return valid; }
    Buffers *operator->() { return this; }
    RendererRD::MFXSpatialContext *get_mfx_spatial_context() { return context; }
    void set_metalfx_status(const char *provider, const char *, const char *) { assert(provider); }
    uint32_t get_view_count() const { return views; }
    Size2i get_target_size() const { return {}; }
    RID get_texture_slice(const char *scope, const char *, uint32_t view, int) const {
        return {int((std::string(scope) == "SMAA" ? 20 : 10) + view)};
    }
    RID get_texture(const char *scope, const char *) const { return {std::string(scope) == "SMAA" ? 20 : 10}; }
};
struct SpatialUpscaler {
    int ensured = 0, fail_view = -1; std::vector<RID> sources, targets;
    const char *get_label() const { return "upscaler"; }
    void ensure_context(Buffers &) { ++ensured; }
    void process(Buffers &, RID src, RID dst) { sources.push_back(src); targets.push_back(dst); }
    bool try_process(Buffers &rb, RID src, RID dst) {
        if (dst.value == fail_view) { rb.context->usable = false; return false; }
        process(rb, src, dst); return true;
    }
};
struct TextureStorage {
    bool resolved = false;
    RID render_target_get_rd_texture_slice(RID, uint32_t view) { return {int(100 + view)}; }
    RID render_target_get_rd_texture(RID) { return {200}; }
    RID render_target_get_rd_texture_msaa(RID) { return {201}; }
    void render_target_set_msaa_needs_resolve(RID, bool value) { resolved = value; }
};
struct RD {
    struct FramebufferPass { Vector<int> color_attachments; };
    int begun = 0, ended = 0;
    static RD *get_singleton() { static RD device; return &device; }
    void draw_command_begin_label(const char *) { ++begun; }
    void draw_command_end_label() { ++ended; }
};
struct FramebufferCacheRD {
    static FramebufferCacheRD *get_singleton() { static FramebufferCacheRD cache; return &cache; }
    RID get_cache_multipass(Vector<RID> targets, Vector<RD::FramebufferPass> passes, uint32_t views) {
        assert(targets.size() == 1 && targets[0].value == 200 && passes.size() == 1);
        assert(passes[0].color_attachments.size() == 1 && passes[0].color_attachments[0] == 0);
        return {int(300 + views)};
    }
    RID get_cache(RID target) { assert(target.value == 201); return {400}; }
};
struct CopyEffects {
    struct Call { RID src, dst; bool multiview, bilinear; Size2i size; };
    std::vector<Call> calls;
    void copy_to_fb_rect(RID src, RID dst, Rect2i rect, bool = false, bool = false, bool = false,
            bool = false, RID = {}, bool multiview = false, bool = false, bool = false, bool = false,
            Rect2 = {}, float = 1.0f, bool bilinear = true) {
        calls.push_back({src, dst, multiview, bilinear, rect.size});
    }
};
int main() {
    Buffers rb; bool using_scaling_pass = true, use_smaa = true, dest_is_msaa_2d = false;
    int scale_mode = RSE::VIEWPORT_SCALING_3D_MODE_METALFX_SPATIAL; RID render_target;
    TextureStorage storage; TextureStorage *texture_storage = &storage;
    CopyEffects copy; CopyEffects *copy_effects = &copy;
    SpatialUpscaler metal, fsr; SpatialUpscaler *mfx_spatial = &metal;
    SpatialUpscaler *spatial_upscaler = mfx_spatial;
    RendererRD::MFXSpatialContext failed, good; good.usable = true;
    auto run = [&]() {
@SPATIAL_BLOCK@
    };
    rb.context = &failed; run();
    assert(metal.ensured == 1 && metal.sources.empty() && copy.calls.size() == 1);
    assert(copy.calls[0].src.value == 20 && copy.calls[0].dst.value == 302);
    assert(copy.calls[0].multiview && copy.calls[0].bilinear);
    assert(copy.calls[0].size.width == 1920 && copy.calls[0].size.height == 1080);
    copy.calls.clear(); rb.views = 1; rb.context = nullptr; use_smaa = false; dest_is_msaa_2d = true;
    spatial_upscaler = mfx_spatial; run();
    assert(copy.calls.size() == 2 && copy.calls[0].src.value == 10 && copy.calls[0].dst.value == 301);
    assert(!copy.calls[0].multiview && copy.calls[0].bilinear && copy.calls[1].dst.value == 400 && storage.resolved);
    copy.calls.clear(); rb.views = 2; rb.context = &good; dest_is_msaa_2d = false; spatial_upscaler = mfx_spatial; run();
    assert(copy.calls.empty() && metal.sources.size() == 2 && metal.targets[0].value == 100 && metal.targets[1].value == 101);
    copy.calls.clear(); rb.context = &failed; spatial_upscaler = &fsr; run();
    assert(copy.calls.empty() && fsr.ensured == 1 && fsr.sources.size() == 2);
    metal.fail_view = 101; rb.context = &good; spatial_upscaler = mfx_spatial; run();
    assert(!good.usable && copy.calls.size() == 1 && copy.calls[0].dst.value == 302);
    assert(RD::get_singleton()->begun == 5 && RD::get_singleton()->ended == 5);
    std::puts("spatial fallback, multiview, MSAA and existing FSR controls passed");
}
'''


CALLBACK_STUB = r'''
#include <cassert>
#include <cstdint>
#include <cstdio>
#include <vector>
using Error = int;
constexpr Error OK = 0;
static int allocations = 0;
template<class T> T *tracked_new(T *p) { ++allocations; return p; }
template<class T> void tracked_delete(T *p) { --allocations; delete p; }
#define memnew(x) tracked_new(new x)
#define memdelete(x) tracked_delete(x)
#define ERR_FAIL_COND_V(cond, value) do { if (cond) return value; } while (false)
struct RID { int value = 0; bool is_valid() const { return value != 0; } };
struct Vector2 { double x = 0, y = 0; };
template<class T> struct Ref { T *value; T *operator->() const { return value; } };
template<class T> struct VectorView { VectorView(T *, unsigned) {} };
namespace RDC { constexpr int DRIVER_RESOURCE_TEXTURE = 0; }
namespace MTL { struct Texture {}; }
struct Resource { int refs = 1; void retain() { ++refs; } void release() { assert(refs > 0); --refs; } };
namespace MTLFX {
struct SpatialScalerBase : Resource {
    void setFence(int) {} void setColorTexture(MTL::Texture *) {} void setOutputTexture(MTL::Texture *) {}
};
struct TemporalScalerBase : Resource {
    void setFence(int) {} void setReset(bool) {} void setColorTexture(MTL::Texture *) {}
    void setDepthTexture(MTL::Texture *) {} void setMotionTexture(MTL::Texture *) {}
    void setExposureTexture(MTL::Texture *) {} void setJitterOffsetX(double) {} void setJitterOffsetY(double) {}
    void setOutputTexture(MTL::Texture *) {}
};
struct SpatialScaler : SpatialScalerBase { void encodeToCommandBuffer(int) {} };
struct TemporalScaler : TemporalScalerBase { void encodeToCommandBuffer(int) {} };
}
struct RDD {
    struct TextureID { uintptr_t id = 0; TextureID() = default; explicit TextureID(uintptr_t p) : id(p) {} };
    struct CommandBufferID { uintptr_t id; };
    using DriverCallback = void (*)(RDD *, CommandBufferID, void *);
};
struct MDCommandBufferBase {
    Resource *held = nullptr;
    void end() {} int external_pass_fence() { return 0; }
    template<class T> void retain_resource(T *p) { assert(!held); held = p; p->retain(); }
    void release_resource() { held->release(); held = nullptr; }
};
namespace MTL3 { struct MDCommandBuffer : MDCommandBufferBase { int get_command_buffer() { return 0; } }; }
struct RD {
    enum { CALLBACK_RESOURCE_USAGE_TEXTURE_SAMPLE, CALLBACK_RESOURCE_USAGE_STORAGE_IMAGE_READ_WRITE };
    struct CallbackResource { RID rid; int usage; };
    bool fail = false; RDD::DriverCallback pending = nullptr; void *data = nullptr;
    static RD *get_singleton() { static RD value; return &value; }
    uintptr_t get_driver_resource(int, RID rid) { return uintptr_t(rid.value); }
    Error driver_callback_add(RDD::DriverCallback callback, void *userdata, VectorView<CallbackResource>) {
        if (fail) return 1;
        assert(!pending); pending = callback; data = userdata; return OK;
    }
    void run(MTL3::MDCommandBuffer &cmd) {
        auto cb = pending; void *payload = data; pending = nullptr; data = nullptr;
        assert(cb); cb(nullptr, RDD::CommandBufferID{reinterpret_cast<uintptr_t>(&cmd)}, payload);
    }
};
namespace RendererRD {
@CONTEXTS@
struct RenderSceneBuffersRD {
    MFXSpatialContext *context = nullptr;
    MFXSpatialContext *get_mfx_spatial_context() { return context; }
};
class MFXSpatialEffect {
public:
    struct CallbackArgs @SPATIAL_ARGS@;
    static void callback(RDD *, RDD::CommandBufferID, CallbackArgs *);
    bool try_process(Ref<RenderSceneBuffersRD>, RID, RID);
};
class MFXTemporalEffect {
public:
    struct CallbackArgs @TEMPORAL_ARGS@;
    struct Params { RID src, depth, motion, exposure, dst; Vector2 jitter_offset; bool reset = false; };
    static void callback(RDD *, RDD::CommandBufferID, CallbackArgs *);
    bool process(MFXTemporalContext *, Params);
};
}
using namespace RendererRD;
@SPATIAL_DESTRUCTOR@
@TEMPORAL_DESTRUCTOR@
@SPATIAL_PROCESS@
@TEMPORAL_PROCESS@
@SPATIAL_CALLBACK@
@TEMPORAL_CALLBACK@
int main() {
    RD *rd = RD::get_singleton(); MTL3::MDCommandBuffer cmd;
    MTLFX::SpatialScaler spatial_scaler;
    MFXSpatialContext spatial; spatial.scaler = &spatial_scaler; spatial.allocation_status = MFXAllocationStatus::SCALER_CREATED;
    RenderSceneBuffersRD buffers; buffers.context = &spatial;
    MFXSpatialEffect spatial_effect;
    rd->fail = true;
    assert(!spatial_effect.try_process({&buffers}, {1}, {2}));
    assert(spatial.submission_status == MFXSubmissionStatus::ENQUEUE_FAILED && spatial_scaler.refs == 1 && allocations == 0);
    rd->fail = false; spatial.submission_status = MFXSubmissionStatus::NOT_ATTEMPTED;
    assert(spatial_effect.try_process({&buffers}, {1}, {2}));
    assert(spatial_scaler.refs == 2 && allocations == 1);
    spatial_scaler.release(); spatial.scaler = nullptr; // context goes away before callback
    rd->run(cmd); assert(spatial_scaler.refs == 1 && allocations == 0); cmd.release_resource(); assert(spatial_scaler.refs == 0);
    MTLFX::TemporalScaler temporal_scaler;
    MFXTemporalContext temporal; temporal.scaler = &temporal_scaler; temporal.allocation_status = MFXAllocationStatus::SCALER_CREATED;
    MFXTemporalEffect temporal_effect; MFXTemporalEffect::Params params; params.src = {1}; params.depth = {2}; params.motion = {3}; params.dst = {4};
    rd->fail = true;
    assert(!temporal_effect.process(&temporal, params));
    assert(temporal.submission_status == MFXSubmissionStatus::ENQUEUE_FAILED && temporal_scaler.refs == 1 && allocations == 0);
    rd->fail = false; temporal.submission_status = MFXSubmissionStatus::NOT_ATTEMPTED;
    assert(temporal_effect.process(&temporal, params));
    assert(temporal_scaler.refs == 2 && allocations == 1);
    temporal_scaler.release(); temporal.scaler = nullptr;
    rd->run(cmd); assert(temporal_scaler.refs == 1 && allocations == 0); cmd.release_resource(); assert(temporal_scaler.refs == 0);
    std::puts("callback failure and lifetime controls passed");
}
'''


STATUS_STUB = r'''
#include <cassert>
#include <cstdint>
#include <string>
#include <unordered_map>
#include <variant>
#define GDCLASS(a, b)
#define ERR_FAIL_NULL_V(p, value) do { if (!(p)) return value; } while (false)
using String = std::string;
using Value = std::variant<int, int64_t, bool, String>;
struct Dictionary : std::unordered_map<String, Value> {};
struct RefCounted {};
namespace RSE { enum ViewportAnisotropicFiltering { NONE }; }
struct RenderSceneBuffersConfiguration {};
@RENDER_SCENE_BUFFERS@
struct TestBuffers : RenderSceneBuffers {
    void configure(const RenderSceneBuffersConfiguration *) override {}
    void set_fsr_sharpness(float) override {} void set_texture_mipmap_bias(float) override {}
    void set_anisotropic_filtering_level(RSE::ViewportAnisotropicFiltering) override {}
    void set_use_debanding(bool) override {}
};
template<class T> struct Ref {
    T *value = nullptr;
    bool is_valid() const { return value != nullptr; }
    T *operator->() const { return value; }
};
struct RID { int id = 0; };
class RendererViewport {
public:
    struct Viewport { Ref<RenderSceneBuffers> render_buffers; uint64_t metal_fx_generation = 0; int scaling_3d_mode = 3; };
    struct Owner { Viewport *viewport = nullptr; Viewport *get_or_null(RID) const { return viewport; } } viewport_owner;
    Dictionary viewport_get_metalfx_status(RID) const;
};
@VIEWPORT_GETTER@
int main() {
    RendererViewport viewport; RendererViewport::Viewport state; viewport.viewport_owner.viewport = &state;
    auto unavailable = viewport.viewport_get_metalfx_status({});
    assert(!std::get<bool>(unavailable.at("render_buffers_available")));
    assert(std::get<int>(unavailable.at("configured_mode")) == -1);
    assert(std::get<String>(unavailable.at("submission")) == "not_attempted");
    TestBuffers buffers; state.render_buffers.value = &buffers; state.metal_fx_generation = 7;
    buffers.set_metalfx_configured_mode(3); buffers.set_metalfx_status("spatial", "scaler_unavailable", "not_attempted");
    auto failed = viewport.viewport_get_metalfx_status({});
    assert(std::get<int64_t>(failed.at("generation")) == 7 && std::get<int>(failed.at("requested_mode")) == 3);
    assert(std::get<int>(failed.at("configured_mode")) == 3 && std::get<String>(failed.at("provider")) == "spatial");
    assert(std::get<String>(failed.at("allocation")) == "scaler_unavailable");
    buffers.set_metalfx_status("temporal", "created", "enqueue_failed");
    auto enqueue = viewport.viewport_get_metalfx_status({});
    assert(std::get<String>(enqueue.at("submission")) == "enqueue_failed");
    ++state.metal_fx_generation; buffers.reset_metalfx_status(); buffers.set_metalfx_configured_mode(3);
    auto fresh = viewport.viewport_get_metalfx_status({});
    assert(std::get<int64_t>(fresh.at("generation")) == 8);
    assert(std::get<String>(fresh.at("provider")) == "none" && std::get<String>(fresh.at("allocation")) == "not_attempted");
    assert(std::get<String>(fresh.at("submission")) == "not_attempted");
    return 0;
}
'''

class MetalFXPatchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        if not ARCHIVE.is_file():
            raise RuntimeError(f"Pinned engine archive is required: {ARCHIVE}")
        digest = hashlib.sha256()
        with ARCHIVE.open("rb") as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(block)
        if digest.hexdigest() != ARCHIVE_SHA256:
            raise RuntimeError("Pinned engine archive SHA-256 differs")
        cls.temp = tempfile.TemporaryDirectory(prefix="openrc-metalfx-patch-")
        cls.base = Path(cls.temp.name)
        with zipfile.ZipFile(ARCHIVE) as archive:
            for name in PATHS:
                destination = cls.base / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(archive.read(f"godot-{COMMIT}/{name}"))
        subprocess.run(["git", "apply", "--check", str(PATCH)], cwd=cls.base, check=True, capture_output=True)
        subprocess.run(["git", "apply", str(PATCH)], cwd=cls.base, check=True, capture_output=True)
        cls.header = (cls.base / PATHS[0]).read_text(encoding="utf-8")
        cls.metal = (cls.base / PATHS[1]).read_text(encoding="utf-8")
        cls.spatial = (cls.base / PATHS[2]).read_text(encoding="utf-8")
        cls.temporal = (cls.base / PATHS[3]).read_text(encoding="utf-8")

    @classmethod
    def tearDownClass(cls) -> None:
        cls.temp.cleanup()

    def compile_and_run(self, source: str, name: str) -> str:
        compiler = shutil.which("g++") or shutil.which("clang++")
        if not compiler:
            self.fail("A C++17 compiler is required for the focused engine patch checks")
        cpp = self.base / (name + ".cpp")
        binary = self.base / (name + (".exe" if os.name == "nt" else ""))
        cpp.write_text(source, encoding="utf-8")
        compiled = subprocess.run([compiler, "-std=c++17", "-Wall", "-Wextra", "-Werror", "-Wno-unused-parameter", str(cpp), "-o", str(binary)],
                                  cwd=self.base, capture_output=True, text=True)
        self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
        return subprocess.run([str(binary)], cwd=self.base, check=True, capture_output=True, text=True).stdout

    def test_patch_applies_only_to_unmodified_pinned_source(self) -> None:
        subprocess.run(["git", "apply", "--reverse", "--check", str(PATCH)], cwd=self.base, check=True, capture_output=True)
        target = self.base / PATHS[1]
        original = target.read_bytes()
        try:
            target.write_bytes(original.replace(b"newTemporalScaler(dev)", b"newTemporalScaler(other)", 1))
            refused = subprocess.run(["git", "apply", "--reverse", "--check", str(PATCH)], cwd=self.base, capture_output=True)
            self.assertNotEqual(refused.returncode, 0)
        finally:
            target.write_bytes(original)

    def test_factories_reject_nil_without_dereferencing_it(self) -> None:
        start = self.header.index("// Synchronous factory outcome")
        spatial_end = self.header.index("class MFXSpatialEffect", start)
        temporal_start = self.header.index("struct MFXTemporalContext")
        temporal_end = self.header.index("class MFXTemporalEffect", temporal_start)
        contexts = self.header[start:spatial_end] + self.header[temporal_start:temporal_end]
        spatial = cxx_function(self.metal, "MFXSpatialContext *MFXSpatialEffect::create_context(")
        temporal = cxx_function(self.metal, "MFXTemporalContext *MFXTemporalEffect::create_context(")
        source = FACTORY_STUB.replace("@CONTEXTS@", contexts).replace("@SPATIAL_FACTORY@", spatial).replace("@TEMPORAL_FACTORY@", temporal)
        self.assertIn("factory allocation controls passed", self.compile_and_run(source, "factory_controls"))

    def test_viewport_status_resets_and_setters_reconfigure(self) -> None:
        base = (self.base / "servers/rendering/storage/render_scene_buffers.h").read_text(encoding="utf-8")
        viewport = (self.base / "servers/rendering/renderer_viewport.cpp").read_text(encoding="utf-8")
        declaration = "class RenderSceneBuffers : public RefCounted " + cxx_block(base, base.index("class RenderSceneBuffers :")) + ";"
        getter = cxx_function(viewport, "Dictionary RendererViewport::viewport_get_metalfx_status(")
        source = STATUS_STUB.replace("@RENDER_SCENE_BUFFERS@", declaration).replace("@VIEWPORT_GETTER@", getter)
        self.compile_and_run(source, "status_controls")
        configure = cxx_function(viewport, "void RendererViewport::_configure_3d_render_buffers(")
        self.assertLess(configure.index("++p_viewport->metal_fx_generation"), configure.index("reset_metalfx_status()"))
        self.assertLess(configure.index("->configure(&rb_config)"), configure.index("set_metalfx_configured_mode"))
        for signature in ("void RendererViewport::viewport_set_scaling_3d_mode(",
                          "void RendererViewport::viewport_set_scaling_3d_scale(",
                          "void RendererViewport::_viewport_set_size("):
            self.assertIn("_configure_3d_render_buffers(", cxx_function(viewport, signature))
        xr = cxx_function(viewport, "void RendererViewport::viewport_set_use_xr(")
        self.assertIn("++viewport->metal_fx_generation", xr)
        self.assertIn("reset_metalfx_status()", xr)
        disabled = cxx_function(viewport, "void RendererViewport::viewport_set_disable_3d(")
        self.assertIn("++viewport->metal_fx_generation", disabled)
        self.assertIn("reset_metalfx_observation()", disabled)
        binding = (self.base / "servers/rendering/rendering_server.cpp").read_text(encoding="utf-8")
        threaded = (self.base / "servers/rendering/rendering_server_default.h").read_text(encoding="utf-8")
        self.assertIn('D_METHOD("viewport_get_metalfx_status", "viewport")', binding)
        self.assertIn("FUNC1RC(Dictionary, viewport_get_metalfx_status, RID)", threaded)

    def test_enqueue_failure_and_callback_lifetime(self) -> None:
        start = self.header.index("// Synchronous factory outcome")
        spatial_end = self.header.index("class MFXSpatialEffect", start)
        temporal_start = self.header.index("struct MFXTemporalContext")
        temporal_end = self.header.index("class MFXTemporalEffect", temporal_start)
        contexts = self.header[start:spatial_end] + self.header[temporal_start:temporal_end]
        spatial_args = cxx_block(self.header, self.header.index("struct CallbackArgs", spatial_end))
        temporal_args = cxx_block(self.header, self.header.index("struct CallbackArgs", temporal_end))
        parts = {"@CONTEXTS@": contexts, "@SPATIAL_ARGS@": spatial_args, "@TEMPORAL_ARGS@": temporal_args,
                 "@SPATIAL_DESTRUCTOR@": cxx_function(self.metal, "MFXSpatialContext::~MFXSpatialContext("),
                 "@TEMPORAL_DESTRUCTOR@": cxx_function(self.metal, "MFXTemporalContext::~MFXTemporalContext("),
                 "@SPATIAL_PROCESS@": cxx_function(self.metal, "bool MFXSpatialEffect::try_process("),
                 "@TEMPORAL_PROCESS@": cxx_function(self.metal, "bool MFXTemporalEffect::process("),
                 "@SPATIAL_CALLBACK@": cxx_function(self.metal, "void MFXSpatialEffect::callback("),
                 "@TEMPORAL_CALLBACK@": cxx_function(self.metal, "void MFXTemporalEffect::callback(")}
        source = CALLBACK_STUB
        for key, value in parts.items():
            source = source.replace(key, value)
        self.assertIn("callback failure and lifetime controls passed", self.compile_and_run(source, "callback_controls"))

    def test_temporal_fallback_writes_each_view_and_reset_remains_distinct(self) -> None:
        ensure = cxx_function(self.temporal, "bool RenderForwardClustered::RenderBufferDataForwardClustered::ensure_mfx_temporal(")
        branch = self.temporal.index("} else if (scale_type == SCALE_MFX)")
        start = self.temporal.index("bool submitted = context", branch)
        end = self.temporal.index("RD::get_singleton()->draw_command_end_label();", start)
        loop = self.temporal[start:end]
        source = TEMPORAL_STUB.replace("@ENSURE@", ensure).replace("@TEMPORAL_LOOP@", loop)
        self.assertIn("temporal fallback and reset controls passed", self.compile_and_run(source, "temporal_controls"))

    def test_spatial_fallback_writes_target_and_preserves_other_upscalers(self) -> None:
        start = self.spatial.index("if (rb.is_valid() && using_scaling_pass)")
        opening = self.spatial.index("{", start)
        block = self.spatial[start:opening] + cxx_block(self.spatial, opening)
        source = SPATIAL_STUB.replace("@SPATIAL_BLOCK@", block)
        self.assertIn("spatial fallback, multiview, MSAA and existing FSR controls passed",
                      self.compile_and_run(source, "spatial_controls"))


if __name__ == "__main__":
    unittest.main()
