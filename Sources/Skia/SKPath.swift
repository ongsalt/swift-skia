/// Geometry made of lines and curves. Built with `SKPathBuilder`.
/// Reference semantics: `let b = a` shares one path; use `copy()` for an independent one.
public final class SKPath {
	public let handle: OpaquePointer

	init(handle: OpaquePointer) {
		self.handle = handle
	}

	public init() {
		handle = __sk_path_new()
	}

	deinit {
		__sk_path_delete(handle)
	}

	public func copy() -> SKPath {
		SKPath(handle: __sk_path_clone(handle))
	}

	/// Parses SVG path data such as `"M 0 0 L 10 10 Z"`.
	public static func parseSvgString(_ svg: String) -> SKPath? {
		let path = SKPath()
		return __sk_path_parse_svg_string(path.handle, svg) ? path : nil
	}

	public var svgString: String {
		let string = sk_string_new_empty()
		defer { sk_string_destructor(string) }
		__sk_path_to_svg_string(handle, string)
		return String(cString: sk_string_get_c_str(string))
	}

	public var fillType: SKPathFillType {
		get { __sk_path_get_filltype(handle) }
		set { __sk_path_set_filltype(handle, newValue) }
	}

	public var bounds: SKRect {
		var rect = SKRect()
		__sk_path_get_bounds(handle, &rect)
		return rect
	}

	public var tightBounds: SKRect {
		var rect = SKRect()
		__sk_path_compute_tight_bounds(handle, &rect)
		return rect
	}

	public var pointCount: Int32 { __sk_path_count_points(handle) }

	public var verbCount: Int32 { __sk_path_count_verbs(handle) }

	public var points: [SKPoint] {
		var points = [SKPoint](repeating: SKPoint(), count: Int(pointCount))
		var span: MutableSpan<SKPoint>? = points.mutableSpan
		_ = __sk_path_get_points(handle, &span)
		return points
	}

	public var lastPoint: SKPoint? {
		var point = SKPoint()
		return __sk_path_get_last_point(handle, &point) ? point : nil
	}

	public var isConvex: Bool { __sk_path_is_convex(handle) }

	public func contains(_ x: Float, _ y: Float) -> Bool {
		__sk_path_contains(handle, x, y)
	}

	public func transform(_ matrix: SKMatrix) {
		var matrix = matrix
		__sk_path_transform(handle, &matrix)
	}

	public func reset() {
		__sk_path_reset(handle)
	}

	public func rewind() {
		__sk_path_rewind(handle)
	}
}
