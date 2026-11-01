// Graphite draws straight into a window's Vulkan swapchain images.
// usage: swift run VulkanWindow [--frames N] [--screenshot out.png] [--resize-test]
// Set CW_VALIDATION=1 to enable the Vulkan validation layers.
import CWindow
import Skia

#if canImport(Glibc)
import Glibc
#elseif canImport(ucrt)
import ucrt
#endif

let arguments = CommandLine.arguments
func option(_ name: String) -> String? {
	arguments.firstIndex(of: name).flatMap { $0 + 1 < arguments.count ? arguments[$0 + 1] : nil }
}
let maxFrames = option("--frames").flatMap(Int.init)
let screenshotPath = option("--screenshot")
/// Requests a different window size every frame, to exercise swapchain recreation.
let resizeTest = arguments.contains("--resize-test")

guard let window = cw_create("Skia · Graphite · Vulkan", 800, 500) else { fatalError("could not open a window") }
defer { cw_destroy(window) }

let device = cw_get_device(window)
let backend = SKGraphiteVulkanBackend(
	instance: OpaquePointer(device.instance), physicalDevice: OpaquePointer(device.physicalDevice),
	device: OpaquePointer(device.device), queue: OpaquePointer(device.queue),
	graphicsQueueIndex: device.queueFamily, maxAPIVersion: device.apiVersion,
	getInstanceProcAddr: unsafeBitCast(device.getInstanceProcAddr, to: SKVkGetInstanceProcAddr.self),
	getDeviceProcAddr: unsafeBitCast(device.getDeviceProcAddr, to: SKVkGetDeviceProcAddr.self))
guard var context = SKGraphiteContext.vulkan(backend) else { fatalError("Skia rejected the Vulkan device") }
guard var recorder = context.makeRecorder() else { fatalError("could not create a Graphite recorder") }
print("Graphite on \(String(cString: cw_device_name(window)))")

let titleFont = SKFont(SKTypeface.default(.bold), 40)
let smallFont = SKFont(SKTypeface.default(.bold), 18)
let paint = SKPaint()
paint.isAntialias = true

/// VkFormat → Skia color type, for the formats window.c picks from.
func colorType(_ format: Int32) -> SKColorType {
	switch format {
	case 44: .bgra8888   // VK_FORMAT_B8G8R8A8_UNORM
	case 37: .rgba8888   // VK_FORMAT_R8G8B8A8_UNORM
	case 43: .srgba8888  // VK_FORMAT_R8G8B8A8_SRGB
	default: fatalError("unexpected swapchain format \(format)")
	}
}

let presentable = SKGraphiteMutableTextureState.vulkan(1_000_001_002 /* VK_IMAGE_LAYOUT_PRESENT_SRC_KHR */, device.queueFamily)!

/// A frame the CPU recorded and the GPU may still be working on.
final class FrameSlot {
	var inFlight = false
}
let slots = (0..<Int(CW_FRAMES_IN_FLIGHT)).map { _ in FrameSlot() }

/// Waits until the GPU has finished every inserted recording.
func finishGPUWork() {
	var sync = SKGraphiteSubmitInfo()
	sync.fSync = true
	context.submit(sync)
	context.checkAsyncWorkCompletion()
}

@MainActor
func draw(_ canvas: borrowing SKCanvas, _ width: Float, _ height: Float, _ time: Float, _ fps: Float) {
	paint.color = 0xFF00_0000  // the shader takes the paint's alpha
	let colors: [SKColor] = [0xFF0F_172A, 0xFF31_2E81]
	paint.shader = SKShader.linearGradient(
		[SKPoint(x: 0, y: 0), SKPoint(x: width, y: height)], colors.span, nil, .clamp, nil)
	canvas.drawPaint(paint)
	paint.shader = nil

	let (cx, cy) = (width / 2, height / 2 + 20)
	for i in 0..<8 {
		let angle = time * 1.2 + Float(i) * .pi / 4
		let radius = min(width, height) * 0.28
		paint.color = [0xE6F4_3F5E, 0xE6F5_9E0B, 0xE610_B981, 0xE638_BDF8][i % 4]
		canvas.drawCircle(cx + radius * cos(angle), cy + radius * sin(angle), 26 + 8 * sin(time * 3 + Float(i)), paint)
	}

	paint.color = 0xFFFF_FFFF
	canvas.drawText("Skia · Graphite · Vulkan", 32, 64, titleFont, paint)
	paint.color = 0xB3FF_FFFF
	canvas.drawText("\(Int(fps)) fps  \(Int(width))×\(Int(height))", 32, height - 24, smallFont, paint)
}

