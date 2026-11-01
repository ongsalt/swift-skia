import Skia
import Testing

@Suite struct RRectTests {
	@Test func shapesAndRadii() {
		let rect = SKRect(left: 0, top: 0, right: 100, bottom: 50)
		let rrect = SKRRect.makeRectXY(rect, 10, 5)
		#expect(rrect.type == .simple)
		#expect(rrect.radii(.upperLeft).x == 10)
		#expect(rrect.width == 100)

		rrect.setRectRadii(rect, [SKPoint(x: 1, y: 1), SKPoint(x: 2, y: 2), SKPoint(x: 3, y: 3), SKPoint(x: 4, y: 4)])
		#expect(rrect.type == .complex)
		#expect(rrect.radii(.lowerLeft).x == 4)

		rrect.rect = rect
		#expect(rrect.type == .rect)
		#expect(SKRRect.makeOval(rect).type == .oval)
		#expect(rrect.contains(SKRect(left: 10, top: 10, right: 20, bottom: 20)))
	}
}

@Suite struct PathGeometryTests {
	func square() -> SKPath {
		let builder = SKPathBuilder()
		builder.addRect(SKRect(left: 0, top: 0, right: 10, bottom: 10))
		return builder.detach()
	}

	@Test func shapeQueries() {
		#expect(square().isRect?.rect == SKRect(left: 0, top: 0, right: 10, bottom: 10))
		#expect(square().isOval == nil)

		let oval = SKPathBuilder()
		oval.addOval(SKRect(left: 0, top: 0, right: 20, bottom: 10))
		#expect(oval.detach().isOval == SKRect(left: 0, top: 0, right: 20, bottom: 10))

		let rrect = SKPathBuilder()
		rrect.addRRect(SKRRect.makeRectXY(SKRect(left: 0, top: 0, right: 20, bottom: 20), 4, 4))
		#expect(rrect.detach().isRRect?.type == .simple)

		let line = SKPathBuilder()
		line.moveTo(1, 2)
		line.lineTo(3, 4)
		let points = line.detach().isLine
		#expect(points?[1] == SKPoint(x: 3, y: 4))
	}

	@Test func pointsAndTransform() {
		let path = square()
		#expect(path.countPoints() == 4)
		#expect(path.getPoint(2) == SKPoint(x: 10, y: 10))
		let moved = path.makeTransform(.translate(5, 0))
		#expect(moved.bounds.left == 5)
		#expect(path.bounds.left == 0)
	}

	@Test func booleanOps() throws {
		let other = square().makeTransform(.translate(5, 0))
		let union = try #require(square().op(other, .union))
		#expect(union.bounds == SKRect(left: 0, top: 0, right: 15, bottom: 10))
		let intersection = try #require(square().op(other, .intersect))
		#expect(intersection.bounds == SKRect(left: 5, top: 0, right: 10, bottom: 10))

		let builder = SKOpBuilder()
		builder.add(square(), .union)
		builder.add(other, .difference)
		#expect(try #require(builder.resolve()).bounds == SKRect(left: 0, top: 0, right: 5, bottom: 10))
	}

	@Test func iteration() {
		let rect = square()
		var verbs: [SKPathVerb] = []
		for segment in rect { verbs.append(segment.verb) }
		// Iter adds the line back to the start before .close; RawIter yields what's stored.
		#expect(verbs == [.move, .line, .line, .line, .line, .close])

		var rawVerbs: [SKPathVerb] = []
		var rawRect = SKPath.RawIter(rect)
		while let segment = rawRect.next() { rawVerbs.append(segment.verb) }
		#expect(rawVerbs == [.move, .line, .line, .line, .close])

		let open = SKPathBuilder()
		open.moveTo(0, 0)
		open.lineTo(10, 0)
		open.lineTo(10, 10)
		let path = open.detach()
		var iter = SKPath.Iter(path, true)
		var closeLines = 0
		while let segment = iter.next() {
			if segment.verb == .line, iter.isCloseLine { closeLines += 1 }
		}
		#expect(closeLines == 1)

		var raw = SKPath.RawIter(path)
		#expect(raw.peek() == .move)
		#expect(raw.next()?.points == [SKPoint(x: 0, y: 0)])
	}

