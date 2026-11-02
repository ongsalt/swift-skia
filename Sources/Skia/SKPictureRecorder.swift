/// `SkPictureRecorder`: records drawing commands into an `SKPicture` or `SKDrawable`.
/// Like rust-skia's `PictureRecorder`, the canvas borrows the recorder exclusively.
public struct SKPictureRecorder: ~Copyable {
	public let handle: OpaquePointer

	public init() {
		handle = __sk_picture_recorder_new()
	}

	deinit {
		__sk_picture_recorder_delete(handle)
	}

	/// Starts recording drawing culled to `bounds`. An R-tree speeds up playback of pictures
	/// drawn partially (by clip).
	@_lifetime(&self)
	public mutating func beginRecording(_ bounds: SKRect, _ bbhFactory: borrowing SKRTreeFactory? = nil) -> SKCanvas {
		var bounds = bounds
		let canvas = switch bbhFactory {
		case .some(let factory): __sk_picture_recorder_begin_recording_with_bbh_factory(handle, &bounds, factory.handle)
		case .none: __sk_picture_recorder_begin_recording(handle, &bounds)
		}
		return SKCanvas(canvas!, dependingOn: &self)
	}

	/// The canvas being recorded into, nil when not recording.
	public var recordingCanvas: SKCanvas? {
		@_lifetime(&self)
		mutating get {
			guard let canvas = __sk_picture_get_recording_canvas(handle) else { return nil }
			return SKCanvas(canvas, dependingOn: &self)
		}
	}

	/// Ends recording. Nil when nothing was being recorded.
	public mutating func finishRecordingAsPicture() -> SKPicture? {
		__sk_picture_recorder_end_recording(handle)
	}

	/// Ends recording into a drawable that replays the commands each time it's drawn.
	public mutating func finishRecordingAsDrawable() -> SKDrawable? {
		__sk_picture_recorder_end_recording_as_drawable(handle)
	}
}

/// `SkRTreeFactory`: a bounding-box hierarchy for `SKPictureRecorder.beginRecording`.
public final class SKRTreeFactory {
	public let handle: OpaquePointer

	public init() {
		handle = __sk_rtree_factory_new()
	}

	deinit {
		__sk_rtree_factory_delete(handle)
	}
}

extension SKImage {
	/// `makeShader(sampling, localMatrix)`, clamping on both axes.
	public func makeShader(_ sampling: SKSamplingOptions = SKSamplingOptions(), _ localMatrix: SKMatrix? = nil) -> SKShader? {
		makeShader(.clamp, .clamp, sampling, localMatrix)
	}
}
