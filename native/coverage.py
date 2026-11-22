#!/usr/bin/env python3
"""Reports which SkiaSharp C API functions Swift code can't reach.

Reads Sources/CSkia/include/CSkia.apinotes (run gen_apinotes.py first), the Swift sources in
Sources/Skia, and the C headers gen_apinotes.py caches at native/skia.pin. A function is
unreachable when it is
  - SwiftPrivate (`__sk_*`) and nothing in Sources/Skia calls it: a gap in the hand-written layer;
  - hidden only because it takes a Ganesh (`gr_*`) type, so raster callers can't pass null;
  - declared in a header gen_apinotes.py leaves out (EXCLUDED_HEADERS).
Ganesh functions and ref/unref are hidden on purpose and only counted.

usage: native/coverage.py [--all]     --all also lists the UNWRAPPED_ON_PURPOSE functions
"""
import argparse
import collections
import re

import gen_apinotes

ROOT = gen_apinotes.ROOT
HEADERS = gen_apinotes.CACHE / "skia-src" / "include" / "c"

# Private functions the hand-written layer covers another way, or that don't fit its model.
UNWRAPPED_ON_PURPOSE = {
    "sk_canvas_destroy": "SKCanvas is borrowed; its owner destroys it",
    "sk_font_measure_text_no_return": "measureText covers it",
    "sk_pathmeasure_new": "init(path) covers it; setPath resets",
    "sk_pixmap_get_writeable_addr_with_xy": "mutableBytes with rowBytes covers it",
    "sk_pixmap_reset_with_params": "would change which pixels the pixmap borrows; make a new pixmap",
    "sk_surface_draw": "draw(canvas, x, y, sampling, paint) covers it",
}

DECL = re.compile(r"SK_C_API\b[^;(]*?\b((?:sk|gr|skottie|sksg|skresources)_\w+)\s*\(")


def header_functions() -> dict[str, str]:
    """C function -> header file name."""
    if not HEADERS.is_dir():
        raise SystemExit(f"{HEADERS} missing: run native/gen_apinotes.py first")
    return {name: h.name for h in sorted(HEADERS.glob("*.h")) for name in DECL.findall(h.read_text())}


def function_notes() -> dict[str, str]:
    """C function -> its apinotes entry text."""
    notes = (ROOT / "Sources" / "CSkia" / "include" / "CSkia.apinotes").read_text()
    section = notes.split("\nFunctions:\n", 1)[1].split("\nEnumerators:\n", 1)[0]
    entries = {}
    for entry in re.split(r"\n(?=- Name: )", section):
        m = re.match(r"\s*- Name: (\w+)", entry)
        if m:
            entries[m.group(1)] = entry
    return entries


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--all", action="store_true", help="also list functions unwrapped on purpose")
    args = ap.parse_args()

    headers = header_functions()
    notes = function_notes()
    swift = "".join(p.read_text() for p in (ROOT / "Sources" / "Skia").rglob("*.swift"))
    called = set(re.findall(r"\b__((?:sk|gr)_\w+)\s*\(", swift))

    excluded = collections.defaultdict(list)
    gaps = collections.defaultdict(list)
    on_purpose = []
    gr_params = collections.defaultdict(list)
    intentional_hidden = 0
    for name, header in sorted(headers.items()):
        if header in gen_apinotes.EXCLUDED_HEADERS:
            excluded[header].append(name)
            continue
        note = notes.get(name, "")
        if "SwiftPrivate: true" in note and name not in called:
            if name in UNWRAPPED_ON_PURPOSE:
                on_purpose.append(name)
            else:
                gaps[header].append(name)
        elif "Availability: nonswift" in note:
            if name.startswith("gr_") or re.search(r"_(ref|unref)$", name):
                intentional_hidden += 1
            else:
                gr_params[header].append(name)

    def section(title: str, groups: dict[str, list[str]]) -> None:
        total = sum(len(v) for v in groups.values())
        print(f"## {title} ({total})")
        for header in sorted(groups, key=lambda h: (-len(groups[h]), h)):
            print(f"  {header} ({len(groups[header])}): {' '.join(groups[header])}")
        print()

    reachable = len(headers) - sum(len(v) for v in (*excluded.values(), *gaps.values(), *gr_params.values()))
    reachable -= len(on_purpose) + intentional_hidden
    print(f"{len(headers)} C functions; {reachable} reachable from Swift, "
          f"{intentional_hidden} Ganesh/ref-count hidden on purpose, {len(on_purpose)} unwrapped on purpose\n")
    section("Private, not called by Sources/Skia", gaps)
    section("Hidden for a gr_* parameter (may accept null)", gr_params)
    section("In EXCLUDED_HEADERS", {h: v for h, v in excluded.items()})
    if args.all:
        print(f"## Unwrapped on purpose ({len(on_purpose)})")
        for name in on_purpose:
            print(f"  {name}: {UNWRAPPED_ON_PURPOSE[name]}")


if __name__ == "__main__":
    main()
