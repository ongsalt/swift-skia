/// Typeface plus size and rendering options for text.
public final class SKFont {
	public let handle: OpaquePointer

	public init(_ typeface: SKTypeface? = nil, _ size: Float = 12, _ scaleX: Float = 1, _ skewX: Float = 0) {
		handle = __sk_font_new_with_values(typeface, size, scaleX, skewX)
	}

	deinit {
		__sk_font_delete(handle)
	}

	public var typeface: SKTypeface? {
		get { __sk_font_get_typeface(handle) }
		set { __sk_font_set_typeface(handle, newValue) }
	}

	public var size: Float {
		get { __sk_font_get_size(handle) }
		set { __sk_font_set_size(handle, newValue) }
	}

	public var scaleX: Float {
		get { __sk_font_get_scale_x(handle) }
		set { __sk_font_set_scale_x(handle, newValue) }
	}

	public var skewX: Float {
		get { __sk_font_get_skew_x(handle) }
		set { __sk_font_set_skew_x(handle, newValue) }
	}

	public var edging: SKFontEdging {
		get { __sk_font_get_edging(handle) }
		set { __sk_font_set_edging(handle, newValue) }
	}

	public var hinting: SKFontHinting {
		get { __sk_font_get_hinting(handle) }
		set { __sk_font_set_hinting(handle, newValue) }
	}

	public var isForceAutoHinting: Bool {
		get { __sk_font_is_force_auto_hinting(handle) }
		set { __sk_font_set_force_auto_hinting(handle, newValue) }
	}

	public var isEmbeddedBitmaps: Bool {
		get { __sk_font_is_embedded_bitmaps(handle) }
		set { __sk_font_set_embedded_bitmaps(handle, newValue) }
	}

	public var isSubpixel: Bool {
		get { __sk_font_is_subpixel(handle) }
		set { __sk_font_set_subpixel(handle, newValue) }
	}

	public var isLinearMetrics: Bool {
		get { __sk_font_is_linear_metrics(handle) }
		set { __sk_font_set_linear_metrics(handle, newValue) }
	}

	public var isEmbolden: Bool {
		get { __sk_font_is_embolden(handle) }
		set { __sk_font_set_embolden(handle, newValue) }
	}

	public var isBaselineSnap: Bool {
		get { __sk_font_is_baseline_snap(handle) }
		set { __sk_font_set_baseline_snap(handle, newValue) }
	}

	public var metrics: SKFontMetrics {
		var metrics = SKFontMetrics()
		__sk_font_get_metrics(handle, &metrics)
		return metrics
	}

	/// Recommended distance between lines of text.
	public var spacing: Float {
		var metrics = SKFontMetrics()
		return __sk_font_get_metrics(handle, &metrics)
	}

	public func measureText(_ text: String, _ paint: SKPaint? = nil) -> Float {
		__sk_font_measure_text(handle, text.utf8.span.bytes, .utf8, nil, paint?.handle)
	}

	public func textToGlyphs(_ text: String) -> [UInt16] {
		let bytes = text.utf8.span.bytes
		var none: MutableSpan<UInt16>? = nil
		let count = __sk_font_text_to_glyphs(handle, bytes, .utf8, &none)
		var glyphs = [UInt16](repeating: 0, count: Int(count))
		var span: MutableSpan<UInt16>? = glyphs.mutableSpan
		_ = __sk_font_text_to_glyphs(handle, bytes, .utf8, &span)
		return glyphs
	}

	public func unicharToGlyph(_ unichar: Unicode.Scalar) -> UInt16 {
		__sk_font_unichar_to_glyph(handle, Int32(bitPattern: unichar.value))
	}

	public func unicharsToGlyphs(_ unichars: [Unicode.Scalar]) -> [UInt16] {
		let unichars = unichars.map { Int32(bitPattern: $0.value) }
		var glyphs = [UInt16](repeating: 0, count: unichars.count)
		var span = glyphs.mutableSpan
		__sk_font_unichars_to_glyphs(handle, unichars.span, &span)
		return glyphs
	}

	/// Advance widths of `glyphs`.
	public func getWidths(_ glyphs: [UInt16], _ paint: SKPaint? = nil) -> [Float] {
		var widths = [Float](repeating: 0, count: glyphs.count)
		var span: MutableSpan<Float>? = widths.mutableSpan
		var noBounds: MutableSpan<SKRect>? = nil
		__sk_font_get_widths_bounds(handle, glyphs.span, &span, &noBounds, paint?.handle)
		return widths
	}

	/// Bounds of each glyph, relative to its origin.
	public func getBounds(_ glyphs: [UInt16], _ paint: SKPaint? = nil) -> [SKRect] {
		var bounds = [SKRect](repeating: SKRect(), count: glyphs.count)
		var span: MutableSpan<SKRect>? = bounds.mutableSpan
		var noWidths: MutableSpan<Float>? = nil
		__sk_font_get_widths_bounds(handle, glyphs.span, &noWidths, &span, paint?.handle)
		return bounds
	}

	/// Where each glyph is drawn when laid out in a row starting at `origin`.
	public func getPos(_ glyphs: [UInt16], _ origin: SKPoint = SKPoint()) -> [SKPoint] {
		var positions = [SKPoint](repeating: SKPoint(), count: glyphs.count)
		var span = positions.mutableSpan
		var origin = origin
		__sk_font_get_pos(handle, glyphs.span, &span, &origin)
		return positions
	}

	public func getXPos(_ glyphs: [UInt16], _ origin: Float = 0) -> [Float] {
		var positions = [Float](repeating: 0, count: glyphs.count)
		var span = positions.mutableSpan
		__sk_font_get_xpos(handle, glyphs.span, &span, origin)
		return positions
	}

	/// Nil for glyphs without an outline (e.g. bitmap glyphs).
	public func getPath(_ glyph: UInt16) -> SKPath? {
		let path = SKPath()
		return __sk_font_get_path(handle, glyph, path.handle) ? path : nil
	}

	/// How much of `text` fits in `maxWidth`: its length in UTF-8 bytes and its width.
	public func breakText(_ text: String, _ maxWidth: Float, _ paint: SKPaint? = nil) -> (byteCount: Int, width: Float) {
		var width: Float = 0
		let count = __sk_font_break_text(handle, text.utf8.span.bytes, .utf8, maxWidth, &width, paint?.handle)
		return (count, width)
	}

	/// `SkTextUtils::GetPath`: the outlines of `text` drawn at (`x`, `y`).
	public func getTextPath(_ text: String, _ x: Float, _ y: Float) -> SKPath {
		let path = SKPath()
		__sk_text_utils_get_path(text.utf8.span.bytes, .utf8, x, y, handle, path.handle)
		return path
	}
}
