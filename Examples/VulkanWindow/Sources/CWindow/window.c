#include "CWindow.h"

#include <SDL3/SDL.h>
#include <SDL3/SDL_vulkan.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <vulkan/vulkan.h>

#define MAX_IMAGES 8

struct cw_window {
    SDL_Window* window;
    VkInstance instance;
    VkSurfaceKHR surface;
    VkPhysicalDevice physicalDevice;
    VkDevice device;
    VkQueue queue;
    uint32_t queueFamily;
    char deviceName[VK_MAX_PHYSICAL_DEVICE_NAME_SIZE];

    VkSwapchainKHR swapchain;
    VkImage images[MAX_IMAGES];
    uint32_t imageCount;
    VkFormat format;
    VkImageUsageFlags usage;
    VkExtent2D extent;
    bool needsRecreate;  // size changed or swapchain suboptimal: recreate when the interval allows
    bool outOfDate;      // the swapchain can't be presented any more
    Uint64 lastRecreateNS;
    uint32_t recreateCount;
    Uint64 lastPresentNS;

    VkCommandPool commandPool;
    VkCommandBuffer commandBuffer;
    VkFence fence;
};

static const uint32_t kApiVersion = VK_API_VERSION_1_1;

// While the window is being resized, recreate the swapchain at most this often and keep
// presenting the old (suboptimal) one in between. A fresh swapchain's images are all
// available at once, so recreating every frame would also defeat FIFO pacing.
static const Uint64 kRecreateIntervalNS = 50 * 1000000ull;

static bool create_swapchain(cw_window* w) {
    VkSurfaceCapabilitiesKHR caps;
    vkGetPhysicalDeviceSurfaceCapabilitiesKHR(w->physicalDevice, w->surface, &caps);

    uint32_t formatCount = 0;
    vkGetPhysicalDeviceSurfaceFormatsKHR(w->physicalDevice, w->surface, &formatCount, NULL);
    VkSurfaceFormatKHR formats[64];
    if (formatCount > 64) formatCount = 64;
    vkGetPhysicalDeviceSurfaceFormatsKHR(w->physicalDevice, w->surface, &formatCount, formats);
    VkSurfaceFormatKHR chosen = formats[0];
    for (uint32_t i = 0; i < formatCount; i++) {
        if (formats[i].format == VK_FORMAT_B8G8R8A8_UNORM || formats[i].format == VK_FORMAT_R8G8B8A8_UNORM) {
            chosen = formats[i];
            break;
        }
    }

    VkExtent2D extent = caps.currentExtent;
    if (extent.width == UINT32_MAX) {
        int pw, ph;
        SDL_GetWindowSizeInPixels(w->window, &pw, &ph);
        extent.width = (uint32_t)pw;
        extent.height = (uint32_t)ph;
    }
    if (extent.width == 0 || extent.height == 0) return false;  // minimized

    uint32_t imageCount = caps.minImageCount + 1;
    if (caps.maxImageCount && imageCount > caps.maxImageCount) imageCount = caps.maxImageCount;
    if (imageCount > MAX_IMAGES) imageCount = MAX_IMAGES;

    // What Graphite renders into a target with; input attachment enables its dst-read path.
    VkImageUsageFlags usage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT |
                              VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_INPUT_ATTACHMENT_BIT;
    usage &= caps.supportedUsageFlags;

    VkSwapchainKHR old = w->swapchain;
    VkSwapchainCreateInfoKHR info = {
        .sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .surface = w->surface,
        .minImageCount = imageCount,
        .imageFormat = chosen.format,
        .imageColorSpace = chosen.colorSpace,
        .imageExtent = extent,
        .imageArrayLayers = 1,
        .imageUsage = usage,
        .imageSharingMode = VK_SHARING_MODE_EXCLUSIVE,
        .preTransform = caps.currentTransform,
        .compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .presentMode = VK_PRESENT_MODE_FIFO_KHR,
        .clipped = VK_TRUE,
        .oldSwapchain = old,
    };
    if (vkCreateSwapchainKHR(w->device, &info, NULL, &w->swapchain) != VK_SUCCESS) return false;
    if (old) vkDestroySwapchainKHR(w->device, old, NULL);

    w->imageCount = MAX_IMAGES;
    vkGetSwapchainImagesKHR(w->device, w->swapchain, &w->imageCount, w->images);
    w->format = chosen.format;
    w->usage = usage;
    w->extent = extent;
    w->needsRecreate = false;
    return true;
}

