/// `SkRRect`: a rectangle with rounded corners, each corner with its own x and y radius.
/// Reference semantics: `let b = a` shares one round rect; use `copy()` for an independent one.
public final class SKRRect {
	public let handle: OpaquePointer

	init(handle: OpaquePointer) {
		self.handle = handle
	}

	/// Empty.
	public init() {
		handle = __sk_rrect_new()
	}

	deinit {
		__sk_rrect_delete(handle)
	}

	public func copy() -> SKRRect {
		SKRRect(handle: __sk_rrect_new_copy(handle))
	}

	public static func makeRect(_ rect: SKRect) -> SKRRect {
		let rrect = SKRRect()
		rrect.rect = rect
		return rrect
	}

	public static func makeOval(_ oval: SKRect) -> SKRRect {
		let rrect = SKRRect()
		rrect.setOval(oval)
		return rrect
	}

	public static func makeRectXY(_ rect: SKRect, _ xRad: Float, _ yRad: Float) -> SKRRect {
		let rrect = SKRRect()
		rrect.setRectXY(rect, xRad, yRad)
		return rrect
	}

	public var type: SKRoundRectType { __sk_rrect_get_type(handle) }

	/// The bounds. Setting it makes the corners square (`setRect`).
	public var rect: SKRect {
		get {
			var rect = SKRect()
			__sk_rrect_get_rect(handle, &rect)
			return rect
		}
		set {
			var rect = newValue
			__sk_rrect_set_rect(handle, &rect)
		}
	}

	public var width: Float { __sk_rrect_get_width(handle) }

	public var height: Float { __sk_rrect_get_height(handle) }

	public var isValid: Bool { __sk_rrect_is_valid(handle) }

	public func radii(_ corner: SKRoundRectCorner) -> SKPoint {
		var radii = SKPoint()
		__sk_rrect_get_radii(handle, corner, &radii)
		return radii
	}

	public func setEmpty() {
		__sk_rrect_set_empty(handle)
	}

	public func setOval(_ oval: SKRect) {
		var oval = oval
		__sk_rrect_set_oval(handle, &oval)
	}

	public func setRectXY(_ rect: SKRect, _ xRad: Float, _ yRad: Float) {
		var rect = rect
		__sk_rrect_set_rect_xy(handle, &rect, xRad, yRad)
	}

	public func setNinePatch(_ rect: SKRect, _ leftRad: Float, _ topRad: Float, _ rightRad: Float, _ bottomRad: Float) {
		var rect = rect
		__sk_rrect_set_nine_patch(handle, &rect, leftRad, topRad, rightRad, bottomRad)
	}

	/// `radii` in `SKRoundRectCorner` order: upper left, upper right, lower right, lower left.
	public func setRectRadii(_ rect: SKRect, _ radii: [4 of SKPoint]) {
		var rect = rect
		radii.span.withUnsafeBufferPointer { __sk_rrect_set_rect_radii(handle, &rect, $0.baseAddress) }
	}

	public func contains(_ rect: SKRect) -> Bool {
		var rect = rect
		return __sk_rrect_contains(handle, &rect)
	}

	public func inset(_ dx: Float, _ dy: Float) {
		__sk_rrect_inset(handle, dx, dy)
	}

	public func outset(_ dx: Float, _ dy: Float) {
		__sk_rrect_outset(handle, dx, dy)
	}

	public func offset(_ dx: Float, _ dy: Float) {
		__sk_rrect_offset(handle, dx, dy)
	}

	/// Nil when `matrix` would make the corners non-elliptical (only scale, translate and
	/// 90° rotations keep them elliptical).
	public func transform(_ matrix: SKMatrix) -> SKRRect? {
		let result = SKRRect()
		var matrix = matrix
		return __sk_rrect_transform(handle, &matrix, result.handle) ? result : nil
	}
}
