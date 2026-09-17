class_name ZoneBounds
extends Control

## The boundaries of the board's zones, drawn over the board while a card is
## being dragged.
##
## A zone takes a card anywhere inside it, so while a drag is in flight the
## whole of every zone that would accept the card is banded and named. The
## bands are drawn as an overlay rather than as children of the zones: a label
## added to a zone mid-drag would change that zone's minimum size, and the
## board would shift out from under the pointer.

## How strongly a zone's interior is washed with its highlight colour.
const FILL_ALPHA := 0.16
const BORDER_W := 3
## A band smaller than this in either direction is left as just its boundary,
## with no name written in it.
const MIN_LABEL_ROOM := Vector2(16.0, 10.0)

## One entry per zone: {"rect": Rect2 (global), "hint": String}.
var _bands: Array = []
var _font: Font = null
var _font_size: int = UiTheme.fs(12)


func _init() -> void:
    name = "ZoneBounds"
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_anchors_preset(Control.PRESET_FULL_RECT)


func _ready() -> void:
    _font = get_theme_default_font()


## Band these zones. Called with an empty list when the drag ends.
func show_zones(bands: Array) -> void:
    _bands = bands
    queue_redraw()


## What is currently banded, for the tests and for anything that wants to know
## whether a drag is being offered a home.
func bands() -> Array:
    return _bands


## A zone's rect as it is actually on screen: the part of it that its scrolling
## strips and clipping panels have not cut away.
static func visible_rect(zone: Control) -> Rect2:
    var r := zone.get_global_rect()
    var node := zone.get_parent()
    while node is Control:
        var c := node as Control
        if c is ScrollContainer or c.clip_contents:
            r = r.intersection(c.get_global_rect())
        node = c.get_parent()
    return r


func _draw() -> void:
    var to_local_xf := get_global_transform().affine_inverse()
    for band in _bands:
        var rect: Rect2 = to_local_xf * (band.get("rect", Rect2()) as Rect2)
        if rect.size.x < 8.0 or rect.size.y < 8.0:
            continue
        draw_style_box(UiTheme.panel_style(
            Color(UiTheme.GOOD, FILL_ALPHA), UiTheme.GOOD, BORDER_W, 6), rect)
        var hint := String(band.get("hint", ""))
        if hint.is_empty() or _font == null:
            continue
        var text := _font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size)
        if text.x + MIN_LABEL_ROOM.x > rect.size.x or text.y + MIN_LABEL_ROOM.y > rect.size.y:
            continue
        var pill := Rect2(rect.get_center() - (text + MIN_LABEL_ROOM) * 0.5,
            text + MIN_LABEL_ROOM)
        draw_style_box(UiTheme.panel_style(Color(0, 0, 0, 0.74), UiTheme.GOOD, 1, 4), pill)
        draw_string(_font,
            Vector2(pill.position.x + MIN_LABEL_ROOM.x * 0.5,
                pill.position.y + MIN_LABEL_ROOM.y * 0.5 + _font.get_ascent(_font_size)),
            hint, HORIZONTAL_ALIGNMENT_LEFT, -1, _font_size, UiTheme.PARCHMENT)
