extension SKRuntimeEffect {
	/// `SkRuntimeEffect::Result::errorText` when SkSL fails to compile.
	public struct CompileError: Error, CustomStringConvertible {
		public var errorText: String
		public var description: String { errorText }
	}

	public static func makeForShader(_ sksl: String) throws(CompileError) -> SKRuntimeEffect {
		try make(sksl) { makeForShader($0, $1) }
	}

	public static func makeForColorFilter(_ sksl: String) throws(CompileError) -> SKRuntimeEffect {
		try make(sksl) { makeForColorFilter($0, $1) }
	}

	public static func makeForBlender(_ sksl: String) throws(CompileError) -> SKRuntimeEffect {
		try make(sksl) { makeForBlender($0, $1) }
	}

	private static func make(
		_ sksl: String, _ factory: (OpaquePointer?, OpaquePointer?) -> SKRuntimeEffect?
	) throws(CompileError) -> SKRuntimeEffect {
		var sksl = sksl
		let source = sksl.withUTF8 { sk_string_new_with_copy($0.baseAddress, $0.count) }
		let error = sk_string_new_empty()
		defer {
			sk_string_destructor(source)
			sk_string_destructor(error)
		}
		guard let effect = factory(source, error) else {
			throw CompileError(errorText: String(cString: sk_string_get_c_str(error)))
		}
		return effect
	}

	/// `SkRuntimeEffect::ChildPtr`: a child effect the SkSL samples. Nil clears it.
	public enum ChildPtr: Sendable {
		case shader(SKShader)
		case colorFilter(SKColorFilter)
		case blender(SKBlender)
	}
}

/// `SkRuntimeEffectBuilder`: a runtime effect with its uniform values and children, set by name.
/// Reference semantics: `let b = a` shares one builder; use `copy()` for an independent one.
public final class SKRuntimeEffectBuilder {
	public let handle: OpaquePointer

	public enum Error: Swift.Error {
		case noSuchUniform(String)
		/// The value's size doesn't match the uniform's.
		case uniformSizeMismatch(name: String, expected: Int, actual: Int)
		case noSuchChild(String)
	}

	private init(handle: OpaquePointer) {
		self.handle = handle
	}

	/// With `uniforms` nil, uniforms start zeroed.
	public init(_ effect: SKRuntimeEffect, _ uniforms: SKData? = nil) {
		handle = swsk_runtimeeffect_builder_new(effect, uniforms)
	}

	deinit {
		swsk_runtimeeffect_builder_delete(handle)
	}

	public func copy() -> SKRuntimeEffectBuilder {
		SKRuntimeEffectBuilder(handle: swsk_runtimeeffect_builder_clone(handle))
	}

	public var effect: SKRuntimeEffect { swsk_runtimeeffect_builder_get_effect(handle) }

	/// A snapshot of the uniform values, in the layout `SKRuntimeEffect.makeShader` takes.
	public var uniforms: SKData { swsk_runtimeeffect_builder_get_uniforms(handle) }

	/// `uniform(name) = value`. `value` must have the uniform's exact size, e.g. `Float` for
	/// `float`, `SIMD2<Float>` for `float2`, `[4 of Float]` for `float[4]`.
	public func setUniform<T: BitwiseCopyable>(_ name: String, _ value: T) throws(Error) {
		var value = value
		try withUnsafeBytes(of: &value) { bytes throws(Error) in try setUniform(name, bytes) }
	}

	/// `uniform(name).set(values, count)`, for arrays.
	public func setUniform<T: BitwiseCopyable>(_ name: String, _ values: Span<T>) throws(Error) {
		try values.withUnsafeBytes { bytes throws(Error) in try setUniform(name, bytes) }
	}

	private func setUniform(_ name: String, _ bytes: UnsafeRawBufferPointer) throws(Error) {
		let size = Int(swsk_runtimeeffect_builder_set_uniform(handle, name, bytes.baseAddress, bytes.count))
		if size < 0 { throw .noSuchUniform(name) }
		if size != bytes.count { throw .uniformSizeMismatch(name: name, expected: size, actual: bytes.count) }
	}

	/// `child(name) = child`.
	public func setChild(_ name: String, _ child: SKRuntimeEffect.ChildPtr?) throws(Error) {
		let found: Bool
		switch child {
		case .shader(let shader): found = swsk_runtimeeffect_builder_set_child(handle, name, shader, nil, nil)
		case .colorFilter(let filter): found = swsk_runtimeeffect_builder_set_child(handle, name, nil, filter, nil)
		case .blender(let blender): found = swsk_runtimeeffect_builder_set_child(handle, name, nil, nil, blender)
		case nil: found = swsk_runtimeeffect_builder_set_child(handle, name, nil, nil, nil)
		}
		if !found { throw .noSuchChild(name) }
	}

	/// Nil when the effect isn't a shader effect or a child is missing.
	public func makeShader(_ localMatrix: SKMatrix? = nil) -> SKShader? {
		_skWithOptionalPointer(localMatrix) { swsk_runtimeeffect_builder_make_shader(handle, $0) }
	}

	public func makeColorFilter() -> SKColorFilter? {
		swsk_runtimeeffect_builder_make_color_filter(handle)
	}

	public func makeBlender() -> SKBlender? {
		swsk_runtimeeffect_builder_make_blender(handle)
	}
}

extension SKImageFilter {
	/// `SkImageFilters::RuntimeShader`: fills with `builder`'s shader, its child shader
	/// `childShaderName` bound to `input` (nil: the source image). `sampleRadius` is how far
	/// from each pixel the SkSL samples that child.
	public static func runtimeShader(
		_ builder: SKRuntimeEffectBuilder, _ sampleRadius: Float = 0, _ childShaderName: String = "",
		_ input: SKImageFilter? = nil, restrictOutputToInputBounds: Bool = false
	) -> SKImageFilter? {
		swsk_imagefilter_new_runtime_shader(builder.handle, sampleRadius, childShaderName, input, restrictOutputToInputBounds)
	}

	/// `SkImageFilters::RuntimeShader` binding several child shaders, `childShaderNames[i]` to
	/// `inputs[i]`.
	public static func runtimeShader(
		_ builder: SKRuntimeEffectBuilder, _ maxSampleRadius: Float, _ childShaderNames: [String],
		_ inputs: [SKImageFilter?]
	) -> SKImageFilter? {
		precondition(childShaderNames.count == inputs.count, "\(childShaderNames.count) names for \(inputs.count) inputs")
		// All names NUL-terminated in one buffer.
		var packed: [CChar] = []
		var offsets: [Int] = []
		for name in childShaderNames {
			offsets.append(packed.count)
			packed += name.utf8CString
		}
		return packed.withUnsafeBufferPointer { packed in
			let names = offsets.map { Optional(packed.baseAddress! + $0) }
			return names.withUnsafeBufferPointer { names in
				inputs.withUnsafeBufferPointer { inputs in
					swsk_imagefilter_new_runtime_shader_multi(
						builder.handle, maxSampleRadius, names.baseAddress, inputs.baseAddress, Int32(inputs.count))
				}
			}
		}
	}
}
