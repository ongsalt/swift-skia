/// How to draw: color, style, stroke, and the shader/filter/blend effects.
/// Reference semantics: `let b = a` shares one paint; use `copy()` for an independent one.
public final class SKPaint {
	public let handle: OpaquePointer

	init(handle: OpaquePointer) {
		self.handle = handle
	}

	public init() {
		handle = __sk_paint_new()
	}

	deinit {
		__sk_paint_delete(handle)
	}

	public func copy() -> SKPaint {
		SKPaint(handle: __sk_paint_clone(handle))
	}

	public func reset() {
		__sk_paint_reset(handle)
	}

	public var isAntiAlias: Bool {
		get { __sk_paint_is_antialias(handle) }
		set { __sk_paint_set_antialias(handle, newValue) }
	}

	public var isDither: Bool {
		get { __sk_paint_is_dither(handle) }
		set { __sk_paint_set_dither(handle, newValue) }
	}

	public var color: SKColor {
		get { __sk_paint_get_color(handle) }
		set { __sk_paint_set_color(handle, newValue) }
	}

	public var color4f: SKColor4f {
		var color = SKColor4f()
		__sk_paint_get_color4f(handle, &color)
		return color
	}

	public func setColor(_ color: SKColor4f, _ colorSpace: SKColorSpace? = nil) {
		var color = color
		__sk_paint_set_color4f(handle, &color, colorSpace)
	}

	public var style: SKPaintStyle {
		get { __sk_paint_get_style(handle) }
		set { __sk_paint_set_style(handle, newValue) }
	}

	public var strokeWidth: Float {
		get { __sk_paint_get_stroke_width(handle) }
		set { __sk_paint_set_stroke_width(handle, newValue) }
	}

	public var strokeMiter: Float {
		get { __sk_paint_get_stroke_miter(handle) }
		set { __sk_paint_set_stroke_miter(handle, newValue) }
	}

	public var strokeCap: SKStrokeCap {
		get { __sk_paint_get_stroke_cap(handle) }
		set { __sk_paint_set_stroke_cap(handle, newValue) }
	}

	public var strokeJoin: SKStrokeJoin {
		get { __sk_paint_get_stroke_join(handle) }
		set { __sk_paint_set_stroke_join(handle, newValue) }
	}

	public var blendMode: SKBlendMode {
		get { __sk_paint_get_blendmode(handle) }
		set { __sk_paint_set_blendmode(handle, newValue) }
	}

	public var blender: SKBlender? {
		get { __sk_paint_get_blender(handle) }
		set { __sk_paint_set_blender(handle, newValue) }
	}

	public var shader: SKShader? {
		get { __sk_paint_get_shader(handle) }
		set { __sk_paint_set_shader(handle, newValue) }
	}

	public var colorFilter: SKColorFilter? {
		get { __sk_paint_get_colorfilter(handle) }
		set { __sk_paint_set_colorfilter(handle, newValue) }
	}

	public var maskFilter: SKMaskFilter? {
		get { __sk_paint_get_maskfilter(handle) }
		set { __sk_paint_set_maskfilter(handle, newValue) }
	}

	public var imageFilter: SKImageFilter? {
		get { __sk_paint_get_imagefilter(handle) }
		set { __sk_paint_set_imagefilter(handle, newValue) }
	}

	public var pathEffect: SKPathEffect? {
		get { __sk_paint_get_path_effect(handle) }
		set { __sk_paint_set_path_effect(handle, newValue) }
	}

	/// The outline this paint would fill when drawing `path` (applying stroke and path effect).
	/// `cullRect` limits the work to an area; a `matrix` that scales up adds precision.
	/// Nil when the result is a hairline (to be stroked, not filled).
	public func getFillPath(_ path: SKPath, _ cullRect: SKRect? = nil, _ matrix: SKMatrix = .identity) -> SKPath? {
		let builder = SKPathBuilder()
		var matrix = matrix
		let filled = _skWithOptionalPointer(cullRect) { cullRect in
			__sk_paint_get_fill_path(handle, path.handle, builder.handle, cullRect, &matrix)
		}
		return filled ? builder.detach() : nil
	}

	/// Whether `computeFastBounds` can be used (false for some effects).
	public var canComputeFastBounds: Bool { __sk_paint_can_compute_fast_bounds(handle) }

	/// A conservative bound of what drawing a shape with `bounds` covers with this paint.
	public func computeFastBounds(_ bounds: SKRect) -> SKRect {
		var bounds = bounds
		var result = SKRect()
		__sk_paint_compute_fast_bounds(handle, &bounds, &result)
		return result
	}
}
