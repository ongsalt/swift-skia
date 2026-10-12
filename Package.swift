// swift-tools-version: 6.4

import Foundation
import PackageDescription

// Prebuilt Skia from the "Release Skia" workflow (one bundle per target, see native/).
// Set SWIFT_SKIA_LOCAL_BUNDLE to a local skia-<target>.artifactbundle directory,
// relative to this package, to test a CI build artifact instead.
// var localBundle: String? = ProcessInfo.processInfo.environment["SWIFT_SKIA_LOCAL_BUNDLE"].flatMap {
// 	$0.isEmpty ? nil : $0
// }
var localBundle: String? = nil

let skiaLib: Target =
	if let localBundle {
		.binaryTarget(name: "SkiaLib", path: localBundle)
	} else {
		.binaryTarget(
			name: "SkiaLib",
			url:
				"https://github.com/ongsalt/swift-skia/releases/download/skia-a9e4fac6f758/skia.artifactbundleindex",
			checksum: "280364e91cb5356969941fd7ca14d07f226068cef996c6a63622015abddc44d8"
		)
	}

let package = Package(
	name: "swift-skia",
	products: [
		.library(name: "Skia", targets: ["Skia"])
	],
	targets: [
		skiaLib,
		.target(
			name: "CSkia",
			dependencies: ["SkiaLib"],
			linkerSettings: [
				.linkedLibrary("stdc++", .when(platforms: [.linux])),
				.linkedLibrary("m", .when(platforms: [.linux])),
				.linkedLibrary("dl", .when(platforms: [.linux])),
				.linkedLibrary("pthread", .when(platforms: [.linux])),
			]
		),
		.target(
			name: "Skia",
			dependencies: ["CSkia"],
			swiftSettings: [
				.enableExperimentalFeature("Lifetimes"),
				// Span overloads for C functions whose buffers CSkia.apinotes annotates.
				.enableExperimentalFeature("SafeInteropWrappers"),
			]
		),
		.executableTarget(
			name: "WriteImage",
			dependencies: [
				"Skia",
			],
			path: "Examples/WriteImage"
		),
		.target(
			name: "CVulkanTestSupport",
			path: "Tests/CVulkanTestSupport",
			linkerSettings: [.linkedLibrary("vulkan")]
		),
		.testTarget(
			name: "SkiaTests",
			dependencies: [
				"Skia",
				"CVulkanTestSupport",
			]
		),
	]
)