cw_window* cw_create(const char* title, int width, int height) {
    if (!SDL_Init(SDL_INIT_VIDEO)) {
        fprintf(stderr, "SDL_Init: %s\n", SDL_GetError());
        return NULL;
    }
    cw_window* w = calloc(1, sizeof *w);
    w->window = SDL_CreateWindow(title, width, height, SDL_WINDOW_VULKAN | SDL_WINDOW_RESIZABLE);
    if (!w->window) {
        fprintf(stderr, "SDL_CreateWindow: %s\n", SDL_GetError());
        cw_destroy(w);
        return NULL;
    }

    Uint32 extensionCount = 0;
    const char* const* extensions = SDL_Vulkan_GetInstanceExtensions(&extensionCount);
    const char* validation = "VK_LAYER_KHRONOS_validation";
    const bool wantValidation = getenv("CW_VALIDATION") != NULL;
    VkApplicationInfo app = {
        .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = title,
        .apiVersion = kApiVersion,
    };
    VkInstanceCreateInfo instanceInfo = {
        .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &app,
        .enabledExtensionCount = extensionCount,
        .ppEnabledExtensionNames = extensions,
        .enabledLayerCount = wantValidation ? 1 : 0,
        .ppEnabledLayerNames = &validation,
    };
    if (vkCreateInstance(&instanceInfo, NULL, &w->instance) != VK_SUCCESS ||
        !SDL_Vulkan_CreateSurface(w->window, w->instance, NULL, &w->surface)) {
        fprintf(stderr, "Vulkan instance/surface creation failed: %s\n", SDL_GetError());
        cw_destroy(w);
        return NULL;
    }

    // Prefer a real GPU; fall back to CPU drivers.
    uint32_t count = 16;
    VkPhysicalDevice devices[16];
    vkEnumeratePhysicalDevices(w->instance, &count, devices);
    for (int pass = 0; pass < 2 && !w->physicalDevice; pass++) {
        for (uint32_t i = 0; i < count && !w->physicalDevice; i++) {
            VkPhysicalDeviceProperties props;
            vkGetPhysicalDeviceProperties(devices[i], &props);
            if ((pass == 0) == (props.deviceType == VK_PHYSICAL_DEVICE_TYPE_CPU)) continue;
            if (props.apiVersion < kApiVersion) continue;
            uint32_t queueCount = 32;
            VkQueueFamilyProperties queues[32];
            vkGetPhysicalDeviceQueueFamilyProperties(devices[i], &queueCount, queues);
            for (uint32_t q = 0; q < queueCount; q++) {
                VkBool32 present = VK_FALSE;
                vkGetPhysicalDeviceSurfaceSupportKHR(devices[i], q, w->surface, &present);
                if ((queues[q].queueFlags & VK_QUEUE_GRAPHICS_BIT) && present) {
                    w->physicalDevice = devices[i];
                    w->queueFamily = q;
                    memcpy(w->deviceName, props.deviceName, sizeof w->deviceName);
                    break;
                }
            }
        }
    }
    if (!w->physicalDevice) {
        fprintf(stderr, "no Vulkan device can present to this window\n");
        cw_destroy(w);
        return NULL;
    }

    const float priority = 1.0f;
    const char* deviceExtensions[] = {VK_KHR_SWAPCHAIN_EXTENSION_NAME};
    VkDeviceQueueCreateInfo queueInfo = {
        .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = w->queueFamily,
        .queueCount = 1,
        .pQueuePriorities = &priority,
    };
    VkDeviceCreateInfo deviceInfo = {
        .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .queueCreateInfoCount = 1,
        .pQueueCreateInfos = &queueInfo,
        .enabledExtensionCount = 1,
        .ppEnabledExtensionNames = deviceExtensions,
    };
    if (vkCreateDevice(w->physicalDevice, &deviceInfo, NULL, &w->device) != VK_SUCCESS) {
        fprintf(stderr, "vkCreateDevice failed\n");
        cw_destroy(w);
        return NULL;
    }
    vkGetDeviceQueue(w->device, w->queueFamily, 0, &w->queue);

    VkCommandPoolCreateInfo poolInfo = {
        .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = w->queueFamily,
    };
    vkCreateCommandPool(w->device, &poolInfo, NULL, &w->commandPool);
    VkCommandBufferAllocateInfo allocInfo = {
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = w->commandPool,
        .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = 1,
    };
    vkAllocateCommandBuffers(w->device, &allocInfo, &w->commandBuffer);
    VkFenceCreateInfo fenceInfo = {.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO};
    vkCreateFence(w->device, &fenceInfo, NULL, &w->fence);

    if (!create_swapchain(w)) w->needsRecreate = true;
    return w;
}

void cw_destroy(cw_window* w) {
    if (!w) return;
    if (w->device) {
        vkDeviceWaitIdle(w->device);
        if (w->fence) vkDestroyFence(w->device, w->fence, NULL);
        if (w->commandPool) vkDestroyCommandPool(w->device, w->commandPool, NULL);
        if (w->swapchain) vkDestroySwapchainKHR(w->device, w->swapchain, NULL);
        vkDestroyDevice(w->device, NULL);
    }
    if (w->surface) SDL_Vulkan_DestroySurface(w->instance, w->surface, NULL);
    if (w->instance) vkDestroyInstance(w->instance, NULL);
    if (w->window) SDL_DestroyWindow(w->window);
    SDL_Quit();
    free(w);
}

