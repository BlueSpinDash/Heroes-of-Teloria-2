class_name BattleDropTarget
extends PanelContainer

## A panel on the battle screen that can be dragged from, dropped onto, or
## both.
##
## Dragging is an addition, never a requirement: every action it offers is also
## available by clicking, so the game stays usable with a trackpad, a
## touchscreen or a keyboard-driven pointer.

signal dropped(payload: Dictionary)

## Returned to Godot's drag system when a drag starts here. Null means this
## panel cannot be dragged from.
var drag_payload = null
## func(payload: Dictionary) -> bool. Null means nothing can be dropped here.
var accepts_check: Callable = Callable()
## A short reason shown while dragging, explaining what this target would do.
var drop_hint: String = ""

var _bg: Color = UiTheme.BG_RAISED
var _border: Color = UiTheme.GOLD_DIM
var _width: int = 1
var _radius: int = 5
var _highlighted: bool = false


func style(bg: Color, border: Color, width: int = 1, radius: int = 5) -> void:
    _bg = bg
    _border = border
    _width = width
    _radius = radius
    _apply()


func _apply() -> void:
    if _highlighted:
        add_theme_stylebox_override("panel",
            UiTheme.panel_style(_bg.lightened(0.10), UiTheme.GOOD, max(2, _width + 1), _radius))
    else:
        add_theme_stylebox_override("panel", UiTheme.panel_style(_bg, _border, _width, _radius))


## Light this target up while a compatible card is being dragged.
func set_highlight(on: bool) -> void:
    if _highlighted == on:
        return
    _highlighted = on
    _apply()


## Make everything inside transparent to the mouse, so this panel is what a
## drag sees rather than one of its labels.
func claim_mouse() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    _ignore_below(self)


static func _ignore_below(node: Node) -> void:
    for child in node.get_children():
        if child is Button or child is LineEdit or child is OptionButton or child is SpinBox:
            continue  # real controls keep their own input
        if child is Control:
            (child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
        _ignore_below(child)


func can_accept(payload) -> bool:
    if not (payload is Dictionary):
        return false
    if accepts_check.is_null():
        return false
    return bool(accepts_check.call(payload))


# ------------------------------------------------------------ drag and drop ---

func _get_drag_data(_at_position: Vector2) -> Variant:
    if drag_payload == null:
        return null
    var ghost := UiTheme.panel(UiTheme.BG_PANEL, UiTheme.GOLD, 2, 5)
    ghost.modulate = Color(1, 1, 1, 0.85)
    ghost.add_child(UiTheme.label(String((drag_payload as Dictionary).get("label", "Dragging")),
        13, UiTheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
    set_drag_preview(ghost)
    return drag_payload


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
    return can_accept(data)


func _drop_data(_at_position: Vector2, data: Variant) -> void:
    if can_accept(data):
        dropped.emit(data as Dictionary)