func writePNG(_ pixels: [UInt8], _ rowBytes: Int, _ info: SKImageInfo, _ path: String) {
	var info = info
	guard let png = SKImage.rasterCopy(info, pixels, rowBytes)?.encode(.png),
		let file = fopen(path, "wb")
	else { return }
	png.span.withUnsafeBufferPointer { _ = fwrite($0.baseAddress, 1, $0.count, file) }
	fclose(file)
}

var frame = cw_frame()
var frameCount = 0
let clock = ContinuousClock()
let start = clock.now
var lastTick = start
var fps: Float = 0

func seconds(_ duration: Duration) -> Float {
	Float(duration.components.seconds) + Float(duration.components.attoseconds) / 1e18
}

while cw_poll(window) {
	let slot = slots[frameCount % slots.count]
	while slot.inFlight {  // its acquire semaphore is reused below
		context.checkAsyncWorkCompletion()
		if slot.inFlight { usleep(200) }
	}
	if cw_recreate_pending(window) { finishGPUWork() }  // the swapchain images are about to go away
	guard cw_acquire(window, UInt32(frameCount % slots.count), &frame) else { continue }

	let textureInfo = SKGraphiteVkTextureInfo(
		fSampleCount: 1, fMipmapped: false, fFlags: 0, fFormat: frame.format,
		fImageTiling: 0 /* OPTIMAL */, fImageUsageFlags: frame.usage,
		fSharingMode: 0 /* EXCLUSIVE */, fAspectMask: 1 /* COLOR */)
	guard
		let texture = SKGraphiteBackendTexture.vulkan(
			frame.width, frame.height, textureInfo, 0 /* UNDEFINED */, device.queueFamily, OpaquePointer(frame.image)!),
		var surface = SKSurface.wrapBackendTexture(&recorder, texture, colorType(frame.format))
	else { fatalError("could not wrap swapchain image \(frame.index)") }

	let now = clock.now
	fps = 0.9 * fps + 0.1 / max(seconds(now - lastTick), 1e-6)
	lastTick = now
	draw(surface.canvas, Float(frame.width), Float(frame.height), seconds(now - start), fps)

	// draw() always records something, so a nil snap means Graphite failed.
	guard let recording = recorder.snap() else { fatalError("Graphite recorded nothing") }
	slot.inFlight = true
	let status = context.insertRecording(
		recording,
		options: SKGraphiteInsertOptions(
			targetSurface: surface,
			targetTextureState: presentable,
			waitSemaphores: [SKGraphiteBackendSemaphore.vulkan(frame.acquiredSemaphore)!],
			signalSemaphores: [SKGraphiteBackendSemaphore.vulkan(frame.renderFinishedSemaphore)!],
			finished: { success in
				if !success { print("frame \(frameCount): GPU work failed") }
				slot.inFlight = false
			}))
	guard status == .success else { fatalError("insertRecording failed: \(status)") }
	context.submit()

	if frameCount == 0 { print("swapchain: VkFormat \(frame.format)") }
	if resizeTest { cw_set_size(window, 640 + Int32(frameCount * 37 % 400), 400 + Int32(frameCount * 23 % 200)) }
	frameCount += 1
	if let maxFrames, frameCount >= maxFrames, let screenshotPath {
		// The readback moves the image out of PRESENT_SRC, so this frame isn't presented.
		let info = SKImageInfo(colorspace: nil, width: frame.width, height: frame.height, colorType: .rgba8888, alphaType: .premul)
		if let (pixels, rowBytes) = context.readPixels(surface, info) {
			writePNG(pixels, rowBytes, info, screenshotPath)
			print("wrote \(screenshotPath)")
		}
		break
	}
	cw_present(window, &frame)
	if let maxFrames, frameCount >= maxFrames { break }
}
finishGPUWork()
let elapsed = seconds(clock.now - start)
print("\(frameCount) frames in \(Int(elapsed * 1000)) ms (\(Int(Float(frameCount) / elapsed)) fps average), \(cw_recreate_count(window)) swapchain recreations")
