// SDL3 window + Vulkan device + swapchain. Skia draws into the swapchain images.
#pragma once
#include <stdbool.h>
#include <stdint.h>

typedef struct cw_window cw_window;

typedef struct {
    void* instance;             // VkInstance
    void* physicalDevice;       // VkPhysicalDevice
    void* device;               // VkDevice
    void* queue;                // VkQueue
    uint32_t queueFamily;
    uint32_t apiVersion;
    void* getInstanceProcAddr;  // PFN_vkGetInstanceProcAddr
    void* getDeviceProcAddr;    // PFN_vkGetDeviceProcAddr
} cw_device;

typedef struct {
    void* image;     // VkImage, in VK_IMAGE_LAYOUT_UNDEFINED after acquire
    uint32_t index;
    int32_t width;
    int32_t height;
    int32_t format;  // VkFormat
    uint32_t usage;  // VkImageUsageFlags
} cw_frame;

/// Validation layers are enabled when CW_VALIDATION is set.
cw_window* cw_create(const char* title, int width, int height);
void cw_destroy(cw_window* window);
cw_device cw_get_device(const cw_window* window);
const char* cw_device_name(const cw_window* window);

/// Handles window events. Returns false once the window should close.
bool cw_poll(cw_window* window);

/// Acquires the next swapchain image, recreating the swapchain after a resize.
bool cw_acquire(cw_window* window, cw_frame* frame);

/// Moves the image from COLOR_ATTACHMENT_OPTIMAL (where Graphite leaves it after drawing) to
/// PRESENT_SRC and presents it. Call after a synchronous Graphite submit.
bool cw_present(cw_window* window, const cw_frame* frame);

/// Requests a new window size (the compositor may ignore it, e.g. when tiling).
void cw_set_size(cw_window* window, int width, int height);

/// How many times the swapchain has been recreated after a resize.
uint32_t cw_recreate_count(const cw_window* window);
