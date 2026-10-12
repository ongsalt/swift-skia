/// Pixel memory owned by something else (a raster surface or image), with its format.
///
/// Like rust-skia's `Pixmap<'a>`: it borrows the pixels, so it's `~Escapable` and can't outlive
/// the surface or image it came from. Its own small C handle is freed in `deinit`.
public struct SKPixmap: ~Copyable, ~Escapable {
	public let handle: OpaquePointer

	/// Unconstrained; the `peekPixels()` that returns it declares the real dependency.
	@_lifetime(immortal)
	init(_unsafeHandle handle: OpaquePointer) {
		self.handle = handle
	}

	deinit {
		__sk_pixmap_destructor(handle)
	}

	public var info: SKImageInfo {
		var info = SKImageInfo()
		__sk_pixmap_get_info(handle, &info)
		return info
	}

	public var width: Int32 { info.width }

	public var height: Int32 { info.height }

	public var colorType: SKColorType { info.colorType }

	public var rowBytes: Int { __sk_pixmap_get_row_bytes(handle) }

	public var isOpaque: Bool { __sk_pixmap_compute_is_opaque(handle) }

	private func checkBounds(_ x: Int32, _ y: Int32) {
		let info = info
		precondition(x >= 0 && x < info.width && y >= 0 && y < info.height, "pixel (\(x), \(y)) outside \(info.width)x\(info.height)")
	}

	/// The pixel at (`x`, `y`), converted to unpremultiplied ARGB.
	public func pixelColor(_ x: Int32, _ y: Int32) -> SKColor {
		checkBounds(x, y)
		return __sk_pixmap_get_pixel_color(handle, x, y)
	}

	/// The pixel at (`x`, `y`), converted to unpremultiplied RGBA floats.
	public func pixelColor4f(_ x: Int32, _ y: Int32) -> SKColor4f {
		checkBounds(x, y)
		var color = SKColor4f()
		__sk_pixmap_get_pixel_color4f(handle, x, y, &color)
		return color
	}

	public func pixelAlpha(_ x: Int32, _ y: Int32) -> Float {
		checkBounds(x, y)
		return __sk_pixmap_get_pixel_alphaf(handle, x, y)
	}

	/// The pixel rows, `rowBytes` apart. The last row ends at its last pixel, as Skia allocates it.
	public var bytes: RawSpan {
		@_lifetime(copy self)
		get {
			let info = info
			let byteCount = info.height > 0
				? rowBytes * Int(info.height - 1) + Int(info.width) * info.colorType.bytesPerPixel : 0
			guard byteCount > 0, let start = __sk_pixmap_get_writable_addr(handle) else {
				return unsafe _overrideLifetime(RawSpan(), copying: self)
			}
			let span = unsafe RawSpan(_unsafeStart: start, byteCount: byteCount)
			return unsafe _overrideLifetime(span, copying: self)
		}
	}

	public var colorSpace: SKColorSpace? {
		get { __sk_pixmap_get_colorspace(handle) }
		nonmutating set { __sk_pixmap_set_colorspace(handle, newValue) }
	}

	/// Fills the pixels (or `subset` of them) with `color`.
	@discardableResult
	public func erase(_ color: SKColor, _ subset: SKRectI? = nil) -> Bool {
		guard var subset else { return __sk_pixmap_erase_color(handle, color, nil) }
		return __sk_pixmap_erase_color(handle, color, &subset)
	}

	@discardableResult
	public func erase(_ color: SKColor4f, _ subset: SKRectI? = nil) -> Bool {
		var color = color
		guard var subset else { return __sk_pixmap_erase_color4f(handle, &color, nil) }
		return __sk_pixmap_erase_color4f(handle, &color, &subset)
	}

	/// Copies pixels into `dst`, converting to `dstInfo`. Returns false if the conversion isn't
	/// supported or `dst` is too small for `dstInfo` at `dstRowBytes`.
	public func readPixels(
		_ dstInfo: SKImageInfo, _ dst: inout MutableRawSpan, _ dstRowBytes: Int, _ srcX: Int32 = 0, _ srcY: Int32 = 0
	) -> Bool {
		let needed = dstInfo.height > 0
			? dstRowBytes * Int(dstInfo.height - 1) + Int(dstInfo.width) * dstInfo.colorType.bytesPerPixel : 0
		guard dst.byteCount >= needed, dstRowBytes >= Int(dstInfo.width) * dstInfo.colorType.bytesPerPixel else { return false }
		var dstInfo = dstInfo
		return unsafe dst.withUnsafeMutableBytes { buffer in
			__sk_pixmap_read_pixels(handle, &dstInfo, buffer.baseAddress, dstRowBytes, srcX, srcY)
		}
	}

	/// Scales these pixels into `dst`'s size and format.
	public func scalePixels(_ dst: borrowing SKPixmap, _ sampling: SKSamplingOptions = SKSamplingOptions()) -> Bool {
		var sampling = sampling
		return __sk_pixmap_scale_pixels(handle, dst.handle, &sampling)
	}

