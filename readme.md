# Editor setup

If SourceKit-LSP reports `No such module 'Skia'`, switch it to Swift Build by adding
`.sourcekit-lsp/config.json` (or `~/.sourcekit-lsp/config.json`) and restarting the language server:

```json
{ "swiftPM": { "buildSystem": "swiftbuild" } }
```

The default native build system can't index modules that depend on static-library artifact bundles.

# Acknowledgement
- `SkiaSharp` for c binding and skia build
- `skia-safe` for ownership model
- `dawn` for packaging
- `SkiaKit`
