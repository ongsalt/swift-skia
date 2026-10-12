/// Records drawing commands for Graphite. Draw into surfaces made from it, then `snap()`.
///
/// Unique owner, like rust-skia's `graphite::Recorder` (`RefHandle`): `~Copyable`, deleted in `deinit`.
public struct SKGraphiteRecorder: ~Copyable {
	public let handle: OpaquePointer

	init(handle: OpaquePointer) {
		self.handle = handle
	}

	deinit {
		__sk_graphite_recorder_delete(handle)
	}

	public var backend: SKGraphiteBackend { __sk_graphite_recorder_get_backend(handle) }

	public var maxTextureSize: Int32 { __sk_graphite_recorder_get_max_texture_size(handle) }

	/// Ends the current batch of work. `nil` if nothing was recorded since the last snap.
	public mutating func snap() -> SKGraphiteRecording? {
		__sk_graphite_recorder_snap(handle).map(SKGraphiteRecording.init(handle:))
	}
}

/// A finished batch of GPU work, ready for `SKGraphiteContext.insertRecording(_:)`.
///
/// Unique owner, like rust-skia's `graphite::Recording` (`RefHandle`): `~Copyable`, deleted in `deinit`.
public struct SKGraphiteRecording: ~Copyable {
	public let handle: OpaquePointer

	init(handle: OpaquePointer) {
		self.handle = handle
	}

	deinit {
		__sk_graphite_recording_delete(handle)
	}
}

extension _SKExclusiveAccess where Self == SKSurface {
	/// A GPU surface drawn through `recorder`. As in rust-skia, the surface doesn't depend on the
	/// recorder's lifetime; snap the recorder to submit what was drawn.
	public static func renderTarget(
		_ recorder: inout SKGraphiteRecorder, _ info: SKImageInfo, _ mipmapped: Bool = false,
		_ props: OpaquePointer? = nil
	) -> SKSurface? {
		var info = info
		return __sk_graphite_surface_make_render_target(recorder.handle, &info, mipmapped, props)
	}
}
