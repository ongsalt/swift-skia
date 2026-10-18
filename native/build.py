#!/usr/bin/env python3
"""Builds mono/skia (SkiaSharp's Skia fork, which carries the C API) as one static
library and stages it for native/bundle.py.

usage: native/build.py <target> <arch>       e.g. native/build.py linux x86_64
env:
  SKIA_SRC   checkout directory         (default: ./skia-src)
  BUILDS     staging root               (default: ./builds)
  CLANG_WIN  LLVM install, Windows only (default: C:/Program Files/LLVM)
output: $BUILDS/<target>-<arch>/{libSkiaSharp.a or SkiaSharp.lib, include/, manifest.json}

Needs git, ninja and clang on PATH. On Windows also Visual Studio (C++ tools +
Windows SDK), which GN finds itself, and a `python3` on PATH for GN's scripts.
"""
import json
import os
import pathlib
import shutil
import subprocess
import sys

import merge_archives

HERE = pathlib.Path(__file__).resolve().parent

# --- target -------------------------------------------------------------------
# Everything that differs per platform lives here.
TRIPLES = {
    "linux-x86_64": "x86_64-unknown-linux-gnu",
    "linux-arm64": "aarch64-unknown-linux-gnu",
    "windows-x86_64": "x86_64-unknown-windows-msvc",
    "windows-arm64": "aarch64-unknown-windows-msvc",
}
CPUS = {"x86_64": "x64", "arm64": "arm64"}


def target_config(target: str) -> tuple[str, str, list[str]]:
    """(library file name, object suffix, GN args) for a target OS."""
    if target == "linux":
        # SkiaSharp's native/linux build.cake ("nodeps" variant), but libstdc++
        # instead of -stdlib=libc++, because Swift on Linux links libstdc++.
        return "libSkiaSharp.a", "o", [
            'target_os="linux"',
            'cc="clang"',
            'cxx="clang++"',
            "skia_use_fontconfig=false",
            "skia_enable_fontmgr_custom_directory=true",
            'extra_cflags=["-fPIC", "-ffunction-sections", "-fdata-sections", '
            '"-DHAVE_SYSCALL_GETRANDOM", "-DXML_DEV_URANDOM"]',
        ]
    if target == "windows":
        # SkiaSharp's native/windows build.cake (clang-cl, DirectWrite fonts, no
        # GDI font manager, no Direct3D), but:
        #   - /MD (dynamic CRT) instead of /MT, because Swift on Windows links the
        #     dynamic CRT and the MSVC STL refuses to mix the two
        #   - SK_C_API empty instead of SKIA_C_DLL's __declspec(dllexport), so
        #     executables linking the static library don't export the C API
        clang_win = os.environ.get("CLANG_WIN", "C:/Program Files/LLVM").replace("\\", "/")
        return "SkiaSharp.lib", "obj", [
            'target_os="win"',
            f'clang_win="{clang_win}"',
            "skia_enable_fontmgr_win=true",
            "skia_enable_fontmgr_win_gdi=false",
            'extra_cflags=["/MD", "-DSK_C_API="]',
        ]
    sys.exit(f"unsupported target: {target}")


# Shared by every target. Differences from SkiaSharp:
#   - static (is_static_skiasharp) instead of a shared library
#   - RAW codec off (its dng_sdk/piex sources aren't in the fork's DEPS)
COMMON_ARGS = [
    "is_official_build=true",
    "is_debug=false",
    "is_component_build=false",
    "is_static_skiasharp=true",

    "skia_enable_ganesh=true",
    "skia_enable_graphite=true",
    "skia_use_vulkan=true",
    "skia_use_gl=false",
    "skia_use_dawn=false",

    "skia_enable_skottie=true",
    "skia_enable_pdf=false",
    "skia_enable_svg=false",
    "skia_enable_tools=false",

    "skia_use_icu=false",
    "skia_use_harfbuzz=false",

    "skia_use_dng_sdk=false",
    "skia_use_piex=false",
    "skia_use_partition_alloc=false",
    "skia_use_perfetto=false",

    "skia_use_system_expat=false",
    "skia_use_system_freetype2=false",
    "skia_use_system_libjpeg_turbo=false",
    "skia_use_system_libpng=false",
    "skia_use_system_libwebp=false",
    "skia_use_system_zlib=false",
]


