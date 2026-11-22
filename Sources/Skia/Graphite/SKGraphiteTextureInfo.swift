/// `skgpu::graphite::TextureInfo`: a texture's format, sample count and mipmapping, for creating
/// backend textures. Backend-specific factories (`.vulkan(_:)`) make one.
///
/// Unique owner of the description: `~Copyable`, deleted in `deinit`.
public struct SKGraphiteTextureInfo: ~Copyable {
	public let handle: OpaquePointer

	init(handle: OpaquePointer) {
		self.handle = handle
	}

	deinit {
		sk_graphite_texture_info_delete(handle)
	}

	public var isValid: Bool { sk_graphite_texture_info_is_valid(handle) }

	public var backend: SKGraphiteBackend { sk_graphite_texture_info_get_backend(handle) }

	public var sampleCount: Int32 { sk_graphite_texture_info_get_sample_count(handle) }

	public var mipmapped: Bool { sk_graphite_texture_info_get_mipmapped(handle) }
}

extension SKGraphiteRecorder {
	/// Allocates a GPU texture. Free it with `deleteBackendTexture` here or on the context:
	/// dropping the returned description doesn't.
	public mutating func createBackendTexture(
		_ width: Int32, _ height: Int32, _ info: borrowing SKGraphiteTextureInfo
	) -> SKGraphiteBackendTexture? {
		__sk_graphite_recorder_create_backend_texture(handle, width, height, info.handle)
			.map(SKGraphiteBackendTexture.init(handle:))
	}

	public mutating func deleteBackendTexture(_ texture: borrowing SKGraphiteBackendTexture) {
		__sk_graphite_recorder_delete_backend_texture(handle, texture.handle)
	}
}

extension SKGraphiteContext {
	public var supportsProtectedContent: Bool { __sk_graphite_context_supports_protected_content(handle) }

	/// Frees a texture from `SKGraphiteRecorder.createBackendTexture`.
	public mutating func deleteBackendTexture(_ texture: borrowing SKGraphiteBackendTexture) {
		__sk_graphite_context_delete_backend_texture(handle, texture.handle)
	}
}

extension SKImage {
	/// `SkImages::TextureFromImage`: `image` uploaded to the GPU for `recorder` (or `image` itself
	/// when it already is one of its textures).
	public static func textureFromImage(
		_ recorder: inout SKGraphiteRecorder, _ image: SKImage, _ mipmapped: Bool = false
	) -> SKImage? {
		__sk_graphite_image_make_texture(recorder.handle, image, mipmapped)
	}

	/// `SkImages::WrapTexture`: samples `texture` as an image. `release` runs once, when Skia is done
	/// with the GPU image or if wrapping fails.
	public static func wrapTexture(
		_ recorder: inout SKGraphiteRecorder, _ texture: borrowing SKGraphiteBackendTexture,
		_ colorType: SKColorType, _ alphaType: SKAlphaType, _ colorSpace: SKColorSpace? = nil,
		_ release: (@Sendable () -> Void)? = nil
	) -> SKImage? {
		final class Release {
			let body: @Sendable () -> Void
			init(_ body: @escaping @Sendable () -> Void) { self.body = body }
		}
		guard let release else {
			return __sk_graphite_image_wrap_texture(recorder.handle, texture.handle, colorType, alphaType, colorSpace, nil, nil)
		}
		return __sk_graphite_image_wrap_texture(
			recorder.handle, texture.handle, colorType, alphaType, colorSpace,
			{ context in Unmanaged<Release>.fromOpaque(context!).takeRetainedValue().body() },
			Unmanaged.passRetained(Release(release)).toOpaque())
	}
}