cw_device cw_get_device(const cw_window* w) {
    return (cw_device){
        .instance = w->instance,
        .physicalDevice = w->physicalDevice,
        .device = w->device,
        .queue = w->queue,
        .queueFamily = w->queueFamily,
        .apiVersion = kApiVersion,
        .getInstanceProcAddr = (void*)vkGetInstanceProcAddr,
        .getDeviceProcAddr = (void*)vkGetDeviceProcAddr,
    };
}

const char* cw_device_name(const cw_window* w) { return w->deviceName; }

bool cw_poll(cw_window* w) {
    SDL_Event event;
    while (SDL_PollEvent(&event)) {
        switch (event.type) {
            case SDL_EVENT_QUIT:
            case SDL_EVENT_WINDOW_CLOSE_REQUESTED:
                return false;
            case SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED:
                if ((uint32_t)event.window.data1 != w->extent.width ||
                    (uint32_t)event.window.data2 != w->extent.height)
                    w->needsRecreate = true;
                break;
            default:
                break;
        }
    }
    return true;
}

bool cw_acquire(cw_window* w, cw_frame* frame) {
    const bool mustRecreate = w->outOfDate || !w->swapchain;
    if (w->needsRecreate || mustRecreate) {
        const Uint64 since = SDL_GetTicksNS() - w->lastRecreateNS;
        if (since < kRecreateIntervalNS && mustRecreate) SDL_DelayNS(kRecreateIntervalNS - since);
        if (since >= kRecreateIntervalNS || mustRecreate) {
            vkDeviceWaitIdle(w->device);
            const bool created = create_swapchain(w);
            w->lastRecreateNS = SDL_GetTicksNS();
            if (!created) {  // minimized: nothing to draw into
                SDL_DelayNS(16 * 1000000ull);
                return false;
            }
            w->outOfDate = false;
            w->recreateCount++;
        }
    }
    uint32_t index;
    VkResult result = vkAcquireNextImageKHR(w->device, w->swapchain, UINT64_MAX, VK_NULL_HANDLE, w->fence, &index);
    if (result == VK_ERROR_OUT_OF_DATE_KHR) {
        w->outOfDate = true;
        return false;
    }
    if (result != VK_SUCCESS && result != VK_SUBOPTIMAL_KHR) return false;
    vkWaitForFences(w->device, 1, &w->fence, VK_TRUE, UINT64_MAX);
    vkResetFences(w->device, 1, &w->fence);
    if (result == VK_SUBOPTIMAL_KHR) w->needsRecreate = true;

    *frame = (cw_frame){
        .image = w->images[index],
        .index = index,
        .width = (int32_t)w->extent.width,
        .height = (int32_t)w->extent.height,
        .format = w->format,
        .usage = w->usage,
    };
    return true;
}

bool cw_present(cw_window* w, const cw_frame* frame) {
    VkCommandBufferBeginInfo begin = {
        .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT,
    };
    vkBeginCommandBuffer(w->commandBuffer, &begin);
    VkImageMemoryBarrier barrier = {
        .sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
        .srcAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
        .dstAccessMask = 0,
        .oldLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
        .newLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
        .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
        .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
        .image = (VkImage)frame->image,
        .subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1},
    };
    vkCmdPipelineBarrier(w->commandBuffer, VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
                         VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, 0, 0, NULL, 0, NULL, 1, &barrier);
    vkEndCommandBuffer(w->commandBuffer);

    VkSubmitInfo submit = {
        .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .commandBufferCount = 1,
        .pCommandBuffers = &w->commandBuffer,
    };
    vkQueueSubmit(w->queue, 1, &submit, w->fence);
    vkWaitForFences(w->device, 1, &w->fence, VK_TRUE, UINT64_MAX);
    vkResetFences(w->device, 1, &w->fence);

    VkPresentInfoKHR present = {
        .sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .swapchainCount = 1,
        .pSwapchains = &w->swapchain,
        .pImageIndices = &frame->index,
    };
    // FIFO only blocks once every image is in flight, which a fresh swapchain never is, and
    // some compositors don't block at all; cap at the display's refresh rate ourselves.
    const SDL_DisplayMode* mode = SDL_GetCurrentDisplayMode(SDL_GetDisplayForWindow(w->window));
    const float refresh = mode && mode->refresh_rate > 0 ? mode->refresh_rate : 60.0f;
    const Uint64 interval = (Uint64)(1e9f / refresh);
    const Uint64 now = SDL_GetTicksNS();
    if (w->lastPresentNS && now - w->lastPresentNS < interval) SDL_DelayPrecise(interval - (now - w->lastPresentNS));
    w->lastPresentNS = SDL_GetTicksNS();

    VkResult result = vkQueuePresentKHR(w->queue, &present);
    if (result == VK_ERROR_OUT_OF_DATE_KHR) w->outOfDate = true;
    if (result == VK_SUBOPTIMAL_KHR) w->needsRecreate = true;
    return result == VK_SUCCESS || result == VK_SUBOPTIMAL_KHR;
}

void cw_set_size(cw_window* w, int width, int height) { SDL_SetWindowSize(w->window, width, height); }

uint32_t cw_recreate_count(const cw_window* w) { return w->recreateCount; }
