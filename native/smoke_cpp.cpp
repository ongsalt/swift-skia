// C++ against the staged headers (headers/skia/...) with no compiler flags: SkUserConfig.h must
// carry the defines libSkiaSharp was built with, or layouts and colors won't match the library.
#include <cstdio>

#include "skia/include/core/SkCanvas.h"
#include "skia/include/core/SkColor.h"
#include "skia/include/core/SkPaint.h"
#include "skia/include/core/SkPixmap.h"
#include "skia/include/core/SkSurface.h"

int main() {
    sk_sp<SkSurface> surface = SkSurfaces::Raster(SkImageInfo::MakeN32Premul(16, 16));
    if (!surface) { std::fprintf(stderr, "SkSurfaces::Raster failed\n"); return 1; }
    SkCanvas* canvas = surface->getCanvas();
    canvas->clear(SK_ColorWHITE);
    SkPaint paint;
    paint.setColor(SK_ColorRED);
    canvas->drawRect(SkRect::MakeWH(8, 16), paint);

    SkPixmap pixmap;
    if (!surface->peekPixels(&pixmap)) { std::fprintf(stderr, "peekPixels failed\n"); return 1; }
    SkColor left = pixmap.getColor(2, 2), right = pixmap.getColor(12, 2);
    if (left != SK_ColorRED || right != SK_ColorWHITE) {
        std::fprintf(stderr, "wrong pixels: %08x %08x\n", left, right);
        return 1;
    }
    std::printf("C++ API ok\n");
    return 0;
}
