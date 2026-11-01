/// `skgpu::graphite::InsertRecordingInfo` beyond the recording (Sources/CSkia/swsk_graphite.cpp).
public struct SKGraphiteInsertOptions {
	/// Required with `targetTextureState`, and for recordings made with a deferred canvas.
	public var targetSurface: SKSurface?
	public var targetTextureState: SKGraphiteMutableTextureState?
	public var waitSemaphores: [SKGraphiteBackendSemaphore]
	public var signalSemaphores: [SKGraphiteBackendSemaphore]
	/// Called once with whether the GPU work succeeded, from inside `submit` or
	/// `checkAsyncWorkCompletion`.
	public var finished: ((Bool) -> Void)?

	public init(
		targetSurface: SKSurface? = nil,
		targetTextureState: SKGraphiteMutableTextureState? = nil,
		waitSemaphores: [SKGraphiteBackendSemaphore] = [],
		signalSemaphores: [SKGraphiteBackendSemaphore] = [],
		finished: ((Bool) -> Void)? = nil
	) {
		self.targetSurface = targetSurface
		self.targetTextureState = targetTextureState
		self.waitSemaphores = waitSemaphores
		self.signalSemaphores = signalSemaphores
		self.finished = finished
	}
}

extension SKGraphiteContext {
	/// The recording stays valid and can be inserted again.
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
		info.targetTextureState = options.targetTextureState?.handle
		if let body = options.finished {
			info.finishedProc = { context, success in
				Unmanaged<Finished>.fromOpaque(context!).takeRetainedValue().body(success)
			}
			info.finishedContext = Unmanaged.passRetained(Finished(body)).toOpaque()
		}
		let wait: [OpaquePointer?] = options.waitSemaphores.map(\.handle)
		let signal: [OpaquePointer?] = options.signalSemaphores.map(\.handle)
		let handle = self.handle
		return withExtendedLifetime(options) {
			wait.withUnsafeBufferPointer { wait in
				signal.withUnsafeBufferPointer { signal in
					info.waitSemaphores = wait.baseAddress
					info.waitSemaphoreCount = Int32(wait.count)
					info.signalSemaphores = signal.baseAddress
					info.signalSemaphoreCount = Int32(signal.count)
					return swsk_graphite_context_insert_recording(handle, recording.handle, &info)
				}
			}
		}
	}
}
