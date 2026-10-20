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
			checksum: "fb66c9f179e8acc9afc0d311784ad7ad3b2c52cbf7b07409d2d9f87a83808730"
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
				// Skia's GN targets list these for Windows (native/build.py).
				.linkedLibrary("Ole32", .when(platforms: [.windows])),
				.linkedLibrary("OleAut32", .when(platforms: [.windows])),
				.linkedLibrary("User32", .when(platforms: [.windows])),
				.linkedLibrary("Usp10", .when(platforms: [.windows])),
				.linkedLibrary("FontSub", .when(platforms: [.windows])),
				.linkedLibrary("Gdi32", .when(platforms: [.windows])),
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
			linkerSettings: [
				.linkedLibrary("vulkan", .when(platforms: [.linux])),
				.linkedLibrary("vulkan-1", .when(platforms: [.windows])),
			]
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
