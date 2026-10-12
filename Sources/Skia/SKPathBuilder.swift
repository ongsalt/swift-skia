/// Accumulates contours, then produces an `SKPath` with `detach()` or `snapshot()`.
public final class SKPathBuilder {
	public let handle: OpaquePointer

	public init() {
		handle = __sk_pathbuilder_new()
	}

	public init(_ path: SKPath) {
		handle = __sk_pathbuilder_new_from_path(path.handle)
	}

	deinit {
		__sk_pathbuilder_delete(handle)
	}

	/// Returns the path built so far and resets the builder.
	public func detach() -> SKPath {
		SKPath(handle: __sk_pathbuilder_detach_path(handle))
	}

	/// Returns the path built so far and keeps building.
	public func snapshot() -> SKPath {
		SKPath(handle: __sk_pathbuilder_snapshot_path(handle))
	}

	public func reset() {
		__sk_pathbuilder_reset(handle)
	}

	public var fillType: SKPathFillType {
		get { __sk_pathbuilder_get_filltype(handle) }
		set { __sk_pathbuilder_set_filltype(handle, newValue) }
	}

	// MARK: Contours

	public func moveTo(_ x: Float, _ y: Float) {
		__sk_pathbuilder_move_to(handle, x, y)
	}

	public func lineTo(_ x: Float, _ y: Float) {
		__sk_pathbuilder_line_to(handle, x, y)
	}

	public func quadTo(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float) {
		__sk_pathbuilder_quad_to(handle, x0, y0, x1, y1)
	}

	public func conicTo(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float, _ weight: Float) {
		__sk_pathbuilder_conic_to(handle, x0, y0, x1, y1, weight)
	}

	public func cubicTo(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float) {
		__sk_pathbuilder_cubic_to(handle, x0, y0, x1, y1, x2, y2)
	}

	/// SVG-style elliptical arc to (`x`, `y`).
	public func arcTo(
		_ rx: Float, _ ry: Float, _ xAxisRotate: Float, _ largeArc: SKPathArcSize, _ sweep: SKPathDirection,
		_ x: Float, _ y: Float
	) {
		__sk_pathbuilder_arc_to(handle, rx, ry, xAxisRotate, largeArc, sweep, x, y)
	}

	/// Arc of `oval` from `startAngle`, sweeping `sweepAngle` degrees.
	public func arcTo(_ oval: SKRect, _ startAngle: Float, _ sweepAngle: Float, _ forceMoveTo: Bool) {
		var oval = oval
		__sk_pathbuilder_arc_to_with_oval(handle, &oval, startAngle, sweepAngle, forceMoveTo)
	}

	/// Arc tangent to the lines (last point → `x1`,`y1`) and (`x1`,`y1` → `x2`,`y2`).
	public func arcTo(_ x1: Float, _ y1: Float, _ x2: Float, _ y2: Float, _ radius: Float) {
		__sk_pathbuilder_arc_to_with_points(handle, x1, y1, x2, y2, radius)
	}

	public func close() {
		__sk_pathbuilder_close(handle)
	}

	// MARK: Relative contours

	public func rMoveTo(_ dx: Float, _ dy: Float) {
		__sk_pathbuilder_rmove_to(handle, dx, dy)
	}

	public func rLineTo(_ dx: Float, _ dy: Float) {
		__sk_pathbuilder_rline_to(handle, dx, dy)
	}

	public func rQuadTo(_ dx0: Float, _ dy0: Float, _ dx1: Float, _ dy1: Float) {
		__sk_pathbuilder_rquad_to(handle, dx0, dy0, dx1, dy1)
	}

	public func rConicTo(_ dx0: Float, _ dy0: Float, _ dx1: Float, _ dy1: Float, _ weight: Float) {
		__sk_pathbuilder_rconic_to(handle, dx0, dy0, dx1, dy1, weight)
	}

	public func rCubicTo(_ dx0: Float, _ dy0: Float, _ dx1: Float, _ dy1: Float, _ dx2: Float, _ dy2: Float) {
		__sk_pathbuilder_rcubic_to(handle, dx0, dy0, dx1, dy1, dx2, dy2)
	}

	public func rArcTo(
		_ rx: Float, _ ry: Float, _ xAxisRotate: Float, _ largeArc: SKPathArcSize, _ sweep: SKPathDirection,
		_ dx: Float, _ dy: Float
	) {
		__sk_pathbuilder_rarc_to(handle, rx, ry, xAxisRotate, largeArc, sweep, dx, dy)
	}

	// MARK: Shapes

	public func addRect(_ rect: SKRect, _ direction: SKPathDirection = .clockwise) {
		var rect = rect
		__sk_pathbuilder_add_rect(handle, &rect, direction)
	}

	public func addRect(_ rect: SKRect, _ direction: SKPathDirection, _ startIndex: UInt32) {
		var rect = rect
		__sk_pathbuilder_add_rect_start(handle, &rect, direction, startIndex)
	}

	public func addRoundRect(_ rect: SKRect, _ rx: Float, _ ry: Float, _ direction: SKPathDirection = .clockwise) {
		var rect = rect
		__sk_pathbuilder_add_rounded_rect(handle, &rect, rx, ry, direction)
	}

	public func addOval(_ rect: SKRect, _ direction: SKPathDirection = .clockwise) {
		var rect = rect
		__sk_pathbuilder_add_oval(handle, &rect, direction)
	}

	public func addCircle(_ x: Float, _ y: Float, _ radius: Float, _ direction: SKPathDirection = .clockwise) {
		__sk_pathbuilder_add_circle(handle, x, y, radius, direction)
	}

	public func addArc(_ oval: SKRect, _ startAngle: Float, _ sweepAngle: Float) {
		var oval = oval
		__sk_pathbuilder_add_arc(handle, &oval, startAngle, sweepAngle)
	}

	public func addPoly(_ points: [SKPoint], _ close: Bool = true) {
		__sk_pathbuilder_add_poly(handle, points, Int32(points.count), close)
	}

	public func addPath(_ path: SKPath, _ mode: SKPathAddMode = .append) {
		__sk_pathbuilder_add_path(handle, path.handle, mode)
	}

	public func addPath(_ path: SKPath, _ dx: Float, _ dy: Float, _ mode: SKPathAddMode = .append) {
		__sk_pathbuilder_add_path_offset(handle, path.handle, dx, dy, mode)
	}

	public func addPath(_ path: SKPath, _ matrix: SKMatrix, _ mode: SKPathAddMode = .append) {
		var matrix = matrix
		__sk_pathbuilder_add_path_matrix(handle, path.handle, &matrix, mode)
	}

	public func reverseAddPath(_ path: SKPath) {
		__sk_pathbuilder_reverse_add_path(handle, path.handle)
	}
}
