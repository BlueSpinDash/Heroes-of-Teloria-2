extends SceneTree

## Turns the board's painted deck plates into mats a deck can stand on.
##
## Each plate arrives with its name and its icon painted across the middle —
## exactly where a deck standing in the centre of its zone covers them. The
## paint is the only part that has to go: the gold frame around it is the
## board's own, and a deck standing inside that frame reads as a deck on a
## table rather than as a card on a coloured rectangle.
##
## So the middle is drawn out and the frame is kept. The interior is refilled
## line by line, fading between the clean surface at either end of the line, so
## it meets the frame with no seam and keeps the plate's own colour and its
## shading down the plate.
##
## The mats are then rebuilt at the shape the screen wants. A plate is painted
## wide and shallow; a deck standing on one with its name above it is nearly
## square. Stretching the plate into that shape would stretch its corners with
## it, so instead the frame's top and bottom are copied across untouched and
## only the rails down the sides and the interior between them are drawn
## longer — the same trick a nine-patch plays, done once here at the artwork's
## own resolution so the live screen only ever scales the result down.
##
##   godot --headless --path . --script tools/prepare_deck_mats.gd

const DIR := "res://assets/board/"

## How tall each mat is drawn relative to its width. The screen's own
## `DECK_MAT_ASPECT` is the other side of this number: art and layout have to
## agree on the shape or one of them is stretching the other.
const MAT_ASPECT := 1.0 / 1.15

## Each plate: the slice to read, the mat to write, the inside of its frame,
## and how much of the frame at the top and bottom is copied rather than
## stretched. The insides differ because the three plates were painted at
## different widths.
const MATS := {
    "hit": {
        "src": "deck_hit",
        "out": "deck_mat_hit",
        # [x, y, w, h]: the interior, held a few pixels clear of the frame so
        # the line that refills it never reads the frame's own gold.
        "inside": [25, 20, 272, 121],
        "cap": 40,
    },
    "exhaust": {
        "src": "deck_exhaust",
        "out": "deck_mat_exhaust",
        "inside": [33, 20, 206, 121],
        "cap": 40,
    },
    "wound": {
        "src": "deck_wound",
        "out": "deck_mat_wound",
        "inside": [29, 20, 209, 121],
        "cap": 40,
    },
}


func _initialize() -> void:
    for kind in MATS:
        if not _build(String(kind), MATS[kind]):
            quit(1)
            return
    quit(0)


func _build(kind: String, spec: Dictionary) -> bool:
    var src: String = DIR + String(spec["src"]) + ".png"
    var img := Image.new()
    if img.load(ProjectSettings.globalize_path(src)) != OK:
        push_error("could not load %s" % src)
        return false
    img.convert(Image.FORMAT_RGBA8)
    var inside: Array = spec["inside"]
    _blank(img, Rect2i(int(inside[0]), int(inside[1]), int(inside[2]), int(inside[3])))
    var mat := _restretch(img, int(spec["cap"]),
        int(round(float(img.get_width()) * MAT_ASPECT)))
    var out: String = DIR + String(spec["out"]) + ".png"
    if mat.save_png(ProjectSettings.globalize_path(out)) != OK:
        push_error("could not write %s" % out)
        return false
    print("%-8s %dx%d -> %s %dx%d" % [kind, img.get_width(), img.get_height(),
        out, mat.get_width(), mat.get_height()])
    return true


## Draw the icon and the name out of the plate's interior.
##
## Every line of the interior is refilled by fading between the pixel just
## outside its left end and the pixel just outside its right end. Both of those
## are surface the paint never touched, so the line lands on the plate's own
## colour at that height and the plate's shading from top to bottom carries
## through. Nothing outside the rect is read or written, so the frame is
## untouched.
func _blank(img: Image, at: Rect2i) -> void:
    var left := at.position.x - 1
    var right := at.position.x + at.size.x
    for y in range(at.position.y, at.position.y + at.size.y):
        var before := img.get_pixel(left, y)
        var after := img.get_pixel(right, y)
        for x in range(at.position.x, right):
            img.set_pixel(x, y, before.lerp(after,
                float(x - left) / float(right - left)))


## Redraw the plate at a new height without redrawing its corners.
##
## The top and bottom bands — the frame's corners and the flourishes along its
## short edges — are copied at their own size. Everything between them is one
## band that is simply drawn taller: the rails down the sides are straight, and
## the interior between them is now a smooth fade, so both carry a stretch
## without anything to smear.
func _restretch(img: Image, cap: int, height: int) -> Image:
    var w := img.get_width()
    var h := img.get_height()
    var out := Image.create_empty(w, height, false, Image.FORMAT_RGBA8)
    out.blit_rect(img, Rect2i(0, 0, w, cap), Vector2i.ZERO)
    out.blit_rect(img, Rect2i(0, h - cap, w, cap), Vector2i(0, height - cap))
    var middle := img.get_region(Rect2i(0, cap, w, h - 2 * cap))
    middle.resize(w, height - 2 * cap, Image.INTERPOLATE_BILINEAR)
    out.blit_rect(middle, Rect2i(0, 0, w, height - 2 * cap), Vector2i(0, cap))
    return out
