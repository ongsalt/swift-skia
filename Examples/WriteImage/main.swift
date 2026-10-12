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
guard var surface = SKSurface.raster(&info, 0, nil) else {
	fatalError("could not create a raster surface")
}

let paint = SKPaint()
paint.isAntialias = true

// A five-pointed star.
let builder = SKPathBuilder()
let (cx, cy, outer, inner): (Float, Float, Float, Float) = (500, 150, 90, 38)
for k in 0..<10 {
	let angle = Float(k) * .pi / 5 - .pi / 2
	let r = k.isMultiple(of: 2) ? outer : inner
	let (x, y) = (cx + r * cos(angle), cy + r * sin(angle))
	k == 0 ? builder.moveTo(x, y) : builder.lineTo(x, y)
}
builder.close()
let star = builder.detach()

// Text, in the default family of the system font directory.
let font = SKFont(SKTypeface.default(.bold), 44)

do {
	let canvas = surface.canvas

	// Background: diagonal gradient. SKColor is 0xAARRGGBB.
	paint.shader = SKShader.linearGradient(
		[SKPoint(x: 0, y: 0), SKPoint(x: Float(width), y: Float(height))],
		[0xFF1E_3A8A, 0xFF9D_174D], nil, 2, .clamp, nil)
	canvas.drawPaint(paint)
	paint.shader = nil

	for (i, color) in [0xCCF5_9E0B, 0xCC10_B981, 0xCC38_BDF8].enumerated() {
		paint.color = SKColor(color)
		canvas.drawCircle(140 + Float(i) * 70, 150, 80, paint)
	}

	paint.color = 0xFFFD_E047
	canvas.drawPath(star, paint)
	let outline = paint.copy()
	outline.style = .stroke
	outline.strokeWidth = 4
	outline.color = 0xFFFF_FFFF
	canvas.drawPath(star, outline)

	paint.color = 0xFFFF_FFFF
	canvas.drawText("Skia from Swift", 40, 310, font, paint)
}

guard let png = surface.peekPixels()?.encode(.png) else { fatalError("PNG encoding failed") }
guard let file = fopen(path, "wb") else { fatalError("can't open \(path)") }
png.span.withUnsafeBufferPointer { _ = fwrite($0.baseAddress, 1, $0.count, file) }
fclose(file)
print("wrote \(path) (\(width)x\(height), \(png.size) bytes)")
