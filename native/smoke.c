// Link + run check for libSkiaSharp.a: draws to a raster surface and writes a PNG.
// It also takes the address of the Graphite/Vulkan entry point so linking fails
// if Graphite was not built in.
#include <stdio.h>
#include <string.h>

#include "include/c/sk_canvas.h"
#include "include/c/sk_graphite_vulkan.h"
#include "include/c/sk_paint.h"
#include "include/c/sk_pixmap.h"
#include "include/c/sk_stream.h"
#include "include/c/sk_surface.h"

int main(int argc, char** argv) {
    const char* path = argc > 1 ? argv[1] : "smoke.png";

    volatile void* graphite = (void*)&sk_graphite_context_make_vulkan;
    (void)graphite;

    sk_imageinfo_t info = {
        .colorspace = NULL,
        .width = 256,
        .height = 256,
        .colorType = RGBA_8888_SK_COLORTYPE,
        .alphaType = PREMUL_SK_ALPHATYPE,
    };
    sk_surface_t* surface = sk_surface_new_raster(&info, 0, NULL);
    if (!surface) { fprintf(stderr, "sk_surface_new_raster failed\n"); return 1; }

    sk_canvas_t* canvas = sk_surface_get_canvas(surface);
    sk_canvas_clear(canvas, 0xFFFFFFFF);

    sk_paint_t* paint = sk_paint_new();
    sk_paint_set_antialias(paint, true);
    sk_paint_set_color(paint, 0xFF2266DD);
    sk_canvas_draw_circle(canvas, 128, 128, 96, paint);

    sk_pixmap_t* pixmap = sk_pixmap_new();
    if (!sk_surface_peek_pixels(surface, pixmap)) { fprintf(stderr, "peek_pixels failed\n"); return 1; }

    sk_wstream_filestream_t* file = sk_filewstream_new(path);
    sk_pngencoder_options_t options;
    memset(&options, 0, sizeof options);
    options.fFilterFlags = ALL_SK_PNGENCODER_FILTER_FLAGS;
    options.fZLibLevel = 6;
    bool ok = sk_pngencoder_encode((sk_wstream_t*)file, pixmap, &options);
    sk_filewstream_destroy(file);

    sk_pixmap_destructor(pixmap);
    sk_paint_delete(paint);
    sk_surface_unref(surface);

    if (!ok) { fprintf(stderr, "png encode failed\n"); return 1; }
    printf("wrote %s\n", path);
    return 0;
}