def run(*cmd, cwd=None) -> None:
    print("+", " ".join(str(c) for c in cmd), flush=True)
    subprocess.run([str(c) for c in cmd], cwd=cwd, check=True)


def checkout(src: pathlib.Path, pin: str) -> None:
    head = None
    if (src / ".git").is_dir():
        head = subprocess.run(["git", "-C", src, "rev-parse", "HEAD"],
                              capture_output=True, text=True).stdout.strip()
    if head != pin:
        shutil.rmtree(src, ignore_errors=True)
        run("git", "init", "-q", src)
        run("git", "-C", src, "fetch", "-q", "--depth", "1", "https://github.com/mono/skia", pin)
        run("git", "-C", src, "checkout", "-q", "FETCH_HEAD")
    # The fork's DEPS is already trimmed (no Dawn/ANGLE/V8); shallow clones by default.
    run(sys.executable, "tools/git-sync-deps", cwd=src)
    run(sys.executable, "bin/fetch-gn", cwd=src)


def main() -> None:
    if len(sys.argv) != 3:
        sys.exit("usage: build.py <target> <arch>")
    target, arch = sys.argv[1:]
    name = f"{target}-{arch}"
    if name not in TRIPLES:
        sys.exit(f"unsupported target: {name}")
    src = pathlib.Path(os.environ.get("SKIA_SRC", "skia-src")).resolve()
    stage = pathlib.Path(os.environ.get("BUILDS", "builds")).resolve() / name
    out = pathlib.Path("out", name).resolve()
    pin = (HERE / "skia.pin").read_text().strip()
    lib, obj, target_args = target_config(target)

    checkout(src, pin)

    # --- configure ------------------------------------------------------------
    args = target_args + [f'target_cpu="{CPUS[arch]}"'] + COMMON_ARGS
    out.mkdir(parents=True, exist_ok=True)
    gn = src / "bin" / ("gn.exe" if os.name == "nt" else "gn")
    run(gn, "gen", out.as_posix(), f"--args={' '.join(args)}", cwd=src)

    # --- build ----------------------------------------------------------------
    run("ninja", "-C", out, "SkiaSharp")

    # --- stage ----------------------------------------------------------------
    shutil.rmtree(stage, ignore_errors=True)
    stage.mkdir(parents=True)

    # complete_static_lib doesn't fold static_library deps (libskia.a, skcms, ...)
    # into libSkiaSharp.a, so merge every archive the build produced.
    # Excluded:
    #   gr_context.o   SkiaSharp's Ganesh C API; it references the GL backend,
    #                  which we don't build, and the Swift side hides gr_* anyway.
    #   SkiaKeeper.o   references C API functions so a shared library keeps them;
    #                  meaningless for a static library, and it pulls in gr_*.
    #                  (Its object is prefixed "libSkiaSharp." on Linux,
    #                  "SkiaSharp." on Windows.)
    archives = sorted(out.glob(f"*{pathlib.Path(lib).suffix}"))
    merge_archives.merge(stage / lib, archives, exclude={
        f"core.gr_context.{obj}",
        f"libSkiaSharp.SkiaKeeper.{obj}",
        f"SkiaSharp.SkiaKeeper.{obj}",
    })

    # The headers include each other as "include/c/...", so stage include/ itself.
    keep = ("sk_", "gr_", "skottie_", "sksg_", "skresources_")
    for d in ("c", "xamarin"):
        for h in (src / "include" / d).rglob("*.h"):
            if h.name.startswith(keep):
                dest = stage / "include" / h.relative_to(src / "include")
                dest.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(h, dest)

    manifest = {
        "name": name,
        "platform": target,
        "library": lib,
        "supportedTriples": [TRIPLES[name]],
        "skiaCommit": pin,
    }
    (stage / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"{stage / lib}: {(stage / lib).stat().st_size >> 20} MiB")


if __name__ == "__main__":
    main()
