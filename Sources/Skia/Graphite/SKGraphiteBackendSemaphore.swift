/// A GPU semaphore, from a backend factory such as `vulkan(_:)`. Doesn't own the semaphore.
public final class SKGraphiteBackendSemaphore {
	public let handle: OpaquePointer

	init(handle: OpaquePointer) {
		self.handle = handle
	}

	deinit {
		swsk_graphite_backend_semaphore_delete(handle)
	}
}

/// The state Graphite leaves a target texture in, from a backend factory such as `vulkan(_:_:)`.
public final class SKGraphiteMutableTextureState {
	public let handle: OpaquePointer

	init(handle: OpaquePointer) {
		self.handle = handle
	}

	deinit {
		swsk_graphite_mutable_texture_state_delete(handle)
	}
}
