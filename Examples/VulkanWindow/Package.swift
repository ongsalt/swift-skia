// swift-tools-version: 6.4

// Graphite drawing into a window's Vulkan swapchain. A separate package so the main one
// doesn't need SDL3 or the Vulkan headers. Requires SDL3 and Vulkan development packages.
import PackageDescription

let package = Package(
	name: "VulkanWindow",
	dependencies: [
		.package(path: "../..")
	],
	targets: [
		.target(
			name: "CWindow",
			linkerSettings: [.linkedLibrary("SDL3"), .linkedLibrary("vulkan")]
		),
		.executableTarget(
			name: "VulkanWindow",
			dependencies: ["CWindow", .product(name: "Skia", package: "swift-skia")]
		),
	]
)
