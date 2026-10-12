/// A caller-owned GPU texture described to Graphite, e.g. a swapchain `VkImage`.
///
/// Unique owner of the description only: deleting it doesn't free the GPU image. Surfaces wrapping
/// it keep their own reference, so it can be dropped once the surface exists (as in rust-skia).
public struct SKGraphiteBackendTexture: ~Copyable {
	public let handle: OpaquePointer

	deinit {
		__sk_graphite_backend_texture_delete(handle)
	}

	/// Wraps a `VkImage` whose memory is already bound.
	/// - `imageLayout`: the `VkImageLayout` the image is in now (`VK_IMAGE_LAYOUT_UNDEFINED` = 0 for a
	///   freshly acquired swapchain image whose contents may be discarded).
	public static func vulkan(
		_ width: Int32, _ height: Int32, _ info: SKGraphiteVkTextureInfo, _ imageLayout: Int32,
		_ queueFamilyIndex: UInt32, _ image: OpaquePointer
	) -> SKGraphiteBackendTexture? {
		var info = info
		guard let handle = __sk_graphite_vk_backend_texture_new(width, height, &info, imageLayout, queueFamilyIndex, UnsafeMutableRawPointer(image))
		else { return nil }
		return SKGraphiteBackendTexture(handle: handle)
	}

	private init(handle: OpaquePointer) {
		self.handle = handle
	}

	public var isValid: Bool { __sk_graphite_backend_texture_is_valid(handle) }

	public var backend: SKGraphiteBackend { __sk_graphite_backend_texture_get_backend(handle) }

	public var width: Int32 {
		var (width, height): (Int32, Int32) = (0, 0)
		__sk_graphite_backend_texture_get_dimensions(handle, &width, &height)
		return width
	}

	public var height: Int32 {
		var (width, height): (Int32, Int32) = (0, 0)
		__sk_graphite_backend_texture_get_dimensions(handle, &width, &height)
		return height
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
