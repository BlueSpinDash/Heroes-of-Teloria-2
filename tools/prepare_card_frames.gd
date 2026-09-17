extends SceneTree

## Turns a painted card template into the frame the game draws on.
##
## A template arrives with placeholder text on it — a name, some numbers, some
## lorem rules text, the words AFFINITY and RARITY. Those are the parts the
## game fills in per card, so they are painted out here and the live card draws
## its own. Everything that is the same on every card of the type — the type
## banner, the stat captions, the ornament, the silhouette that stands in for
## missing art — stays.
##
## Painting out is done by stretching a clean patch of the same surface over
## the words: the surfaces are parchment, stone and cut gems, all of which
## carry through a stretch without a visible seam. A patch is cut at the same
## width as the region it covers wherever possible, so the tone matches exactly
## and the stretch leaves no seam down either side.
##
##   godot --headless --path . --script tools/prepare_card_frames.gd

const DIR := "res://assets/frames/"

## Each frame: its template, the file to write, and the placeholders to paint
## out as [clean_x, clean_y, clean_w, clean_h, over_x, over_y, over_w, over_h]
## in the template's own pixels.
const FRAMES := {
    "hero": {
        "src": "_hero_template_src.png",
        "out": "hero_frame.png",
        "patches": [
            # The three stat numbers, patched with clean facets of their gems.
            [100, 215, 42, 70, 140, 206, 62, 82],
            [118, 484, 30, 80, 148, 484, 72, 80],
            [116, 724, 30, 80, 148, 724, 70, 80],
            # The name banner and the rules block, patched with a band of the
            # same parchment from a gap between two lines of placeholder text.
            [336, 872, 404, 10, 336, 878, 404, 68],
            [192, 1166, 676, 9, 192, 1000, 676, 218],
            # The word AFFINITY, from the clean top of its own banner.
            [438, 1360, 174, 9, 438, 1368, 174, 40],
            # The two footer lines, from the clean stone beside them.
            [320, 1392, 120, 32, 88, 1388, 230, 40],
            [650, 1392, 150, 32, 790, 1388, 180, 40],
        ],
    },
    "skill": {
        "src": "_skill_template_src.png",
        "out": "skill_frame.png",
        # The Energy gem sits over the art window's top-left corner on this
        # frame, the way the printed card draws it: art first, gem on top. It
        # is cut out here so the card can put it back above the artwork instead
        # of losing that corner of the window to it. "keep" is the gem's own
        # hexagon, measured off the template; everything outside it in the
        # rect is window backdrop and is cleared so the artwork shows through.
        "cutouts": {
            "skill_energy_gem": {
                "rect": [66, 118, 212, 296],
                "keep": [[170, 128], [265, 201], [265, 329],
                    [170, 404], [74, 329], [74, 201]],
                "grow": 3.0,
            },
        },
        # The Energy number. Every facet of this gem is lit differently, so a
        # patch cut from elsewhere on it lands as a visible block; the number
        # is drawn out column by column instead, between the clean gem above
        # it and the clean gem below.
        "inpaints": [[146, 205, 46, 89]],
        "patches": [
            # The name banner, from a clean band of its own parchment.
            [336, 872, 404, 10, 336, 878, 404, 68],
            # The rules block. This template's placeholder text sits lower than
            # the Hero one's, so the clean band is taken from below it.
            [192, 1196, 676, 14, 192, 1000, 676, 218],
            [438, 1360, 174, 9, 438, 1368, 174, 40],
            [320, 1392, 120, 32, 88, 1388, 230, 40],
            [650, 1392, 150, 32, 790, 1388, 180, 40],
        ],
    },
    "taahma": {
        "src": "_taahma_template_src.png",
        "out": "taahma_frame.png",
        # This gem is pale stone and its number is inked dark, where the Hero's
        # and the Skill's are white on blue.
        "inpaints": [[145, 205, 49, 93]],
        "patches": [
            [265, 882, 545, 10, 265, 888, 545, 72],
            [192, 1200, 676, 9, 192, 1020, 676, 214],
            [330, 1420, 120, 24, 95, 1416, 200, 30],
            [640, 1420, 150, 24, 815, 1416, 180, 30],
        ],
    },
    "companion": {
        "src": "_companion_template_src.png",
        "out": "companion_frame.png",
        "inpaints": [
            [112, 186, 75, 100, "vertical"],
            [112, 504, 75, 66, "horizontal"],
            [112, 740, 75, 64, "horizontal"],
        ],
        "patches": [
            [265, 897, 545, 10, 265, 903, 545, 74],
            [192, 1200, 676, 9, 192, 1030, 676, 193],
            [330, 1420, 120, 24, 80, 1416, 200, 30],
            [640, 1420, 150, 24, 830, 1416, 200, 30],
        ],
    },
    "equipment": {
        "src": "_equipment_template_src.png",
        "out": "equipment_frame.png",
        "inpaints": [
            [112, 197, 80, 94, "vertical"],
            [112, 505, 80, 60, "horizontal"],
            [112, 746, 80, 60, "horizontal"],
        ],
        "patches": [
            [265, 912, 545, 10, 265, 918, 545, 74],
            [192, 1215, 676, 9, 192, 1045, 676, 195],
            [330, 1444, 120, 20, 80, 1440, 200, 24],
            [640, 1444, 150, 20, 835, 1440, 200, 24],
        ],
    },
}


func _initialize() -> void:
    for name in FRAMES:
        if not _build(String(name), FRAMES[name]):
            quit(1)
            return
    quit(0)


