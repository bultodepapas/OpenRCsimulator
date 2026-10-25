#pragma once

#include "servers/rendering/renderer_rd/shaders/effects/motion_vector_decode.glsl.gen.h"

namespace RendererRD {

struct FSR3ContextInternal;

class FSR3Context {
public:
	struct Parameters {
		FSR3Context *context = nullptr;
		Size2i internal_size;
		RID color;
		RID depth;
		RID velocity;
		RID reactive;
		RID exposure;
		RID output;
		float z_near = 0.0f;
		float z_far = 0.0f;
		float fovy = 0.0f;
		Vector2 jitter;
		float delta_time = 0.0f;
		float sharpness = 0.0f;
		bool reset_accumulation = false;
		Projection reprojection;
	};

	virtual ~FSR3Context();
	bool is_valid() const { return internal != nullptr; }

private:
	FSR3ContextInternal *internal = nullptr;
	friend class FSR3Effect;
};

class FSR3Effect {
public:
	struct Shaders {
		MotionVectorDecodeShaderRD motion_vector_decode;
		RID motion_vector_decode_version;
		RID motion_vector_decode_pipeline;
	} shaders;

	FSR3Effect();
	~FSR3Effect();

	static bool is_available();
	FSR3Context *create_context(Size2i p_internal_size, Size2i p_target_size);
	void upscale(const FSR3Context::Parameters &p_params);
	bool is_ready(const FSR3Context *p_context) const;

private:
	struct DispatchPayload;
	static void _dispatch_graph_callback(RenderingDeviceDriver *p_driver, RDD::CommandBufferID p_command_buffer, void *p_userdata);
};

} // namespace RendererRD
