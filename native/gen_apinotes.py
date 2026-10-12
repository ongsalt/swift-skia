#!/usr/bin/env python3
"""Generates Sources/CSkia/include/{CSkia.h, CSkia.apinotes} from SkiaSharp's C API.

Inputs (fetched once into .build/gen_apinotes/, or passed explicitly):
  - mono/skia include/c and src/c at native/skia.pin             (the C API and its shims)
  - mono/SkiaSharp binding/SkiaSharp/Generated at native/skiasharp.pin
    (C# names for every C struct/enum/enumerator, e.g. sk_colortype_t -> SKColorType)

What the apinotes do:
  - ref-counted types (have *_ref/*_unref) -> Swift classes (SKImage, SKShader, ...)
  - their functions -> initializers, methods and getters; returns are +1 ("retained")
  - enums -> Swift enums / option sets with SkiaSharp's names
  - structs -> SkiaSharp's names (SKRect, SKImageInfo, ...)
  - functions touching hand-written types (paint, path, font, canvas) -> SwiftPrivate (__sk_*)
  - Ganesh (gr_*) and ref/unref -> unavailable in Swift
  - counted buffers -> Span overloads (COUNTED_BUFFERS)
  - structs passed by pointer -> Swift overloads taking them by value, written to
    Sources/Skia/Generated/StructOverloads.swift (see gen_overloads.py)
Everything else stays as the raw C API.

usage: native/gen_apinotes.py [--headers DIR] [--skiasharp DIR]
"""
import argparse
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

import gen_overloads

ROOT = pathlib.Path(__file__).resolve().parent.parent
CACHE = ROOT / ".build" / "gen_apinotes"
OUT = ROOT / "Sources" / "CSkia" / "include"
SWIFT_OUT = ROOT / "Sources" / "Skia" / "Generated"

# --- configuration ------------------------------------------------------------

# Headers left out of CSkia.h: Ganesh, backends we don't build, modules that come later.
EXCLUDED_HEADERS = {
    "gr_context.h", "sk_document.h", "sk_svg.h", "sk_linker.h",
    "sk_graphite_metal.h", "sk_graphite_dawn.h",
    "skottie_animation.h", "sksg_invalidation_controller.h", "skresources_resource_provider.h",
}

# Owned (new/delete) types wrapped by hand in Sources/Skia; their C functions become __sk_*.
HAND_WRITTEN = {
    "sk_canvas_t", "sk_paint_t", "sk_path_t", "sk_pathbuilder_t", "sk_font_t",
    "sk_graphite_context_t", "sk_graphite_recorder_t", "sk_graphite_recording_t",
    "sk_graphite_backend_texture_t",
    "sk_pixmap_t", "sk_fontstyle_t",
}

# Base classes, not types of their own.
NOT_REFCOUNTED = {"sk_refcnt_t", "sk_nvrefcnt_t"}

# Swift names where neither SkiaSharp's generated C# nor "SK" + PascalCase(words) fits.
TYPE_NAMES = {
    "sk_colorfilter_t": "SKColorFilter",
    "sk_colorspace_t": "SKColorSpace",
    "sk_fontmgr_t": "SKFontManager",
    "sk_fontstyleset_t": "SKFontStyleSet",
    "sk_imagefilter_t": "SKImageFilter",
    "sk_jpegencoder_options_t": "SKJpegEncoderOptions",
    "sk_maskfilter_t": "SKMaskFilter",
    "sk_pngencoder_options_t": "SKPngEncoderOptions",
    "sk_runtimeeffect_t": "SKRuntimeEffect",
    "sk_textblob_t": "SKTextBlob",
    "sk_webpencoder_options_t": "SKWebpEncoderOptions",
}

