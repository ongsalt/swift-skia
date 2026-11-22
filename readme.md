# swift-skia
Skia bindings for swift.

## Installation
```swift
.package(url: "https://github.com/ongsalt/swift-skia", branch: "main"),
```

```swift
.product(name: "Skia", package: "swift-skia"),
```

## Supported platform
- windows: x86_64
- linux: x86_64
- android: arm64, x86_64

## How it's made
- Skia is [SkiaSharp](https://github.com/mono/SkiaSharp)'s fork, prebuilt in CI and downloaded by SwiftPM.
- `CSkia.apinotes`, `CSkia.h` and `Sources/Skia/Generated/` are generated from SkiaSharp's C API by `native/gen_apinotes.py`.
- The rest is manually-written (ai): the Swift wrappers in `Sources/Skia`, and C shims over Skia's C++ API in `Sources/CSkia/swsk_*`.

## Development

### Bumping SkiaSharp
Update `native/skiasharp.pin` and `native/skia.pin` (its `externals/skia`), run `native/gen_apinotes.py`,
check `native/coverage.py`, then run the Release Skia workflow and update `Package.swift`.

### Editor setup

If SourceKit-LSP reports `No such module 'Skia'`, switch it to Swift Build by adding
`.sourcekit-lsp/config.json` (or `~/.sourcekit-lsp/config.json`) and restarting the language server:

```json
{ "swiftPM": { "buildSystem": "swiftbuild" } }
```

The default native build system can't index modules that depend on static-library artifact bundles.

## Acknowledgement
- `SkiaSharp` for c binding
- `skia-safe` for ownership model
- adobe `swan` for packaging
- `SkiaKit` for some api naming