func _build(name: String, spec: Dictionary) -> bool:
    var src: String = DIR + String(spec["src"])
    var img := Image.new()
    if img.load(ProjectSettings.globalize_path(src)) != OK:
        push_error("could not load %s" % src)
        return false
    print("%s: template %dx%d" % [name, img.get_width(), img.get_height()])
    var card := _trim(img)
    for f in spec.get("inpaints", []):
        _inpaint(card, Rect2i(int(f[0]), int(f[1]), int(f[2]), int(f[3])),
            String(f[4]) if (f as Array).size() > 4 else "vertical")
    for p in spec["patches"]:
        _patch(card, Rect2i(int(p[0]), int(p[1]), int(p[2]), int(p[3])),
            Rect2i(int(p[4]), int(p[5]), int(p[6]), int(p[7])))
    var out: String = DIR + String(spec["out"])
    if card.save_png(ProjectSettings.globalize_path(out)) != OK:
        push_error("could not write %s" % out)
        return false
    print("%s: wrote %s" % [name, out])

    # Pieces of the frame the card puts back on top of its artwork.
    for cut in spec.get("cutouts", {}):
        var cut_path: String = DIR + String(cut) + ".png"
        var piece := _cut(card, spec["cutouts"][cut])
        if piece.save_png(ProjectSettings.globalize_path(cut_path)) != OK:
            push_error("could not write %s" % cut_path)
            return false
        print("%s: wrote %s" % [name, cut_path])
    return true


## Lift one ornament off the frame, with everything around it cleared.
##
## The ornament is not a rectangle, so the rect is only the region to read; the
## shape is the "keep" polygon, grown a little so the gold edge keeps its
## anti-aliasing and its shadow rather than ending on a hard line.
func _cut(card: Image, spec: Dictionary) -> Image:
    var r: Array = spec["rect"]
    var at := Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
    var piece := card.get_region(at)
    piece.convert(Image.FORMAT_RGBA8)
    var keep := PackedVector2Array()
    for point in spec["keep"]:
        keep.append(Vector2(float(point[0]) - at.position.x,
            float(point[1]) - at.position.y))
    var grown: Array = Geometry2D.offset_polygon(keep, float(spec.get("grow", 0.0)))
    var shape: PackedVector2Array = grown[0] if not grown.is_empty() else keep
    var cleared := 0
    for y in piece.get_height():
        for x in piece.get_width():
            if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), shape):
                continue
            piece.set_pixel(x, y, Color(0, 0, 0, 0))
            cleared += 1
    print("cut %dx%d, cleared %d pixels around the shape"
        % [at.size.x, at.size.y, cleared])
    return piece


## Make the backdrop the template was rendered on transparent, so the card's
## rounded corners sit on the board rather than on a grey square.
##
## The backdrop is only reachable from the edges, so a flood fill from the four
## corners clears it without touching anything inside the card.
func _trim(img: Image) -> Image:
    img.convert(Image.FORMAT_RGBA8)
    var w := img.get_width()
    var h := img.get_height()
    var bg := img.get_pixel(0, 0)
    var seen := {}
    var queue: Array[Vector2i] = [Vector2i(0, 0), Vector2i(w - 1, 0),
        Vector2i(0, h - 1), Vector2i(w - 1, h - 1)]
    var cleared := 0
    while not queue.is_empty():
        var at: Vector2i = queue.pop_back()
        if at.x < 0 or at.y < 0 or at.x >= w or at.y >= h:
            continue
        var key := at.y * w + at.x
        if seen.has(key):
            continue
        seen[key] = true
        if not _near(img.get_pixel(at.x, at.y), bg):
            continue
        img.set_pixel(at.x, at.y, Color(0, 0, 0, 0))
        cleared += 1
        queue.append(Vector2i(at.x + 1, at.y))
        queue.append(Vector2i(at.x - 1, at.y))
        queue.append(Vector2i(at.x, at.y + 1))
        queue.append(Vector2i(at.x, at.y - 1))
    print("backdrop cleared: %d pixels" % cleared)
    return img


func _near(a: Color, b: Color) -> bool:
    return absf(a.r - b.r) < 0.12 and absf(a.g - b.g) < 0.12 and absf(a.b - b.b) < 0.12


## Draw a mark out of a surface whose lighting changes across it.
##
## Each line of the rect is refilled by fading between the pixel just outside
## one end and the pixel just outside the other, so it meets the untouched
## surface at both ends with no seam and the surface's own shading carries
## through. Nothing beyond the rect is touched.
##
## A gem is shaded top to bottom, so its lines run down it; a medallion carries
## its icon directly above its number, leaving clean surface only to the sides,
## so there the lines run across.
func _inpaint(img: Image, at: Rect2i, direction: String = "vertical") -> void:
    if direction == "horizontal":
        var left := at.position.x - 1
        var right := at.position.x + at.size.x
        for y in range(at.position.y, at.position.y + at.size.y):
            var before := img.get_pixel(left, y)
            var after := img.get_pixel(right, y)
            for x in range(at.position.x, right):
                img.set_pixel(x, y, before.lerp(after,
                    float(x - left) / float(right - left)))
        return
    var top := at.position.y - 1
    var bottom := at.position.y + at.size.y
    for x in range(at.position.x, at.position.x + at.size.x):
        var above := img.get_pixel(x, top)
        var below := img.get_pixel(x, bottom)
        for y in range(at.position.y, bottom):
            var f := float(y - top) / float(bottom - top)
            img.set_pixel(x, y, above.lerp(below, f))


## Stretch the clean rect over the target rect.
func _patch(img: Image, clean: Rect2i, over: Rect2i) -> void:
    var piece := img.get_region(clean)
    piece.resize(over.size.x, over.size.y, Image.INTERPOLATE_BILINEAR)
    img.blit_rect(piece, Rect2i(Vector2i.ZERO, over.size), over.position)