# Immutable once created (or internally synchronized, like SkFontMgr), so safe to share across threads.
SENDABLE = {
    "sk_blender_t", "sk_colorfilter_t", "sk_colorspace_t", "sk_data_t", "sk_fontmgr_t", "sk_image_t",
    "sk_imagefilter_t", "sk_maskfilter_t", "sk_path_effect_t", "sk_picture_t",
    "sk_runtimeeffect_t", "sk_shader_t", "sk_textblob_t", "sk_typeface_t", "sk_vertices_t",
}

# Functions returning a ref-counted object WITHOUT a +1 (checked in mono/skia src/c).
UNRETAINED = {"sk_get_surface"}

# Buffers passed with their element count: function -> [(buffer, count, nullable)].
# They get BoundsSafety + NoEscape notes, so Swift adds overloads taking Span / MutableSpan
# (RawSpan for void*) with the count dropped. Reviewed by hand: every buffer here is only
# read or written during the call, never kept. Not here on purpose: buffers Skia keeps
# (sk_data_new_with_proc, sk_memorystream_*, sk_colorspace_icc_profile_parse),
# strings (better as String overloads), and
# textblob builder runs (Skia hands those buffers out).
_GRADIENT = [("colors", "colorCount", False), ("colorPos", "colorCount", True)]
COUNTED_BUFFERS = {
    "sk_canvas_draw_atlas": [("xform", "count", False), ("tex", "count", False), ("colors", "count", True)],
    "sk_canvas_draw_points": [("points", "count", False)],
    "sk_canvas_draw_simple_text": [("text", "byte_length", False)],
    "sk_color_premultiply_array": [("colors", "size", False), ("pmcolors", "size", False)],
    "sk_color_unpremultiply_array": [("pmcolors", "size", False), ("colors", "size", False)],
    "sk_data_new_with_copy": [("src", "length", True)],
    "sk_font_break_text": [("text", "byteLength", False)],
    "sk_font_get_paths": [("glyphs", "count", False)],
    "sk_font_get_pos": [("glyphs", "count", False), ("pos", "count", False)],
    "sk_font_get_widths_bounds": [("glyphs", "count", False), ("widths", "count", True), ("bounds", "count", True)],
    "sk_font_get_xpos": [("glyphs", "count", False), ("xpos", "count", False)],
    "sk_font_measure_text": [("text", "byteLength", False)],
    "sk_font_measure_text_no_return": [("text", "byteLength", False)],
    "sk_font_text_to_glyphs": [("text", "byteLength", False), ("glyphs", "maxGlyphCount", True)],
    "sk_font_unichars_to_glyphs": [("uni", "count", False), ("glyphs", "count", False)],
    "sk_matrix_map_points": [("dst", "count", False), ("src", "count", False)],
    "sk_matrix_map_vectors": [("dst", "count", False), ("src", "count", False)],
    "sk_path_effect_create_dash": [("intervals", "count", False)],
    "sk_path_get_points": [("points", "max", True)],
    "sk_pathbuilder_add_poly": [("points", "count", False)],
    "sk_picture_deserialize_from_memory": [("buffer", "length", False)],
    "sk_region_set_rects": [("rects", "count", False)],
    "sk_shader_new_linear_gradient": _GRADIENT,
    "sk_shader_new_linear_gradient_color4f": _GRADIENT,
    "sk_shader_new_radial_gradient": _GRADIENT,
    "sk_shader_new_radial_gradient_color4f": _GRADIENT,
    "sk_shader_new_sweep_gradient": _GRADIENT,
    "sk_shader_new_sweep_gradient_color4f": _GRADIENT,
    "sk_shader_new_two_point_conical_gradient": _GRADIENT,
    "sk_shader_new_two_point_conical_gradient_color4f": _GRADIENT,
    "sk_stream_peek": [("buffer", "size", False)],
    "sk_stream_read": [("buffer", "size", True)],
    "sk_swizzle_swap_rb": [("dest", "count", False), ("src", "count", False)],
    "sk_text_utils_get_path": [("text", "length", False)],
    "sk_text_utils_get_pos_path": [("text", "length", False)],
    "sk_typeface_get_kerning_pair_adjustments": [("glyphs", "count", False), ("adjustments", "count", True)],
    "sk_typeface_get_table_data": [("data", "length", True)],
    "sk_typeface_get_variation_design_parameters": [("parameters", "parameterCount", True)],
    "sk_typeface_get_variation_design_position": [("coordinates", "coordinateCount", True)],
    "sk_typeface_unichars_to_glyphs": [("unichars", "count", False), ("glyphs", "count", False)],
    "sk_vertices_make_copy": [("positions", "vertexCount", False), ("texs", "vertexCount", True),
                              ("colors", "vertexCount", True), ("indices", "indexCount", True)],
    "sk_wstream_write": [("buffer", "size", False)],
}

