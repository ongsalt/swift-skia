#include "include/swsk_runtimeeffect.h"

#include "skia/include/core/SkBlender.h"
#include "skia/include/core/SkColorFilter.h"
#include "skia/include/core/SkData.h"
#include "skia/include/core/SkImageFilter.h"
#include "skia/include/core/SkMatrix.h"
#include "skia/include/core/SkShader.h"
#include "skia/include/effects/SkImageFilters.h"
#include "skia/include/effects/SkRuntimeEffect.h"

#include <string_view>
#include <vector>

namespace {

SkRuntimeEffectBuilder* as_builder(swsk_runtimeeffect_builder_t* builder) {
    return reinterpret_cast<SkRuntimeEffectBuilder*>(builder);
}

const SkRuntimeEffectBuilder& as_builder(const swsk_runtimeeffect_builder_t* builder) {
    return *reinterpret_cast<const SkRuntimeEffectBuilder*>(builder);
}

template <typename T>
sk_sp<T> ref(void* object) {
    return sk_ref_sp(reinterpret_cast<T*>(object));
}

}  // namespace

extern "C" swsk_runtimeeffect_builder_t* swsk_runtimeeffect_builder_new(sk_runtimeeffect_t* effect, sk_data_t* uniforms) {
    auto skEffect = ref<SkRuntimeEffect>(effect);
    auto* builder = uniforms ? new SkRuntimeEffectBuilder(std::move(skEffect), ref<SkData>(uniforms))
                             : new SkRuntimeEffectBuilder(std::move(skEffect));
    return reinterpret_cast<swsk_runtimeeffect_builder_t*>(builder);
}

extern "C" swsk_runtimeeffect_builder_t* swsk_runtimeeffect_builder_clone(const swsk_runtimeeffect_builder_t* builder) {
    return reinterpret_cast<swsk_runtimeeffect_builder_t*>(new SkRuntimeEffectBuilder(as_builder(builder)));
}

extern "C" void swsk_runtimeeffect_builder_delete(swsk_runtimeeffect_builder_t* builder) {
    delete as_builder(builder);
}

extern "C" sk_runtimeeffect_t* swsk_runtimeeffect_builder_get_effect(const swsk_runtimeeffect_builder_t* builder) {
    auto* effect = const_cast<SkRuntimeEffect*>(as_builder(builder).effect());
    return reinterpret_cast<sk_runtimeeffect_t*>(SkRef(effect));
}

extern "C" sk_data_t* swsk_runtimeeffect_builder_get_uniforms(const swsk_runtimeeffect_builder_t* builder) {
    // A copy: the builder writes into its own data in place while it's unique.
    auto uniforms = as_builder(builder).uniforms();
    return reinterpret_cast<sk_data_t*>(SkData::MakeWithCopy(uniforms->data(), uniforms->size()).release());
}

extern "C" int64_t swsk_runtimeeffect_builder_set_uniform(swsk_runtimeeffect_builder_t* builder, const char* name, const void* data, size_t size) {
    auto* skBuilder = as_builder(builder);
    const auto* uniform = skBuilder->effect()->findUniform(name);
    if (!uniform) {
        return -1;
    }
    if (uniform->sizeInBytes() == size) {
        skBuilder->uniform(name).set(static_cast<const uint8_t*>(data), static_cast<int>(size));
    }
    return static_cast<int64_t>(uniform->sizeInBytes());
}

extern "C" bool swsk_runtimeeffect_builder_set_child(swsk_runtimeeffect_builder_t* builder, const char* name, sk_shader_t* shader, sk_colorfilter_t* colorFilter, sk_blender_t* blender) {
    auto* skBuilder = as_builder(builder);
    if (!skBuilder->effect()->findChild(name)) {
        return false;
    }
    auto child = skBuilder->child(name);
    if (shader) {
        child = ref<SkShader>(shader);
    } else if (colorFilter) {
        child = ref<SkColorFilter>(colorFilter);
    } else if (blender) {
        child = ref<SkBlender>(blender);
    } else {
        child = nullptr;
    }
    return true;
}

extern "C" sk_shader_t* swsk_runtimeeffect_builder_make_shader(const swsk_runtimeeffect_builder_t* builder, const sk_matrix_t* localMatrix) {
    SkMatrix matrix;
    if (localMatrix) {
        matrix = SkMatrix::MakeAll(localMatrix->scaleX, localMatrix->skewX, localMatrix->transX,
                                   localMatrix->skewY, localMatrix->scaleY, localMatrix->transY,
                                   localMatrix->persp0, localMatrix->persp1, localMatrix->persp2);
    }
    auto shader = as_builder(builder).makeShader(localMatrix ? &matrix : nullptr);
    return reinterpret_cast<sk_shader_t*>(shader.release());
}

extern "C" sk_colorfilter_t* swsk_runtimeeffect_builder_make_color_filter(const swsk_runtimeeffect_builder_t* builder) {
    return reinterpret_cast<sk_colorfilter_t*>(as_builder(builder).makeColorFilter().release());
}

extern "C" sk_blender_t* swsk_runtimeeffect_builder_make_blender(const swsk_runtimeeffect_builder_t* builder) {
    return reinterpret_cast<sk_blender_t*>(as_builder(builder).makeBlender().release());
}

extern "C" sk_imagefilter_t* swsk_imagefilter_new_runtime_shader(const swsk_runtimeeffect_builder_t* builder, float sampleRadius, const char* childShaderName, sk_imagefilter_t* input, bool restrictOutputToInputBounds) {
    auto filter = SkImageFilters::RuntimeShader(as_builder(builder), sampleRadius, childShaderName,
                                                ref<SkImageFilter>(input), restrictOutputToInputBounds);
    return reinterpret_cast<sk_imagefilter_t*>(filter.release());
}

extern "C" sk_imagefilter_t* swsk_imagefilter_new_runtime_shader_multi(const swsk_runtimeeffect_builder_t* builder, float maxSampleRadius, const char* const* childShaderNames, sk_imagefilter_t* const* inputs, int32_t count) {
    std::vector<std::string_view> names(childShaderNames, childShaderNames + count);
    std::vector<sk_sp<SkImageFilter>> skInputs;
    for (int32_t i = 0; i < count; i++) {
        skInputs.push_back(ref<SkImageFilter>(inputs[i]));
    }
    auto filter = SkImageFilters::RuntimeShader(as_builder(builder), maxSampleRadius, names.data(),
                                                skInputs.data(), count);
    return reinterpret_cast<sk_imagefilter_t*>(filter.release());
}
