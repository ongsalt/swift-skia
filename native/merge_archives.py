#!/usr/bin/env python3
"""Merges static archives into one, dropping duplicate objects.

GN's complete_static_lib only folds source_set deps into libSkiaSharp.a; objects
of static_library deps (libskia.a, skcms, ...) stay in their own archives. Those
archives also repeat source_set objects (core.*), so members are deduplicated by
content hash. Not by name: two sources in one target can share a basename.

Reads GNU ar archives and MSVC/COFF .lib files (same container; COFF stores
member paths and NUL-terminates long names). Writes with `ar`, or `llvm-lib`
when the output ends in .lib. --exclude matches a member's file name.

usage: merge_archives.py <output.a|.lib> <input>... [--exclude <member.o>]...
       (native/build.py imports merge() instead)
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
        if name in ("/", "/SYM64/") or name.startswith("/<"):  # symbol tables, rebuilt
            continue
        if name == "//":                       # long-name table
            long_names = body
            continue
        if name.startswith("/"):               # "/<offset>" into long-name table
            offset = int(name[1:])
            end = offset                       # GNU ends names with "/\n", COFF with NUL
            while end < len(long_names) and long_names[end] not in b"\0\n":
                end += 1
            name = long_names[offset:end].decode()
        # COFF members are paths ("obj/src/core/core.SkCanvas.obj").
        name = name.rstrip("/").replace("\\", "/").rsplit("/", 1)[-1]
        yield name, body


def merge(out: pathlib.Path, inputs: list[pathlib.Path], exclude: set[str]) -> None:
    seen: set[str] = set()
    with tempfile.TemporaryDirectory() as tmp:
        files = []
        for archive in inputs:
            for name, body in members(archive):
                if name in exclude:
                    continue
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
        if out.suffix == ".lib":
            cmd = ["llvm-lib", "/nologo", f"/out:{out.resolve()}", f"@{rsp.name}"]
        else:
            cmd = ["ar", "rcs", out.resolve(), f"@{rsp.name}"]
        subprocess.run(cmd, cwd=tmp, check=True)
    print(f"{out}: {len(files)} objects from {len(inputs)} archives")


def main() -> None:
    args, exclude = sys.argv[1:], set()
    while "--exclude" in args:
        i = args.index("--exclude")
        exclude.add(args[i + 1])
        del args[i:i + 2]
    merge(pathlib.Path(args[0]), [pathlib.Path(p) for p in args[1:]], exclude)


if __name__ == "__main__":
    main()
