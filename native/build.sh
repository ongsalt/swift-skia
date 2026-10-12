#!/usr/bin/env bash
# Builds mono/skia (SkiaSharp's Skia fork, which carries the C API) as one static
# libSkiaSharp.a and stages it for native/bundle.py.
#
# usage: native/build.sh <target> <arch>       e.g. native/build.sh linux x86_64
# env:
#   SKIA_SRC  checkout directory        (default: ./skia-src)
#   BUILDS    staging root              (default: ./builds)
# output: $BUILDS/<target>-<arch>/{libSkiaSharp.a, include/, manifest.json}
set -euo pipefail

TARGET=${1:?usage: build.sh <target> <arch>}
ARCH=${2:?usage: build.sh <target> <arch>}
NAME="$TARGET-$ARCH"
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(realpath -m "${SKIA_SRC:-skia-src}")
STAGE=$(realpath -m "${BUILDS:-builds}/$NAME")
OUT=$(realpath -m "out/$NAME")
PIN=$(tr -d '[:space:]' < "$HERE/skia.pin")

# --- target -----------------------------------------------------------------
# Everything that differs per platform lives here.
case "$NAME" in
  linux-x86_64)
    PLATFORM=linux
    TRIPLES='["x86_64-unknown-linux-gnu"]'
    TARGET_ARGS=('target_os="linux"' 'target_cpu="x64"')
    ;;
  linux-arm64)
    PLATFORM=linux
    TRIPLES='["aarch64-unknown-linux-gnu"]'
    TARGET_ARGS=('target_os="linux"' 'target_cpu="arm64"')
    ;;
  *)
    echo "unsupported target: $NAME" >&2
    exit 1
    ;;
esac

# --- source -----------------------------------------------------------------
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
  "${TARGET_ARGS[@]}"
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

# --- build ------------------------------------------------------------------
ninja -C "$OUT" SkiaSharp

# --- stage ------------------------------------------------------------------
rm -rf "$STAGE"
mkdir -p "$STAGE"

# complete_static_lib doesn't fold static_library deps (libskia.a, skcms, ...)
# into libSkiaSharp.a, so merge every archive the build produced.
python3 "$HERE/merge_archives.py" "$STAGE/libSkiaSharp.a" "$OUT"/*.a

# The headers include each other as "include/c/...", so stage include/ itself.
mkdir -p "$STAGE/include"
cp -r "$SRC/include/c" "$SRC/include/xamarin" "$STAGE/include/"
find "$STAGE/include" -type f ! -name 'sk_*.h' ! -name 'gr_*.h' ! -name 'skottie_*.h' ! -name 'sksg_*.h' ! -name 'skresources_*.h' -delete

cat > "$STAGE/manifest.json" <<EOF
{
  "name": "$NAME",
  "platform": "$PLATFORM",
  "library": "libSkiaSharp.a",
  "supportedTriples": $TRIPLES,
  "skiaCommit": "$PIN"
}
EOF
ls -lh "$STAGE/libSkiaSharp.a"
