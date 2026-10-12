/// Draws into the surface (or other owner) it was obtained from.
///
/// A non-owning, non-escapable view, like rust-skia's `Surface::canvas(&mut self) -> &Canvas`:
/// while a canvas is alive its owner is exclusively borrowed, and the canvas can't outlive it.
public struct SKCanvas: ~Copyable, ~Escapable {
	public let handle: OpaquePointer

	@_lifetime(&owner)
	init<Owner: AnyObject>(_ handle: OpaquePointer, dependingOn owner: inout Owner) {
		self.handle = handle
	}

	// MARK: State

	@discardableResult
	public func save() -> Int32 {
		__sk_canvas_save(handle)
	}

	@discardableResult
	public func saveLayer(_ bounds: SKRect? = nil, _ paint: SKPaint? = nil) -> Int32 {
		guard var bounds else { return __sk_canvas_save_layer(handle, nil, paint?.handle) }
		return __sk_canvas_save_layer(handle, &bounds, paint?.handle)
	}

	public func restore() {
		__sk_canvas_restore(handle)
	}

	public func restoreToCount(_ count: Int32) {
		__sk_canvas_restore_to_count(handle, count)
	}

	public var saveCount: Int32 { __sk_canvas_get_save_count(handle) }

	// MARK: Transform

	public func translate(_ dx: Float, _ dy: Float) {
		__sk_canvas_translate(handle, dx, dy)
	}

	public func scale(_ sx: Float, _ sy: Float) {
		__sk_canvas_scale(handle, sx, sy)
	}

	public func scale(_ s: Float) {
		__sk_canvas_scale(handle, s, s)
	}

	public func rotateDegrees(_ degrees: Float) {
		__sk_canvas_rotate_degrees(handle, degrees)
	}

	public func rotateRadians(_ radians: Float) {
		__sk_canvas_rotate_radians(handle, radians)
	}

	public func skew(_ sx: Float, _ sy: Float) {
		__sk_canvas_skew(handle, sx, sy)
	}

	public func concat(_ matrix: SKMatrix44) {
		var matrix = matrix
		__sk_canvas_concat(handle, &matrix)
	}

	public func resetMatrix() {
		__sk_canvas_reset_matrix(handle)
	}

	public var totalMatrix: SKMatrix44 {
		get {
			var matrix = SKMatrix44()
			__sk_canvas_get_matrix(handle, &matrix)
			return matrix
		}
		nonmutating set {
			var matrix = newValue
			__sk_canvas_set_matrix(handle, &matrix)
		}
	}

	// MARK: Clip

	public func clipRect(_ rect: SKRect, _ operation: SKClipOperation = .intersect, _ antialias: Bool = false) {
		var rect = rect
		__sk_canvas_clip_rect_with_operation(handle, &rect, operation, antialias)
	}

	public func clipPath(_ path: SKPath, _ operation: SKClipOperation = .intersect, _ antialias: Bool = false) {
		__sk_canvas_clip_path_with_operation(handle, path.handle, operation, antialias)
	}

	public var localClipBounds: SKRect {
		var rect = SKRect()
		_ = __sk_canvas_get_local_clip_bounds(handle, &rect)
		return rect
	}

	public var deviceClipBounds: SKRectI {
		var rect = SKRectI()
		_ = __sk_canvas_get_device_clip_bounds(handle, &rect)
		return rect
	}

	public var isClipEmpty: Bool { __sk_canvas_is_clip_empty(handle) }

	public var isClipRect: Bool { __sk_canvas_is_clip_rect(handle) }

	public func quickReject(_ rect: SKRect) -> Bool {
		var rect = rect
		return __sk_canvas_quick_reject(handle, &rect)
	}

	// MARK: Drawing

	public func clear(_ color: SKColor = 0) {
		__sk_canvas_clear(handle, color)
	}

	public func clear(_ color: SKColor4f) {
		__sk_canvas_clear_color4f(handle, color)
	}

	public func discard() {
		__sk_canvas_discard(handle)
	}

	public func drawColor(_ color: SKColor, _ mode: SKBlendMode = .srcOver) {
		__sk_canvas_draw_color(handle, color, mode)
	}

	public func drawPaint(_ paint: SKPaint) {
		__sk_canvas_draw_paint(handle, paint.handle)
	}

	public func drawPoint(_ x: Float, _ y: Float, _ paint: SKPaint) {
		__sk_canvas_draw_point(handle, x, y, paint.handle)
	}

	public func drawPoints(_ mode: SKPointMode, _ points: [SKPoint], _ paint: SKPaint) {
		__sk_canvas_draw_points(handle, mode, points.count, points, paint.handle)
	}

