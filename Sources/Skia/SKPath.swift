/// `SkPath`: geometry made of lines and curves. Built with `SKPathBuilder`.
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

	/// `SkParsePath::FromSVGString`, e.g. `"M 0 0 L 10 10 Z"`.
	public static func fromSVGString(_ svg: String) -> SKPath? {
		let path = SKPath()
		return __sk_path_parse_svg_string(path.handle, svg) ? path : nil
	}

	/// `SkParsePath::ToSVGString`.
	public func toSVGString() -> String {
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

	public func computeTightBounds() -> SKRect {
		var rect = SKRect()
		__sk_path_compute_tight_bounds(handle, &rect)
		return rect
	}

	public func countPoints() -> Int32 { __sk_path_count_points(handle) }

	public func countVerbs() -> Int32 { __sk_path_count_verbs(handle) }

	public func getPoint(_ index: Int32) -> SKPoint {
		precondition(index >= 0 && index < countPoints(), "point \(index) outside 0..<\(countPoints())")
		var point = SKPoint()
		__sk_path_get_point(handle, index, &point)
		return point
	}

	/// `getPoints`, all of them.
	public var points: [SKPoint] {
		var points = [SKPoint](repeating: SKPoint(), count: Int(countPoints()))
		var span: MutableSpan<SKPoint>? = points.mutableSpan
		_ = __sk_path_get_points(handle, &span)
		return points
	}

	public var lastPt: SKPoint? {
		var point = SKPoint()
		return __sk_path_get_last_point(handle, &point) ? point : nil
	}

	public var segmentMasks: SKPathSegmentMask { SKPathSegmentMask(rawValue: __sk_path_get_segment_masks(handle)) }

	public var isConvex: Bool { __sk_path_is_convex(handle) }

	/// The line's two points, when the path is a single line.
	public var isLine: [2 of SKPoint]? {
		var line: [2 of SKPoint] = [SKPoint(), SKPoint()]
		var span = line.mutableSpan
		let isLine = span.withUnsafeMutableBufferPointer { __sk_path_is_line(handle, $0.baseAddress) }
		return isLine ? line : nil
	}

	/// The oval's bounds, when the path is an oval or circle.
	public var isOval: SKRect? {
		var bounds = SKRect()
		return __sk_path_is_oval(handle, &bounds) ? bounds : nil
	}

	public var isRect: (rect: SKRect, isClosed: Bool, direction: SKPathDirection)? {
		var rect = SKRect()
		var isClosed = false
		var direction = SKPathDirection.clockwise
		return __sk_path_is_rect(handle, &rect, &isClosed, &direction) ? (rect, isClosed, direction) : nil
	}

	public var isRRect: SKRRect? {
		let rrect = SKRRect()
		return __sk_path_is_rrect(handle, rrect.handle) ? rrect : nil
	}

	public func contains(_ x: Float, _ y: Float) -> Bool {
		__sk_path_contains(handle, x, y)
	}

	public func transform(_ matrix: SKMatrix) {
		var matrix = matrix
		__sk_path_transform(handle, &matrix)
	}

	public func makeTransform(_ matrix: SKMatrix) -> SKPath {
		let result = SKPath()
		var matrix = matrix
		__sk_path_transform_to_dest(handle, &matrix, result.handle)
		return result
	}

	public func reset() {
		__sk_path_reset(handle)
	}

	public func rewind() {
		__sk_path_rewind(handle)
	}
}

// MARK: - SkPathOps

extension SKPath {
	/// `Op(self, other, op)`; nil when the result can't be computed.
	public func op(_ other: SKPath, _ op: SKPathOp) -> SKPath? {
		let result = SKPath()
		return __sk_pathop_op(handle, other.handle, op, result.handle) ? result : nil
	}

	/// `Simplify`: the same area without overlapping contours.
	public func simplify() -> SKPath? {
		let result = SKPath()
		return __sk_pathop_simplify(handle, result.handle) ? result : nil
	}

	/// `AsWinding`: the same area with the winding fill type.
	public func asWinding() -> SKPath? {
		let result = SKPath()
		return __sk_pathop_as_winding(handle, result.handle) ? result : nil
	}
}

/// `SkOpBuilder`: combines many paths more efficiently than chaining `SKPath.op`.
public final class SKOpBuilder {
	public let handle: OpaquePointer

