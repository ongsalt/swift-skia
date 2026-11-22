/// `SkTextBlobBuilder`: builds an `SKTextBlob` from runs of glyphs you fill in.
///
/// Unique owner, like rust-skia's `TextBlobBuilder`: `~Copyable`, deleted in `deinit`. Each
/// `allocRun*` returns the run's storage, which borrows the builder until you're done filling it.
public struct SKTextBlobBuilder: ~Copyable {
	public let handle: OpaquePointer

	public init() {
		handle = sk_textblob_builder_new()
	}

	deinit {
		sk_textblob_builder_delete(handle)
	}

	/// The blob of every run so far, nil if there are none. The builder starts over.
	public mutating func make() -> SKTextBlob? {
		sk_textblob_builder_make(handle)
	}

	/// `SkTextBlobBuilder::RunBuffer`: storage for one run. Only the spans the `allocRun*` call
	/// sets up are non-empty.
	public struct RunBuffer: ~Copyable, ~Escapable {
		public var glyphs: MutableSpan<UInt16>
		/// One x per glyph (`allocRunPosH`, `allocRunTextPosH`).
		public var pos: MutableSpan<Float>
		/// One point per glyph (`allocRunPos`, `allocRunTextPos`).
		public var points: MutableSpan<SKPoint>
		/// One transform per glyph (`allocRunRSXform`, `allocRunTextRSXform`).
		public var xforms: MutableSpan<SKRotationScaleMatrix>
		/// The run's UTF-8 text (`allocRunText*`).
		public var utf8text: MutableSpan<UInt8>
		/// One text byte offset per glyph (`allocRunText*`).
		public var clusters: MutableSpan<UInt32>

		@_lifetime(copy glyphs, copy pos, copy points, copy xforms, copy utf8text, copy clusters)
		init(
			glyphs: consuming MutableSpan<UInt16>, pos: consuming MutableSpan<Float>,
			points: consuming MutableSpan<SKPoint>, xforms: consuming MutableSpan<SKRotationScaleMatrix>,
			utf8text: consuming MutableSpan<UInt8>, clusters: consuming MutableSpan<UInt32>
		) {
			self.glyphs = glyphs
			self.pos = pos
			self.points = points
			self.xforms = xforms
			self.utf8text = utf8text
			self.clusters = clusters
		}
	}

	private enum Positioning {
		case none, horizontal, full, rsxform
	}

	/// Glyphs laid out from (`x`, `y`) by their advances.
	@_lifetime(&self)
	public mutating func allocRun(
		_ font: borrowing SKFont, _ count: Int32, _ x: Float, _ y: Float, _ bounds: SKRect? = nil
	) -> RunBuffer {
		var raw = SKRunBuffer()
		_skWithOptionalPointer(bounds) { __sk_textblob_builder_alloc_run(handle, font.handle, count, x, y, $0, &raw) }
		return runBuffer(raw, count, .none, 0)
	}

	/// Glyphs on the baseline `y`, each at its own x.
	@_lifetime(&self)
	public mutating func allocRunPosH(
		_ font: borrowing SKFont, _ count: Int32, _ y: Float, _ bounds: SKRect? = nil
	) -> RunBuffer {
		var raw = SKRunBuffer()
		_skWithOptionalPointer(bounds) { __sk_textblob_builder_alloc_run_pos_h(handle, font.handle, count, y, $0, &raw) }
		return runBuffer(raw, count, .horizontal, 0)
	}

	/// Glyphs each at its own point.
	@_lifetime(&self)
	public mutating func allocRunPos(_ font: borrowing SKFont, _ count: Int32, _ bounds: SKRect? = nil) -> RunBuffer {
		var raw = SKRunBuffer()
		_skWithOptionalPointer(bounds) { __sk_textblob_builder_alloc_run_pos(handle, font.handle, count, $0, &raw) }
		return runBuffer(raw, count, .full, 0)
	}

	/// Glyphs each with its own rotation, scale and translation.
	@_lifetime(&self)
	public mutating func allocRunRSXform(_ font: borrowing SKFont, _ count: Int32, _ bounds: SKRect? = nil) -> RunBuffer {
		var raw = SKRunBuffer()
		_skWithOptionalPointer(bounds) { __sk_textblob_builder_alloc_run_rsxform(handle, font.handle, count, $0, &raw) }
		return runBuffer(raw, count, .rsxform, 0)
	}

