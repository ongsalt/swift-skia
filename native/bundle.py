#!/usr/bin/env python3
"""Packages build.py output as SwiftPM (SE-0482) static-library artifact bundles.

One bundle per target; an .artifactbundleindex points SwiftPM at the right one
by triple.

usage:
  bundle.py bundle <builds/name> --version <v> --dist dist
      -> dist/skia-<name>.artifactbundle.zip
         dist/skia-<name>.entry.json        (this zip's line in the index)
  bundle.py index --dist dist
      -> dist/skia.artifactbundleindex      (from every dist/*.entry.json)
         dist/skia.artifactbundleindex.sha256
"""
import argparse
import hashlib
import json
import pathlib
import shutil
import zipfile


def sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def bundle(stage: pathlib.Path, version: str, dist: pathlib.Path) -> None:
    manifest = json.loads((stage / "manifest.json").read_text())
    name = f"skia-{manifest['name']}.artifactbundle"
    root = dist / name
    if root.exists():
        shutil.rmtree(root)
    root.mkdir(parents=True)

    variant = root / manifest["name"]
    variant.mkdir()
    shutil.copy2(stage / manifest["library"], variant / manifest["library"])
    # The headers include each other as "include/c/...", so the search path is
    # the directory containing include/.
    shutil.copytree(stage / "include", variant / "headers" / "include")

    info = {
        "schemaVersion": "1.0",
        "artifacts": {
            "SkiaSharp": {
                "version": version,
                "type": "staticLibrary",
                "variants": [{
                    "path": f"{manifest['name']}/{manifest['library']}",
                    "staticLibraryMetadata": {"headerPaths": [f"{manifest['name']}/headers"]},
                    "supportedTriples": manifest["supportedTriples"],
                }],
            }
        },
    }
    (root / "info.json").write_text(json.dumps(info, indent=2) + "\n")
    (root / "skia_version.json").write_text(
        json.dumps({"version": version, "mono_skia_commit": manifest["skiaCommit"]}, indent=2) + "\n")

    zip_path = dist / f"{name}.zip"
    zip_path.unlink(missing_ok=True)
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
        for f in sorted(root.rglob("*")):
            z.write(f, f.relative_to(dist))
    shutil.rmtree(root)

    entry = {"fileName": zip_path.name, "checksum": sha256(zip_path),
             "supportedTriples": manifest["supportedTriples"]}
    (dist / f"skia-{manifest['name']}.entry.json").write_text(json.dumps(entry, indent=2) + "\n")
    print(f"{zip_path} {zip_path.stat().st_size >> 20} MiB sha256={entry['checksum']}")


def index(dist: pathlib.Path) -> None:
    entries = [json.loads(p.read_text()) for p in sorted(dist.glob("*.entry.json"))]
    if not entries:
        raise SystemExit(f"no *.entry.json in {dist}")
    path = dist / "skia.artifactbundleindex"
    path.write_text(json.dumps({"schemaVersion": "1.0", "archives": entries}, indent=2) + "\n")
    digest = sha256(path)
    pathlib.Path(f"{path}.sha256").write_text(digest + "\n")
    print(f"{path} ({len(entries)} archives) sha256={digest}")


def main() -> None:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("bundle")
    b.add_argument("stage", type=pathlib.Path)
    b.add_argument("--version", required=True)
    b.add_argument("--dist", required=True, type=pathlib.Path)
    i = sub.add_parser("index")
    i.add_argument("--dist", required=True, type=pathlib.Path)
    args = ap.parse_args()

    if args.cmd == "bundle":
        bundle(args.stage, args.version, args.dist)
    else:
        index(args.dist)


if __name__ == "__main__":
    main()
