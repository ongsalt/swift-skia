#!/usr/bin/env bash
# Builds mono/skia (SkiaSharp's Skia fork, which carries the C API) as one static
# libSkiaSharp.a for x86_64 Linux. Meant to run in CI inside swift:6.4-jammy.
#
# env:
#   SKIA_SRC  checkout directory  (default: ./skia-src)
#   SKIA_OUT  GN output directory (default: ./out/linux-x64)
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(realpath -m "${SKIA_SRC:-skia-src}")
OUT=$(realpath -m "${SKIA_OUT:-out/linux-x64}")
PIN=$(tr -d '[:space:]' < "$HERE/skia.pin")

# --- source ---------------------------------------------------------------
if [ ! -d "$SRC/.git" ] || [ "$(git -C "$SRC" rev-parse HEAD)" != "$PIN" ]; then
  rm -rf "$SRC"
  git init -q "$SRC"
  git -C "$SRC" fetch -q --depth 1 https://github.com/mono/skia "$PIN"
  git -C "$SRC" checkout -q FETCH_HEAD
fi

# The fork's DEPS is already trimmed (no Dawn/ANGLE/V8); shallow clones by default.
(cd "$SRC" && python3 tools/git-sync-deps)
(cd "$SRC" && python3 bin/fetch-gn)

# --- configure --------------------------------------------------------------
# Based on SkiaSharp's native/linux build.cake ("nodeps" variant), but:
#   - static (is_static_skiasharp) instead of a .so
#   - libstdc++ instead of -stdlib=libc++, because Swift on Linux links libstdc++
#   - RAW codec off (its dng_sdk/piex sources aren't in the fork's DEPS)
ARGS=(
  'target_os="linux"'
  'target_cpu="x64"'
  'cc="clang"'
  'cxx="clang++"'
  'is_official_build=true'
  'is_debug=false'
  'is_component_build=false'
  'is_static_skiasharp=true'

  'skia_enable_ganesh=true'
  'skia_enable_graphite=true'
  'skia_use_vulkan=true'
  'skia_use_gl=false'
  'skia_use_dawn=false'

  'skia_enable_skottie=true'
  'skia_enable_pdf=false'
  'skia_enable_svg=false'
  'skia_enable_tools=false'

  'skia_use_icu=false'
  'skia_use_harfbuzz=false'
  'skia_use_fontconfig=false'
  'skia_enable_fontmgr_custom_directory=true'

  'skia_use_dng_sdk=false'
  'skia_use_piex=false'
  'skia_use_partition_alloc=false'
  'skia_use_perfetto=false'

  'skia_use_system_expat=false'
  'skia_use_system_freetype2=false'
  'skia_use_system_libjpeg_turbo=false'
  'skia_use_system_libpng=false'
  'skia_use_system_libwebp=false'
  'skia_use_system_zlib=false'

  'extra_cflags=["-fPIC", "-ffunction-sections", "-fdata-sections", "-DHAVE_SYSCALL_GETRANDOM", "-DXML_DEV_URANDOM"]'
)

mkdir -p "$OUT"
(cd "$SRC" && bin/gn gen "$OUT" --args="${ARGS[*]}")

# --- build ----------------------------------------------------------------
ninja -C "$OUT" SkiaSharp
ls -lh "$OUT/libSkiaSharp.a"
