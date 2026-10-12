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