SWIFT_KEYWORDS = {
    "as", "break", "case", "catch", "class", "continue", "default", "defer", "deinit", "do",
    "else", "enum", "extension", "fallthrough", "false", "for", "func", "guard", "if", "import",
    "in", "init", "inout", "internal", "is", "let", "nil", "operator", "private", "protocol",
    "public", "repeat", "rethrows", "return", "self", "Self", "static", "struct", "subscript",
    "super", "switch", "throw", "throws", "true", "try", "typealias", "var", "where", "while",
}

# --- inputs -------------------------------------------------------------------


def sparse_checkout(url: str, commit: str, paths: list[str], dest: pathlib.Path) -> pathlib.Path:
    marker = dest / f".done-{commit}"
    if marker.exists():
        return dest
    shutil.rmtree(dest, ignore_errors=True)
    dest.mkdir(parents=True)
    git = ["git", "-C", str(dest)]
    subprocess.run(git + ["init", "-q"], check=True)
    subprocess.run(git + ["sparse-checkout", "set", "--no-cone", *paths], check=True)
    subprocess.run(git + ["fetch", "-q", "--depth", "1", "--filter=blob:none", url, commit], check=True)
    subprocess.run(git + ["checkout", "-q", "FETCH_HEAD"], check=True)
    marker.touch()
    return dest


def pin(name: str) -> str:
    return (ROOT / "native" / name).read_text().strip()


# --- C API (clang JSON AST) ---------------------------------------------------

POINTER = re.compile(r"^(?:const\s+)?(\w+)\s*\*$")


def pointee(qual_type: str) -> str | None:
    m = POINTER.match(qual_type.strip())
    return m.group(1) if m else None


def parse_c_api(headers: pathlib.Path, header_names: list[str]):
    with tempfile.TemporaryDirectory() as tmp:
        main = pathlib.Path(tmp) / "all.h"
        main.write_text("".join(f'#include "include/c/{h}"\n' for h in header_names))
        dump = subprocess.run(
            ["clang", "-x", "c", "-std=c11", "-fsyntax-only", "-Xclang", "-ast-dump=json",
             f"-I{headers}", str(main)],
            check=True, capture_output=True, text=True).stdout
    decls = json.loads(dump)["inner"]

    complete_records = {n["id"] for n in decls if n["kind"] == "RecordDecl" and n.get("completeDefinition")}
    complete_named = {n["name"] for n in decls if n["kind"] == "RecordDecl" and n.get("completeDefinition") and n.get("name")}

    typedefs = {}  # name -> "opaque" | "struct" | "enum" | "other"
    for n in decls:
        name = n.get("name", "")
        if n["kind"] != "TypedefDecl" or not name.startswith("sk_"):
            continue
        tag = n.get("inner", [{}])[0].get("ownedTagDecl")
        qual = n["type"]["qualType"]
        if qual.startswith("enum "):
            typedefs[name] = "enum"
        elif qual.startswith("struct "):
            tag_name = qual[len("struct "):]
            complete = (tag and tag["id"] in complete_records) or tag_name in complete_named
            typedefs[name] = "struct" if complete else "opaque"
        elif "(*)" in qual:
            typedefs[name] = "fnptr"
        else:
            typedefs[name] = "other"

    functions = {}
    for n in decls:
        name = n.get("name", "")
        if n["kind"] != "FunctionDecl" or not name.startswith(("sk_", "gr_")):
            continue
        params = [(p.get("name", ""), p["type"]["qualType"]) for p in n.get("inner", []) if p["kind"] == "ParmVarDecl"]
        ret = n["type"]["qualType"].split("(", 1)[0].strip()
        functions[name] = {"ret": ret, "params": params}
    return typedefs, functions


