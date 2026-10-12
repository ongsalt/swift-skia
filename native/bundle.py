#!/usr/bin/env python3
"""Packages libSkiaSharp.a + the C API headers as a SwiftPM (SE-0482) artifact bundle.

usage: bundle.py --lib <out>/libSkiaSharp.a --skia-src <skia-src> --version <v> --dist dist

Produces:
  dist/skia-linux.artifactbundle.zip
  dist/skia-linux.artifactbundle.zip.sha256   (what `swift package compute-checksum` prints)
"""
import argparse
import hashlib
import json
import pathlib
import shutil
import subprocess
import zipfile

BUNDLE = "skia-linux.artifactbundle"
VARIANT = "x86_64-linux"
TRIPLES = ["x86_64-unknown-linux-gnu"]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--lib", required=True, type=pathlib.Path)
    ap.add_argument("--skia-src", required=True, type=pathlib.Path)
    ap.add_argument("--version", required=True)
    ap.add_argument("--dist", required=True, type=pathlib.Path)
    args = ap.parse_args()

    root = args.dist / BUNDLE
    if root.exists():
        shutil.rmtree(root)
    variant = root / VARIANT
    variant.mkdir(parents=True)

    shutil.copy2(args.lib, variant / "libSkiaSharp.a")

    # The headers include each other as "include/c/...", so the header search
    # path must be the directory that contains include/.
    headers = variant / "headers"
    for sub in ("include/c", "include/xamarin"):
        shutil.copytree(args.skia_src / sub, headers / sub, ignore=shutil.ignore_patterns("*.cpp", "Sk*.h"))

    commit = subprocess.check_output(["git", "-C", str(args.skia_src), "rev-parse", "HEAD"], text=True).strip()
    (root / "skia_version.json").write_text(json.dumps({"mono_skia_commit": commit, "version": args.version}, indent=2) + "\n")

    info = {
        "schemaVersion": "1.0",
        "artifacts": {
            "SkiaSharp": {
                "version": args.version,
                "type": "staticLibrary",
                "variants": [{
                    "path": f"{VARIANT}/libSkiaSharp.a",
                    "staticLibraryMetadata": {"headerPaths": [f"{VARIANT}/headers"]},
                    "supportedTriples": TRIPLES,
                }],
            }
        },
    }
    (root / "info.json").write_text(json.dumps(info, indent=2) + "\n")

    zip_path = args.dist / f"{BUNDLE}.zip"
    zip_path.unlink(missing_ok=True)
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
        for f in sorted(root.rglob("*")):
            z.write(f, f.relative_to(args.dist))

    digest = hashlib.sha256(zip_path.read_bytes()).hexdigest()
    pathlib.Path(f"{zip_path}.sha256").write_text(digest + "\n")
    print(f"{zip_path} {zip_path.stat().st_size // (1 << 20)} MiB sha256={digest}")


if __name__ == "__main__":
    main()
