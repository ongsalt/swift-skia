extension SKColorSpace {
	/// Creates a color space from ICC profile bytes, or returns nil if unsupported or invalid.
	/// The returned color space is independent of the input buffer.
	public static func icc(_ bytes: RawSpan) -> SKColorSpace? {
		guard bytes.byteCount > 0 else { return nil }
		return bytes.withUnsafeBytes { buffer in
			guard let profile = sk_colorspace_icc_profile_new() else { return nil }
			defer { sk_colorspace_icc_profile_delete(profile) }
			// Parsing borrows the buffer. Construct the owned color space before that borrow ends.
			guard sk_colorspace_icc_profile_parse(buffer.baseAddress, buffer.count, profile) else { return nil }
			return icc(profile)
		}
	}

	/// Creates a color space from ICC profile bytes.
	public static func icc(_ bytes: [UInt8]) -> SKColorSpace? {
		icc(bytes.span.bytes)
	}
}