	public func drawLine(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float, _ paint: SKPaint) {
		__sk_canvas_draw_line(handle, x0, y0, x1, y1, paint.handle)
	}

	public func drawLine(_ p0: SKPoint, _ p1: SKPoint, _ paint: SKPaint) {
		__sk_canvas_draw_line(handle, p0.x, p0.y, p1.x, p1.y, paint.handle)
	}

	public func drawRect(_ rect: SKRect, _ paint: SKPaint) {
		var rect = rect
		__sk_canvas_draw_rect(handle, &rect, paint.handle)
	}

	public func drawRect(_ x: Float, _ y: Float, _ width: Float, _ height: Float, _ paint: SKPaint) {
		drawRect(SKRect(left: x, top: y, right: x + width, bottom: y + height), paint)
	}

	public func drawRoundRect(_ rect: SKRect, _ rx: Float, _ ry: Float, _ paint: SKPaint) {
		var rect = rect
		__sk_canvas_draw_round_rect(handle, &rect, rx, ry, paint.handle)
	}

	public func drawOval(_ rect: SKRect, _ paint: SKPaint) {
		var rect = rect
		__sk_canvas_draw_oval(handle, &rect, paint.handle)
	}

	public func drawCircle(_ cx: Float, _ cy: Float, _ radius: Float, _ paint: SKPaint) {
		__sk_canvas_draw_circle(handle, cx, cy, radius, paint.handle)
	}

	public func drawCircle(_ center: SKPoint, _ radius: Float, _ paint: SKPaint) {
		__sk_canvas_draw_circle(handle, center.x, center.y, radius, paint.handle)
	}

	public func drawArc(_ oval: SKRect, _ startAngle: Float, _ sweepAngle: Float, _ useCenter: Bool, _ paint: SKPaint) {
		var oval = oval
		__sk_canvas_draw_arc(handle, &oval, startAngle, sweepAngle, useCenter, paint.handle)
	}

	public func drawPath(_ path: SKPath, _ paint: SKPaint) {
		__sk_canvas_draw_path(handle, path.handle, paint.handle)
	}

	public func drawImage(
		_ image: SKImage, _ x: Float, _ y: Float, _ sampling: SKSamplingOptions = SKSamplingOptions(),
		_ paint: SKPaint? = nil
	) {
		var sampling = sampling
		__sk_canvas_draw_image(handle, image, x, y, &sampling, paint?.handle)
	}

	public func drawImage(
		_ image: SKImage, _ dest: SKRect, _ sampling: SKSamplingOptions = SKSamplingOptions(),
		_ paint: SKPaint? = nil
	) {
		var (dest, sampling) = (dest, sampling)
		__sk_canvas_draw_image_rect(handle, image, nil, &dest, &sampling, paint?.handle)
	}

	public func drawImage(
		_ image: SKImage, _ source: SKRect, _ dest: SKRect, _ sampling: SKSamplingOptions = SKSamplingOptions(),
		_ paint: SKPaint? = nil
	) {
		var (source, dest, sampling) = (source, dest, sampling)
		__sk_canvas_draw_image_rect(handle, image, &source, &dest, &sampling, paint?.handle)
	}

	public func drawText(_ text: String, _ x: Float, _ y: Float, _ font: SKFont, _ paint: SKPaint) {
		var text = text
		text.withUTF8 { utf8 in
			__sk_canvas_draw_simple_text(handle, utf8.baseAddress, utf8.count, .utf8, x, y, font.handle, paint.handle)
		}
	}

	public func drawTextBlob(_ blob: SKTextBlob, _ x: Float, _ y: Float, _ paint: SKPaint) {
		__sk_canvas_draw_text_blob(handle, blob, x, y, paint.handle)
	}

	public func drawPicture(_ picture: SKPicture, _ matrix: SKMatrix? = nil, _ paint: SKPaint? = nil) {
		guard var matrix else { return __sk_canvas_draw_picture(handle, picture, nil, paint?.handle) }
		__sk_canvas_draw_picture(handle, picture, &matrix, paint?.handle)
	}
}

/// Gives class owners a `mutating` accessor, which classes can't declare themselves,
/// so a borrowed canvas can hold an exclusive (`inout`) borrow of its owner.
public protocol _SKExclusiveAccess {}

extension SKSurface: _SKExclusiveAccess {}

extension _SKExclusiveAccess where Self == SKSurface {
	/// The surface's canvas. While it's alive, the surface variable is exclusively borrowed.
	public var canvas: SKCanvas {
		@_lifetime(&self)
		mutating get {
			SKCanvas(__sk_surface_get_canvas(self), dependingOn: &self)
		}
	}
}
