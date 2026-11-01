// Graphite API SkiaSharp's C API doesn't cover yet. Backend-specific constructors live in
// swsk_graphite_<backend>.h.
#pragma once

#include "skia/include/c/sk_graphite.h"

SK_C_PLUS_PLUS_BEGIN_GUARD

// skgpu::graphite::BackendSemaphore. Deleting it doesn't destroy the GPU semaphore.
typedef struct swsk_graphite_backend_semaphore_t swsk_graphite_backend_semaphore_t;
// skgpu::MutableTextureState.
typedef struct swsk_graphite_mutable_texture_state_t swsk_graphite_mutable_texture_state_t;

SK_C_API void swsk_graphite_backend_semaphore_delete(swsk_graphite_backend_semaphore_t* semaphore);
SK_C_API void swsk_graphite_mutable_texture_state_delete(swsk_graphite_mutable_texture_state_t* state);

typedef void (*swsk_graphite_finished_proc)(void* context, bool success);

// skgpu::graphite::InsertRecordingInfo minus the recording. Only read during the call.
typedef struct {
    sk_surface_t* targetSurface;  // required with targetTextureState
    const swsk_graphite_mutable_texture_state_t* targetTextureState;
    const swsk_graphite_backend_semaphore_t* const* waitSemaphores;
    int32_t waitSemaphoreCount;
    const swsk_graphite_backend_semaphore_t* const* signalSemaphores;
    int32_t signalSemaphoreCount;
    swsk_graphite_finished_proc finishedProc;  // called exactly once, failure included
    void* finishedContext;
} swsk_graphite_insert_options_t;

SK_C_API sk_graphite_insert_status_t swsk_graphite_context_insert_recording(
    sk_graphite_context_t* context,
    sk_graphite_recording_t* recording,
    const swsk_graphite_insert_options_t* options);

SK_C_PLUS_PLUS_END_GUARD
