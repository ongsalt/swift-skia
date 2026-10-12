#if canImport(Glibc)
import Glibc
#endif

/// Weight, width and slant of a typeface.
public final class SKFontStyle {
	public let handle: OpaquePointer

	init(handle: OpaquePointer) {
		self.handle = handle
	}

	/// `weight` 100–1000 (400 normal, 700 bold); `width` 1–9 (5 normal).
	public init(_ weight: Int32 = 400, _ width: Int32 = 5, _ slant: SKFontStyleSlant = .upright) {
		handle = __sk_fontstyle_new(weight, width, slant)
	}

	deinit {
		__sk_fontstyle_delete(handle)
	}

	public static var normal: SKFontStyle { SKFontStyle() }
	public static var bold: SKFontStyle { SKFontStyle(700) }
	public static var italic: SKFontStyle { SKFontStyle(400, 5, .italic) }
	public static var boldItalic: SKFontStyle { SKFontStyle(700, 5, .italic) }

	public var weight: Int32 { __sk_fontstyle_get_weight(handle) }

	public var width: Int32 { __sk_fontstyle_get_width(handle) }

	public var slant: SKFontStyleSlant { __sk_fontstyle_get_slant(handle) }
}

extension SKFontManager {
	/// The platform's default font manager (on Linux: fonts found under `/usr/share/fonts`).
	/// Created once; scanning the font directory is expensive.
	public static let `default`: SKFontManager = createDefault()

	/// The closest match in `family`, or nil if the family isn't installed.
	public func matchFamilyStyle(_ family: String?, _ style: SKFontStyle) -> SKTypeface? {
		__sk_fontmgr_match_family_style(self, family, style.handle)
	}

	/// A typeface in `family` (or any family, if nil) that can render `character`, preferring the
	/// given BCP 47 languages (e.g. `["ja"]`). For font fallback.
	/// Always nil with Skia's directory font manager (the Linux default without fontconfig),
	/// which doesn't implement character matching.
	public func matchFamilyStyleCharacter(
		_ family: String?, _ style: SKFontStyle, _ bcp47: [String], _ character: Unicode.Scalar
	) -> SKTypeface? {
		let tags = bcp47.map { strdup($0) }
		defer { tags.forEach { free($0) } }
		var pointers = tags.map { $0.map { UnsafePointer($0) } }
		// "" rather than nil for "any family", as SkiaSharp does (https://bugs.chromium.org/p/skia/issues/detail?id=6196).
		return __sk_fontmgr_match_family_style_character(
			self, family ?? "", style.handle, &pointers, Int32(pointers.count), Int32(bitPattern: character.value))
	}

	/// The closest match in `family`, falling back to the default family (`family` may be nil).
	public func legacyCreateTypeface(_ family: String?, _ style: SKFontStyle) -> SKTypeface? {
		__sk_fontmgr_legacy_create_typeface(self, family, style.handle)
	}
}

extension SKTypeface {
	/// The default family in the given style, from the default font manager.
	public static func `default`(_ style: SKFontStyle = .normal) -> SKTypeface? {
		SKFontManager.default.legacyCreateTypeface(nil, style)
	}

	public var fontStyle: SKFontStyle {
		SKFontStyle(handle: __sk_typeface_get_fontstyle(self))
	}
}

extension SKFontStyleSet {
	public func matchStyle(_ style: SKFontStyle) -> SKTypeface? {
		__sk_fontstyleset_match_style(self, style.handle)
	}

	/// The style at `index` (`0..<count`) and its name (e.g. "Bold Italic").
	public func style(_ index: Int32) -> (style: SKFontStyle, name: String) {
		let style = SKFontStyle()
		let name = sk_string_new_empty()
		defer { sk_string_destructor(name) }
		__sk_fontstyleset_get_style(self, index, style.handle, name)
		return (style, String(cString: sk_string_get_c_str(name)))
	}
}