	public init() {
		handle = __sk_opbuilder_new()
	}

	deinit {
		__sk_opbuilder_destroy(handle)
	}

	public func add(_ path: SKPath, _ op: SKPathOp) {
		__sk_opbuilder_add(handle, path.handle, op)
	}

	/// Nil when the result can't be computed. Resets the builder.
	public func resolve() -> SKPath? {
		let result = SKPath()
		return __sk_opbuilder_resolve(handle, result.handle) ? result : nil
	}
}

// MARK: - SkPath::Iter, SkPath::RawIter

extension SKPath {
	/// One verb with its points: 1 for move, 2 for line, 3 for quad and conic, 4 for cubic.
	public struct Segment: Sendable {
		public var verb: SKPathVerb
		public var points: [SKPoint]
		/// Only meaningful for `.conic`.
		public var conicWeight: Float
	}

	/// Bound to its path, like rust-skia's `path::Iter<'a>`. With `forceClose`, open contours get a
	/// closing line.
	public struct Iter: BorrowingIteratorProtocol, ~Copyable, ~Escapable {
		public typealias Element = Segment

		public let handle: OpaquePointer
		private var current: [1 of Segment] = [Segment.done]

		@_lifetime(borrow path)
		public init(_ path: borrowing SKPath, _ forceClose: Bool = false) {
			handle = __sk_path_create_iter(path.handle, forceClose ? 1 : 0)
		}

		deinit {
			__sk_path_iter_destroy(handle)
		}

		@_lifetime(&self)
		@_lifetime(self: copy self)
		public mutating func nextSpan(maxCount: Int) -> Span<Segment> {
			guard maxCount > 0, let segment = next() else { return Span() }
			current[0] = segment
			return current.span
		}

		public mutating func next() -> Segment? {
			Segment.next { __sk_path_iter_next(handle, $0) } conicWeight: { __sk_path_iter_conic_weight(handle) }
		}

		/// Whether the last `.line` returned was added to close the contour.
		public var isCloseLine: Bool { __sk_path_iter_is_close_line(handle) != 0 }

		public var isClosedContour: Bool { __sk_path_iter_is_closed_contour(handle) != 0 }
	}

	/// The verbs exactly as stored, without closing lines.
	public struct RawIter: BorrowingIteratorProtocol, ~Copyable, ~Escapable {
		public typealias Element = Segment

		public let handle: OpaquePointer
		private var current: [1 of Segment] = [Segment.done]

		@_lifetime(borrow path)
		public init(_ path: borrowing SKPath) {
			handle = __sk_path_create_rawiter(path.handle)
		}

		deinit {
			__sk_path_rawiter_destroy(handle)
		}

		@_lifetime(&self)
		public mutating func nextSpan(maxCount: Int) -> Span<Segment> {
			guard maxCount > 0, let segment = next() else { return Span() }
			current[0] = segment
			return current.span
		}

		public mutating func next() -> Segment? {
			Segment.next { __sk_path_rawiter_next(handle, $0) } conicWeight: { __sk_path_rawiter_conic_weight(handle) }
		}

		public func peek() -> SKPathVerb {
			__sk_path_rawiter_peek(handle)
		}
	}
}

/// `for segment in path`, through `SKPath.Iter` without force-closing.
extension SKPath: Iterable {
	@_lifetime(borrow self)
	public func makeBorrowingIterator() -> Iter {
		Iter(self)
	}

	public var underestimatedCount: Int { 0 }
}

extension SKPath.Segment {
	fileprivate static let done = Self(verb: .done, points: [], conicWeight: 0)

	fileprivate static func next(
		_ advance: (UnsafeMutablePointer<SKPoint>) -> SKPathVerb, conicWeight: () -> Float
	) -> Self? {
		withUnsafeTemporaryAllocation(of: SKPoint.self, capacity: 4) { buffer in
			let verb = advance(buffer.baseAddress!)
			let count: Int
			switch verb {
			case .done: return nil
			case .move: count = 1
			case .line: count = 2
			case .quad, .conic: count = 3
			case .cubic: count = 4
			default: count = 0
			}
			return Self(verb: verb, points: Array(buffer.prefix(count)), conicWeight: conicWeight())
		}
	}
}