	/// `allocRun` plus `textByteCount` bytes of UTF-8 text and per-glyph clusters, for PDF text.
	@_lifetime(&self)
	public mutating func allocRunText(
		_ font: borrowing SKFont, _ count: Int32, _ x: Float, _ y: Float, _ textByteCount: Int32,
		_ bounds: SKRect? = nil
	) -> RunBuffer {
		var raw = SKRunBuffer()
		_skWithOptionalPointer(bounds) {
			__sk_textblob_builder_alloc_run_text(handle, font.handle, count, x, y, textByteCount, $0, &raw)
		}
		return runBuffer(raw, count, .none, textByteCount)
	}

	@_lifetime(&self)
	public mutating func allocRunTextPosH(
		_ font: borrowing SKFont, _ count: Int32, _ y: Float, _ textByteCount: Int32, _ bounds: SKRect? = nil
	) -> RunBuffer {
		var raw = SKRunBuffer()
		_skWithOptionalPointer(bounds) {
			__sk_textblob_builder_alloc_run_text_pos_h(handle, font.handle, count, y, textByteCount, $0, &raw)
		}
		return runBuffer(raw, count, .horizontal, textByteCount)
	}

	@_lifetime(&self)
	public mutating func allocRunTextPos(
		_ font: borrowing SKFont, _ count: Int32, _ textByteCount: Int32, _ bounds: SKRect? = nil
	) -> RunBuffer {
		var raw = SKRunBuffer()
		_skWithOptionalPointer(bounds) {
			__sk_textblob_builder_alloc_run_text_pos(handle, font.handle, count, textByteCount, $0, &raw)
		}
		return runBuffer(raw, count, .full, textByteCount)
	}

	@_lifetime(&self)
	public mutating func allocRunTextRSXform(
		_ font: borrowing SKFont, _ count: Int32, _ textByteCount: Int32, _ bounds: SKRect? = nil
	) -> RunBuffer {
		var raw = SKRunBuffer()
		_skWithOptionalPointer(bounds) {
			__sk_textblob_builder_alloc_run_text_rsxform(handle, font.handle, count, textByteCount, $0, &raw)
		}
		return runBuffer(raw, count, .rsxform, textByteCount)
	}

	@_lifetime(&self)
	private mutating func runBuffer(
		_ raw: SKRunBuffer, _ count: Int32, _ positioning: Positioning, _ textByteCount: Int32
	) -> RunBuffer {
		let count = Int(count)
		let textCount = Int(textByteCount)
		let buffer = RunBuffer(
			glyphs: Self.span(raw.glyphs, count),
			pos: Self.span(raw.pos, positioning == .horizontal ? count : 0),
			points: Self.span(raw.pos, positioning == .full ? count : 0),
			xforms: Self.span(raw.pos, positioning == .rsxform ? count : 0),
			utf8text: Self.span(raw.utf8text, textCount),
			clusters: Self.span(raw.clusters, textCount > 0 ? count : 0))
		return unsafe _overrideLifetime(buffer, mutating: &self)
	}

	/// Unconstrained; `runBuffer` ties the result to the builder.
	@_lifetime(immortal)
	private static func span<T>(_ start: UnsafeMutableRawPointer?, _ count: Int) -> MutableSpan<T> {
		guard count > 0, let start else { return MutableSpan() }
		let span = unsafe MutableSpan(_unsafeStart: start.assumingMemoryBound(to: T.self), count: count)
		return unsafe _overrideLifetime(span, copying: ())
	}
}

extension SKTextBlob {
	/// `getIntercepts`: where the glyphs cross the horizontal band `bounds` (top and bottom), as
	/// pairs of x positions, e.g. to gap an underline around descenders.
	public func getIntercepts(_ bounds: [2 of Float], _ paint: SKPaint? = nil) -> [Float] {
		bounds.span.withUnsafeBufferPointer { bounds in
			let count = __sk_textblob_get_intercepts(self, bounds.baseAddress, nil, paint?.handle)
			guard count > 0 else { return [] }
			var intervals = [Float](repeating: 0, count: Int(count))
			intervals.withUnsafeMutableBufferPointer { intervals in
				_ = __sk_textblob_get_intercepts(self, bounds.baseAddress, intervals.baseAddress, paint?.handle)
			}
			return intervals
		}
	}
}
