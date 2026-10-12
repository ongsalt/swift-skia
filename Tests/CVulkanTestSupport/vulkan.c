#include "CVulkanTestSupport.h"

#include <stdlib.h>
#include <string.h>
#include <vulkan/vulkan.h>

bool vkts_create(vkts_device* out) {
    memset(out, 0, sizeof *out);
    const uint32_t apiVersion = VK_API_VERSION_1_1;

    VkApplicationInfo app = {
        .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "swift-skia tests",
        .apiVersion = apiVersion,
    };
    VkInstanceCreateInfo instanceInfo = {
        .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &app,
    };
    VkInstance instance;
    if (vkCreateInstance(&instanceInfo, NULL, &instance) != VK_SUCCESS) return false;

    uint32_t count = 0;
    vkEnumeratePhysicalDevices(instance, &count, NULL);
    VkPhysicalDevice devices[16];
    if (count > 16) count = 16;
    vkEnumeratePhysicalDevices(instance, &count, devices);

    const bool wantCPU = getenv("SKIA_TEST_VULKAN_CPU") != NULL;
    VkPhysicalDevice chosen = VK_NULL_HANDLE;
    uint32_t family = 0;
    VkPhysicalDeviceProperties props;
    for (uint32_t i = 0; i < count && chosen == VK_NULL_HANDLE; i++) {
        vkGetPhysicalDeviceProperties(devices[i], &props);
        if (wantCPU != (props.deviceType == VK_PHYSICAL_DEVICE_TYPE_CPU)) continue;
        if (props.apiVersion < apiVersion) continue;
        uint32_t queueCount = 0;
        vkGetPhysicalDeviceQueueFamilyProperties(devices[i], &queueCount, NULL);
        VkQueueFamilyProperties queues[32];
        if (queueCount > 32) queueCount = 32;
        vkGetPhysicalDeviceQueueFamilyProperties(devices[i], &queueCount, queues);
        for (uint32_t q = 0; q < queueCount; q++) {
            if (queues[q].queueFlags & VK_QUEUE_GRAPHICS_BIT) {
                chosen = devices[i];
                family = q;
                break;
            }
        }
    }
    if (chosen == VK_NULL_HANDLE) {
        vkDestroyInstance(instance, NULL);
        return false;
    }

    const float priority = 1.0f;
    VkDeviceQueueCreateInfo queueInfo = {
        .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = family,
        .queueCount = 1,
        .pQueuePriorities = &priority,
    };
    VkDeviceCreateInfo deviceInfo = {
        .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .queueCreateInfoCount = 1,
        .pQueueCreateInfos = &queueInfo,
    };
    VkDevice device;
    if (vkCreateDevice(chosen, &deviceInfo, NULL, &device) != VK_SUCCESS) {
        vkDestroyInstance(instance, NULL);
        return false;
    }
    VkQueue queue;
    vkGetDeviceQueue(device, family, 0, &queue);

    out->instance = instance;
    out->physicalDevice = chosen;
    out->device = device;
    out->queue = queue;
    out->queueFamily = family;
    out->apiVersion = apiVersion;
    out->getInstanceProcAddr = (void*)vkGetInstanceProcAddr;
    out->getDeviceProcAddr = (void*)vkGetDeviceProcAddr;
    vkGetPhysicalDeviceProperties(chosen, &props);
    strncpy(out->deviceName, props.deviceName, sizeof out->deviceName - 1);
    return true;
}

void vkts_destroy(vkts_device* d) {
    if (d->device) {
        vkDeviceWaitIdle((VkDevice)d->device);
        vkDestroyDevice((VkDevice)d->device, NULL);
    }
    if (d->instance) vkDestroyInstance((VkInstance)d->instance, NULL);
    memset(d, 0, sizeof *d);
}
