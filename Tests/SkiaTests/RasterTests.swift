import Skia
import Testing

@Suite struct RasterTests {
	@Test func drawsIntoRasterSurface() throws {
		var info = SKImageInfo(colorspace: nil, width: 16, height: 16, colorType: .rgba8888, alphaType: .premul)
		let surface = try #require(SKSurface.raster(&info, 0, nil))

		let canvas = try #require(__sk_surface_get_canvas(surface))
		__sk_canvas_clear(canvas, 0xFFFF_FFFF)
		let paint = try #require(__sk_paint_new())
		defer { __sk_paint_delete(paint) }
		__sk_paint_set_color(paint, 0xFFFF_0000)
		var rect = SKRect(left: 0, top: 0, right: 8, bottom: 16)
		__sk_canvas_draw_rect(canvas, &rect, paint)

		var pixels = [UInt32](repeating: 0, count: 16 * 16)
		let ok = pixels.withUnsafeMutableBytes { surface.readPixels(&info, $0.baseAddress, 16 * 4, 0, 0) }
		#expect(ok)
		// RGBA8888 in memory, read as little-endian UInt32: 0xAABBGGRR.
		#expect(pixels[0] == 0xFF00_00FF)       // left half: red
		#expect(pixels[15] == 0xFFFF_FFFF)      // right half: white
	}

	@Test func snapshotIsAnImage() throws {
		var info = SKImageInfo(colorspace: nil, width: 4, height: 3, colorType: .rgba8888, alphaType: .premul)
		let surface = try #require(SKSurface.raster(&info, 0, nil))
		let image = try #require(surface.newImageSnapshot())
		#expect(image.width == 4)
		#expect(image.height == 3)
		#expect(image.colorType == .rgba8888)
	}
}
