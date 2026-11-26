/// `SkRegion`: an area made of integer rectangles, for clipping and hit testing.
/// Reference semantics: `let b = a` shares one region; use `copy()` for an independent one.
public final class SKRegion {
	public let handle: OpaquePointer

	public init() {
		handle = sk_region_new()
	}

	public convenience init(_ rect: SKRectI) {
		self.init()
		setRect(rect)
	}

	deinit {
		sk_region_delete(handle)
	}

	public func copy() -> SKRegion {
		let region = SKRegion()
		region.setRegion(self)
		return region
	}

	public var isEmpty: Bool { sk_region_is_empty(handle) }

	public var isRect: Bool { sk_region_is_rect(handle) }

	public var isComplex: Bool { sk_region_is_complex(handle) }

	public var bounds: SKRectI {
		var rect = SKRectI()
		sk_region_get_bounds(handle, &rect)
		return rect
	}

	/// The outline of the region. Nil when it's empty.
	public func getBoundaryPath() -> SKPath? {
		let path = SKPath()
		return __sk_region_get_boundary_path(handle, path.handle) ? path : nil
	}

	/// The `set*` and `op` methods return whether the result is non-empty.
	@discardableResult
	public func setEmpty() -> Bool { sk_region_set_empty(handle) }

	@discardableResult
	public func setRect(_ rect: SKRectI) -> Bool { sk_region_set_rect(handle, rect) }

	/// The union of `rects`.
	@discardableResult
	public func setRects(_ rects: Span<SKRectI>) -> Bool { sk_region_set_rects(handle, rects) }

	@discardableResult
	public func setRegion(_ region: SKRegion) -> Bool { sk_region_set_region(handle, region.handle) }

	/// The area `path` fills, limited to `clip`.
	@discardableResult
	public func setPath(_ path: SKPath, _ clip: SKRegion) -> Bool {
		__sk_region_set_path(handle, path.handle, clip.handle)
	}

	public func intersects(_ rect: SKRectI) -> Bool { sk_region_intersects_rect(handle, rect) }

	public func intersects(_ region: SKRegion) -> Bool { sk_region_intersects(handle, region.handle) }

	public func contains(_ x: Int32, _ y: Int32) -> Bool { sk_region_contains_point(handle, x, y) }

	public func contains(_ rect: SKRectI) -> Bool { sk_region_contains_rect(handle, rect) }

	public func contains(_ region: SKRegion) -> Bool { sk_region_contains(handle, region.handle) }

	/// Faster than `contains`, but may return false for some rects the region does contain.
	public func quickContains(_ rect: SKRectI) -> Bool { sk_region_quick_contains(handle, rect) }

	/// Faster than `!intersects`, but may return false for some rects the region doesn't touch.
	public func quickReject(_ rect: SKRectI) -> Bool { sk_region_quick_reject_rect(handle, rect) }

	public func quickReject(_ region: SKRegion) -> Bool { sk_region_quick_reject(handle, region.handle) }

	public func translate(_ dx: Int32, _ dy: Int32) {
		sk_region_translate(handle, dx, dy)
	}

	@discardableResult
	public func op(_ rect: SKRectI, _ op: SKRegionOperation) -> Bool { sk_region_op_rect(handle, rect, op) }

	@discardableResult
	public func op(_ region: SKRegion, _ op: SKRegionOperation) -> Bool { sk_region_op(handle, region.handle, op) }
}

// MARK: - SkRegion::Iterator, Cliperator, Spanerator

extension SKRegion {
	/// The region's rectangles, top to bottom, then left to right.
	public struct Iterator: BorrowingIteratorProtocol, ~Copyable, ~Escapable {
		public typealias Element = SKRectI

		public let handle: OpaquePointer
		private var current: [1 of SKRectI] = [SKRectI()]

		@_lifetime(borrow region)
		public init(_ region: borrowing SKRegion) {
			handle = sk_region_iterator_new(region.handle)
		}

		deinit {
			sk_region_iterator_delete(handle)
		}

		@_lifetime(&self)
		@_lifetime(self: copy self)
		public mutating func nextSpan(maxCount: Int) -> Span<SKRectI> {
			guard maxCount > 0, let rect = next() else { return Span() }
			current[0] = rect
			return current.span
		}

		public mutating func next() -> SKRectI? {
			guard !sk_region_iterator_done(handle) else { return nil }
			var rect = SKRectI()
			sk_region_iterator_rect(handle, &rect)
			sk_region_iterator_next(handle)
			return rect
		}

		/// Starts over. False when the region is empty.
		public mutating func rewind() -> Bool {
			sk_region_iterator_rewind(handle)
		}
	}

	/// The region's rectangles that intersect `clip`, clipped to it.
	public struct Cliperator: BorrowingIteratorProtocol, ~Copyable, ~Escapable {
		public typealias Element = SKRectI

		public let handle: OpaquePointer
		private var current: [1 of SKRectI] = [SKRectI()]

		@_lifetime(borrow region)
		public init(_ region: borrowing SKRegion, _ clip: SKRectI) {
			handle = sk_region_cliperator_new(region.handle, clip)!
		}

		deinit {
			sk_region_cliperator_delete(handle)
		}

		@_lifetime(&self)
		@_lifetime(self: copy self)
		public mutating func nextSpan(maxCount: Int) -> Span<SKRectI> {
			guard maxCount > 0, let rect = next() else { return Span() }
			current[0] = rect
			return current.span
		}

		public mutating func next() -> SKRectI? {
			guard !sk_region_cliperator_done(handle) else { return nil }
			var rect = SKRectI()
			sk_region_cliperator_rect(handle, &rect)
			sk_region_cliperator_next(handle)
			return rect
		}
	}

	/// The horizontal runs of row `y` inside the region, limited to `left..<right`.
	public struct Spanerator: ~Copyable, ~Escapable {
		public let handle: OpaquePointer

		@_lifetime(borrow region)
		public init(_ region: borrowing SKRegion, _ y: Int32, _ left: Int32, _ right: Int32) {
			handle = sk_region_spanerator_new(region.handle, y, left, right)
		}

		deinit {
			sk_region_spanerator_delete(handle)
		}

		public mutating func next() -> (left: Int32, right: Int32)? {
			var (left, right): (Int32, Int32) = (0, 0)
			return sk_region_spanerator_next(handle, &left, &right) ? (left, right) : nil
		}
	}
}

/// `for rect in region`, through `SKRegion.Iterator`.
extension SKRegion: Iterable {
	@_lifetime(borrow self)
	public func makeBorrowingIterator() -> Iterator {
		Iterator(self)
	}

	public var underestimatedCount: Int { 0 }
}
