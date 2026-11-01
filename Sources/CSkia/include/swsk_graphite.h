// C API additions over Skia's C++ API, for what SkiaSharp's C API doesn't cover yet.
// Implemented in swsk_graphite.cpp.
#pragma once

#include "skia/include/c/sk_graphite.h"

SK_C_PLUS_PLUS_BEGIN_GUARD

// Called once when the GPU work of an inserted recording has finished (or failed).
typedef void (*swsk_graphite_finished_proc)(void* context, bool success);

// Everything skgpu::graphite::InsertRecordingInfo takes beyond the recording.
typedef struct {
    // Surface the recording draws into when it was recorded with a deferred canvas; usually null.
    sk_surface_t* targetSurface;

    // When set, Graphite leaves the target's image in this VkImageLayout, owned by this queue
    // family (e.g. VK_IMAGE_LAYOUT_PRESENT_SRC_KHR before presenting a swapchain image).
    bool hasTargetVkImageLayout;
    int32_t targetVkImageLayout;
    uint32_t targetVkQueueFamilyIndex;

    // VkSemaphore handles: waited on before the recording's work runs, signaled after it.
    // Only read during the call.
    const uint64_t* waitVkSemaphores;
    int32_t waitVkSemaphoreCount;
    const uint64_t* signalVkSemaphores;
    int32_t signalVkSemaphoreCount;

    swsk_graphite_finished_proc finishedProc;  // nullable
    void* finishedContext;
} swsk_graphite_insert_options_t;

// skgpu::graphite::Context::insertRecording with the full InsertRecordingInfo.
SK_C_API sk_graphite_insert_status_t swsk_graphite_context_insert_recording(
    sk_graphite_context_t* context,
    sk_graphite_recording_t* recording,
    const swsk_graphite_insert_options_t* options);

SK_C_PLUS_PLUS_END_GUARD