# --- SkiaSharp names (C# generated bindings) -----------------------------------

CS_TYPE_COMMENT = re.compile(r"^\s*// (sk_\w+_t)\s*$")
CS_DECL = re.compile(r"^\s*(?:public|internal)\s+(?:unsafe\s+)?(?:partial\s+)?(enum|struct)\s+(\w+)")
CS_ENUMERATOR_COMMENT = re.compile(r"^\s*// (\w+) = ")
CS_MEMBER = re.compile(r"^\s*(\w+)\s*=")


def parse_skiasharp(generated: pathlib.Path):
    types = {}    # c typedef -> (C# name, is_flags)
    members = {}  # C enumerator -> C# member name
    for f in sorted(generated.glob("*.generated.cs")):
        c_type, flags, pending = None, False, None
        for line in f.read_text().splitlines():
            if m := CS_TYPE_COMMENT.match(line):
                c_type, flags = m.group(1), False
            elif c_type and line.strip() == "[Flags]":
                flags = True
            elif c_type and (m := CS_DECL.match(line)):
                name = re.sub(r"(Native|Internal)$", "", m.group(2))
                types[c_type] = (name, flags)
                c_type = None
            elif m := CS_ENUMERATOR_COMMENT.match(line):
                pending = m.group(1)
            elif pending and (m := CS_MEMBER.match(line)):
                members[pending] = m.group(1)
                pending = None
    return types, members


# --- naming helpers -------------------------------------------------------------


def camel(snake: str) -> str:
    words = [w for w in snake.split("_") if w]
    return words[0] + "".join(w[:1].upper() + w[1:] for w in words[1:]) if words else ""


def lower_first(pascal: str) -> str:
    """Rgba8888 -> rgba8888, StrokeAndFill -> strokeAndFill, RGBA -> rgba, SRgb -> sRgb."""
    m = re.match(r"^([A-Z]+)(?=[A-Z][a-z]|[0-9]|$)", pascal)
    if m and len(m.group(1)) > 1:
        return m.group(1).lower() + pascal[len(m.group(1)):]
    return pascal[:1].lower() + pascal[1:]


def mechanical_type_name(c_name: str) -> str:
    core = re.sub(r"^sk_|_t$", "", c_name)
    return "SK" + "".join(w[:1].upper() + w[1:] for w in core.split("_"))


# --- generation -----------------------------------------------------------------


