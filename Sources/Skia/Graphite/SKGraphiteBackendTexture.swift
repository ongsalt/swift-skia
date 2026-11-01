/// A caller-owned GPU texture described to Graphite, e.g. a swapchain image.
///
/// Unique owner of the description only: deleting it doesn't free the GPU image. Surfaces wrapping
/// it keep their own reference, so it can be dropped once the surface exists (as in rust-skia).
public struct SKGraphiteBackendTexture: ~Copyable {
	public let handle: OpaquePointer

	deinit {
		__sk_graphite_backend_texture_delete(handle)
	}

	init(handle: OpaquePointer) {
		self.handle = handle
	}

	public var isValid: Bool { __sk_graphite_backend_texture_is_valid(handle) }

	public var backend: SKGraphiteBackend { __sk_graphite_backend_texture_get_backend(handle) }

	public var dimensions: SKSizeI {
		var size = SKSizeI()
		__sk_graphite_backend_texture_get_dimensions(handle, &size.w, &size.h)
		return size
	}
}

extension _SKExclusiveAccess where Self == SKSurface {
	/// A surface drawing into `texture` through `recorder`. As in rust-skia, the surface doesn't
	/// depend on the recorder's or the texture wrapper's lifetime; the GPU image must stay alive.
	public static func wrapBackendTexture(
		_ recorder: inout SKGraphiteRecorder, _ texture: borrowing SKGraphiteBackendTexture,
		_ colorType: SKColorType, _ colorSpace: SKColorSpace? = nil, _ props: OpaquePointer? = nil
	) -> SKSurface? {
		__sk_graphite_surface_wrap_backend_texture(recorder.handle, texture.handle, colorType, colorSpace, props, nil, nil)
	}
}
