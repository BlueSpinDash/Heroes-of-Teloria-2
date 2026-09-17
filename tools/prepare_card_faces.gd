extends SceneTree

## Trims the backdrop off a supplied card face.
##
## A card face arrives as a picture *of* a card: the card itself, sitting on
## whatever the renderer put behind it — usually black, sometimes grey. The
## game draws the face edge to edge, so the backdrop has to go, or every card
## would come out inset in a border that is not part of it.
##
## This is not a crop in the sense of choosing what to keep. The backdrop is
## only reachable from the edges, so a flood fill from the four corners finds
## exactly it, and what is left is the card: the whole card, as it was drawn,
## with its own rounded corners kept as transparency.
##
##   godot --headless --path . --script tools/prepare_card_faces.gd
##
## Pass filenames to do only those:
##   ... --script tools/prepare_card_faces.gd -- young_blood.png

const DIR := "res://assets/cards/"
## How far a pixel may drift from the corner colour and still be backdrop. The
## mattes are flat, but they carry compression noise and a soft card shadow.
const TOLERANCE := 0.14


func _initialize() -> void:
    var only: Array = []
    for arg in OS.get_cmdline_user_args():
        only.append(String(arg))
    var dir := DirAccess.open(DIR)
    if dir == null:
        push_error("no %s" % DIR)
        quit(1)
        return
    var failed := false
    for file in dir.get_files():
        var name := String(file)
        if not name.ends_with(".png"):
            continue
        if not only.is_empty() and not only.has(name):
            continue
        if not _trim(name):
            failed = true
    quit(1 if failed else 0)


func _trim(name: String) -> bool:
    var path := DIR + name
    var img := Image.new()
    if img.load(ProjectSettings.globalize_path(path)) != OK:
        push_error("could not load %s" % path)
        return false
    img.convert(Image.FORMAT_RGBA8)
    var w := img.get_width()
    var h := img.get_height()
    var was := "%dx%d" % [w, h]

    var bg := img.get_pixel(0, 0)
    var seen := {}
    var queue: Array[Vector2i] = [Vector2i(0, 0), Vector2i(w - 1, 0),
        Vector2i(0, h - 1), Vector2i(w - 1, h - 1)]
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
        queue.append(Vector2i(at.x + 1, at.y))
        queue.append(Vector2i(at.x - 1, at.y))
        queue.append(Vector2i(at.x, at.y + 1))
        queue.append(Vector2i(at.x, at.y - 1))

    var box := _opaque_box(img)
    if box.size.x <= 0 or box.size.y <= 0:
        push_error("%s: the whole picture read as backdrop" % name)
        return false
    var card := img.get_region(box)
    if card.save_png(ProjectSettings.globalize_path(path)) != OK:
        push_error("could not write %s" % path)
        return false
    print("%-30s %s -> %dx%d  (%.4f, a 5:7 card is 0.7143)" % [
        name, was, box.size.x, box.size.y, float(box.size.x) / float(box.size.y)])
    return true


func _near(a: Color, b: Color) -> bool:
    return absf(a.r - b.r) < TOLERANCE and absf(a.g - b.g) < TOLERANCE \
        and absf(a.b - b.b) < TOLERANCE


## The smallest rectangle holding every pixel the flood fill did not clear.
func _opaque_box(img: Image) -> Rect2i:
    var lo := Vector2i(img.get_width(), img.get_height())
    var hi := Vector2i(-1, -1)
    for y in img.get_height():
        for x in img.get_width():
            if img.get_pixel(x, y).a <= 0.0:
                continue
            lo.x = mini(lo.x, x)
            lo.y = mini(lo.y, y)
            hi.x = maxi(hi.x, x)
            hi.y = maxi(hi.y, y)
    if hi.x < lo.x:
        return Rect2i()
    return Rect2i(lo, hi - lo + Vector2i.ONE)
