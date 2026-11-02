import Skia
import Testing

@Suite struct EffectTests {
	let info = SKImageInfo(colorspace: nil, width: 20, height: 20, colorType: .rgba8888, alphaType: .premul)

	@Test func pictureRecorder() throws {
		var recorder = SKPictureRecorder()
		#expect(recorder.recordingCanvas == nil)
		do {
			let canvas = recorder.beginRecording(SKRect(left: 0, top: 0, right: 20, bottom: 20), SKRTreeFactory())
			let paint = SKPaint()
			paint.color = 0xFF00_FF00
			canvas.drawRect(0, 0, 10, 10, paint)
		}
		#expect(recorder.recordingCanvas != nil)
		let picture = try #require(recorder.finishRecordingAsPicture())
		#expect(recorder.recordingCanvas == nil)

		var surface = try #require(SKSurface.raster(info, 0, nil))
		do {
			let canvas = surface.canvas
			canvas.clear(0xFFFF_FFFF)
			canvas.drawPicture(picture)
		}
		let pixmap = try #require(surface.peekPixels())
		#expect(pixmap.getColor(5, 5) == 0xFF00_FF00)
		#expect(pixmap.getColor(15, 15) == 0xFFFF_FFFF)
	}

	@Test func saveLayerWithBackdrop() throws {
		var surface = try #require(SKSurface.raster(info, 0, nil))
		do {
			let canvas = surface.canvas
			canvas.clear(0xFFFF_0000)
			// The backdrop recolors what is below the layer blue; restoring draws the layer back.
			let backdrop = try #require(SKImageFilter.colorFilter(SKColorFilter.mode(0xFF00_00FF, .srcIn)))
			canvas.saveLayer(SKCanvas.SaveLayerRec(bounds: SKRect(left: 0, top: 0, right: 10, bottom: 10), backdrop: backdrop))
			canvas.restore()
		}
		let pixmap = try #require(surface.peekPixels())
		#expect(pixmap.getColor(5, 5) == 0xFF00_00FF)
		#expect(pixmap.getColor(15, 15) == 0xFFFF_0000)
	}

	@Test func runtimeEffectBuilder() throws {
		let effect = try SKRuntimeEffect.makeForShader("""
			uniform half4 color;
			half4 main(float2 p) { return color; }
			""")
		let builder = SKRuntimeEffectBuilder(effect)
		try builder.setUniform("color", SIMD4<Float>(0, 1, 0, 1))
		#expect(throws: SKRuntimeEffectBuilder.Error.self) { try builder.setUniform("color", Float(1)) }
		#expect(throws: SKRuntimeEffectBuilder.Error.self) { try builder.setUniform("missing", Float(1)) }
		#expect(builder.uniforms.size == 16)

		let paint = SKPaint()
		paint.shader = try #require(builder.makeShader())
		var surface = try #require(SKSurface.raster(info, 0, nil))
		do { surface.canvas.drawPaint(paint) }
		#expect(try #require(surface.peekPixels()).getColor(3, 3) == 0xFF00_FF00)
	}

	@Test func compileError() {
		#expect(throws: SKRuntimeEffect.CompileError.self) { try SKRuntimeEffect.makeForShader("not sksl") }
	}

	@Test func runtimeShaderFilter() throws {
		let effect = try SKRuntimeEffect.makeForShader("""
			uniform shader image;
			half4 main(float2 p) { return image.eval(p).bgra; }
			""")
		let filter = try #require(SKImageFilter.runtimeShader(SKRuntimeEffectBuilder(effect), 0, "image"))
		var surface = try #require(SKSurface.raster(info, 0, nil))
		do {
			let canvas = surface.canvas
			let paint = SKPaint()
			paint.imageFilter = filter
			canvas.saveLayer(nil, paint)
			canvas.clear(0xFFFF_0000)
			canvas.restore()
		}
		#expect(try #require(surface.peekPixels()).getColor(3, 3) == 0xFF00_00FF)
	}

	@Test func filterDefaults() throws {
		#expect(SKImageFilter.blur(2, 2, .decal) != nil)
		#expect(SKImageFilter.dropShadow(2, 2, 1, 1, 0xFF00_0000) != nil)
		#expect(SKImageFilter.offset(4, 4) != nil)
	}
}
