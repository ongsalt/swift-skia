import Skia
import Testing

@Suite struct RasterTests {
	func makeSurface(_ width: Int32, _ height: Int32) throws -> SKSurface {
		var info = SKImageInfo(colorspace: nil, width: width, height: height, colorType: .rgba8888, alphaType: .premul)
		return try #require(SKSurface.raster(&info, 0, nil))
	}

	func pixels(_ surface: SKSurface, _ width: Int32, _ height: Int32) -> [UInt32] {
		var info = SKImageInfo(colorspace: nil, width: width, height: height, colorType: .rgba8888, alphaType: .premul)
		var pixels = [UInt32](repeating: 0, count: Int(width * height))
		_ = pixels.withUnsafeMutableBytes { surface.readPixels(&info, $0.baseAddress, Int(width) * 4, 0, 0) }
		return pixels
	}

	@Test func drawsIntoRasterSurface() throws {
		var surface = try makeSurface(16, 16)
		let paint = SKPaint()
		paint.color = 0xFFFF_0000

		let canvas = surface.canvas
		canvas.clear(0xFFFF_FFFF)
		canvas.drawRect(0, 0, 8, 16, paint)

		let pixels = pixels(surface, 16, 16)
		// RGBA8888 in memory, read as little-endian UInt32: 0xAABBGGRR.
		#expect(pixels[0] == 0xFF00_00FF)   // left half: red
		#expect(pixels[15] == 0xFFFF_FFFF)  // right half: white
	}

	@Test func snapshotIsAnImage() throws {
		let surface = try makeSurface(4, 3)
		let image = try #require(surface.newImageSnapshot())
		#expect(image.width == 4)
		#expect(image.height == 3)
		#expect(image.colorType == .rgba8888)
	}

	@Test func canvasTransformsAndClips() throws {
		var surface = try makeSurface(8, 8)
		let paint = SKPaint()
		paint.color = 0xFF00_FF00

		let canvas = surface.canvas
		canvas.clear(0xFF00_0000)
		canvas.save()
		canvas.translate(4, 0)
		canvas.clipRect(SKRect(left: 0, top: 0, right: 4, bottom: 4))
		canvas.drawPaint(paint)
		canvas.restore()
		#expect(canvas.saveCount == 1)

		let pixels = pixels(surface, 8, 8)
		#expect(pixels[0] == 0xFF00_0000)          // (0, 0): outside the clip
		#expect(pixels[5] == 0xFF00_FF00)          // (5, 0): inside
		#expect(pixels[5 + 6 * 8] == 0xFF00_0000)  // (5, 6): below the clip
	}
}

@Suite struct PaintTests {
	@Test func propertiesRoundTrip() {
		let paint = SKPaint()
		paint.isAntialias = true
		paint.color = 0x8011_2233
		paint.style = .stroke
		paint.strokeWidth = 3
		paint.strokeCap = .round
		paint.blendMode = .multiply
		#expect(paint.isAntialias)
		#expect(paint.color == 0x8011_2233)
		#expect(paint.style == .stroke)
		#expect(paint.strokeWidth == 3)
		#expect(paint.strokeCap == .round)
		#expect(paint.blendMode == .multiply)
	}

	@Test func referenceSemanticsAndCopy() {
		let a = SKPaint()
		let shared = a
		let copy = a.copy()
		a.strokeWidth = 7
		#expect(shared.strokeWidth == 7)
		#expect(copy.strokeWidth == 0)
	}

	@Test func shaderIsRetainedByPaint() throws {
		let paint = SKPaint()
		paint.shader = SKShader.color(0xFF12_3456)
		#expect(paint.shader != nil)
		paint.shader = nil
		#expect(paint.shader == nil)
	}
}

@Suite struct PathTests {
	@Test func builderProducesPath() {
		let builder = SKPathBuilder()
		builder.moveTo(10, 10)
		builder.lineTo(30, 10)
		builder.lineTo(30, 40)
		builder.close()
		let path = builder.detach()
		#expect(path.bounds == SKRect(left: 10, top: 10, right: 30, bottom: 40))
		#expect(path.pointCount == 3)
		#expect(path.contains(28, 15))
		#expect(!path.contains(12, 38))
		#expect(path.lastPoint != nil)
	}

	@Test func svgRoundTrip() throws {
		let path = try #require(SKPath.parseSvgString("M0 0L10 0L10 10Z"))
		#expect(path.points.count == 3)
		let again = try #require(SKPath.parseSvgString(path.svgString))
		#expect(again.bounds == path.bounds)
	}

