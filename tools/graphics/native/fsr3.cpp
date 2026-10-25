// SPDX-License-Identifier: MIT
// Copyright (c) 2026 OpenRCsimulator contributors.
#include "fsr3.h"

#include "core/io/file_access.h"
#include "core/os/os.h"
#include "core/variant/dictionary.h"
#include "servers/rendering/rendering_device.h"
#include "servers/rendering/renderer_rd/uniform_set_cache_rd.h"

#if defined(WINDOWS_ENABLED) && defined(VULKAN_ENABLED)

#include "drivers/vulkan/godot_vulkan.h"
#include "thirdparty/amd-fsr3/ffx_api/ffx_api.h"
#include "thirdparty/amd-fsr3/ffx_api/ffx_upscale.h"
#include "thirdparty/amd-fsr3/ffx_api/vk/ffx_api_vk.h"

#include <atomic>
#include <mutex>
#include <string>
#include <vector>

namespace RendererRD {

struct FSR3ContextInternal {
	ffxContext context = nullptr;
	// The FFX API requires pointers in the creation chain to outlive the context.
	ffxCreateBackendVKDesc backend = {};
	ffxCreateContextDescUpscale description = {};
	VkDevice device = VK_NULL_HANDLE;
	Size2i internal_size;
	Size2i target_size;
	RID reactive_mask;
	std::atomic<bool> failed{ false };
	std::atomic<bool> has_successful_dispatch{ false };
	std::atomic<uint32_t> references{ 1 };
};

struct FSR3Api {
	std::mutex mutex;
	bool attempted = false;
	bool loaded = false;
	void *library = nullptr;
	PfnFfxCreateContext create_context = nullptr;
	PfnFfxDestroyContext destroy_context = nullptr;
	PfnFfxQuery query = nullptr;
	PfnFfxDispatch dispatch = nullptr;
	std::string provider_version;
};

static FSR3Api &get_fsr3_api() {
	static FSR3Api api;
	return api;
}

static std::atomic<bool> backend_failed{ false };
static std::atomic<uint64_t> contexts_created{ 0 };
static std::atomic<uint64_t> dispatches_succeeded{ 0 };
static std::atomic<uint32_t> last_return_code{ FFX_API_RETURN_OK };

static void record_backend_failure(uint32_t p_return_code) {
	last_return_code.store(p_return_code, std::memory_order_relaxed);
	backend_failed.store(true, std::memory_order_release);
}

static bool load_fsr3_api() {
	FSR3Api &api = get_fsr3_api();
	std::lock_guard<std::mutex> lock(api.mutex);
	if (api.attempted) {
		return api.loaded;
	}
	api.attempted = true;

	OS *os = OS::get_singleton();
	if (os == nullptr) {
		return false;
	}
	String library_path = os->get_executable_path().get_base_dir().path_join("amd_fidelityfx_vk.dll");
	if (!FileAccess::exists(library_path)) {
		return false; // Optional backend absent: the app keeps Native/FSR2 available.
	}
	if (os->open_dynamic_library(library_path, api.library) != OK) {
		WARN_PRINT("FSR3: could not load amd_fidelityfx_vk.dll beside the executable.");
		api.library = nullptr;
		return false;
	}

	void *symbol = nullptr;
	if (os->get_dynamic_library_symbol_handle(api.library, "ffxCreateContext", symbol) == OK) {
		api.create_context = reinterpret_cast<PfnFfxCreateContext>(symbol);
	}
	symbol = nullptr;
	if (os->get_dynamic_library_symbol_handle(api.library, "ffxDestroyContext", symbol) == OK) {
		api.destroy_context = reinterpret_cast<PfnFfxDestroyContext>(symbol);
	}
	symbol = nullptr;
	if (os->get_dynamic_library_symbol_handle(api.library, "ffxQuery", symbol, true) == OK) {
		api.query = reinterpret_cast<PfnFfxQuery>(symbol);
	}
	symbol = nullptr;
	if (os->get_dynamic_library_symbol_handle(api.library, "ffxDispatch", symbol) == OK) {
		api.dispatch = reinterpret_cast<PfnFfxDispatch>(symbol);
	}

	api.loaded = api.create_context != nullptr && api.destroy_context != nullptr && api.dispatch != nullptr;
	if (!api.loaded) {
		WARN_PRINT("FSR3: amd_fidelityfx_vk.dll is missing a required FFX API export.");
		os->close_dynamic_library(api.library);
		api.library = nullptr;
		api.create_context = nullptr;
		api.destroy_context = nullptr;
		api.query = nullptr;
		api.dispatch = nullptr;
	}
	return api.loaded;
}

static std::mutex retired_contexts_mutex;
static std::vector<FSR3ContextInternal *> retired_contexts;

static void destroy_context_objects(FSR3ContextInternal *p_internal) {
	FSR3Api &api = get_fsr3_api();
	if (p_internal->context != nullptr && api.destroy_context != nullptr) {
		ffxReturnCode_t result = api.destroy_context(&p_internal->context, nullptr);
		if (result != FFX_API_RETURN_OK) {
			WARN_PRINT(vformat("FSR3: context destruction failed (%d).", result));
		}
	}
	RenderingDevice *rd = RD::get_singleton();
	if (rd != nullptr && !p_internal->reactive_mask.is_null()) {
		rd->free_rid(p_internal->reactive_mask);
	}
	memdelete(p_internal);
}

static void destroy_context_internal(FSR3ContextInternal *p_internal) {
	if (p_internal->context != nullptr || !p_internal->reactive_mask.is_null()) {
		if (RenderingDevice *rd = RD::get_singleton()) {
			// The helper submits pending render-graph callbacks and waits for frame fences before
			// FidelityFX releases pipelines and images that may still be referenced by the GPU.
			rd->flush_and_wait_for_external_resources();
		}
	}
	destroy_context_objects(p_internal);
}

static void collect_retired_contexts() {
	std::vector<FSR3ContextInternal *> pending;
	{
		std::lock_guard<std::mutex> lock(retired_contexts_mutex);
		pending.swap(retired_contexts);
	}
	if (pending.empty()) {
		return;
	}
	RenderingDevice *rd = RD::get_singleton();
	if (rd != nullptr) {
		rd->flush_and_wait_for_external_resources();
	}
	for (FSR3ContextInternal *context : pending) {
		destroy_context_objects(context);
	}
}

static void release_context_internal(FSR3ContextInternal *p_internal, bool p_from_graph_callback) {
	if (p_internal->references.fetch_sub(1, std::memory_order_acq_rel) != 1) {
		return;
	}
	if (p_from_graph_callback) {
		// Never stall or destroy FFX objects while the current command buffer is being recorded.
		std::lock_guard<std::mutex> lock(retired_contexts_mutex);
		retired_contexts.push_back(p_internal);
		return;
	}
	destroy_context_internal(p_internal);
}

static bool make_api_resource(RID p_rid, uint32_t p_state, bool p_require_uav, FfxApiResource &r_resource) {
	if (p_rid.is_null()) {
		r_resource = {};
		return !p_require_uav;
	}
	RenderingDevice *rd = RD::get_singleton();
	ERR_FAIL_NULL_V(rd, false);
	RD::TextureFormat texture_format = rd->texture_get_format(p_rid);
	ERR_FAIL_COND_V(texture_format.texture_type != RD::TEXTURE_TYPE_2D || texture_format.array_layers != 1, false);

	VkImageUsageFlags vk_usage = VkImageUsageFlags(rd->get_driver_resource(RD::DRIVER_RESOURCE_TEXTURE_USAGE_FLAGS, p_rid));
	if (p_require_uav && (vk_usage & VK_IMAGE_USAGE_STORAGE_BIT) == 0) {
		ERR_PRINT("FSR3 output texture was not created with Vulkan storage-image usage.");
		return false;
	}
	VkFormat vk_format = VkFormat(rd->get_driver_resource(RD::DRIVER_RESOURCE_TEXTURE_DATA_FORMAT, p_rid));
	uint32_t ffx_format = ffxApiGetSurfaceFormatVK(vk_format);
	if (ffx_format == FFX_API_SURFACE_FORMAT_UNKNOWN) {
		ERR_PRINT("FSR3 encountered a Vulkan texture format unsupported by FidelityFX.");
		return false;
	}
	uint64_t native_image = rd->get_driver_resource(RD::DRIVER_RESOURCE_TEXTURE, p_rid);
	if (native_image == 0) {
		return false;
	}

	FfxApiResourceDescription description = {};
	description.type = FFX_API_RESOURCE_TYPE_TEXTURE2D;
	description.format = ffx_format;
	description.width = texture_format.width;
	description.height = texture_format.height;
	description.depth = 1;
	description.mipCount = texture_format.mipmaps;
	description.flags = FFX_API_RESOURCE_FLAGS_NONE;
	description.usage = FFX_API_RESOURCE_USAGE_READ_ONLY;
	if ((vk_usage & VK_IMAGE_USAGE_STORAGE_BIT) != 0) {
		description.usage |= FFX_API_RESOURCE_USAGE_UAV;
	}
	if (ffxApiIsDepthFormat(vk_format)) {
		description.usage |= FFX_API_RESOURCE_USAGE_DEPTHTARGET;
	}
	if (ffxApiIsStencilFormat(vk_format)) {
		description.usage |= FFX_API_RESOURCE_USAGE_STENCILTARGET;
	}
	void *image = reinterpret_cast<void *>(static_cast<uintptr_t>(native_image));
	r_resource = ffxApiGetResourceVK(image, description, p_state);
	return true;
}

struct FSR3Effect::DispatchPayload {
	FSR3ContextInternal *context = nullptr;
	FSR3Context::Parameters parameters;
	FfxApiResource color = {};
	FfxApiResource depth = {};
	FfxApiResource velocity = {};
	FfxApiResource reactive = {};
	FfxApiResource exposure = {};
	FfxApiResource output = {};
};

FSR3Context::~FSR3Context() {
	if (internal != nullptr) {
		release_context_internal(internal, false);
		internal = nullptr;
	}
}

FSR3Effect::FSR3Effect() {
	Vector<String> modes;
	modes.push_back("\n");
	modes.push_back("\n#define FSR3_PREPARE_REACTIVE 1\n");
	shaders.prepare.initialize(modes, "");
	shaders.prepare_version = shaders.prepare.version_create();
	for (uint32_t i = 0; i < 2; i++) {
		RID shader = shaders.prepare.version_get_shader(shaders.prepare_version, i);
		shaders.prepare_pipeline[i] = RD::get_singleton()->compute_pipeline_create(shader);
	}
}

FSR3Effect::~FSR3Effect() {
	collect_retired_contexts();
	if (RenderingDevice *rd = RD::get_singleton()) {
		for (RID &pipeline : shaders.prepare_pipeline) {
			if (!pipeline.is_null()) {
				rd->free_rid(pipeline);
			}
		}
	}
	shaders.prepare.version_free(shaders.prepare_version);
}

bool FSR3Effect::is_available() {
	if (backend_failed.load(std::memory_order_acquire)) {
		return false;
	}
	RenderingDevice *rd = RD::get_singleton();
	return rd != nullptr && rd->get_device_api_name().to_lower() == "vulkan" && load_fsr3_api();
}

Dictionary FSR3Effect::get_status() {
	Dictionary status;
	status["available"] = is_available();
	status["backend_failed"] = backend_failed.load(std::memory_order_acquire);
	status["contexts_created"] = int64_t(contexts_created.load(std::memory_order_relaxed));
	status["dispatches_succeeded"] = int64_t(dispatches_succeeded.load(std::memory_order_relaxed));
	status["last_return_code"] = int64_t(last_return_code.load(std::memory_order_relaxed));
	FSR3Api &api = get_fsr3_api();
	{
		std::lock_guard<std::mutex> lock(api.mutex);
		status["provider_version"] = String(api.provider_version.c_str());
	}
	return status;
}

FSR3Context *FSR3Effect::create_context(Size2i p_internal_size, Size2i p_target_size) {
	collect_retired_contexts();
	ERR_FAIL_COND_V(!is_available(), nullptr);
	ERR_FAIL_COND_V(p_internal_size.x <= 0 || p_internal_size.y <= 0 || p_target_size.x <= 0 || p_target_size.y <= 0, nullptr);

	RenderingDevice *rd = RD::get_singleton();
	uint64_t device_handle = rd->get_driver_resource(RD::DRIVER_RESOURCE_LOGICAL_DEVICE);
	uint64_t physical_device_handle = rd->get_driver_resource(RD::DRIVER_RESOURCE_PHYSICAL_DEVICE);
	ERR_FAIL_COND_V(device_handle == 0 || physical_device_handle == 0, nullptr);

	FSR3Context *context = memnew(FSR3Context);
	context->internal = memnew(FSR3ContextInternal);
	context->internal->device = (VkDevice)(uintptr_t)device_handle;
	context->internal->internal_size = p_internal_size;
	context->internal->target_size = p_target_size;

	ffxCreateBackendVKDesc &backend = context->internal->backend;
	backend.header.type = FFX_API_CREATE_CONTEXT_DESC_TYPE_BACKEND_VK;
	backend.vkDevice = context->internal->device;
	backend.vkPhysicalDevice = (VkPhysicalDevice)(uintptr_t)physical_device_handle;
	backend.vkDeviceProcAddr = vkGetDeviceProcAddr;

	ffxCreateContextDescUpscale &description = context->internal->description;
	description.header.type = FFX_API_CREATE_CONTEXT_DESC_TYPE_UPSCALE;
	description.header.pNext = &backend.header;
	description.flags = FFX_UPSCALE_ENABLE_HIGH_DYNAMIC_RANGE | FFX_UPSCALE_ENABLE_DEPTH_INVERTED;
	description.maxRenderSize = { uint32_t(p_internal_size.x), uint32_t(p_internal_size.y) };
	description.maxUpscaleSize = { uint32_t(p_target_size.x), uint32_t(p_target_size.y) };
	description.fpMessage = nullptr;

	FSR3Api &api = get_fsr3_api();
	ffxReturnCode_t result = api.create_context(&context->internal->context, &description.header, nullptr);
	if (result != FFX_API_RETURN_OK) {
		record_backend_failure(result);
		WARN_PRINT(vformat("FSR3: FFX context creation failed (%d).", result));
		context->internal->context = nullptr;
		memdelete(context);
		return nullptr;
	}
	last_return_code.store(FFX_API_RETURN_OK, std::memory_order_relaxed);
	if (api.query != nullptr) {
		ffxQueryGetProviderVersion provider_query = {};
		provider_query.header.type = FFX_API_QUERY_DESC_TYPE_GET_PROVIDER_VERSION;
		ffxReturnCode_t query_result = api.query(&context->internal->context, &provider_query.header);
		if (query_result == FFX_API_RETURN_OK && provider_query.versionName != nullptr) {
			std::lock_guard<std::mutex> lock(api.mutex);
			api.provider_version = provider_query.versionName;
		}
	}

	RD::TextureFormat mask_format = {};
	mask_format.texture_type = RD::TEXTURE_TYPE_2D;
	mask_format.format = RD::DATA_FORMAT_R8_UNORM;
	mask_format.width = p_internal_size.x;
	mask_format.height = p_internal_size.y;
	mask_format.depth = 1;
	mask_format.array_layers = 1;
	mask_format.mipmaps = 1;
	mask_format.usage_bits = RD::TEXTURE_USAGE_SAMPLING_BIT | RD::TEXTURE_USAGE_STORAGE_BIT;
	mask_format.is_discardable = true;
	context->internal->reactive_mask = rd->texture_create(mask_format, RD::TextureView());
	if (context->internal->reactive_mask.is_null()) {
		record_backend_failure(FFX_API_RETURN_ERROR_RUNTIME_ERROR);
		WARN_PRINT("FSR3: failed to create the R8 reactive-mask texture.");
		memdelete(context);
		return nullptr;
	}
	contexts_created.fetch_add(1, std::memory_order_relaxed);
	return context;
}

void FSR3Effect::upscale(const FSR3Context::Parameters &p_params) {
	collect_retired_contexts();
	ERR_FAIL_COND(p_params.context == nullptr || p_params.context->internal == nullptr);
	ERR_FAIL_COND(p_params.context->internal->failed.load(std::memory_order_acquire) || backend_failed.load(std::memory_order_acquire));
	ERR_FAIL_COND(p_params.color.is_null() || p_params.depth.is_null() || p_params.velocity.is_null() || p_params.output.is_null());
	ERR_FAIL_COND(p_params.color == p_params.output || p_params.depth == p_params.output || p_params.velocity == p_params.output);

	RenderingDevice *rd = RD::get_singleton();
	UniformSetCacheRD *uniform_set_cache = UniformSetCacheRD::get_singleton();
	ERR_FAIL_NULL(uniform_set_cache);

	// Decode Godot's invalid motion vectors and copy the alpha-only view into a real R8
	// image. FFX imports VkImage and creates its own VkImageView, so Godot's alpha swizzle
	// is not carried through to the native FFX backend.
	RD::Uniform velocity_image(RD::UNIFORM_TYPE_IMAGE, 0, p_params.velocity);
	RD::Uniform depth_texture(RD::UNIFORM_TYPE_TEXTURE, 0, p_params.depth);
	RD::Uniform reactive_mask_image(RD::UNIFORM_TYPE_IMAGE, 1, p_params.context->internal->reactive_mask);
	RID shader;
	if (!p_params.reactive.is_null()) {
		RD::Uniform reactive_texture(RD::UNIFORM_TYPE_TEXTURE, 1, p_params.reactive);
		shader = shaders.prepare.version_get_shader(shaders.prepare_version, 1);
		ERR_FAIL_COND(shader.is_null());
		RD::ComputeListID compute_list = rd->compute_list_begin();
		rd->compute_list_bind_compute_pipeline(compute_list, shaders.prepare_pipeline[1]);
		rd->compute_list_bind_uniform_set(compute_list, uniform_set_cache->get_cache(shader, 0, velocity_image, reactive_mask_image), 0);
		rd->compute_list_bind_uniform_set(compute_list, uniform_set_cache->get_cache(shader, 1, depth_texture, reactive_texture), 1);
		float push_constants[20];
		push_constants[0] = p_params.internal_size.x;
		push_constants[1] = p_params.internal_size.y;
		push_constants[2] = 0.0f;
		push_constants[3] = 0.0f;
		memcpy(push_constants + 4, &p_params.reprojection.columns[0].x, sizeof(float) * 16);
		rd->compute_list_set_push_constant(compute_list, push_constants, sizeof(push_constants));
		rd->compute_list_dispatch_threads(compute_list, p_params.internal_size.x, p_params.internal_size.y, 1);
		rd->compute_list_end();
	} else {
		shader = shaders.prepare.version_get_shader(shaders.prepare_version, 0);
		ERR_FAIL_COND(shader.is_null());
		RD::ComputeListID compute_list = rd->compute_list_begin();
		rd->compute_list_bind_compute_pipeline(compute_list, shaders.prepare_pipeline[0]);
		rd->compute_list_bind_uniform_set(compute_list, uniform_set_cache->get_cache(shader, 0, velocity_image, reactive_mask_image), 0);
		rd->compute_list_bind_uniform_set(compute_list, uniform_set_cache->get_cache(shader, 1, depth_texture), 1);
		float push_constants[20];
		push_constants[0] = p_params.internal_size.x;
		push_constants[1] = p_params.internal_size.y;
		push_constants[2] = 0.0f;
		push_constants[3] = 0.0f;
		memcpy(push_constants + 4, &p_params.reprojection.columns[0].x, sizeof(float) * 16);
		rd->compute_list_set_push_constant(compute_list, push_constants, sizeof(push_constants));
		rd->compute_list_dispatch_threads(compute_list, p_params.internal_size.x, p_params.internal_size.y, 1);
		rd->compute_list_end();
	}

	DispatchPayload *payload = memnew(DispatchPayload);
	payload->context = p_params.context->internal;
	payload->parameters = p_params;
	if (!make_api_resource(p_params.color, FFX_API_RESOURCE_STATE_COMPUTE_READ, false, payload->color) ||
			!make_api_resource(p_params.depth, FFX_API_RESOURCE_STATE_COMPUTE_READ, false, payload->depth) ||
			!make_api_resource(p_params.velocity, FFX_API_RESOURCE_STATE_COMPUTE_READ, false, payload->velocity) ||
			!make_api_resource(p_params.exposure, FFX_API_RESOURCE_STATE_COMPUTE_READ, false, payload->exposure) ||
			!make_api_resource(p_params.output, FFX_API_RESOURCE_STATE_UNORDERED_ACCESS, true, payload->output)) {
		p_params.context->internal->failed.store(true, std::memory_order_release);
		record_backend_failure(FFX_API_RETURN_ERROR_RUNTIME_ERROR);
		memdelete(payload);
		return;
	}
	if (!p_params.reactive.is_null() && !make_api_resource(p_params.context->internal->reactive_mask, FFX_API_RESOURCE_STATE_COMPUTE_READ, false, payload->reactive)) {
		p_params.context->internal->failed.store(true, std::memory_order_release);
		record_backend_failure(FFX_API_RETURN_ERROR_RUNTIME_ERROR);
		memdelete(payload);
		return;
	}

	RD::CallbackResource resources[6];
	uint32_t resource_count = 0;
	auto add_read_resource = [&](RID p_rid) {
		if (p_rid.is_null()) {
			return;
		}
		resources[resource_count].rid = p_rid;
		resources[resource_count].usage = RD::CALLBACK_RESOURCE_USAGE_TEXTURE_SAMPLE;
		++resource_count;
	};
	add_read_resource(p_params.color);
	add_read_resource(p_params.depth);
	add_read_resource(p_params.velocity);
	add_read_resource(p_params.reactive.is_null() ? RID() : p_params.context->internal->reactive_mask);
	add_read_resource(p_params.exposure);
	resources[resource_count].rid = p_params.output;
	resources[resource_count].usage = RD::CALLBACK_RESOURCE_USAGE_STORAGE_IMAGE_READ_WRITE;
	++resource_count;

	payload->context->references.fetch_add(1, std::memory_order_relaxed);
	Error error = rd->driver_callback_add((RDD::DriverCallback)_dispatch_graph_callback, payload,
			VectorView<RD::CallbackResource>(resources, resource_count));
	if (error != OK) {
		p_params.context->internal->failed.store(true, std::memory_order_release);
		record_backend_failure(FFX_API_RETURN_ERROR_RUNTIME_ERROR);
		release_context_internal(payload->context, false);
		memdelete(payload);
	}
}

void FSR3Effect::_dispatch_graph_callback(RenderingDeviceDriver *p_driver, RDD::CommandBufferID p_command_buffer, void *p_userdata) {
	DispatchPayload *payload = static_cast<DispatchPayload *>(p_userdata);
	void *native_command_buffer = p_driver->command_buffer_get_native_handle(p_command_buffer);
	const FSR3Context::Parameters &params = payload->parameters;

	ffxDispatchDescUpscale dispatch = {};
	dispatch.header.type = FFX_API_DISPATCH_DESC_TYPE_UPSCALE;
	dispatch.commandList = native_command_buffer;
	dispatch.color = payload->color;
	dispatch.depth = payload->depth;
	dispatch.motionVectors = payload->velocity;
	dispatch.exposure = payload->exposure;
	dispatch.reactive = payload->reactive;
	dispatch.output = payload->output;
	dispatch.jitterOffset = { params.jitter.x, params.jitter.y };
	dispatch.motionVectorScale = { float(params.internal_size.x), float(params.internal_size.y) };
	dispatch.renderSize = { uint32_t(params.internal_size.x), uint32_t(params.internal_size.y) };
	dispatch.upscaleSize = { uint32_t(payload->context->target_size.x), uint32_t(payload->context->target_size.y) };
	dispatch.enableSharpening = params.sharpness > 1e-6f;
	dispatch.sharpness = params.sharpness;
	dispatch.frameTimeDelta = params.delta_time * 1000.0f;
	dispatch.preExposure = 1.0f;
	dispatch.reset = params.reset_accumulation;
	dispatch.cameraNear = params.z_near;
	dispatch.cameraFar = params.z_far;
	dispatch.cameraFovAngleVertical = Math::deg_to_rad(params.fovy);
	dispatch.viewSpaceToMetersFactor = 1.0f;

	FSR3Api &api = get_fsr3_api();
	ffxReturnCode_t result = api.dispatch(&payload->context->context, &dispatch.header);
	if (result != FFX_API_RETURN_OK) {
		payload->context->failed.store(true, std::memory_order_release);
		record_backend_failure(result);
		WARN_PRINT(vformat("FSR3: frame dispatch failed (%d).", result));
	} else {
		last_return_code.store(FFX_API_RETURN_OK, std::memory_order_relaxed);
		dispatches_succeeded.fetch_add(1, std::memory_order_relaxed);
		payload->context->has_successful_dispatch.store(true, std::memory_order_release);
	}
	release_context_internal(payload->context, true);
	memdelete(payload);
}

bool FSR3Effect::is_ready(const FSR3Context *p_context) const {
	return p_context != nullptr && p_context->internal != nullptr && p_context->internal->context != nullptr &&
			p_context->internal->has_successful_dispatch.load(std::memory_order_acquire) &&
			!p_context->internal->failed.load(std::memory_order_acquire) && !backend_failed.load(std::memory_order_acquire) &&
			!shaders.prepare_version.is_null() && !shaders.prepare_pipeline[0].is_null() && !shaders.prepare_pipeline[1].is_null();
}

} // namespace RendererRD

#else

namespace RendererRD {

struct FSR3ContextInternal {};

FSR3Context::~FSR3Context() {}
FSR3Effect::FSR3Effect() {}
FSR3Effect::~FSR3Effect() {}
bool FSR3Effect::is_available() { return false; }
Dictionary FSR3Effect::get_status() { return Dictionary(); }
FSR3Context *FSR3Effect::create_context(Size2i, Size2i) { return nullptr; }
void FSR3Effect::upscale(const FSR3Context::Parameters &) {}
bool FSR3Effect::is_ready(const FSR3Context *) const { return false; }
void FSR3Effect::_dispatch_graph_callback(RenderingDeviceDriver *, RDD::CommandBufferID, void *) {}

} // namespace RendererRD

#endif
