"""Swift overloads that take C structs by value, for gen_apinotes.py.

SkiaSharp's C API passes structs by pointer (`const sk_rect_t* rect`), so Swift callers would
write `&rect` and couldn't express "no matrix" except with a raw nil pointer. For each public
function with such parameters, this emits an overload taking `SKRect` (required) or `SKRect?`
(optional) and marks the C function SwiftPrivate, as rust-skia does by hand from the C++
signatures (`const SkRect&` is required, `const SkMatrix*` is optional).

Whether a pointer may be null is read from SkiaSharp's C shims (mono/skia src/c), which call
C++ exactly that way:
  - an explicit null check (`if (cmatrix)`, `p ? … : …`) means optional;
  - a dereference (`*AsRect(rect)`) or a value helper (`AsMatrix(m)`, `AsImageInfo(info)`) means
    required;
  - anything else (a pointer handed to C++ as-is) is ambiguous: STRUCT_POINTERS says, or the
    parameter keeps its raw pointer type.
"""
import re

# SkiaSharp helpers that dereference their pointer and return a value (src/c/sk_types_priv.h).
VALUE_HELPERS = [
    "AsMatrix", "AsImageInfo", "AsJpegEncoderOptions", "AsPngEncoderOptions", "AsWebpEncoderOptions",
    "AsCanvasSaveLayerRec", "AsTextBlobBuilderRunBuffer",
]

# Reviewed against the C++ callee where the shim alone doesn't say.
# "optional": C++ takes a nullable pointer. "required": C++ dereferences it.
# "array": several structs, not one; keeps its pointer type.
# "input": a non-const pointer the shim only reads (a missing const in the header).
STRUCT_POINTERS = {
    ("sk_bitmap_make_shader", "sampling"): "input",                       # *AsSamplingOptions(sampling)
    ("sk_codec_get_pixels", "options"): "optional",                     # const SkCodec::Options* = nullptr
    ("sk_codec_start_incremental_decode", "options"): "optional",
    ("sk_codec_start_scanline_decode", "options"): "optional",
    ("sk_colorspace_transfer_fn_eval", "transferFn"): "required",       # skcms_* dereference
    ("sk_colorspace_transfer_fn_invert", "src"): "required",
    ("sk_colorspace_xyz_concat", "a"): "required",
    ("sk_colorspace_xyz_concat", "b"): "required",
    ("sk_colorspace_xyz_invert", "src"): "required",
    ("sk_picture_make_shader", "tile"): "optional",                     # const SkRect* tile
    ("sk_shader_new_linear_gradient", "points"): "array",              # SkPoint[2]
    ("sk_shader_new_linear_gradient_color4f", "points"): "array",
    ("sk_shader_new_perlin_noise_fractal_noise", "tileSize"): "optional",  # const SkISize* = nullptr
    ("sk_shader_new_perlin_noise_turbulence", "tileSize"): "optional",
}

# SkImageFilters take `const CropRect&`, constructible from a nullable `const SkRect*`.
OPTIONAL_BY_NAME = {"cropRect"}

SCALARS = {
    "int": "Int32", "unsigned int": "UInt32", "int32_t": "Int32", "uint32_t": "UInt32",
    "int64_t": "Int64", "uint64_t": "UInt64", "size_t": "Int", "float": "Float", "double": "Double",
    "bool": "Bool", "_Bool": "Bool", "uint8_t": "UInt8", "int8_t": "Int8", "uint16_t": "UInt16",
    "int16_t": "Int16", "char": "CChar", "intptr_t": "Int", "uintptr_t": "UInt",
}

SWIFT_KEYWORDS = {
    "as", "break", "case", "catch", "class", "continue", "default", "defer", "deinit", "do", "else",
    "enum", "extension", "fallthrough", "false", "for", "func", "guard", "if", "import", "in", "init",
    "inout", "internal", "is", "let", "nil", "operator", "private", "protocol", "public", "repeat",
    "rethrows", "return", "self", "Self", "static", "struct", "subscript", "super", "switch", "throw",
    "throws", "true", "try", "typealias", "var", "where", "while", "Type",
}


