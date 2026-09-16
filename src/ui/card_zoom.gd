class_name CardZoom
extends Control

## A full-size card face, shown while the pointer rests on a small one.
##
## Cards on the board and in the hand are drawn small enough to fit the table,
## which leaves their rules text too small to read. This shows the same card at
## a size meant for reading, beside whatever the pointer is over.
##
## It is a reader, not a control: it takes no input, sits above everything, and
## never touches match state.

## Wide enough for the rules text to read at its designed size.
const ZOOM_WIDTH := 300.0
## A beat before it appears, so sweeping the pointer across the board does not
## flash a card for every chip it crosses.
const HOVER_DELAY := 0.18
## Clear of the pointer and of the thing being read.
const MARGIN := 12.0

var _card: CardView = null
var _shown: CardDef = null
var _pending: CardDef = null
var _pending_anchor := Rect2()
var _prefer_above := false
var _wait := 0.0


func _init() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_anchors_preset(Control.PRESET_FULL_RECT)
    set_process(true)


## Ask for a card to be shown beside `anchor`, once the pointer has rested.
##
## `above` asks for it to go over the anchor rather than next to it. A card in
## hand wants that: the hand is a row along the bottom of the screen, so a
## reader beside one card covers its neighbours, while a reader above the row
## covers none of them.
func request(def: CardDef, anchor: Rect2, above: bool = false) -> void:
    if def == null:
        dismiss()
        return
    if _shown == def and _card != null:
        return
    _pending = def
    _pending_anchor = anchor
    _prefer_above = above
    # Already reading a card, so move straight to the next one.
    _wait = 0.0 if _card != null else HOVER_DELAY


## Take the card away. Safe to call when nothing is shown.
func dismiss() -> void:
    _pending = null
    _shown = null
    _wait = 0.0
    if _card != null:
        _card.queue_free()
        _card = null


func showing() -> bool:
    return _card != null


## The card currently being read, or null.
func shown_card() -> CardDef:
    return _shown if _card != null else null


## Where the enlarged face is on screen, empty when nothing is being read.
func shown_rect() -> Rect2:
    return _card.get_global_rect() if _card != null else Rect2()


func _process(delta: float) -> void:
    if _pending == null:
        return
    if _wait > 0.0:
        _wait -= delta
        if _wait > 0.0:
            return
    _present()


func _present() -> void:
    if _card != null:
        _card.queue_free()
        _card = null
    if _pending == null:
        return
    _shown = _pending
    _pending = null
    var view := CardView.create(_shown, ZOOM_WIDTH)
    view.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _ignore_below(view)
    view.modulate = Color(1, 1, 1, 0)
    add_child(view)
    _card = view
    view.position = _place(Vector2(ZOOM_WIDTH, ZOOM_WIDTH * CardView.BASE_HEIGHT / CardView.BASE_WIDTH))
    var tw := create_tween()
    tw.tween_property(view, "modulate:a", 1.0, 0.1)


## Beside the anchor if there is room, otherwise on its other side, and always
## inside the screen: a card that reads off the edge is no easier to read than
## the small one it came from.
func _place(card_size: Vector2) -> Vector2:
    var screen := get_global_rect()
    var at := Vector2.ZERO

    var above := _pending_anchor.position.y - MARGIN - card_size.y
    if _prefer_above and above >= screen.position.y:
        at.x = _pending_anchor.get_center().x - card_size.x * 0.5
        at.y = above
    else:
        var right := _pending_anchor.end.x + MARGIN
        var left := _pending_anchor.position.x - MARGIN - card_size.x
        if right + card_size.x <= screen.end.x:
            at.x = right
        elif left >= screen.position.x:
            at.x = left
        else:
            at.x = _pending_anchor.get_center().x - card_size.x * 0.5
        at.y = _pending_anchor.get_center().y - card_size.y * 0.5
    at.x = clampf(at.x, screen.position.x + MARGIN, screen.end.x - card_size.x - MARGIN)
    at.y = clampf(at.y, screen.position.y + MARGIN, screen.end.y - card_size.y - MARGIN)
    return at - screen.position


static func _ignore_below(node: Node) -> void:
    for child in node.get_children():
        if child is Control:
            (child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
        _ignore_below(child)
