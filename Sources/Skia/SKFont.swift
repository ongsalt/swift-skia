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

	public func glyphs(_ text: String) -> [UInt16] {
		let bytes = text.utf8.span.bytes
		var none: MutableSpan<UInt16>? = nil
		let count = __sk_font_text_to_glyphs(handle, bytes, .utf8, &none)
		var glyphs = [UInt16](repeating: 0, count: Int(count))
		var span: MutableSpan<UInt16>? = glyphs.mutableSpan
		_ = __sk_font_text_to_glyphs(handle, bytes, .utf8, &span)
		return glyphs
	}
}