	@Test func copyIsIndependent() {
		let builder = SKPathBuilder()
		builder.addCircle(0, 0, 5)
		let path = builder.detach()
		let copy = path.copy()
		path.fillType = .evenOdd
		#expect(copy.fillType == .winding)
	}
}

@Suite struct FontTests {
	@Test func measuresText() {
		let font = SKFont(nil, 20)
		#expect(font.size == 20)
		font.size = 30
		#expect(font.size == 30)
		#expect(font.glyphs("abc").count == 3)
		#expect(font.measureText("") == 0)
	}
}

extension SKRect: @retroactive Equatable {
	public static func == (a: SKRect, b: SKRect) -> Bool {
		a.left == b.left && a.top == b.top && a.right == b.right && a.bottom == b.bottom
	}
}

@Suite struct EncodeTests {
	func drawnSurface() throws -> SKSurface {
		var info = SKImageInfo(colorspace: nil, width: 6, height: 4, colorType: .rgba8888, alphaType: .premul)
		var surface = try #require(SKSurface.raster(&info, 0, nil))
		let paint = SKPaint()
		paint.color = 0xFF00_80FF
		surface.canvas.drawPaint(paint)
		return surface
	}

	@Test func surfacePixmapReadsPixels() throws {
		var surface = try drawnSurface()
		guard let pixmap = surface.peekPixels() else {
			Issue.record("raster surface has no pixels")
			return
		}
		let (width, height, rowBytes) = (pixmap.width, pixmap.height, pixmap.rowBytes)
		let (color, byteCount, isOpaque) = (pixmap.pixelColor(2, 2), pixmap.bytes.byteCount, pixmap.isOpaque)
		#expect(width == 6)
		#expect(height == 4)
		#expect(rowBytes >= 6 * 4)
		#expect(color == 0xFF00_80FF)
		#expect(byteCount == rowBytes * 4)
		#expect(isOpaque)
	}

	@Test(arguments: [SKEncodedImageFormat.png, .jpeg, .webp])
	func encodesAndDecodes(_ format: SKEncodedImageFormat) throws {
		let image = try #require(try drawnSurface().newImageSnapshot())
		let data = try #require(image.encode(format, 90))
		#expect(data.size > 0)
		let decoded = try #require(SKImage.fromEncoded(data))
		#expect(decoded.width == 6)
		#expect(decoded.height == 4)
	}

	@Test func pngSignature() throws {
		let image = try #require(try drawnSurface().newImageSnapshot())
		let data = try #require(image.encode(.png))
		let span = data.span
		#expect(span.count == data.size)
		#expect([span[0], span[1], span[2], span[3]] == [0x89, 0x50, 0x4E, 0x47])  // "\x89PNG"
	}

	@Test func unsupportedFormatReturnsNil() throws {
		let image = try #require(try drawnSurface().newImageSnapshot())
		#expect(image.encode(.gif) == nil)
	}
}

@Suite struct DataAndFontStyleTests {
	@Test func dataCopiesBytes() throws {
		let data = try #require(SKData.withCopy([1, 2, 3, 250]))
		#expect(data.size == 4)
		let span = data.span
		#expect(span[3] == 250)
	}

	@Test func fontStyle() {
		let style = SKFontStyle(700, 5, .italic)
		#expect(style.weight == 700)
		#expect(style.width == 5)
		#expect(style.slant == .italic)
		#expect(SKFontStyle.bold.weight == 700)
	}

	@Test func defaultTypeface() throws {
		let typeface = try #require(SKTypeface.default(.bold))
		#expect(typeface.fontStyle.weight >= 600)
		let font = SKFont(typeface, 16)
		#expect(font.measureText("hello") > 0)
	}
}

@Suite struct ReviewFixTests {
	@Test func emptyDataHasEmptySpan() throws {
		let data = try #require(SKData.withCopy([]))
		let count = data.span.count
		#expect(count == 0)
	}

	@Test func pixmapBytesStopAtLastPixel() throws {
		var info = SKImageInfo(colorspace: nil, width: 6, height: 4, colorType: .rgba8888, alphaType: .premul)
		var surface = try #require(SKSurface.raster(&info, 32, nil))  // padded rows
		guard let pixmap = surface.peekPixels() else {
			Issue.record("no pixels")
			return
		}
		let (rowBytes, byteCount) = (pixmap.rowBytes, pixmap.bytes.byteCount)
		#expect(rowBytes == 32)
		#expect(byteCount == 32 * 3 + 6 * 4)
	}