	/// A pixmap over the `subset` rectangle of these pixels (no copy).
	@_lifetime(copy self)
	public func extractSubset(_ subset: SKRectI) -> SKPixmap? {
		var subset = subset
		let result = __sk_pixmap_new()!
		guard __sk_pixmap_extract_subset(handle, result, &subset) else {
			__sk_pixmap_destructor(result)
			return nil
		}
		return unsafe _overrideLifetime(SKPixmap(_unsafeHandle: result), copying: self)
	}

	/// Encodes the pixels. `quality` (0–100) applies to JPEG and WebP; WebP at 100 is lossless.
	/// Returns `nil` for formats Skia can't encode (only PNG, JPEG and WebP are built in).
	public func encode(_ format: SKEncodedImageFormat = .png, _ quality: Int32 = 100) -> SKData? {
		let stream = sk_dynamicmemorywstream_new()
		defer { sk_dynamicmemorywstream_destroy(stream) }
		let encoded: Bool
		switch format {
		case .png:
			var options = SKPngEncoderOptions()
			options.fFilterFlags = .allFilters
			options.fZLibLevel = 6
			encoded = __sk_pngencoder_encode(stream, handle, &options)
		case .jpeg:
			var options = SKJpegEncoderOptions()
			options.fQuality = quality
			encoded = __sk_jpegencoder_encode(stream, handle, &options)
		case .webp:
			var options = SKWebpEncoderOptions()
			options.fCompression = quality >= 100 ? .lossless : .lossy
			options.fQuality = Float(quality)
			encoded = __sk_webpencoder_encode(stream, handle, &options)
		default:
			return nil
		}
		return encoded ? sk_dynamicmemorywstream_detach_as_data(stream) : nil
	}
}

extension SKImage {
	/// The image's pixels, if it's a raster image (nil for GPU-backed or lazily decoded images).
	@_lifetime(borrow self)
	public func peekPixels() -> SKPixmap? {
		let handle = __sk_pixmap_new()!
		guard __sk_image_peek_pixels(self, handle) else {
			__sk_pixmap_destructor(handle)
			return nil
		}
		return SKPixmap(_unsafeHandle: handle)
	}

	/// Encodes a raster or lazily decoded image. Returns `nil` for GPU-backed images: read those
	/// back first (`SKGraphiteContext.readPixels(_:_:)`), since that needs the GPU context.
	public func encode(_ format: SKEncodedImageFormat = .png, _ quality: Int32 = 100) -> SKData? {
		guard !isTextureBacked else { return nil }
		let raster = isLazyGenerated ? makeRasterImage() : self
		guard let raster, let pixmap = raster.peekPixels() else { return nil }
		return pixmap.encode(format, quality)
	}

	/// A raster image holding a copy of `pixmap`'s pixels.
	public static func rasterCopy(_ pixmap: borrowing SKPixmap) -> SKImage? {
		__sk_image_new_raster_copy_with_pixmap(pixmap.handle)
	}

	/// Copies pixels into `dst`, converting to its format.
	public func readPixels(
		_ dst: borrowing SKPixmap, _ srcX: Int32 = 0, _ srcY: Int32 = 0, _ cachingHint: SKImageCachingHint = .allow
	) -> Bool {
		__sk_image_read_pixels_into_pixmap(self, dst.handle, srcX, srcY, cachingHint)
	}

	/// Scales the image into `dst`'s size and format.
	public func scalePixels(
		_ dst: borrowing SKPixmap, _ sampling: SKSamplingOptions = SKSamplingOptions(),
		_ cachingHint: SKImageCachingHint = .allow
	) -> Bool {
		var sampling = sampling
		return __sk_image_scale_pixels(self, dst.handle, &sampling, cachingHint)
	}
}

extension _SKExclusiveAccess where Self == SKSurface {
	/// A raster surface's pixels (nil for GPU surfaces). The surface is exclusively borrowed while
	/// the pixmap is alive, like rust-skia's `Surface::peek_pixels(&mut self)`.
	@_lifetime(&self)
	public mutating func peekPixels() -> SKPixmap? {
		let handle = __sk_pixmap_new()!
		guard __sk_surface_peek_pixels(self, handle) else {
			__sk_pixmap_destructor(handle)
			return nil
		}
		return SKPixmap(_unsafeHandle: handle)
	}
}

extension SKColorType {
	/// Bytes per pixel, as Skia's `SkColorTypeBytesPerPixel`. 0 for unknown types.
	public var bytesPerPixel: Int {
		switch self {
		case .unknown: 0
		case .alpha8, .gray8, .r8Unorm: 1
		case .rgb565, .argb4444, .r8g8Unorm, .a16Float, .r16Float, .a16Unorm, .r16Unorm: 2
		case .rgba8888, .rgb888x, .bgra8888, .rgba1010102, .bgra1010102, .rgb101010x, .bgr101010x,
			.bgr101010xXr, .r16g16Float, .r16g16Unorm, .srgba8888:
			4
		case .bgra10101010Xr, .rgba10x6, .rgbaF16Norm, .rgbaF16, .rgbF16f16f16x, .r16g16b16a16Unorm: 8
		case .rgbaF32: 16
		@unknown default: 0
		}
	}
}
