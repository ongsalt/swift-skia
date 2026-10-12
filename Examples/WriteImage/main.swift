// Draws a small scene on a CPU raster surface and writes it as a PNG.
// usage: swift run WriteImage [output.png]
import Skia

#if canImport(Glibc)
import Glibc
#endif

let path = CommandLine.arguments.dropFirst().first ?? "skia-example.png"
let width: Int32 = 640
let height: Int32 = 360

var info = SKImageInfo(colorspace: nil, width: width, height: height, colorType: .rgba8888, alphaType: .premul)
guard let surface = SKSurface(raster: &info, 0, nil), let canvas = __sk_surface_get_canvas(surface) else {
	fatalError("could not create a raster surface")
}

let paint = __sk_paint_new()!
defer { __sk_paint_delete(paint) }
__sk_paint_set_antialias(paint, true)

// Background: diagonal gradient. sk_color_t is 0xAARRGGBB.
let gradient = SKShader(
	linearGradient: [SKPoint(x: 0, y: 0), SKPoint(x: Float(width), y: Float(height))],
	[0xFF1E_3A8A, 0xFF9D_174D], nil, 2, .clamp, nil)
__sk_paint_set_shader(paint, gradient)
__sk_canvas_draw_paint(canvas, paint)
__sk_paint_set_shader(paint, nil)

// Circles.
for (i, color) in [0xCCF5_9E0B, 0xCC10_B981, 0xCC38_BDF8].enumerated() {
	__sk_paint_set_color(paint, sk_color_t(color))
	__sk_canvas_draw_circle(canvas, 140 + Float(i) * 70, 150, 80, paint)
}

// A five-pointed star.
let builder = __sk_pathbuilder_new()!
defer { __sk_pathbuilder_delete(builder) }
let (cx, cy, outer, inner): (Float, Float, Float, Float) = (500, 150, 90, 38)
for k in 0..<10 {
	let angle = Float(k) * .pi / 5 - .pi / 2
	let r = k.isMultiple(of: 2) ? outer : inner
	let (x, y) = (cx + r * cos(angle), cy + r * sin(angle))
	k == 0 ? __sk_pathbuilder_move_to(builder, x, y) : __sk_pathbuilder_line_to(builder, x, y)
}
__sk_pathbuilder_close(builder)
let star = __sk_pathbuilder_detach_path(builder)!
defer { __sk_path_delete(star) }
__sk_paint_set_color(paint, 0xFFFD_E047)
__sk_canvas_draw_path(canvas, star, paint)
__sk_paint_set_style(paint, .stroke)
__sk_paint_set_stroke_width(paint, 4)
__sk_paint_set_color(paint, 0xFFFF_FFFF)
__sk_canvas_draw_path(canvas, star, paint)
__sk_paint_set_style(paint, .fill)

// Text, in the default family of the system font directory.
let fontManager = SKFontManager.createDefault()!
let style = sk_fontstyle_new(700, 5, .upright)
defer { sk_fontstyle_delete(style) }
let typeface = fontManager.legacyCreateTypeface(nil, style)
let font = __sk_font_new_with_values(typeface, 44, 1, 0)!
defer { __sk_font_delete(font) }
__sk_paint_set_color(paint, 0xFFFF_FFFF)
let text = "Skia from Swift"
text.withCString { __sk_canvas_draw_simple_text(canvas, $0, strlen($0), .utf8, 40, 310, font, paint) }

// Encode as PNG.
let pixmap = sk_pixmap_new()!
defer { sk_pixmap_destructor(pixmap) }
guard surface.peekPixels(pixmap) else { fatalError("peekPixels failed") }

let stream = sk_filewstream_new(path)!
var options = SKPngencoderOptions()
options.fZLibLevel = 6
let encoded = sk_pngencoder_encode(stream, pixmap, &options)
sk_filewstream_destroy(stream)

guard encoded else { fatalError("PNG encoding failed") }
print("wrote \(path) (\(width)x\(height), \(fontManager.countFamilies()) font families)")