	@Test func pixmapEraseReadAndSubset() throws {
		var info = SKImageInfo(colorspace: nil, width: 4, height: 4, colorType: .rgba8888, alphaType: .premul)
		var surface = try #require(SKSurface.raster(&info, 0, nil))
		guard let pixmap = surface.peekPixels() else {
			Issue.record("no pixels")
			return
		}
		pixmap.erase(0xFF00_FF00)
		pixmap.erase(0xFFFF_0000, SKRectI(left: 2, top: 2, right: 4, bottom: 4))
		var out = [UInt8](repeating: 0, count: 16 * 4)
		var outSpan = out.mutableSpan
		var outBytes = outSpan.mutableBytes
		let read = pixmap.readPixels(info, &outBytes, 16)
		let corner = pixmap.pixelColor(3, 3)
		let subsetWidth = pixmap.extractSubset(SKRectI(left: 1, top: 1, right: 3, bottom: 4))?.width
		#expect(read)
		#expect(Array(out[0..<4]) == [0x00, 0xFF, 0x00, 0xFF])  // green, RGBA bytes
		#expect(corner == 0xFFFF_0000)
		#expect(subsetWidth == 2)

		var tooSmall = [UInt8](repeating: 0, count: 8)
		var smallSpan = tooSmall.mutableSpan
		var smallBytes = smallSpan.mutableBytes
		let rejected = !pixmap.readPixels(info, &smallBytes, 16)
		#expect(rejected)
	}

	@Test func rasterCopyFromPixmap() throws {
		var info = SKImageInfo(colorspace: nil, width: 3, height: 2, colorType: .rgba8888, alphaType: .premul)
		var surface = try #require(SKSurface.raster(&info, 0, nil))
		surface.canvas.clear(0xFF12_3456)
		guard let pixmap = surface.peekPixels() else {
			Issue.record("no pixels")
			return
		}
		let copy = SKImage.rasterCopy(pixmap)
		let image = try #require(copy)
		#expect(image.width == 3)
	}

	@Test func fontFallbackAndStyleSets() throws {
		let manager = SKFontManager.default
		// Skia's directory font manager doesn't implement character matching: always nil here.
		#expect(manager.matchFamilyStyleCharacter(nil, .normal, ["en"], "A") == nil)
		let set = try #require(manager.createStyleset(0))
		if set.count > 0 {
			let (style, _) = set.style(0)
			#expect(style.weight > 0)
		}
	}
}

@Suite struct SpanOverloadTests {
	func pixel(_ shader: SKShader?, _ x: Int32) throws -> SKColor {
		var info = SKImageInfo(colorspace: nil, width: 100, height: 1, colorType: .rgba8888, alphaType: .premul)
		var surface = try #require(SKSurface.raster(&info, 0, nil))
		let paint = SKPaint()
		paint.shader = shader
		surface.canvas.drawPaint(paint)
		guard let pixmap = surface.peekPixels() else { return 0 }
		return pixmap.pixelColor(x, 0)
	}

	@Test func gradientFromSpans() throws {
		let points = [SKPoint(x: 0, y: 0), SKPoint(x: 100, y: 0)]
		let colors: [SKColor] = [0xFFFF_0000, 0xFF00_00FF]
		let even = SKShader.linearGradient(points, colors.span, nil, .clamp, nil)
		let hardStop = SKShader.linearGradient(points, [0xFFFF_0000, 0xFFFF_0000, 0xFF00_00FF, 0xFF00_00FF].span, [0, 0.9, 0.9, 1].span, .clamp, nil)
		let (left, right, beforeStop) = (try pixel(even, 0), try pixel(even, 99), try pixel(hardStop, 80))
		// 0xAARRGGBB: mostly red at the left edge, mostly blue at the right.
		#expect((left >> 16) & 0xFF > 0xF0 && left & 0xFF < 0x10)
		#expect((right >> 16) & 0xFF < 0x10 && right & 0xFF > 0xF0)
		#expect(beforeStop == 0xFFFF_0000)
	}

	@Test func pathPointsAndPoly() throws {
		let builder = SKPathBuilder()
		builder.addPoly([SKPoint(x: 1, y: 2), SKPoint(x: 3, y: 4), SKPoint(x: 5, y: 0)], true)
		let path = builder.detach()
		#expect(path.points.map(\.x) == [1, 3, 5])
		#expect(SKPathEffect.createDash([4, 2].span, 0) != nil)
	}

	@Test func textBuffers() throws {
		let font = SKFont(SKTypeface.default(.normal), 16)
		#expect(font.glyphs("hello").count == 5)
		#expect(font.glyphs("").isEmpty)
		#expect(font.measureText("hello") > font.measureText("hi"))
	}

	@Test func dataFromRawSpan() throws {
		let bytes = Array("abc".utf8)
		let copy = SKData.withCopy(bytes.span.bytes)
		let data = try #require(copy)
		#expect(data.size == 3)
	}
}
