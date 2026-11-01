#include "include/swsk_graphite.h"

#include "skia/include/core/SkSurface.h"
#include "skia/include/gpu/MutableTextureState.h"
#include "skia/include/gpu/graphite/BackendSemaphore.h"
#include "skia/include/gpu/graphite/Context.h"
#include "skia/include/gpu/graphite/GraphiteTypes.h"
#include "skia/include/gpu/graphite/Recording.h"
#include "skia/include/gpu/graphite/vk/VulkanGraphiteTypes.h"
#include "skia/include/gpu/vk/VulkanMutableTextureState.h"

#include <vector>

using namespace skgpu::graphite;

namespace {

std::vector<BackendSemaphore> vkSemaphores(const uint64_t* handles, int32_t count) {
    std::vector<BackendSemaphore> semaphores;
    semaphores.reserve(count > 0 ? count : 0);
    for (int32_t i = 0; i < count; i++) {
        semaphores.push_back(BackendSemaphores::MakeVulkan(reinterpret_cast<VkSemaphore>(handles[i])));
    }
    return semaphores;
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

sk_graphite_insert_status_t swsk_graphite_context_insert_recording(
        sk_graphite_context_t* context,
        sk_graphite_recording_t* recording,
        const swsk_graphite_insert_options_t* options) {
    InsertRecordingInfo info;
    info.fRecording = reinterpret_cast<Recording*>(recording);

    std::vector<BackendSemaphore> wait, signal;
    skgpu::MutableTextureState state;
    if (options) {
        info.fTargetSurface = reinterpret_cast<SkSurface*>(options->targetSurface);
        if (options->hasTargetVkImageLayout) {
            state = skgpu::MutableTextureStates::MakeVulkan(
                    static_cast<VkImageLayout>(options->targetVkImageLayout), options->targetVkQueueFamilyIndex);
            info.fTargetTextureState = &state;
        }
        wait = vkSemaphores(options->waitVkSemaphores, options->waitVkSemaphoreCount);
        signal = vkSemaphores(options->signalVkSemaphores, options->signalVkSemaphoreCount);
        info.fNumWaitSemaphores = wait.size();
        info.fWaitSemaphores = wait.data();
        info.fNumSignalSemaphores = signal.size();
        info.fSignalSemaphores = signal.data();
        if (options->finishedProc) {
            info.fFinishedProc = finished;
            info.fFinishedContext = new Finished{options->finishedProc, options->finishedContext};
        }
    }

    // Graphite calls the finished proc on failure too, so the Finished box is always freed.
    InsertStatus::V status = reinterpret_cast<Context*>(context)->insertRecording(info);
    return static_cast<sk_graphite_insert_status_t>(status);
}
