#include "include/swsk_graphite_vulkan.h"

#include "skia/include/core/SkTypes.h"  // SkUserConfig.h decides SK_VULKAN

#if defined(SK_VULKAN)

#include "skia/include/gpu/MutableTextureState.h"
#include "skia/include/gpu/graphite/BackendSemaphore.h"
#include "skia/include/gpu/graphite/vk/VulkanGraphiteTypes.h"
#include "skia/include/gpu/vk/VulkanMutableTextureState.h"

extern "C" swsk_graphite_backend_semaphore_t* swsk_graphite_vk_backend_semaphore_new(uint64_t vkSemaphore) {
    auto* semaphore = new skgpu::graphite::BackendSemaphore(
            skgpu::graphite::BackendSemaphores::MakeVulkan(reinterpret_cast<VkSemaphore>(vkSemaphore)));
    return reinterpret_cast<swsk_graphite_backend_semaphore_t*>(semaphore);
}

extern "C" swsk_graphite_mutable_texture_state_t* swsk_graphite_vk_mutable_texture_state_new(
        int32_t vkImageLayout, uint32_t queueFamilyIndex) {
    auto* state = new skgpu::MutableTextureState(
            skgpu::MutableTextureStates::MakeVulkan(static_cast<VkImageLayout>(vkImageLayout), queueFamilyIndex));
    return reinterpret_cast<swsk_graphite_mutable_texture_state_t*>(state);
}

#else

extern "C" swsk_graphite_backend_semaphore_t* swsk_graphite_vk_backend_semaphore_new(uint64_t) { return nullptr; }

extern "C" swsk_graphite_mutable_texture_state_t* swsk_graphite_vk_mutable_texture_state_new(int32_t, uint32_t) {
    return nullptr;
}

#endif
