// SDL3 window + Vulkan device + swapchain. Skia draws into the swapchain images.
#pragma once
#include <stdbool.h>
#include <stdint.h>

typedef struct cw_window cw_window;

/// Frames the CPU may record ahead of the GPU. Each has its own acquire semaphore.
#define CW_FRAMES_IN_FLIGHT 2

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
    uint64_t acquiredSemaphore;        // VkSemaphore: signaled once the image is ready to draw into
    uint64_t renderFinishedSemaphore;  // VkSemaphore: signal it when drawing is done; present waits on it
} cw_frame;

/// Validation layers are enabled when CW_VALIDATION is set.
cw_window* cw_create(const char* title, int width, int height);
void cw_destroy(cw_window* window);
cw_device cw_get_device(const cw_window* window);
const char* cw_device_name(const cw_window* window);

/// Handles window events. Returns false once the window should close.
bool cw_poll(cw_window* window);

/// True when the next cw_acquire recreates the swapchain. Its images then go away: first finish
/// every GPU use of them and drop anything wrapping them.
bool cw_recreate_pending(const cw_window* window);

/// Acquires the next swapchain image for frame slot `slot` (0..<CW_FRAMES_IN_FLIGHT), recreating
/// the swapchain after a resize. The slot's previous frame must have finished on the GPU.
bool cw_acquire(cw_window* window, uint32_t slot, cw_frame* frame);

/// Presents the frame once its renderFinishedSemaphore is signaled. The image must be in
/// VK_IMAGE_LAYOUT_PRESENT_SRC_KHR by then.
bool cw_present(cw_window* window, const cw_frame* frame);

/// Requests a new window size (the compositor may ignore it, e.g. when tiling).
void cw_set_size(cw_window* window, int width, int height);

/// How many times the swapchain has been recreated after a resize.
uint32_t cw_recreate_count(const cw_window* window);