	@Test func measure() throws {
		let line = SKPathBuilder()
		line.moveTo(0, 0)
		line.lineTo(100, 0)
		let measure = SKPathMeasure(line.detach())
		#expect(measure.length == 100)
		let (position, tangent) = try #require(measure.getPosTan(25))
		#expect(position == SKPoint(x: 25, y: 0))
		#expect(tangent == SKPoint(x: 1, y: 0))
		let segment = try #require(measure.getSegment(10, 30)).bounds
		#expect(abs(segment.left - 10) < 1e-4 && abs(segment.right - 30) < 1e-4)
		#expect(segment.top == 0 && segment.bottom == 0)
		#expect(!measure.nextContour())
	}
}

@Suite struct FontAndPaintTests {
	let font = SKFont(SKTypeface.default(.normal), 20)

	@Test func glyphQueries() throws {
		let glyphs = font.textToGlyphs("Hi!")
		#expect(glyphs.count == 3)
		#expect(font.unicharToGlyph("H") == glyphs[0])
		#expect(font.unicharsToGlyphs(["H", "i"]) == Array(glyphs.prefix(2)))
		let widths = font.getWidths(glyphs)
		#expect(widths.allSatisfy { $0 > 0 })
		let xs = font.getXPos(glyphs, 10)
		#expect(xs[0] == 10 && xs[1] == 10 + widths[0])
		#expect(font.getPos(glyphs)[1].x == widths[0])
		#expect(try #require(font.getPath(glyphs[0])).bounds.width > 0)
		#expect(font.getTextPath("Hi", 0, 20).bounds.height > 0)
	}

	@Test func breakText() {
		let (bytes, width) = font.breakText("hello world", font.measureText("hello"))
		#expect(bytes == 5)
		#expect(width <= font.measureText("hello"))
	}

	@Test func fillPathFromStroke() throws {
		let line = SKPathBuilder()
		line.moveTo(0, 0)
		line.lineTo(100, 0)
		let paint = SKPaint()
		paint.style = .stroke
		paint.strokeWidth = 10
		let filled = try #require(paint.getFillPath(line.detach()))
		#expect(filled.bounds.height == 10)
		#expect(paint.canComputeFastBounds)
		#expect(paint.computeFastBounds(SKRect(left: 0, top: 0, right: 10, bottom: 10)).left < 0)
	}
}

@Suite struct CanvasAdditionTests {
	@Test func roundRectsAndPatch() throws {
		let info = SKImageInfo(colorspace: nil, width: 40, height: 40, colorType: .rgba8888, alphaType: .premul)
		var surface = try #require(SKSurface.raster(info, 0, nil))
		let paint = SKPaint()
		do {
			let canvas = surface.canvas
			canvas.clear(0xFFFF_FFFF)
			paint.color = 0xFFFF_0000
			canvas.drawRRect(SKRRect.makeRectXY(SKRect(left: 0, top: 0, right: 20, bottom: 20), 6, 6), paint)
			paint.color = 0xFF00_00FF
			canvas.drawDRRect(
				SKRRect.makeRect(SKRect(left: 20, top: 20, right: 40, bottom: 40)),
				SKRRect.makeRect(SKRect(left: 25, top: 25, right: 35, bottom: 35)), paint)
		}
		guard let pixmap = surface.peekPixels() else { return }
		let (center, corner, ring, hole) = (pixmap.getColor(10, 10), pixmap.getColor(0, 0), pixmap.getColor(21, 21), pixmap.getColor(30, 30))
		#expect(center == 0xFFFF_0000)
		#expect(corner == 0xFFFF_FFFF)  // rounded away
		#expect(ring == 0xFF00_00FF)
		#expect(hole == 0xFFFF_FFFF)
	}
}
