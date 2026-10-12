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

	struct Procs {
		var getInstanceProcAddr: SKVkGetInstanceProcAddr
		var getDeviceProcAddr: SKVkGetDeviceProcAddr?
	}

	var procs: Procs { Procs(getInstanceProcAddr: getInstanceProcAddr, getDeviceProcAddr: getDeviceProcAddr) }

	/// Skia's lookup callback: device functions via `vkGetDeviceProcAddr` when available.
	static let getProc: sk_graphite_vk_get_proc = { userData, name, instance, device in
		let procs = userData!.assumingMemoryBound(to: Procs.self).pointee
		let function: SKVkVoidFunction?
		if let device, let getDeviceProcAddr = procs.getDeviceProcAddr {
			function = getDeviceProcAddr(device, name)
		} else {
			function = procs.getInstanceProcAddr(instance, name)
		}
		return function
	}
}
