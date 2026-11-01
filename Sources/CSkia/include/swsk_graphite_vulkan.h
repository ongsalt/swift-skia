// Return null when Skia was built without Vulkan.
#pragma once

#include "swsk_graphite.h"

SK_C_PLUS_PLUS_BEGIN_GUARD

SK_C_API swsk_graphite_backend_semaphore_t* swsk_graphite_vk_backend_semaphore_new(uint64_t vkSemaphore);

SK_C_API swsk_graphite_mutable_texture_state_t* swsk_graphite_vk_mutable_texture_state_new(
    int32_t vkImageLayout, uint32_t queueFamilyIndex);

SK_C_PLUS_PLUS_END_GUARD
