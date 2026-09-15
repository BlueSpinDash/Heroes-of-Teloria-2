class_name CardArt
extends Control

## The card portrait: a supplied image when the definition names one, and a
## deterministic abstract sigil when it does not.
##
## Either way this draws decoration only. Cost, stats and rules text always
## live in real controls outside the art, per the template direction, so the
## art can be replaced freely without changing what a card does or says.

var art_seed: int = 0
var hue: float = 210.0
var saturation: float = 0.45
var sigil_points: int = 6
var texture: Texture2D = null
var fit: String = "cover"


func setup(art: Dictionary) -> void:
    art_seed = int(art.get("seed", 0))
    hue = float(art.get("hue", 210))
    saturation = float(art.get("saturation", 0.45))
    sigil_points = 4 + (art_seed % 5)
    fit = String(art.get("fit", "cover"))
    texture = ArtLibrary.texture_for(art)
    clip_contents = true
    queue_redraw()


func _draw() -> void:
    var r := Rect2(Vector2.ZERO, size)
    if size.x <= 2.0 or size.y <= 2.0:
        return
    if texture != null:
        _draw_supplied_art()
        return
    var base := Color.from_hsv(hue / 360.0, saturation * 0.7, 0.20)
    var mid := Color.from_hsv(hue / 360.0, saturation * 0.55, 0.32)
    var glow := Color.from_hsv(hue / 360.0, saturation * 0.35, 0.55)

    draw_rect(r, base, true)
    # Horizon bands give the placeholder some depth without implying subject.
    var bands := 5
    for i in bands:
        var t := float(i) / float(bands)
        var band := Rect2(0, size.y * (0.45 + t * 0.11), size.x, size.y * 0.06)
        draw_rect(band, mid.darkened(t * 0.35), true)

    var centre := Vector2(size.x * 0.5, size.y * 0.44)
    var radius: float = min(size.x, size.y) * 0.30

    # Concentric rings.
    for i in 3:
        var rr := radius * (0.55 + 0.22 * float(i))
        draw_arc(centre, rr, 0.0, TAU, 48, glow.darkened(0.25 + 0.15 * i), 1.5, true)

    # A seeded sigil: the point count and rotation come from the art seed.
    var rot := float(art_seed % 360) * PI / 180.0
    var pts := PackedVector2Array()
    for i in sigil_points * 2:
        var ang := rot + TAU * float(i) / float(sigil_points * 2)
        var rr2: float = radius * (1.0 if i % 2 == 0 else 0.42)
        pts.append(centre + Vector2(cos(ang), sin(ang)) * rr2)
    if pts.size() >= 3:
        draw_colored_polygon(pts, glow.darkened(0.15))
        var outline := pts.duplicate()
        outline.append(pts[0])
        draw_polyline(outline, UiTheme.GOLD_DIM, 1.5, true)

    # A faint compass cross, echoing the frame's motif.
    draw_line(Vector2(centre.x, centre.y - radius * 1.35),
        Vector2(centre.x, centre.y + radius * 1.35), glow.darkened(0.45), 1.0, true)
    draw_line(Vector2(centre.x - radius * 1.35, centre.y),
        Vector2(centre.x + radius * 1.35, centre.y), glow.darkened(0.45), 1.0, true)

    _draw_vignette()


## Fit a supplied image to the portrait window. "cover" fills the window and
## crops the overflow; "contain" shows the whole image on a dark ground.
func _draw_supplied_art() -> void:
    var tw := float(texture.get_width())
    var th := float(texture.get_height())
    if tw <= 0.0 or th <= 0.0:
        return
    draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.05, 0.06), true)
    var scale_factor: float = max(size.x / tw, size.y / th) if fit != "contain" \
        else min(size.x / tw, size.y / th)
    var drawn := Vector2(tw * scale_factor, th * scale_factor)
    var at := (size - drawn) * 0.5
    draw_texture_rect(texture, Rect2(at, drawn), false)
    _draw_vignette()


func _draw_vignette() -> void:
    var edge := Color(0, 0, 0, 0.35)
    draw_rect(Rect2(0, 0, size.x, size.y * 0.06), edge, true)
    draw_rect(Rect2(0, size.y * 0.94, size.x, size.y * 0.06), edge, true)
