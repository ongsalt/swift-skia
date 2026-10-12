# swift-skia design

Swift bindings for Skia, using the Graphite backend, distributed through SwiftPM.

Guiding rule: **do as little of our own work as possible.** We reuse SkiaSharp's C API and its Linux build configuration. We generate what can be generated and hand-write only the parts that need real ownership decisions.

## Prior art: SkiaKit

[migueldeicaza/SkiaKit](https://github.com/migueldeicaza/SkiaKit) (last commit July 2023) and its fork [UnGast/SkiaKit](https://github.com/UnGast/SkiaKit) (last commit January 2022) took the same basic approach: SkiaSharp's C API with a Swift layer on top. They're unmaintained. What we take from them:

| SkiaKit did | Problem | What we do |
|---|---|---|
| About 7,400 lines of hand-written Swift, including an enum mirror with `toNative()`/`fromNative()` for every C enum | Coverage never caught up: most open issues are "X missing bits" | Generate apinotes; hand-write only five types; raw functions stay callable for gaps |
| Copied SkiaSharp headers into the Swift repo | Headers can drift from the binary | Headers ship **inside** the bundle, next to the `.a` they describe |
| A per-object `owns` flag; a surface's canvas is `owns: .doesNotOwn` and doesn't keep the surface alive | Possible use-after-free; an "audit every deinit" issue has been open since 2019 | Ownership is decided by type kind (ref-counted, owned, borrowed); the canvas can't outlive its closure |
| Linux: download the SkiaSharp NuGet `libSkiaSharp.so` and link with `.unsafeFlags(["-L", dir])` | `unsafeFlags` is rejected for versioned dependencies (its README says to depend on a branch), and users must ship the `.so` themselves | SE-0482 static artifactbundle, with no unsafe flags |
| UnGast: a `sudo` script that installs `libskia.a` into `/usr/local/lib`, linked with system freetype and fontconfig | Manual setup outside SwiftPM; both authors were "waiting for SwiftPM binary support on Linux" | That support now exists (SE-0482); freetype bundled, no fontconfig |
| `import Foundation` everywhere | A heavy dependency on Linux | No Foundation dependency |

## v1 scope

| In | Later |
|---|---|
| `x86_64-unknown-linux-gnu` | aarch64 Linux, macOS (Graphite on Metal), Windows |
| Graphite on Vulkan, with the caller's Vulkan device | A helper that creates the Vulkan device (like SkiaSharp's) |
| CPU raster surfaces (headless rendering, tests) | Dawn backend |
| Core 2D: canvas, paint, path, image, shader, filters, color space, codecs | Skottie, SVG, PDF |
| Simple text: `Font` / `Typeface` / `TextBlob` | Shaping and paragraphs (HarfBuzz, SkParagraph, a Unicode library) |
| Fonts from the system font directory or from files and data | fontconfig matching |

## Hard constraints

1. **No Swift C++ interop.** Interop is viral: tested on Swift 6.4, a client target without `-cxx-interoperability-mode` fails to build even when the wrapper uses `internal import`. Swift only ever sees **C headers**.
2. **No local Skia builds.** Contributors don't have the disk space for them. Skia is built in CI only; local development downloads a prebuilt bundle.
3. **Static library, not shared.** SwiftPM handles static binary artifacts well (SE-0482); shared libraries are awkward to package and locate at runtime.

## Architecture

```
 user code ──► Skia      Swift: re-exports CSkia + a small hand-written layer
                 │
               CSkia     C module: modulemap, wrapper header, generated .apinotes
                 │         (no C++ sources; only an empty .c file to satisfy SwiftPM)
               SkiaLib   binaryTarget: SE-0482 static-library artifactbundle
                           libSkiaSharp.a (mono/skia + SkiaSharp's C API) + include/c/*.h
```

## 1. Native library: built in CI

