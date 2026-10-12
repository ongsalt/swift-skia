extension SKData {
	/// A copy of `bytes`.
	public static func withCopy(_ bytes: [UInt8]) -> SKData? {
		withCopy(bytes.span.bytes)
	}

	/// The data's bytes. Valid while the data is alive.
	public var span: Span<UInt8> {
		@_lifetime(borrow self)
		get {
			// Empty SkData has no buffer at all.
			guard size > 0, let bytes = bytes else { return Span() }
			// The bytes live as long as `self`; the accessor's annotation ties the span to it.
			let span = unsafe Span(_unsafeStart: bytes, count: size)
			return unsafe _overrideLifetime(span, copying: ())
		}
	}
}