def generate(headers: pathlib.Path, generated_cs: pathlib.Path, shims: pathlib.Path) -> None:
    header_names = sorted(p.name for p in (headers / "include" / "c").glob("*.h") if p.name not in EXCLUDED_HEADERS)
    typedefs, functions = parse_c_api(headers, header_names)
    cs_types, cs_members = parse_skiasharp(generated_cs)

    # Ref-counted types: X_unref(T*). Types without X_ref are SkRefCnt subclasses
    # that SkiaSharp retains via sk_refcnt_safe_ref; CSkia.h gets a typed shim.
    refcounted, ref_fns, ref_shims = {}, set(), {}
    for name, fn in functions.items():
        if not name.endswith("_unref") or len(fn["params"]) != 1:
            continue
        t = pointee(fn["params"][0][1])
        if not t or typedefs.get(t) != "opaque" or t in NOT_REFCOUNTED:
            continue
        ref = name[: -len("_unref")] + "_ref"
        if ref not in functions:
            ref = "cskia_" + name[len("sk_"): -len("_unref")] + "_ref"
            ref_shims[t] = ref
        refcounted[t] = {"retain": ref, "release": name}
        ref_fns |= {name, ref}

    used_names: dict[str, str] = {}

    def claim(swift: str, c: str) -> bool:
        if swift in used_names and used_names[swift] != c:
            print(f"warning: {c} -> {swift} collides with {used_names[swift]}; left unrenamed", file=sys.stderr)
            return False
        used_names[swift] = c
        return True

    tags, typedef_notes, enumerators = [], [], []
    class_names = {}
    for t in sorted(refcounted):
        swift = TYPE_NAMES.get(t, mechanical_type_name(t))
        if claim(swift, t):
            class_names[t] = swift
            tags.append({"Name": t, "SwiftName": swift, "SwiftImportAs": "reference",
                         "SwiftRetainOp": refcounted[t]["retain"], "SwiftReleaseOp": refcounted[t]["release"]})

    enum_constants = {}  # typedef -> [C enumerators], from the AST via C# comments or name suffix
    for t, kind in sorted(typedefs.items()):
        if kind not in ("enum", "struct"):
            continue
        cs = cs_types.get(t)
        swift = TYPE_NAMES.get(t) or (cs[0] if cs else mechanical_type_name(t))
        if not claim(swift, t):
            continue
        tag = {"Name": t, "SwiftName": swift}
        if kind == "enum":
            tag["EnumExtensibility"] = "open"
            if cs and cs[1]:
                tag["FlagEnum"] = "true"
        # Tag too, not just the typedef: `typedef struct sk_x_t {…} sk_x_t` imports by tag name.
        tags.append(tag)
        typedef_notes.append({"Name": t, "SwiftName": swift})

    for c_name, member in sorted(cs_members.items()):
        swift = lower_first(member)
        # Keywords are fine as case names (`.repeat`); these few aren't.
        if swift not in ("init", "self", "Self", "Type"):
            enumerators.append({"Name": c_name, "SwiftName": swift})

    # Functions.
    receivers = sorted(class_names, key=lambda t: -len(t))  # longest prefix wins
    gr = re.compile(r"\bgr_\w+_t\b")
    getters = getter_types(functions, receivers, typedefs)
    swift_types = {n["Name"]: n["SwiftName"] for n in typedef_notes}
    sources = "".join(p.read_text() for p in sorted(shims.glob("*.cpp")))
    planner = gen_overloads.Planner(typedefs, swift_types, class_names, COUNTED_BUFFERS,
                                    gen_overloads.shim_definitions(sources))
    overloads = []
    fn_notes, method_names = [], set()
    for t, shim in sorted(ref_shims.items()):
        if t in class_names:
            fn_notes.append({"Name": shim, "Availability": "nonswift"})
    for name in sorted(functions):
        fn = functions[name]
        types = [fn["ret"]] + [p[1] for p in fn["params"]]
        note = {"Name": name}

        ret_t = pointee(fn["ret"])
        if ret_t in refcounted:
            note["SwiftReturnOwnership"] = "unretained" if name in UNRETAINED else "retained"

        if name.startswith("gr_") or name in ref_fns or any(gr.search(t) for t in types):
            note["Availability"] = "nonswift"
        elif any(pointee(t) in HAND_WRITTEN for t in types):
            note["SwiftPrivate"] = "true"
        else:
            swift = swift_name(name, fn, receivers, class_names, typedefs, getters)
            if swift in method_names:
                swift = None
            code = planner.plan(name, fn, swift)
            if swift:
                method_names.add(swift)
            if code:
                overloads.append(code)
                note["SwiftPrivate"] = "true"
            elif swift:
                note["SwiftName"] = swift

        if name in COUNTED_BUFFERS and "Availability" not in note:
            note["Parameters"] = buffer_notes(name, fn, COUNTED_BUFFERS[name])

        if len(note) > 1:
            fn_notes.append(note)

    write_header(header_names, {t: s for t, s in ref_shims.items() if t in class_names})
    SWIFT_OUT.mkdir(parents=True, exist_ok=True)
    (SWIFT_OUT / "StructOverloads.swift").write_text(
        "// Generated by native/gen_apinotes.py (gen_overloads.py). Do not edit.\n\n"
        + gen_overloads.SUPPORT + "\n" + "\n".join(overloads))
    write_apinotes(tags, typedef_notes, fn_notes, enumerators)
    print(f"{len(class_names)} classes, {sum(1 for t in tags if 'EnumExtensibility' in t)} enums, "
          f"{len(typedef_notes) - sum(1 for t in tags if 'EnumExtensibility' in t)} structs, "
          f"{sum('SwiftName' in n for n in fn_notes)} renamed functions, "
          f"{sum('SwiftPrivate' in n for n in fn_notes)} private, "
          f"{sum('Availability' in n for n in fn_notes)} hidden, {len(overloads)} by-value struct overloads")