def shim_definitions(sources: str) -> dict[str, tuple[list[str], str]]:
    """C function name -> (parameter names as defined, body)."""
    defs = {}
    for m in re.finditer(r"^[\w\s\*]+?\b(sk_\w+)\s*\(([^)]*)\)\s*\{(.*?)^\}", sources, re.S | re.M):
        names = [re.sub(r"\[.*?\]", "", p).strip().split(" ")[-1].lstrip("*") for p in m.group(2).split(",")]
        defs[m.group(1)] = (names, m.group(3))
    return defs


def classify(body: str, name: str) -> str:
    q = re.escape(name)
    if re.search(rf"\bif\s*\(\s*!?\s*{q}\s*\)|\b{q}\s*\?|\b{q}\s*&&|!\s*{q}\b|\b{q}\s*[!=]=\s*(nullptr|NULL)", body):
        return "optional"
    if re.search(rf"\*\s*As\w+\(\s*{q}\s*\)|As\w+\(\s*{q}\s*\)\s*->|\*\s*{q}\b|\b{q}\s*->", body):
        return "required"
    if re.search(rf"\b(?:{'|'.join(VALUE_HELPERS)})\(\s*{q}\s*\)", body):
        return "required"
    return "unknown"


class Planner:
    def __init__(self, typedefs, swift_types, class_names, counted_buffers, definitions):
        self.typedefs = typedefs            # C typedef -> opaque | struct | enum | fnptr | other
        self.swift_types = swift_types      # C struct/enum typedef -> Swift name
        self.class_names = class_names      # ref-counted C typedef -> Swift class
        self.counted = counted_buffers      # COUNTED_BUFFERS
        self.definitions = definitions

    # --- C -> Swift types --------------------------------------------------------------

    def value_type(self, c: str) -> str | None:
        c = c.strip()
        if c in SCALARS:
            return SCALARS[c]
        kind = self.typedefs.get(c)
        if kind in ("struct", "enum"):
            return self.swift_types.get(c)
        if kind == "fnptr":
            return f"{c}?"
        if kind == "other":
            return c
        return None

    def pointer_type(self, q: str) -> str | None:
        """Swift type for a pointer parameter that isn't a by-value struct or a counted buffer."""
        q = q.strip()
        if q.count("*") != 1 or "[" in q:
            return None
        is_const = q.startswith("const ")
        base = re.sub(r"\bconst\b|\*", "", q).strip()
        if base == "void":
            return "UnsafeRawPointer?" if is_const else "UnsafeMutableRawPointer?"
        if base in self.class_names:
            return f"{self.class_names[base]}?"
        if self.typedefs.get(base) == "opaque":
            return "OpaquePointer?"
        element = self.value_type(base)
        if element is None or element.endswith("?"):
            return None
        return f"UnsafePointer<{element}>?" if is_const else f"UnsafeMutablePointer<{element}>?"

    def return_type(self, q: str) -> str | None:
        q = q.strip()
        if q == "void":
            return ""
        if "*" in q:
            base = re.sub(r"\bconst\b|\*", "", q).strip()
            if base in self.class_names:
                return f"{self.class_names[base]}?"
            return self.pointer_type(q)
        return self.value_type(q)

    # --- planning -----------------------------------------------------------------------

    def plan(self, name: str, fn: dict, swift_name: str | None) -> str | None:
        """Swift source for the overload, or None if this function keeps its imported form."""
        if swift_name and swift_name.startswith(("getter:", "setter:")) or swift_name and ".init(" in swift_name:
            return None
        def_names, body = self.definitions.get(name, ([], ""))
        params = fn["params"]
        buffers = {b: (count, nullable) for b, count, nullable in self.counted.get(name, [])}
        dropped = {count for count, _ in buffers.values()}

        receiver_type, method = None, None
        if swift_name:
            receiver_type, rest = swift_name.split(".", 1)
            method = rest.split("(", 1)[0]
            is_instance = "(self:" in rest
        decl, args, wraps, prelude, has_struct = [], [], [], [], False
        for i, (pname, ptype) in enumerate(params):
            shim_name = def_names[i] if i < len(def_names) else ""
            label = swift_ident(pname or shim_name or f"p{i}")
            if i == 0 and swift_name and is_instance:
                args.append("self")
                continue
            if pname in dropped:
                continue
            if pname in buffers:
                _, nullable = buffers[pname]
                if not ptype.startswith("const "):
                    return None  # mutable buffers can't be used inside the pointer closures
                base = re.sub(r"\bconst\b|\*|\[\d*\]", "", ptype).strip()
                elem = "RawSpan" if base == "void" else f"Span<{self.value_type(base)}>"
                if "None" in elem:
                    return None
                decl.append(f"_ {label}: {elem}{'?' if nullable else ''}")
                args.append(label)
                continue
            pointee = re.sub(r"\bconst\b|\*", "", ptype).strip() if ptype.count("*") == 1 else None
            if pointee and self.typedefs.get(pointee) == "struct":
                kind = STRUCT_POINTERS.get((name, pname or shim_name))
                if kind is None:
                    kind = "optional" if (pname or shim_name) in OPTIONAL_BY_NAME else classify(body, shim_name or pname)
                swift = self.swift_types[pointee]
                if not ptype.startswith("const "):
                    kind = {"required": "inout", "input": "copy"}.get(kind, "raw")
                if kind == "copy":  # non-const C parameter, but only read: copy so the caller passes a value
                    decl.append(f"_ {label}: {swift}")
                    prelude.append(f"var {label} = {label}")
                    args.append(f"&{label}")
                    continue
                if kind in ("required", "optional"):
                    has_struct = True
                    decl.append(f"_ {label}: {swift}{'?' if kind == 'optional' else ''}")
                    wraps.append((label, kind))
                    args.append(label)
                    continue
                if kind == "inout":
                    decl.append(f"_ {label}: inout {swift}")
                    args.append(f"&{label}")
                    continue
                pointer = f"UnsafePointer<{swift}>?" if ptype.startswith("const ") else f"UnsafeMutablePointer<{swift}>?"
                decl.append(f"_ {label}: {pointer}")
                args.append(label)
                continue
            swift = self.value_type(ptype) if "*" not in ptype else self.pointer_type(ptype)
            if swift is None:
                return None
            decl.append(f"_ {label}: {swift}")
            args.append(label)
        if not has_struct:
            return None
        ret = self.return_type(fn["ret"])
        if ret is None:
            return None

        call = f"__{name}({', '.join(args)})"
        for label, kind in reversed(wraps):
            helper = "withUnsafePointer(to: " if kind == "required" else "_skWithOptionalPointer("
            call = f"{helper}{label}) {{ {label} in {call} }}"
        signature = f"({', '.join(decl)}){f' -> {ret}' if ret else ''}"
        if prelude and ret:
            call = f"return {call}"
        if swift_name is None:
            body = "".join(f"\t{line}\n" for line in prelude + [call])
            return f"public func {name}{signature} {{\n{body}}}\n"
        static = "" if is_instance else "static "
        body = "".join(f"\t\t{line}\n" for line in prelude + [call])
        return f"extension {receiver_type} {{\n\tpublic {static}func {method}{signature} {{\n{body}\t}}\n}}\n"


def swift_ident(name: str) -> str:
    return f"`{name}`" if name in SWIFT_KEYWORDS else name


SUPPORT = '''/// Calls `body` with a pointer to `value`, or with nil.
@inline(__always)
func _skWithOptionalPointer<T, R>(_ value: T?, _ body: (UnsafePointer<T>?) throws -> R) rethrows -> R {
	guard let value else { return try body(nil) }
	return try withUnsafePointer(to: value) { try body($0) }
}
'''
