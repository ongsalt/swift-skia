import CVulkanTestSupport
import Skia
import Testing

/// Drives Graphite on a real Vulkan device. Set SKIA_TEST_VULKAN_CPU to use a CPU driver (lavapipe).
@Suite(.serialized) struct GraphiteTests {
	final class Device {
		var raw = vkts_device()
		init?() {
			guard vkts_create(&raw) else { return nil }
		}
		deinit { vkts_destroy(&raw) }

		var name: String { withUnsafeBytes(of: raw.deviceName) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) } }

		var backend: SKGraphiteVulkanBackend {
			SKGraphiteVulkanBackend(
				instance: OpaquePointer(raw.instance), physicalDevice: OpaquePointer(raw.physicalDevice),
				device: OpaquePointer(raw.device), queue: OpaquePointer(raw.queue),
				graphicsQueueIndex: raw.queueFamily, maxAPIVersion: raw.apiVersion,
				getInstanceProcAddr: unsafeBitCast(raw.getInstanceProcAddr, to: SKVkGetInstanceProcAddr.self),
				getDeviceProcAddr: unsafeBitCast(raw.getDeviceProcAddr, to: SKVkGetDeviceProcAddr.self))
		}
	}

	@Test func vulkanIsCompiledIn() {
		#expect(sk_graphite_backend_is_available(.vulkan))
	}

	@Test func drawsOnTheGPU() throws {
		let device = try #require(Device(), "no Vulkan device with a graphics queue")
		guard var context = SKGraphiteContext.vulkan(device.backend) else {
			Issue.record("Skia rejected the Vulkan device \(device.name)")
			return
		}
		let (backend, deviceLost) = (context.backend, context.isDeviceLost)
		#expect(backend == .vulkan)
		#expect(!deviceLost)

		guard var recorder = context.makeRecorder() else {
			Issue.record("makeRecorder failed")
			return
		}
		let info = SKImageInfo(colorspace: nil, width: 8, height: 8, colorType: .rgba8888, alphaType: .premul)
		var surface = try #require(SKSurface.renderTarget(&recorder, info))

		let paint = SKPaint()
		paint.color = 0xFFFF_0000
		do {
			let canvas = surface.canvas
			canvas.clear(0xFF00_00FF)
			canvas.drawRect(0, 0, 4, 8, paint)
		}

		guard let recording = recorder.snap() else {
			Issue.record("nothing recorded")
			return
		}
		let inserted = context.insertRecording(recording)
		let submitted = context.submit()
		#expect(inserted == .success)
		#expect(submitted)

		let read = context.readPixels(surface, info)
		let (pixels, rowBytes) = try #require(read)
		func pixel(_ x: Int, _ y: Int) -> [UInt8] { Array(pixels[(y * rowBytes + x * 4)..<(y * rowBytes + x * 4 + 4)]) }
		#expect(pixel(0, 0) == [0xFF, 0x00, 0x00, 0xFF])  // left half: red (RGBA bytes)
		#expect(pixel(7, 7) == [0x00, 0x00, 0xFF, 0xFF])  // right half: blue
	}

	@Test func recordingCanBeInsertedAgain() throws {
		let device = try #require(Device(), "no Vulkan device with a graphics queue")
		guard var context = SKGraphiteContext.vulkan(device.backend) else {
			Issue.record("Skia rejected the Vulkan device \(device.name)")
			return
		}
		guard var recorder = context.makeRecorder() else {
			Issue.record("makeRecorder failed")
			return
		}
		let info = SKImageInfo(colorspace: nil, width: 4, height: 4, colorType: .rgba8888, alphaType: .premul)
		var surface = try #require(SKSurface.renderTarget(&recorder, info))
		surface.canvas.clear(0xFF00_FF00)
		guard let recording = recorder.snap() else {
			Issue.record("nothing recorded")
			return
		}
		let first = context.insertRecording(recording)
		let second = context.insertRecording(recording)
		let submitted = context.submit()
		#expect(first == .success)
		#expect(second == .success)
		#expect(submitted)
	}
}
