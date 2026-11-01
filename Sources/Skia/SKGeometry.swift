// Value semantics for the C geometry structs, and SkRect/SkIRect's helpers.

extension SKPoint: @retroactive Equatable, @retroactive Hashable {
	public static func == (a: Self, b: Self) -> Bool { a.x == b.x && a.y == b.y }
	public func hash(into hasher: inout Hasher) { hasher.combine(x); hasher.combine(y) }
}

extension SKPointI: @retroactive Equatable, @retroactive Hashable {
	public static func == (a: Self, b: Self) -> Bool { a.x == b.x && a.y == b.y }
	public func hash(into hasher: inout Hasher) { hasher.combine(x); hasher.combine(y) }
}

extension SKPoint3: @retroactive Equatable, @retroactive Hashable {
	public static func == (a: Self, b: Self) -> Bool { a.x == b.x && a.y == b.y && a.z == b.z }
	public func hash(into hasher: inout Hasher) { hasher.combine(x); hasher.combine(y); hasher.combine(z) }
}

extension SKSize: @retroactive Equatable, @retroactive Hashable {
	public static func == (a: Self, b: Self) -> Bool { a.w == b.w && a.h == b.h }
	public func hash(into hasher: inout Hasher) { hasher.combine(w); hasher.combine(h) }
}

extension SKSizeI: @retroactive Equatable, @retroactive Hashable {
	public static func == (a: Self, b: Self) -> Bool { a.w == b.w && a.h == b.h }
	public func hash(into hasher: inout Hasher) { hasher.combine(w); hasher.combine(h) }
}

extension SKColor4f: @retroactive Equatable, @retroactive Hashable {
	public static func == (a: Self, b: Self) -> Bool { a.fR == b.fR && a.fG == b.fG && a.fB == b.fB && a.fA == b.fA }
	public func hash(into hasher: inout Hasher) { hasher.combine(fR); hasher.combine(fG); hasher.combine(fB); hasher.combine(fA) }
}

extension SKRect: @retroactive Equatable, @retroactive Hashable {
	public static func == (a: Self, b: Self) -> Bool {
		a.left == b.left && a.top == b.top && a.right == b.right && a.bottom == b.bottom
	}
	public func hash(into hasher: inout Hasher) {
		hasher.combine(left); hasher.combine(top); hasher.combine(right); hasher.combine(bottom)
	}

	public static func makeLTRB(_ left: Float, _ top: Float, _ right: Float, _ bottom: Float) -> Self {
		Self(left: left, top: top, right: right, bottom: bottom)
	}

	public static func makeXYWH(_ x: Float, _ y: Float, _ width: Float, _ height: Float) -> Self {
		Self(left: x, top: y, right: x + width, bottom: y + height)
	}

	public static func makeWH(_ width: Float, _ height: Float) -> Self {
		Self(left: 0, top: 0, right: width, bottom: height)
	}

	public var width: Float { right - left }
	public var height: Float { bottom - top }
	public var isEmpty: Bool { !(left < right && top < bottom) }
}

extension SKRectI: @retroactive Equatable, @retroactive Hashable {
	public static func == (a: Self, b: Self) -> Bool {
		a.left == b.left && a.top == b.top && a.right == b.right && a.bottom == b.bottom
	}
	public func hash(into hasher: inout Hasher) {
		hasher.combine(left); hasher.combine(top); hasher.combine(right); hasher.combine(bottom)
	}

	public static func makeLTRB(_ left: Int32, _ top: Int32, _ right: Int32, _ bottom: Int32) -> Self {
		Self(left: left, top: top, right: right, bottom: bottom)
	}

	public static func makeXYWH(_ x: Int32, _ y: Int32, _ width: Int32, _ height: Int32) -> Self {
		Self(left: x, top: y, right: x + width, bottom: y + height)
	}

	public static func makeWH(_ width: Int32, _ height: Int32) -> Self {
		Self(left: 0, top: 0, right: width, bottom: height)
	}

	public var width: Int32 { right - left }
	public var height: Int32 { bottom - top }
	public var isEmpty: Bool { !(left < right && top < bottom) }
}

extension SKMatrix {
	/// `SkMatrix::I()`. `SKMatrix()` is all zeros, not identity.
	public static let identity = Self(scaleX: 1, skewX: 0, transX: 0, skewY: 0, scaleY: 1, transY: 0, persp0: 0, persp1: 0, persp2: 1)

	public static func translate(_ dx: Float, _ dy: Float) -> Self {
		Self(scaleX: 1, skewX: 0, transX: dx, skewY: 0, scaleY: 1, transY: dy, persp0: 0, persp1: 0, persp2: 1)
	}

	public static func scale(_ sx: Float, _ sy: Float) -> Self {
		Self(scaleX: sx, skewX: 0, transX: 0, skewY: 0, scaleY: sy, transY: 0, persp0: 0, persp1: 0, persp2: 1)
	}
}
