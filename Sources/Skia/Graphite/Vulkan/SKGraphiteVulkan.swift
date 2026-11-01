/// `PFN_vkVoidFunction`.
public typealias SKVkVoidFunction = @convention(c) () -> Void
/// `PFN_vkGetInstanceProcAddr`: `(VkInstance, const char*) -> PFN_vkVoidFunction`.
public typealias SKVkGetInstanceProcAddr = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> SKVkVoidFunction?
/// `PFN_vkGetDeviceProcAddr`: `(VkDevice, const char*) -> PFN_vkVoidFunction`.
public typealias SKVkGetDeviceProcAddr = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> SKVkVoidFunction?

/// The caller's Vulkan device, for `SKGraphiteContext.vulkan(_:_:)`.
///
/// Handles are passed as opaque pointers, so any Vulkan binding works and Skia's package needs
/// no Vulkan headers. The device must outlive the context.
public struct SKGraphiteVulkanBackend {
	public var instance: OpaquePointer
	public var physicalDevice: OpaquePointer
	public var device: OpaquePointer
	public var queue: OpaquePointer
	public var graphicsQueueIndex: UInt32
	/// The highest Vulkan API version the app uses (e.g. `VK_API_VERSION_1_1`).
	public var maxAPIVersion: UInt32
	public var getInstanceProcAddr: SKVkGetInstanceProcAddr
	/// Optional: device-level lookups go through `vkGetInstanceProcAddr` when `nil`.
	public var getDeviceProcAddr: SKVkGetDeviceProcAddr?
	public var isProtected: Bool

	public init(
		instance: OpaquePointer, physicalDevice: OpaquePointer, device: OpaquePointer, queue: OpaquePointer,
		graphicsQueueIndex: UInt32, maxAPIVersion: UInt32,
		getInstanceProcAddr: SKVkGetInstanceProcAddr, getDeviceProcAddr: SKVkGetDeviceProcAddr? = nil,
		isProtected: Bool = false
	) {
		self.instance = instance
		self.physicalDevice = physicalDevice
		self.device = device
		self.queue = queue
		self.graphicsQueueIndex = graphicsQueueIndex
		self.maxAPIVersion = maxAPIVersion
		self.getInstanceProcAddr = getInstanceProcAddr
		self.getDeviceProcAddr = getDeviceProcAddr
		self.isProtected = isProtected
	}

	/// Kept alive by the context; Skia calls back into it through `getProc`.
	final class Procs {
		let getInstanceProcAddr: SKVkGetInstanceProcAddr
		let getDeviceProcAddr: SKVkGetDeviceProcAddr?
		init(_ backend: SKGraphiteVulkanBackend) {
			getInstanceProcAddr = backend.getInstanceProcAddr
			getDeviceProcAddr = backend.getDeviceProcAddr
		}
	}

	/// Skia's lookup callback: device functions via `vkGetDeviceProcAddr` when available.
	static let getProc: sk_graphite_vk_get_proc = { userData, name, instance, device in
		let procs = Unmanaged<Procs>.fromOpaque(userData!).takeUnretainedValue()
		let function: SKVkVoidFunction?
		if let device, let getDeviceProcAddr = procs.getDeviceProcAddr {
			function = getDeviceProcAddr(device, name)
		} else {
			function = procs.getInstanceProcAddr(instance, name)
		}
		return function
	}
}

extension SKGraphiteContext {
	/// Nil if Skia rejects the device or was built without Vulkan.
	public static func vulkan(
		_ backend: SKGraphiteVulkanBackend, _ options: SKGraphiteContextOptions? = nil
	) -> SKGraphiteContext? {
		let procs = SKGraphiteVulkanBackend.Procs(backend)
		let initInfo = SKGraphiteVkBackendContext(
			fInstance: backend.instance,
			fPhysicalDevice: backend.physicalDevice,
			fDevice: backend.device,
			fQueue: backend.queue,
			fGraphicsQueueIndex: backend.graphicsQueueIndex,
			fMaxAPIVersion: backend.maxAPIVersion,
			fGetProc: SKGraphiteVulkanBackend.getProc,
			fGetProcUserData: Unmanaged.passUnretained(procs).toOpaque(),
			fProtectedContext: backend.isProtected)
		let handle: OpaquePointer?
		if var options {
			handle = __sk_graphite_context_make_vulkan(initInfo, &options)
		} else {
			handle = __sk_graphite_context_make_vulkan(initInfo, nil)
		}
		return handle.map { SKGraphiteContext(handle: $0, keepAlive: procs) }
	}
}

extension SKGraphiteBackendTexture {
	/// Wraps a `VkImage` whose memory is already bound.
	/// - `imageLayout`: the `VkImageLayout` the image is in now (`VK_IMAGE_LAYOUT_UNDEFINED` = 0 for a
	///   freshly acquired swapchain image whose contents may be discarded).
	public static func vulkan(
		_ width: Int32, _ height: Int32, _ info: SKGraphiteVkTextureInfo, _ imageLayout: Int32,
		_ queueFamilyIndex: UInt32, _ image: OpaquePointer
	) -> SKGraphiteBackendTexture? {
		var info = info
		return __sk_graphite_vk_backend_texture_new(width, height, &info, imageLayout, queueFamilyIndex, UnsafeMutableRawPointer(image))
			.map(SKGraphiteBackendTexture.init(handle:))
	}
}

extension SKGraphiteBackendSemaphore {
	/// The `VkSemaphore` must outlive the GPU work using it.
	public static func vulkan(_ semaphore: UInt64) -> SKGraphiteBackendSemaphore? {
		swsk_graphite_vk_backend_semaphore_new(semaphore).map(SKGraphiteBackendSemaphore.init(handle:))
	}
}

extension SKGraphiteMutableTextureState {
	/// `imageLayout` is a raw `VkImageLayout`, e.g. `VK_IMAGE_LAYOUT_PRESENT_SRC_KHR` (1000001002).
	public static func vulkan(_ imageLayout: Int32, _ queueFamilyIndex: UInt32) -> SKGraphiteMutableTextureState? {
		swsk_graphite_vk_mutable_texture_state_new(imageLayout, queueFamilyIndex).map(SKGraphiteMutableTextureState.init(handle:))
	}
}