**Source.** [mono/skia](https://github.com/mono/skia), branch `skiasharp`, pinned to a commit. As of 2026-10-05 it tracks upstream `chrome/m156`. The fork compiles SkiaSharp's C API (`src/c/*.cpp`) into Skia's `:core` target, and the fork's own `SkiaSharp` GN target with `is_static_skiasharp=true` produces one complete static `libSkiaSharp.a` (Skia, its bundled third-party code, pathops, the C API). That is the configuration SkiaSharp ships for its static platforms. Our side needs no shim and no C++. The fork's DEPS is already trimmed (no Dawn, ANGLE or V8), so a plain `git-sync-deps` stays small.

**GN args** (the full list is in `native/build.sh`). These are SkiaSharp's own Linux "no dependencies" args, built as a static library:

```
target_os="linux" target_cpu="x64"
is_official_build=true is_component_build=false
skia_enable_graphite=true  skia_use_vulkan=true
skia_enable_ganesh=true          # see note
skia_use_gl=false skia_use_dawn=false
skia_use_icu=false skia_use_harfbuzz=false
skia_use_fontconfig=false        # fork falls back to scanning the system font dir
skia_enable_fontmgr_custom_directory=true
skia_enable_skottie=true         # the SkiaSharp target depends on it; compiled in, not exposed
skia_enable_svg=false skia_enable_pdf=false
skia_use_dng_sdk=false skia_use_piex=false   # RAW codec sources aren't in the fork's DEPS
skia_use_partition_alloc=false   # avoids undefined raw_ptr symbols in static builds
skia_use_system_{expat,freetype2,libjpeg_turbo,libpng,libwebp,zlib}=false
is_static_skiasharp=true
extra_cflags=["-fPIC","-ffunction-sections","-fdata-sections","-DHAVE_SYSCALL_GETRANDOM","-DXML_DEV_URANDOM"]
```

- **Ganesh stays compiled in.** The fork's `gr_context.cpp` and the Ganesh functions in `sk_surface.cpp` aren't guarded by `#if`. Turning Ganesh off would need patching the fork; leaving it on costs only binary size. We expose no `gr_*` function to Swift. This matches SkiaSharp's own Graphite Linux build.
- **Use libstdc++, not libc++.** SkiaSharp builds with `-stdlib=libc++`; we drop that flag. Swift on Linux already links libstdc++, and the toolchain ships no static libc++.
- **Build environment.** The `swift:6.4-jammy` container, using the clang that ships with Swift. Ubuntu 22.04 sets the glibc/libstdc++ baseline. Without Dawn, the checkout and build should fit on a standard GitHub runner.

**Output.** One `libSkiaSharp.a` plus the C headers (`include/c`, `include/xamarin`). Skia's C++ headers are not shipped. CI links and runs `native/smoke.c` against it: a raster draw and PNG encode, plus a reference to the Graphite/Vulkan entry point.

## 2. Artifact bundle

The CI layout follows [adobe/swan](https://github.com/adobe/swan), except that each target gets **its own bundle**, and one `.artifactbundleindex` lists them all by triple. SwiftPM downloads only the zip for the triple it's building for.

```
skia.artifactbundleindex           { "archives": [ { fileName, checksum, supportedTriples }, … ] }
skia-linux-x86_64.artifactbundle.zip
skia-linux-arm64.artifactbundle.zip   (later)

skia-linux-x86_64.artifactbundle/
  info.json
  linux-x86_64/
    libSkiaSharp.a
    headers/include/c/*.h          the headers include each other as "include/c/…",
    headers/include/xamarin/*.h    so headers/ is the search path
  skia_version.json                { "mono_skia_commit": "...", "version": "skia-<sha12>" }
```

```json
{
  "schemaVersion": "1.0",
  "artifacts": {
    "SkiaSharp": {
      "version": "skia-<sha12>",
      "type": "staticLibrary",
      "variants": [{
        "path": "linux-x86_64/libSkiaSharp.a",
        "staticLibraryMetadata": { "headerPaths": ["linux-x86_64/headers"] },
        "supportedTriples": ["x86_64-unknown-linux-gnu"]
      }]
    }
  }
}
```

- **Workflows:**
  - `.github/workflows/skia.yaml` is reusable, and also runs on changes to `native/`. Each matrix job (`platform`, `container`, `target`, `arch`) runs `native/build.sh <target> <arch>`, smoke-tests the result, and bundles its own zip with `native/bundle.py bundle`. An `index` job then writes `skia.artifactbundleindex` from each job's `*.entry.json`.
  - `skia-release.yaml` (manual) calls it and publishes everything as release `skia-<sha12>`.
  - Adding a platform means one matrix entry plus one `case` in `build.sh`.
- The package points at the index URL; its checksum is the index file's sha256.
- `SWIFT_SKIA_LOCAL_BUNDLE=/path/to/skia-<target>.artifactbundle` overrides the URL for testing a CI build artifact locally.
- Verified locally, using `bundle.py` output with the real SkiaSharp headers and a stand-in `.a`: SwiftPM picks up the bundle, Swift imports all the core and Graphite/Vulkan C headers in plain C mode with no warnings, and the linker searches the bundled library.

```swift
// Package.swift (sketch)
let skiaLib: Target = if let path = env["SWIFT_SKIA_LOCAL_BUNDLE"] {
  .binaryTarget(name: "SkiaLib", path: path)
} else {
  .binaryTarget(name: "SkiaLib", url: "https://github.com/<owner>/swift-skia/releases/download/skia-<sha12>/skia.artifactbundleindex", checksum: "…")
}

targets: [
  skiaLib,
  .target(name: "CSkia", dependencies: ["SkiaLib"],
          linkerSettings: [.linkedLibrary("stdc++"), .linkedLibrary("m"),
                           .linkedLibrary("dl"), .linkedLibrary("pthread")]),
  .target(name: "Skia", dependencies: ["CSkia"]),
  .testTarget(name: "SkiaTests", dependencies: ["Skia"]),
]
```

## 3. CSkia: making SkiaSharp's C API look like Swift

We never edit the SkiaSharp headers. Everything is layered on top:

- **`module.modulemap`** exposes one header, `CSkia.h`.
- **`CSkia.h`** (generated) includes the allow-listed `include/c/sk_*.h` headers: core, `sk_graphite.h` and `sk_graphite_vulkan.h`. It excludes `gr_*`, Metal, Dawn, Skottie, `sksg`, `skresources`, SVG and document. It also redeclares thread-safe ref-counted tags as `Sendable`:
  `struct __attribute__((swift_attr("@Sendable"))) sk_image_t;`
- **`CSkia.apinotes`** (generated) supplies names, nullability and ownership.

Verified on Swift 6.4 in plain C mode (no C++ interop):

| Mechanism | Result |
|---|---|
| `SwiftImportAs: reference` + `SwiftRetainOp: sk_x_ref` / `SwiftReleaseOp: sk_x_unref` | The C opaque type imports as a Swift class; ARC calls ref/unref |
| `SwiftName: SKImage.fromEncoded(_:)`, `SKImage.makeShader(self:_:_:_:_:)`, `getter:`/`setter:` | C functions become static factories, methods and properties |
| `NullabilityOfRet` / `Nullability` in apinotes | Non-optional results without touching the headers |
| Tag redeclaration with `swift_attr("@Sendable")` | The type conforms to `Sendable` |
| `SwiftRetainOp: immortal` | Borrowed pointers import as classes without retain/release |

**What apinotes can't do** (measured on the 837 functions in the v1 headers; enum and struct-pointer cases tested):

| C pattern | Count | Without help, Swift sees | Fix (generated Swift) |
|---|---|---|---|
| Struct input passed by pointer (`const sk_rect_t*`) | 167 | `UnsafePointer<Rect>`; callers must write `var r = …; f(&r)` | Overload taking `Rect` by value |
| Out-parameter (`void f(x, sk_matrix_t* out)`) | 56 | Caller passes `&out` | Return the value, or make it a property |
| Pointer plus count | 51 | Pointer and `Int32` arguments | Take a `Span` or `Array` |
| `sk_string_t*` out | 15 | Raw string object | Return `String` |
| Callback plus context | 13 | `@convention(c)` function plus raw pointer | Closure-based wrapper |

**Enums work through apinotes.** SkiaSharp's anonymous `typedef enum { … } sk_x_t` imports as a real Swift enum when the tag gets `EnumExtensibility` (plus `Enumerators: SwiftName` for case names). With `FlagEnum: true` it becomes an `OptionSet`. Tested: `switch` works, and `[.a, .b]` passes `3`. Use `EnumExtensibility: open` by default: a `closed` enum is undefined behavior if C returns a value missing from the header, which can happen when the fork adds cases.

About 548 functions (65%) need nothing beyond apinotes. Some SkiaSharp functions take inputs through non-const pointers (for example `sk_bitmap_erase_rect`), so whether a pointer is an output can't be inferred reliably. The overrides file decides those cases.

## 4. Swift API: how each kind of type maps

The SkiaSharp C API has about 20 **ref-counted** types (they have `_ref`/`_unref`) and about 35 **owned** types (they have `_new`/`_delete`).

| Kind | Types (v1) | How it's exposed | Work |
|---|---|---|---|
| Ref-counted | Image, Shader, Surface, Typeface, Data, ColorSpace, ColorFilter, ImageFilter, MaskFilter, PathEffect, Blender, Picture, TextBlob, Vertices, RuntimeEffect, FontMgr | Swift classes straight from apinotes | **generated** |
| Simple data structs and enums | `sk_rect_t`, `sk_point_t`, `sk_matrix_t`, `sk_color4f_t`, `sk_imageinfo_t`, enums | Renamed via apinotes (`Rect`, `Point`, …); small Swift extensions add initializers and operators | generated, plus a few small extensions |
| Owned and passed to other calls | Paint, Path, PathBuilder, Font, FontStyle | `final class` that wraps the pointer, with `deinit` calling `_delete`, properties for get/set pairs, and one-line forwarding methods. Reference semantics like the C API; `copy()` via `sk_*_clone` | **hand-written** |
| Borrowed | Canvas (from a surface or picture recorder), iterators, byte views | `~Escapable` views whose lifetime depends on their owner; see **Lifetimes** below | **hand-written** |
| Graphite | Context, Recorder, Recording, BackendTexture, TextureInfo | Unique owners, as in rust-skia: `~Copyable` structs whose `deinit` deletes the handle. `insert` borrows the recording, which can be inserted again | **hand-written** |

Paint, Path, Font and Canvas are hand-written for one reason: the C functions that use them take raw `sk_paint_t*` and similar pointers. Apinotes can't put a method that takes our wrapper type onto Canvas, and owned types can't be imported as ref-counted classes. These five types are most of the hand-written Swift in v1.

**Generator rule:** a C function becomes public API through apinotes only if its shape is already fine. Otherwise it's marked `SwiftPrivate` (so it imports as `__sk_…`), and either a generated Swift overload or the hand-written layer calls it. Functions that take an owned type (Paint, Path, Font) always go through a wrapper.

**API style:**
- Types keep SkiaSharp's `SK` prefix.
- Skia's own API has no argument labels: methods and factories take `_:` throughout, so constructor variants are unlabeled static factories (`SKImage.fromEncoded(_:)`, `SKSurface.raster(_:_:_:)`). Only overloads we add have labels.
- Accessors are properties, never `getX()`/`setX(_:)` methods.
- No copy-on-write: owned types have reference semantics, as in the C API.

**Later, not v1:** generating the forwarding wrappers from `swift-synthesize-interface` output.

### Lifetimes: follow rust-skia

rust-skia has already decided which Skia objects depend on which (`ref/rust-skia/skia-safe`). We use the same dependencies, expressed with Swift 6.4's `~Escapable` + `@_lifetime`:

| rust-skia | Used for | Swift |
|---|---|---|
| `fn canvas(&mut self) -> &Canvas` | `Surface::canvas`, `PictureRecorder::begin_recording`, `Document::canvas`, Graphite `Recorder::make_deferred_canvas` | `var canvas: SKCanvas { @_lifetime(&self) mutating get }`, the same shape as the standard library's `Array.mutableSpan`. `SKCanvas` is `~Copyable` and `~Escapable` and never deletes the canvas. The owner must be a `var`, like Rust's `let mut` |
| `fn as_bytes(&self) -> &[u8]` | `Data::as_bytes` | `SKData.span: Span<UInt8>` with `@_lifetime(borrow self)` |
| `Pixmap<'a>` from `peek_pixels` | `Image::peek_pixels(&self)`, `Surface::peek_pixels(&mut self)` | `SKPixmap` (`~Copyable`, `~Escapable`, frees its C handle in `deinit`): `image.peekPixels()` with `@_lifetime(borrow self)`, `surface.peekPixels()` with `@_lifetime(&self)`; `pixmap.bytes: RawSpan` |
| `Iter<'a>` with `PhantomData<&'a Path>` | path, region and text blob iterators | `~Escapable` iterator struct with `@_lifetime(borrow path)` |
| `BorrowedRecorder<'a>` | `Canvas::recorder()` | `~Escapable` recorder view tied to the canvas, which doesn't delete the recorder |
| `RefHandle<T>` (unique owner, no `Clone`) | Graphite `Context`, `Recorder`, `Recording` | `~Copyable` struct with `deinit` |
| `Handle<T>` (value with `Clone`) | `Paint`, `Path`, `Font` | `final class` with `copy()`; reference semantics, no copy-on-write |
| `RCHandle<T>` | `Image`, `Shader`, `Surface`, … | generated ARC class |
| `OwnedCanvas<'pixels>`, `Borrows<'pixels, Surface>` | canvases and surfaces over caller-owned pixels | later |

Graphite surfaces are plain `SKSurface`s with no dependency on their recorder, matching rust-skia's `graphite::surface::render_target(&mut Recorder, …) -> Option<Surface>`.

How the `&mut self` case works in Swift 6.4 (tested):
- **Exclusivity:** while the canvas is alive, any other use of the surface variable is a compile error (`overlapping accesses … requires exclusive access`). The access ends at the canvas's last use, as with Rust's non-lexical lifetimes.
- **Why `~Copyable`:** a *copyable* `~Escapable` view keeps the access open until the end of its lexical scope, rejecting code after its last use. `~Copyable` gives last-use behavior, which is also why the standard library's `MutableSpan` is `~Copyable`.
- **Classes:** classes can't declare `mutating` accessors, so `SKSurface` (an imported reference type) gets `canvas` from a protocol extension constrained to `Self == SKSurface`, which may declare one. As with Rust's `&mut` on a cloneable `RCHandle`, exclusivity covers the variable, not the object: another reference to the same surface can still be used.
- **Escaping:** returning a view out of the function is a compile error.
- **Swift 6.4 status:** `@_lifetime` is still experimental (`Lifetimes` feature, proposal under review as swift-evolution PR #3145). SE-0507's `borrow`/`mutate` accessors don't fit here: they must return stored storage and aren't allowed on classes.

### Graphite on Vulkan: the device is passed in

```swift
import Skia

let ctx = try SKGraphiteContext.vulkan(.init(
  instance: vkInstance, physicalDevice: vkPhysicalDevice, device: vkDevice,
  queue: vkQueue, graphicsQueueIndex: queueFamily, maxAPIVersion: apiVersion,
  getProc: vkGetInstanceProcAddr))           // -> sk_graphite_context_make_vulkan

let recorder = ctx.makeRecorder()
let surface = try SKSurface.renderTarget(recorder, info, false, nil)
// or: SKSurface.wrap(recorder, backendTexture, …)
let canvas = surface.canvas           // ~Escapable: can't outlive `surface`
canvas.clear(.white)
canvas.drawCircle(400, 300, 100, paint)
if let recording = recorder.snap() { ctx.insert(recording) }   // borrows; can be inserted again
ctx.submit()
```

Our layer translates the caller's `vkGetInstanceProcAddr` into SkiaSharp's `sk_graphite_vk_get_proc(userData, name, instance, device)` with a `@convention(c)` function. Vulkan handles are passed as opaque pointers, so the package never depends on Vulkan headers.

## 5. Generator

`native/gen_apinotes.py`: a Python script, run by hand, with its output committed. Python because v1 only emits apinotes and a header (text from JSON), and `bundle.py` already requires Python. A Swift executable plus command plugin, like swan, would be about twice the code for the same output.

1. **Input:** `clang -Xclang -ast-dump=json -fsyntax-only` run over `CSkia.h` with the bundle's include path. We use the toolchain's clang, so there's no libclang dependency.
2. **Classify types:** a type with `X_ref`/`X_unref` is ref-counted; a type with `X_new`/`X_delete` is owned. `sk_refcnt_t` and `sk_nvrefcnt_t` are base types.
3. **Name things:** types and enum cases take SkiaSharp's names from its generated C# (`sk_colortype_t` → `SKColorType`, `RGBA_8888_SK_COLORTYPE` → `.rgba8888`), with an override table for the few it lacks. The first parameter becomes `self`. `sk_x_new_foo(...)` becomes the static factory `SKX.foo(_:...)`, and plain `sk_x_new(...)` becomes `init(_:...)`. `get_foo` becomes a property, settable when a matching `set_foo` exists, and `is_*`/`has_*` become `Bool` properties. No argument labels.
4. **Overrides:** `apinotes-overrides.yaml` fixes names, nullability (the headers have none, so a default plus exceptions) and functions to skip.
5. **Output (v1):** `CSkia.apinotes` and `CSkia.h`: ref-counted classes, enums and option sets, renames, nullability, and `SwiftPrivate` for wrapped functions.
6. **Later:** `Sources/Skia/Generated/*.swift` with overloads for the struct-pointer, out-parameter, array, string and callback patterns in §3. The raw functions stay callable until then.

A CI check regenerates both files and fails if they differ from what's committed. When the mono/skia pin changes, the diff shows exactly what changed in the API.

## 6. Repository layout

```
Package.swift
Sources/CSkia/         include/{module.modulemap, CSkia.h, CSkia.apinotes}, shim.c (empty)
Sources/Skia/          re-export, Paint/Path/PathBuilder/Font/Canvas, Graphite/, Generated/
native/                build.sh (per-target gn args + staging), merge_archives.py, bundle.py (info.json + zip), gen_apinotes.py, apinotes-overrides.yaml, smoke.c, skia.pin
.github/workflows/     skia.yaml (build + bundle + index), skia-release.yaml (publish), ci.yml (build + test against released bundle)
Tests/SkiaTests/       raster render tests; Graphite tests on lavapipe (Mesa software Vulkan)
```

## 7. Order of work

1. **Done:** `skia.yaml` builds mono/skia per target, runs the C smoke test, makes one bundle per target plus the index; `skia-release.yaml` publishes them.
2. **Done:** `Package.swift` with the binaryTarget pointing at the release's `.artifactbundleindex`; raster tests and the `WriteImage` example.
3. The generator (`gen_apinotes.py`): apinotes and `CSkia.h`. Generated Swift overloads come after v1.
4. **Done:** the hand-written layer: `SKPaint`, `SKPath`, `SKPathBuilder`, `SKFont` (`final class`es), and `SKCanvas` (`~Copyable` + `~Escapable`, from `surface.canvas`).
5. **Done:** Graphite on Vulkan: `SKGraphiteContext.vulkan(_:_:)` on the caller's device, `SKGraphiteRecorder`/`SKGraphiteRecording` (`~Copyable`), `SKSurface.renderTarget(_:_:_:_:)`, and `readPixels` via async readback. Tested on a real GPU (RADV) and on llvmpipe; tests create the device through a test-only C target (`Tests/CVulkanTestSupport`). Caller-owned `VkImage`s wrap through `SKGraphiteBackendTexture` and `SKSurface.wrapBackendTexture(_:_:_:_:_:)`; `Examples/VulkanWindow` (a separate package needing SDL3) draws into a swapchain this way. The C API can't pass Graphite a final image layout or semaphores, so the example submits synchronously and moves the image from `COLOR_ATTACHMENT_OPTIMAL` to `PRESENT_SRC_KHR` itself; the validation layers report no errors with that.

## 8. Risks and open items

- **Third-party symbol clashes.** The bundled zlib, libpng, freetype, expat, libjpeg-turbo and libwebp are visible in `libSkiaSharp.a` and can clash with other copies in an app. Not handled in v1. The fix is an `ld -r` merge plus `objcopy --localize-symbol` for the third-party symbols.
- **No per-character font fallback on Linux.** Without fontconfig, Skia uses its directory font manager, whose `matchFamilyStyleCharacter` always returns nil. Text in scripts the chosen typeface lacks shows missing glyphs. Enabling fontconfig, or a fallback list chosen in Swift, would fix it.
- **Fork lag.** We depend on mono/skia keeping up with upstream Skia. Today it's current.
- **Nullability defaults.** A wrong "non-null" assumption crashes at runtime rather than failing at compile time. Default to non-null only for results of `_new`/`_make` functions; annotate the rest explicitly.
- **Canvas escaping through raw pointers.** The `~Escapable` canvas covers the Swift API; the raw `__sk_canvas_*` functions remain unsafe by design.
- **Lifetime annotations are still experimental.** `@_lifetime` needs `.enableExperimentalFeature("Lifetimes")` on the `Skia` target. That's tested on 6.4: client targets need no flag. The underscored spelling may change in a later Swift, but only our own sources would need updating.
- **libstdc++ build.** SkiaSharp builds with libc++; we build with libstdc++. The workflow links the whole archive with `--no-undefined` to catch any symbol this leaves unresolved.
