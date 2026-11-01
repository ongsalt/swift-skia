#include "include/swsk_graphite.h"

#include "skia/include/core/SkSurface.h"
#include "skia/include/gpu/MutableTextureState.h"
#include "skia/include/gpu/graphite/BackendSemaphore.h"
#include "skia/include/gpu/graphite/Context.h"
#include "skia/include/gpu/graphite/GraphiteTypes.h"
#include "skia/include/gpu/graphite/Recording.h"

#include <vector>

using namespace skgpu::graphite;

namespace {

std::vector<BackendSemaphore> semaphores(const swsk_graphite_backend_semaphore_t* const* list, int32_t count) {
    std::vector<BackendSemaphore> result;
    for (int32_t i = 0; i < count; i++) {
        result.push_back(*reinterpret_cast<const BackendSemaphore*>(list[i]));
    }
    return result;
}

struct Finished {
    swsk_graphite_finished_proc proc;
    void* context;
};

void finished(GpuFinishedContext context, skgpu::CallbackResult result) {
    auto* f = static_cast<Finished*>(context);
    f->proc(f->context, result == skgpu::CallbackResult::kSuccess);
    delete f;
}

}  // namespace

extern "C" void swsk_graphite_backend_semaphore_delete(swsk_graphite_backend_semaphore_t* semaphore) {
    delete reinterpret_cast<BackendSemaphore*>(semaphore);
}

extern "C" void swsk_graphite_mutable_texture_state_delete(swsk_graphite_mutable_texture_state_t* state) {
    delete reinterpret_cast<skgpu::MutableTextureState*>(state);
}

extern "C" sk_graphite_insert_status_t swsk_graphite_context_insert_recording(
        sk_graphite_context_t* context,
        sk_graphite_recording_t* recording,
        const swsk_graphite_insert_options_t* options) {
    InsertRecordingInfo info;
    info.fRecording = reinterpret_cast<Recording*>(recording);

    std::vector<BackendSemaphore> wait, signal;
    if (options) {
        info.fTargetSurface = reinterpret_cast<SkSurface*>(options->targetSurface);
        // Graphite only reads it.
        info.fTargetTextureState = const_cast<skgpu::MutableTextureState*>(
                reinterpret_cast<const skgpu::MutableTextureState*>(options->targetTextureState));
        wait = semaphores(options->waitSemaphores, options->waitSemaphoreCount);
        signal = semaphores(options->signalSemaphores, options->signalSemaphoreCount);
        info.fNumWaitSemaphores = wait.size();
        info.fWaitSemaphores = wait.data();
        info.fNumSignalSemaphores = signal.size();
        info.fSignalSemaphores = signal.data();
        if (options->finishedProc) {
            info.fFinishedProc = finished;
            info.fFinishedContext = new Finished{options->finishedProc, options->finishedContext};
        }
    }

    // Graphite calls finished() on failure too, so the box is always freed.
    InsertStatus::V status = reinterpret_cast<Context*>(context)->insertRecording(info);
    return static_cast<sk_graphite_insert_status_t>(status);
}