def receiver_of(name: str, receivers: list[str], typedefs: dict) -> str | None:
    receiver = next((t for t in receivers if name.startswith(t[:-1])), None)
    # sk_textblob_builder_new belongs to sk_textblob_builder_t, not sk_textblob_t.
    if receiver and any(len(t) > len(receiver) and name.startswith(t[:-1]) for t in typedefs):
        return None
    return receiver


def base_type(qual_type: str) -> str:
    return re.sub(r"\bconst\b|\s+", "", qual_type)


def getter_types(functions: dict, receivers: list[str], typedefs: dict) -> dict[tuple[str, str], str]:
    """(receiver, property) -> C type, for every X_get_foo(self) that becomes a property."""
    getters = {}
    for name, fn in functions.items():
        receiver = receiver_of(name, receivers, typedefs)
        suffix = name[len(receiver) - 1:] if receiver else ""
        if (receiver and suffix.startswith("get_") and len(fn["params"]) == 1
                and pointee(fn["params"][0][1]) == receiver and fn["ret"] != "void"):
            getters[(receiver, camel(suffix[4:]))] = base_type(fn["ret"])
    return getters


def swift_name(name: str, fn: dict, receivers: list[str], class_names: dict[str, str], typedefs: dict,
               getters: dict[tuple[str, str], str]) -> str | None:
    """Skia's own API gets no argument labels: methods and factories take `_:` throughout.
    Non-throwing get/set pairs become properties instead of getX()/setX(_:)."""
    receiver = receiver_of(name, receivers, typedefs)
    if not receiver:
        return None
    cls, suffix = class_names[receiver], name[len(receiver) - 1:]
    params = fn["params"]
    is_method = params and pointee(params[0][1]) == receiver
    rest = params[1:] if is_method else params
    unlabeled = "_:" * len(rest)

    def ok(base: str) -> bool:
        # Keywords work as member names (`.default`); these few don't.
        return bool(base) and base not in ("init", "self", "Self", "Type") and base[0].isalpha()

    if is_method:
        prop = camel(suffix[4:])
        if not rest and fn["ret"] != "void" and suffix.startswith("get_") and ok(prop):
            return f"getter:{cls}.{prop}(self:)"
        if (len(rest) == 1 and fn["ret"] == "void" and suffix.startswith("set_") and ok(prop)
                and getters.get((receiver, prop)) == base_type(rest[0][1])):
            return f"setter:{cls}.{prop}(self:newValue:)"
        if not rest and fn["ret"] in ("bool", "_Bool") and suffix.startswith(("is_", "has_")):
            return f"getter:{cls}.{camel(suffix)}(self:)"
        base = camel(suffix)
        return f"{cls}.{base}(self:{unlabeled})" if ok(base) else None

    # Constructors: sk_x_new(...) -> init(_:...); sk_x_new_foo(...) -> static foo(_:...).
    if pointee(fn["ret"]) == receiver and (suffix == "new" or suffix.startswith("new_")):
        factory = camel(suffix[4:])
        if ok(factory):
            return f"{cls}.{factory}({unlabeled})"
        return f"{cls}.init({unlabeled})" if suffix == "new" else None

    base = camel(suffix)
    return f"{cls}.{base}({unlabeled})" if ok(base) else None


