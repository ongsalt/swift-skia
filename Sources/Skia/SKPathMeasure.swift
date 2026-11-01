/// Measures a path's contours one at a time: length, position and tangent at a distance, segments.
/// Works on its own copy of the path.
public final class SKPathMeasure {
	public let handle: OpaquePointer

	/// `resScale` > 1 measures curves more precisely (e.g. the canvas scale they'll be drawn at).
	public init(_ path: SKPath, _ forceClosed: Bool = false, _ resScale: Float = 1) {
		handle = __sk_pathmeasure_new_with_path(path.handle, forceClosed, resScale)
	}

	deinit {
		__sk_pathmeasure_destroy(handle)
	}

	/// Starts over on `path`, at its first contour.
	public func setPath(_ path: SKPath, _ forceClosed: Bool = false) {
		__sk_pathmeasure_set_path(handle, path.handle, forceClosed)
	}

	/// Of the current contour.
	public var length: Float { __sk_pathmeasure_get_length(handle) }

	public var isClosed: Bool { __sk_pathmeasure_is_closed(handle) }

	/// Moves to the next contour. False when there are no more.
	public func nextContour() -> Bool {
		__sk_pathmeasure_next_contour(handle)
	}

	/// Position and unit tangent at `distance` along the current contour (clamped to its length).
	public func getPosTan(_ distance: Float) -> (position: SKPoint, tangent: SKPoint)? {
		var position = SKPoint()
		var tangent = SKPoint()
		return __sk_pathmeasure_get_pos_tan(handle, distance, &position, &tangent) ? (position, tangent) : nil
	}

	public func getMatrix(_ distance: Float, _ flags: SKPathMeasureMatrixFlags = .getPositionAndTangent) -> SKMatrix? {
		var matrix = SKMatrix()
		return __sk_pathmeasure_get_matrix(handle, distance, &matrix, flags) ? matrix : nil
	}

	/// The part of the current contour between `start` and `stop`.
	public func getSegment(_ start: Float, _ stop: Float, _ startWithMoveTo: Bool = true) -> SKPath? {
		let builder = SKPathBuilder()
		return __sk_pathmeasure_get_segment(handle, start, stop, builder.handle, startWithMoveTo) ? builder.detach() : nil
	}
}
