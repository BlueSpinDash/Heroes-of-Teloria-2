extends SceneTree

## Turns the painted Hero card template into the frame the game draws on.
##
## The template arrives with placeholder text on it — a name, three stat
## numbers, some lorem rules text, the words AFFINITY and RARITY. Those are the
## parts the game fills in per card, so they are painted out here and the live
## card draws its own. Everything that is the same on every Hero — the HERO
## banner, the MAX ENERGY, ATTACK and DEFENSE captions, the ornament — stays.
##
## Painting out is done by stretching a clean patch of the same surface over
## the words: the surfaces are parchment, stone and cut gems, all of which
## carry through a stretch without a visible seam.

const SRC := "res://assets/frames/_hero_template_src.png"
const OUT := "res://assets/frames/hero_frame.png"

## [clean_x, clean_y, clean_w, clean_h, over_x, over_y, over_w, over_h], in
## the template's own pixels. The clean rect is the surface the patch is cut
## from; the over rect is the placeholder it is stretched across.
const PATCHES := [
    # The three stat numbers, patched with clean facets of their own gems.
    [100, 215, 42, 70, 140, 206, 62, 82],
    [118, 484, 30, 80, 148, 484, 72, 80],
    [116, 724, 30, 80, 148, 724, 70, 80],
    # The name banner and the rules block. Both are patched with a clean band
    # of their own parchment at their own width, so the tone matches exactly
    # and the stretch leaves no seam down either side.
    [336, 872, 404, 10, 336, 878, 404, 68],
    [192, 1160, 676, 12, 192, 1000, 676, 218],
    # The word AFFINITY, patched from the clean top of its own banner.
    [438, 1360, 174, 9, 438, 1368, 174, 40],
    # The two footer lines, patched with the clean stone beside them.
    [320, 1392, 120, 32, 88, 1388, 230, 40],
    [650, 1392, 150, 32, 790, 1388, 180, 40],
]



func _initialize() -> void:
    var img := Image.new()
    if img.load(ProjectSettings.globalize_path(SRC)) != OK:
        push_error("could not load %s" % SRC)
        quit(1)
        return
    print("template %dx%d" % [img.get_width(), img.get_height()])
    var card := _trim(img)
    print("card %dx%d  aspect %.4f" % [card.get_width(), card.get_height(),
        float(card.get_width()) / float(card.get_height())])
    for p in PATCHES:
        _patch(card, Rect2i(int(p[0]), int(p[1]), int(p[2]), int(p[3])),
            Rect2i(int(p[4]), int(p[5]), int(p[6]), int(p[7])))
    if card.save_png(ProjectSettings.globalize_path(OUT)) != OK:
        push_error("could not write %s" % OUT)
        quit(1)
        return
    print("wrote ", OUT)
    quit(0)


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


## Stretch the clean rect over the target rect.
func _patch(img: Image, clean: Rect2i, over: Rect2i) -> void:
    var piece := img.get_region(clean)
    piece.resize(over.size.x, over.size.y, Image.INTERPOLATE_BILINEAR)
    img.blit_rect(piece, Rect2i(Vector2i.ZERO, over.size), over.position)