def buffer_notes(name: str, fn: dict, buffers: list[tuple[str, str, bool]]) -> list[dict]:
    params = [p[0] for p in fn["params"]]
    notes = []
    for buffer, count, nullable in buffers:
        if buffer not in params or count not in params:
            sys.exit(f"COUNTED_BUFFERS: {name} has no parameter {buffer!r} or {count!r}; params are {params}")
        is_raw = base_type(fn["params"][params.index(buffer)][1]) in ("void*", "void[]")
        kind = ("sized_by" if is_raw else "counted_by") + ("_or_null" if nullable else "")
        note = {"Position": params.index(buffer), "NoEscape": "true"}
        if nullable:
            note["Nullability"] = "O"
        note["BoundsSafety"] = {"Kind": kind, "BoundedBy": count}
        notes.append(note)
    return notes


def write_header(header_names: list[str], ref_shims: dict[str, str]) -> None:
    lines = ["// Generated by native/gen_apinotes.py. Do not edit.", "#pragma once", ""]
    lines += [f'#include "include/c/{h}"' for h in header_names]
    lines += ["", "// Retain functions for SkRefCnt types the C API only exposes X_unref for",
              "// (SkiaSharp retains these through sk_refcnt_safe_ref the same way)."]
    lines += [f"static inline void {shim}(const {t}* p) {{ sk_refcnt_safe_ref((sk_refcnt_t*)p); }}"
              for t, shim in sorted(ref_shims.items())]
    lines += ["", "// Immutable ref-counted types, safe to share across threads."]
    lines += [f'struct __attribute__((swift_attr("@Sendable"))) {t};' for t in sorted(SENDABLE)]
    (OUT / "CSkia.h").write_text("\n".join(lines) + "\n")


def write_entry(out: list[str], entry: dict, indent: str) -> None:
    """One YAML list item; values may be scalars, nested dicts or lists of dicts."""
    first = True
    for k, v in entry.items():
        lead = f"{indent}{'- ' if first else '  '}"
        first = False
        if isinstance(v, list):
            out.append(f"{lead}{k}:")
            for item in v:
                write_entry(out, item, indent + "  ")
        elif isinstance(v, dict):
            out.append(f"{lead}{k}:")
            for kk, vv in v.items():
                out.append(f"{indent}    {kk}: {vv}")
        else:
            out.append(f"{lead}{k}: {v}")


def write_apinotes(tags, typedefs, functions, enumerators) -> None:
    out = ["# Generated by native/gen_apinotes.py. Do not edit.", "---", "Name: CSkia"]
    for section, entries in (("Tags", tags), ("Typedefs", typedefs), ("Functions", functions), ("Enumerators", enumerators)):
        if not entries:
            continue
        out.append(f"{section}:")
        for e in entries:
            write_entry(out, e, "")
    (OUT / "CSkia.apinotes").write_text("\n".join(out) + "\n")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--headers", type=pathlib.Path, help="directory containing include/c (default: fetch mono/skia at native/skia.pin)")
    ap.add_argument("--skiasharp", type=pathlib.Path, help="SkiaSharp binding/SkiaSharp/Generated (default: fetch at native/skiasharp.pin)")
    args = ap.parse_args()

    skia = sparse_checkout(
        "https://github.com/mono/skia", pin("skia.pin"), ["/include/c/", "/src/c/"], CACHE / "skia-src")
    headers = args.headers or skia
    generated = args.skiasharp or sparse_checkout(
        "https://github.com/mono/SkiaSharp", pin("skiasharp.pin"),
        ["/binding/SkiaSharp/Generated/"], CACHE / "skiasharp") / "binding" / "SkiaSharp" / "Generated"
    generate(headers.resolve(), generated.resolve(), (skia / "src" / "c").resolve())


if __name__ == "__main__":
    main()
