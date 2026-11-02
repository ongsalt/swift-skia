// SkRuntimeEffectBuilder and SkImageFilters::RuntimeShader, which SkiaSharp's C API doesn't cover.
#pragma once

#include "skia/include/c/sk_types.h"

SK_C_PLUS_PLUS_BEGIN_GUARD

#define SWSK_RETURNS_RETAINED __attribute__((swift_attr("returns_retained")))

typedef struct swsk_runtimeeffect_builder_t swsk_runtimeeffect_builder_t;

// Null `uniforms` starts them zeroed.
SK_C_API swsk_runtimeeffect_builder_t* swsk_runtimeeffect_builder_new(sk_runtimeeffect_t* effect, sk_data_t* uniforms);
SK_C_API swsk_runtimeeffect_builder_t* swsk_runtimeeffect_builder_clone(const swsk_runtimeeffect_builder_t* builder);
SK_C_API void swsk_runtimeeffect_builder_delete(swsk_runtimeeffect_builder_t* builder);

SK_C_API sk_runtimeeffect_t* swsk_runtimeeffect_builder_get_effect(const swsk_runtimeeffect_builder_t* builder) SWSK_RETURNS_RETAINED;
SK_C_API sk_data_t* swsk_runtimeeffect_builder_get_uniforms(const swsk_runtimeeffect_builder_t* builder) SWSK_RETURNS_RETAINED;

// The uniform's size in bytes, or -1 when the effect has no uniform `name`. Copies `data` only
// when `size` matches.
SK_C_API int64_t swsk_runtimeeffect_builder_set_uniform(swsk_runtimeeffect_builder_t* builder, const char* name, const void* data, size_t size);
// False when the effect has no child `name`. Pass at most one of the three; all null clears it.
SK_C_API bool swsk_runtimeeffect_builder_set_child(swsk_runtimeeffect_builder_t* builder, const char* name, sk_shader_t* shader, sk_colorfilter_t* colorFilter, sk_blender_t* blender);

SK_C_API sk_shader_t* swsk_runtimeeffect_builder_make_shader(const swsk_runtimeeffect_builder_t* builder, const sk_matrix_t* localMatrix) SWSK_RETURNS_RETAINED;
SK_C_API sk_colorfilter_t* swsk_runtimeeffect_builder_make_color_filter(const swsk_runtimeeffect_builder_t* builder) SWSK_RETURNS_RETAINED;
SK_C_API sk_blender_t* swsk_runtimeeffect_builder_make_blender(const swsk_runtimeeffect_builder_t* builder) SWSK_RETURNS_RETAINED;

SK_C_API sk_imagefilter_t* swsk_imagefilter_new_runtime_shader(const swsk_runtimeeffect_builder_t* builder, float sampleRadius, const char* childShaderName, sk_imagefilter_t* input, bool restrictOutputToInputBounds) SWSK_RETURNS_RETAINED;
// `childShaderNames` and `inputs` both hold `count` entries; inputs may be null.
SK_C_API sk_imagefilter_t* swsk_imagefilter_new_runtime_shader_multi(const swsk_runtimeeffect_builder_t* builder, float maxSampleRadius, const char* const* childShaderNames, sk_imagefilter_t* const* inputs, int32_t count) SWSK_RETURNS_RETAINED;

SK_C_PLUS_PLUS_END_GUARD
