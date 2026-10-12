// Test-only: creates a Vulkan instance + device so tests can drive Graphite.
#pragma once
#include <stdbool.h>
#include <stdint.h>

typedef struct {
    void* instance;          // VkInstance
    void* physicalDevice;    // VkPhysicalDevice
    void* device;            // VkDevice
    void* queue;             // VkQueue
    uint32_t queueFamily;
    uint32_t apiVersion;
    void* getInstanceProcAddr;  // PFN_vkGetInstanceProcAddr
    void* getDeviceProcAddr;    // PFN_vkGetDeviceProcAddr
    char deviceName[256];
} vkts_device;

/// Picks the first device with a graphics queue (or the first CPU device when
/// SKIA_TEST_VULKAN_CPU is set). Returns false when no usable device exists.
bool vkts_create(vkts_device* out);
void vkts_destroy(vkts_device* device);
