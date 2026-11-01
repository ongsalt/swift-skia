/// What Graphite needs besides the recording to hand a frame to presentation: the layout to leave
/// the target image in, semaphores to order its GPU work, and a completion callback.
///
/// Covers `skgpu::graphite::InsertRecordingInfo` (through Sources/CSkia/swsk_graphite.cpp), which
/// SkiaSharp's C API doesn't expose yet.
public struct SKGraphiteInsertOptions {
	/// The surface a deferred-canvas recording draws into; nil for ordinary recordings.
	public var targetSurface: SKSurface?
	/// Vulkan: the `VkImageLayout` (raw value) to leave the target's image in, owned by
	/// `queueFamilyIndex`, e.g. `VK_IMAGE_LAYOUT_PRESENT_SRC_KHR` (1000001002) before presenting.
	public var targetVulkanImageLayout: (layout: Int32, queueFamilyIndex: UInt32)?
	/// `VkSemaphore` handles waited on before the recording's GPU work runs.
	public var waitSemaphores: [UInt64]
	/// `VkSemaphore` handles signaled once the recording's GPU work is done.
	public var signalSemaphores: [UInt64]
	/// Called once the GPU work finished (`true`) or failed (`false`), from inside
	/// `SKGraphiteContext.submit` or `checkAsyncWorkCompletion`.
	public var finished: ((Bool) -> Void)?

	public init(
		targetSurface: SKSurface? = nil,
		targetVulkanImageLayout: (layout: Int32, queueFamilyIndex: UInt32)? = nil,
		waitSemaphores: [UInt64] = [],
		signalSemaphores: [UInt64] = [],
		finished: ((Bool) -> Void)? = nil
	) {
		self.targetSurface = targetSurface
		self.targetVulkanImageLayout = targetVulkanImageLayout
		self.waitSemaphores = waitSemaphores
		self.signalSemaphores = signalSemaphores
		self.finished = finished
	}
}

extension SKGraphiteContext {
	/// Queues a recording's work with presentation options. The recording stays valid and can be
	/// inserted again.
	@discardableResult
	public mutating func insertRecording(
		_ recording: borrowing SKGraphiteRecording, options: SKGraphiteInsertOptions
	) -> SKGraphiteInsertStatus {
		final class Finished {
			let body: (Bool) -> Void
			init(_ body: @escaping (Bool) -> Void) { self.body = body }
		}
		var info = swsk_graphite_insert_options_t()
		info.targetSurface = options.targetSurface
		if let state = options.targetVulkanImageLayout {
			info.hasTargetVkImageLayout = true
			info.targetVkImageLayout = state.layout
			info.targetVkQueueFamilyIndex = state.queueFamilyIndex
		}
		if let body = options.finished {
			info.finishedProc = { context, success in
				Unmanaged<Finished>.fromOpaque(context!).takeRetainedValue().body(success)
			}
			// Released by the callback, which Graphite calls exactly once, failure included.
			info.finishedContext = Unmanaged.passRetained(Finished(body)).toOpaque()
		}
		let handle = self.handle
		return options.waitSemaphores.withUnsafeBufferPointer { wait in
			options.signalSemaphores.withUnsafeBufferPointer { signal in
				info.waitVkSemaphores = wait.baseAddress
				info.waitVkSemaphoreCount = Int32(wait.count)
				info.signalVkSemaphores = signal.baseAddress
				info.signalVkSemaphoreCount = Int32(signal.count)
				return swsk_graphite_context_insert_recording(handle, recording.handle, &info)
			}
		}
	}
}
