#!/usr/bin/env python3
"""Merges static archives into one, dropping duplicate objects.

GN's complete_static_lib only folds source_set deps into libSkiaSharp.a; objects
of static_library deps (libskia.a, skcms, ...) stay in their own archives. Those
archives also repeat source_set objects (core.*), so members are deduplicated by
content hash. Not by name: two sources in one target can share a basename.

usage: merge_archives.py <output.a> <input.a>...
"""
import hashlib
import pathlib
import subprocess
import sys
import tempfile


def members(path: pathlib.Path):
    data = path.read_bytes()
    if not data.startswith(b"!<arch>\n"):
        sys.exit(f"{path}: not a regular ar archive")
    pos, long_names = 8, b""
    while pos + 60 <= len(data):
        header = data[pos:pos + 60]
        name = header[:16].decode().rstrip()
        size = int(header[48:58].decode().strip())
        body = data[pos + 60:pos + 60 + size]
        pos += 60 + size + (size & 1)
        if name in ("/", "/SYM64/"):          # symbol table, rebuilt by ar
            continue
        if name == "//":                       # GNU long-name table
            long_names = body
            continue
        if name.startswith("/"):               # "/<offset>" into long-name table
            offset = int(name[1:])
            name = long_names[offset:long_names.index(b"/\n", offset)].decode()
        yield name.rstrip("/"), body


def main() -> None:
    out, inputs = pathlib.Path(sys.argv[1]), [pathlib.Path(p) for p in sys.argv[2:]]
    seen: set[str] = set()
    with tempfile.TemporaryDirectory() as tmp:
        files = []
        for archive in inputs:
            for name, body in members(archive):
                digest = hashlib.sha256(body).hexdigest()
                if digest in seen:
                    continue
                seen.add(digest)
                # Index prefix keeps same-named members from overwriting each other.
                obj = pathlib.Path(tmp) / f"{len(files):05d}.{name}"
                obj.write_bytes(body)
                files.append(obj.name)
        rsp = pathlib.Path(tmp) / "members.rsp"
        rsp.write_text("\n".join(files))
        out.parent.mkdir(parents=True, exist_ok=True)
        out.unlink(missing_ok=True)
        subprocess.run(["ar", "rcs", out.resolve(), f"@{rsp.name}"], cwd=tmp, check=True)
    print(f"{out}: {len(files)} objects from {len(inputs)} archives")


if __name__ == "__main__":
    main()
