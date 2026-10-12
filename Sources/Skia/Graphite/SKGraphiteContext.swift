/// Graphite's GPU context: owns the device-side state and executes recordings.
///
/// Unique owner, like rust-skia's `graphite::Context` (`RefHandle`): `~Copyable`, deleted in `deinit`.
public struct SKGraphiteContext: ~Copyable {
	public let handle: OpaquePointer
	/// Keeps the Vulkan proc-lookup state alive for as long as Skia may call back into it.
	private let vulkanProcs: UnsafeMutablePointer<SKGraphiteVulkanBackend.Procs>?

	private init(handle: OpaquePointer, vulkanProcs: UnsafeMutablePointer<SKGraphiteVulkanBackend.Procs>?) {
		self.handle = handle
		self.vulkanProcs = vulkanProcs
	}

	deinit {
		__sk_graphite_context_delete(handle)
		vulkanProcs?.deinitialize(count: 1)
		vulkanProcs?.deallocate()
	}

	/// Creates a Vulkan-backed context on the caller's device. Returns `nil` if Skia rejects the device.
	public static func vulkan(
		_ backend: SKGraphiteVulkanBackend, _ options: SKGraphiteContextOptions? = nil
	) -> SKGraphiteContext? {
		let procs = UnsafeMutablePointer<SKGraphiteVulkanBackend.Procs>.allocate(capacity: 1)
		procs.initialize(to: backend.procs)
		let initInfo = SKGraphiteVkBackendContext(
			fInstance: backend.instance,
			fPhysicalDevice: backend.physicalDevice,
			fDevice: backend.device,
			fQueue: backend.queue,
			fGraphicsQueueIndex: backend.graphicsQueueIndex,
			fMaxAPIVersion: backend.maxAPIVersion,
			fGetProc: SKGraphiteVulkanBackend.getProc,
			fGetProcUserData: UnsafeMutableRawPointer(procs),
			fProtectedContext: backend.isProtected)

		let handle: OpaquePointer?
		if var options {
			handle = __sk_graphite_context_make_vulkan(initInfo, &options)
		} else {
			handle = __sk_graphite_context_make_vulkan(initInfo, nil)
		}
		guard let handle else {
			procs.deinitialize(count: 1)
			procs.deallocate()
			return nil
		}
		return SKGraphiteContext(handle: handle, vulkanProcs: procs)
	}

	public var backend: SKGraphiteBackend { __sk_graphite_context_get_backend(handle) }

	public var isDeviceLost: Bool { __sk_graphite_context_is_device_lost(handle) }

	public var maxTextureSize: Int32 { __sk_graphite_context_get_max_texture_size(handle) }

	public var currentBudgetedBytes: Int64 { __sk_graphite_context_get_current_budgeted_bytes(handle) }

	public var maxBudgetedBytes: Int64 {
		get { __sk_graphite_context_get_max_budgeted_bytes(handle) }
		set { __sk_graphite_context_set_max_budgeted_bytes(handle, newValue) }
	}

	/// `budgetBytes < 0` uses the context's default.
	public mutating func makeRecorder(_ budgetBytes: Int64 = -1) -> SKGraphiteRecorder? {
		__sk_graphite_context_make_recorder(handle, budgetBytes, nil).map(SKGraphiteRecorder.init(handle:))
	}

	/// Queues a recording's work. The recording stays valid and can be inserted again.
	@discardableResult
	public mutating func insertRecording(_ recording: borrowing SKGraphiteRecording) -> SKGraphiteInsertStatus {
		var info = SKGraphiteInsertRecordingInfo()
		info.fRecording = recording.handle
		return __sk_graphite_context_insert_recording(handle, &info)
	}

	/// Submits queued work to the GPU. With `fSync`, waits for it to finish.
	@discardableResult
	public mutating func submit(_ info: SKGraphiteSubmitInfo? = nil) -> Bool {
		guard var info else { return __sk_graphite_context_submit(handle, nil) }
		return __sk_graphite_context_submit(handle, &info)
	}

	public mutating func checkAsyncWorkCompletion() {
		__sk_graphite_context_check_async_work_completion(handle)
	}

	public mutating func freeGpuResources() {
		__sk_graphite_context_free_gpu_resources(handle)
	}

	public mutating func performDeferredCleanup(_ milliseconds: Int64) {
		__sk_graphite_context_perform_deferred_cleanup(handle, milliseconds)
	}

	/// Reads `surface`'s pixels back to the CPU in `info`'s format, waiting for the GPU.
	/// Submits pending work first. Returns `nil` if the read fails (e.g. device lost).
	public mutating func readPixels(_ surface: SKSurface, _ info: SKImageInfo) -> (pixels: [UInt8], rowBytes: Int)? {
		final class Result {
			var done = false
			var value: (pixels: [UInt8], rowBytes: Int)?
			let height: Int
			init(height: Int) { self.height = height }
		}
		let result = Result(height: Int(info.height))
		var info = info
		var rect = SKRectI(left: 0, top: 0, right: info.width, bottom: info.height)
		__sk_graphite_context_async_rescale_and_read_pixels_surface(
			handle, surface, &info, &rect, .src, .nearest,
			{ context, read in
				let result = Unmanaged<Result>.fromOpaque(context!).takeRetainedValue()
				result.done = true
				guard let read, let data = sk_image_async_read_result_get_data(read, 0) else { return }
				let rowBytes = sk_image_async_read_result_get_row_bytes(read, 0)
				let bytes = UnsafeRawBufferPointer(start: data, count: rowBytes * result.height)
				result.value = (Array(bytes), rowBytes)
			},
			Unmanaged.passRetained(result).toOpaque())

		var sync = SKGraphiteSubmitInfo()
		sync.fSync = true
		while !result.done {
			submit(sync)
			checkAsyncWorkCompletion()
		}
		return result.value
	}
}
