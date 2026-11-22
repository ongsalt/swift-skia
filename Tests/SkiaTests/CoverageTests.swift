import Skia
import Testing

@Suite struct RegionTests {
	@Test func opsAndIteration() {
		let region = SKRegion(SKRectI(left: 0, top: 0, right: 10, bottom: 10))
		region.op(SKRectI(left: 20, top: 0, right: 30, bottom: 10), .union)
		#expect(region.isComplex)
		#expect(region.bounds == SKRectI(left: 0, top: 0, right: 30, bottom: 10))
		#expect(region.contains(5, 5))
		#expect(!region.contains(15, 5))

		var rects: [SKRectI] = []
		for rect in region { rects.append(rect) }
		#expect(rects == [SKRectI(left: 0, top: 0, right: 10, bottom: 10), SKRectI(left: 20, top: 0, right: 30, bottom: 10)])

		var spans = SKRegion.Spanerator(region, 5, 0, 30)
		#expect(spans.next()! == (0, 10))
		#expect(spans.next()! == (20, 30))
		#expect(spans.next() == nil)

		#expect(region.getBoundaryPath() != nil)
		let copy = region.copy()
		copy.translate(5, 0)
		#expect(copy.bounds.left == 5 && region.bounds.left == 0)
	}
}

@Suite struct TextBlobBuilderTests {
	@Test func positionedRun() throws {
		let font = SKFont(SKTypeface.default(.normal), 20)
		let glyphs = font.textToGlyphs("Hi")
		var builder = SKTextBlobBuilder()
		do {
			var run = builder.allocRunPos(font, Int32(glyphs.count))
			for i in glyphs.indices {
				run.glyphs[i] = glyphs[i]
				run.points[i] = SKPoint(x: Float(i) * 20, y: 20)
			}
			#expect(run.pos.isEmpty && run.xforms.isEmpty)
		}
		let blob = try #require(builder.make())
		#expect(builder.make() == nil)
		#expect(!blob.getIntercepts([10, 12]).isEmpty)
	}
}

@Suite struct DrawingAdditionTests {
	let info = SKImageInfo(colorspace: nil, width: 20, height: 20, colorType: .rgba8888, alphaType: .premul)

	@Test func pixmapOverOwnMemory() throws {
		var pixels = [UInt8](repeating: 0, count: 20 * 20 * 4)
		do {
			var span = pixels.mutableSpan
			let pixmap = try #require(SKPixmap(info, span.mutableBytes, 20 * 4))
			pixmap.erase(0xFF00_FF00)
			#expect(pixmap.getColor(3, 3) == 0xFF00_FF00)
		}
		#expect(pixels[1] == 0xFF)  // green channel of the first RGBA pixel
		do {
			var span = pixels.mutableSpan
			let tooSmall = SKPixmap(info, span.mutableBytes, 4)
			#expect(tooSmall == nil)
		}
	}

	@Test func regionAndPlayback() throws {
		var recorder = SKPictureRecorder()
		do {
			let canvas = recorder.beginRecording(SKRect(left: 0, top: 0, right: 20, bottom: 20))
			let paint = SKPaint()
			paint.color = 0xFF00_00FF
			canvas.drawRegion(SKRegion(SKRectI(left: 0, top: 0, right: 10, bottom: 10)), paint)
		}
		let picture = try #require(recorder.finishRecordingAsPicture())

		var surface = try #require(SKSurface.raster(info, 0, nil))
		do {
			let canvas = surface.canvas
			canvas.clear(0xFFFF_FFFF)
			picture.playback(canvas)
			#expect(canvas.surface != nil)
		}
		let pixmap = try #require(surface.peekPixels())
		#expect(pixmap.getColor(5, 5) == 0xFF00_00FF)
		#expect(pixmap.getColor(15, 15) == 0xFFFF_FFFF)

		let image = try #require(SKImage.deferredFromPicture(picture, SKSizeI(w: 20, h: 20)))
		#expect(image.width == 20)
	}

	@Test func pathAdditions() throws {
		let builder = SKPathBuilder()
		builder.addRect(SKRect(left: 0, top: 0, right: 10, bottom: 10))
		let square = builder.detach()
		#expect(square.tightBounds() == SKRect(left: 0, top: 0, right: 10, bottom: 10))
		#expect(SKPathEffect.make1DPath(square, 20, 0, .translate) != nil)
		#expect(SKPathEffect.make2DPath(.scale(10, 10), square) != nil)

		let font = SKFont(SKTypeface.default(.normal), 20)
		var paths = 0
		font.getPaths(font.textToGlyphs("ab")) { path, _ in if path != nil { paths += 1 } }
		#expect(paths == 2)
		#expect(!font.getTextPath("ab", [SKPoint(x: 0, y: 20), SKPoint(x: 30, y: 20)]).bounds.isEmpty)
	}
}
