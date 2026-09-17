extends Control

## Move the pieces of a card, and the metrics of the board, by eye.
##
## Everything here edits `Layout`, which the interface reads. The card preview
## is a real CardView, not a mock, so what is dragged is exactly what a player
## sees. Saving writes `data/layout.json`, which is repository content when the
## game is running from source: the change is a real change to the game, not a
## setting that lives only on this machine.

var app: App

## The size the preview card is drawn at. Large enough to place a footer line.
const PREVIEW_W := 460.0
## How far a nudge moves a slot, as a fraction of the card.
const NUDGE := 0.002

## The layout group being edited: whichever one places the previewed card.
## Frames differ — a Skill has no Attack medallion — so this follows the card.
var _group: String = "hero_card"
var _selected: String = "art"
var _preview_holder: Control
var _card: CardView
var _overlay: Control
var _fields: Dictionary = {}
var _status: Label
var _card_ids: Array = []
var _card_index: int = 0

## Set while a handle is being dragged: which one, and where the pointer was.
var _drag_mode: String = ""
var _drag_from := Vector2.ZERO
var _drag_rect := Rect2()

## Which of the two things is being laid out: the face of a card, or the board
## a match is played on. They are edited the same way and saved to the same
## file; they just need different things under the pointer.
var _mode: String = "card"
var _card_column: Control
var _board_column: Control
var _controls_column: Control
var _board_holder: Control
## The controls whose minimum size follows a board number, so a drag can move
## them without rebuilding the whole board on every pixel.
var _board_rows: Dictionary = {}
## group/key -> the spin box showing that number, so a drag keeps it honest.
var _spins: Dictionary = {}

## Set while a board grab bar is being dragged.
var _grab_key: String = ""
var _grab_axis: String = "v"
var _grab_sign: float = 1.0

const BOARD := "battle_board"


func setup(application: App, _args: Dictionary = {}) -> void:
    app = application
    for d in app.catalog.all_defs():
        if CardView.frame_group(d as CardDef) != "":
            _card_ids.append((d as CardDef).id)
    _card_ids.sort()

    var root := UiTheme.hbox(12)
    root.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(root)
    root.add_child(_build_preview())
    _controls_column = _build_controls()
    root.add_child(_controls_column)
    _set_mode("card")


# ------------------------------------------------------------------ preview ---

func _build_preview() -> Control:
    var column := UiTheme.vbox(8)
    column.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    _tabs = UiTheme.hbox(6)
    column.add_child(_tabs)

    _card_column = _build_card_preview()
    column.add_child(_card_column)
    _board_column = _build_board_preview()
    column.add_child(_board_column)
    return column


var _tabs: HBoxContainer


## The two things this screen lays out. The one being laid out is drawn as the
## chosen button rather than a disabled one: it is where you are, not somewhere
## you cannot go.
func _fill_tabs() -> void:
    for c in _tabs.get_children():
        _tabs.remove_child(c)
        c.queue_free()
    _tabs.add_child(UiTheme.label("Laying out:", 13))
    for name in ["card", "board"]:
        var here := String(name) == _mode
        var hint := "The face of a card." if name == "card" \
            else "The board a match is played on."
        var b := UiTheme.primary_button(String(name).capitalize(), hint) if here \
            else UiTheme.button(String(name).capitalize(), hint)
        b.pressed.connect(func(): _set_mode(String(name)))
        _tabs.add_child(b)


## Show one of the two things, and give the preview the width it needs for it:
## a card is tall and narrow, a board is wide.
func _set_mode(mode: String) -> void:
    _mode = mode
    _card_column.visible = mode == "card"
    _board_column.visible = mode == "board"
    _fill_tabs()
    if _stack_panel_box != null:
        _stack_panel_box.visible = mode == "card"
    if _rect_box != null:
        _rect_box.visible = mode == "card"
    for group in _number_boxes:
        var want := (String(group) == BOARD) == (mode == "board")
        for node in _number_boxes[group]:
            (node as Control).visible = want
    var column := _card_column.get_parent() as Control
    if mode == "card":
        column.custom_minimum_size = Vector2(PREVIEW_W + 40, 0)
        column.size_flags_stretch_ratio = 0.9
        _controls_column.size_flags_stretch_ratio = 1.6
    else:
        column.custom_minimum_size = Vector2(520, 0)
        column.size_flags_stretch_ratio = 1.7
        _controls_column.size_flags_stretch_ratio = 1.0
    _rebuild_all()


func _build_card_preview() -> Control:
    var column := UiTheme.vbox(8)

    var picker := UiTheme.hbox(8)
    picker.add_child(UiTheme.label("Previewing:", 13))
    var prev := UiTheme.button("<", "The previous card with a painted frame.")
    prev.pressed.connect(func(): _step_card(-1))
    picker.add_child(prev)
    _card_label = UiTheme.label("", 13, UiTheme.GOLD)
    picker.add_child(_card_label)
    var next := UiTheme.button(">", "The next card with a painted frame.")
    next.pressed.connect(func(): _step_card(1))
    picker.add_child(next)
    column.add_child(picker)

    _preview_holder = Control.new()
    _preview_holder.custom_minimum_size = Vector2(PREVIEW_W,
        PREVIEW_W * CardView.BASE_HEIGHT / CardView.BASE_WIDTH)
    column.add_child(_preview_holder)

    column.add_child(UiTheme.wrapped(
        "Drag inside a box to move it, or the square at its corner to resize it. "
        + "The arrow keys nudge the selected box, and holding Shift makes them "
        + "resize instead.", 11, UiTheme.TEXT_DIM))
    return column


var _card_label: Label


# -------------------------------------------------------------------- board ---

## The board, at the size a match draws it, with a bar on every edge that a
## number controls.
##
## The zones are built from the same numbers the battle screen reads and are
## filled with real cards, so what is dragged here is the size a player gets.
## Everything is one pixel to one pixel: no scaling to reason about.
func _build_board_preview() -> Control:
    var column := UiTheme.vbox(6)
    column.size_flags_vertical = Control.SIZE_EXPAND_FILL
    column.add_child(UiTheme.wrapped(
        "Drag a gold bar to resize what it sits against: the bars across the "
        + "board set the heights of its rows, and the upright bars set the width "
        + "of the Location plate and of the cards. Every number is also typed "
        + "on the right.", 11, UiTheme.TEXT_DIM))
    _board_holder = UiTheme.vbox(0)
    _board_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
    var scroll := UiTheme.scroll(_board_holder)
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    column.add_child(scroll)
    return column


func _rebuild_board() -> void:
    if _board_holder == null:
        return
    for c in _board_holder.get_children():
        _board_holder.remove_child(c)
        c.queue_free()
    _board_rows = {}
    # Every bar sits under the zone it resizes, so dragging it down makes that
    # zone taller. Both Companion Zones are one number and both deck rows are
    # another, so either bar moves both.
    _board_holder.add_child(_pv_zone(1))
    _board_holder.add_child(_grab("companion_strip_h", "v", 1.0,
        "the Companion Zones"))
    _board_holder.add_child(_pv_decks(1))
    _board_holder.add_child(_grab("deck_plate_h", "v", 1.0, "the deck plates"))
    _board_holder.add_child(_pv_middle())
    _board_holder.add_child(_grab("middle_h", "v", 1.0,
        "the Action Sequence and Location row"))
    _board_holder.add_child(_pv_decks(0))
    _board_holder.add_child(_grab("deck_plate_h", "v", 1.0, "the deck plates"))
    _board_holder.add_child(_pv_zone(0))
    _board_holder.add_child(_grab("companion_strip_h", "v", 1.0,
        "the Companion Zones"))
    _board_holder.add_child(_pv_hand())
    _board_holder.add_child(_grab("hand_strip_h", "v", 1.0, "the hand strip"))


## Remember a control whose minimum size follows a number, and how, so a drag
## can move it without rebuilding the board on every pixel.
##
## `role` says what the number means for this control: "h" its height, "h4" its
## height plus the row's own margin, "plate" a height with the plate's painted
## proportions kept, "w" its width, "card" a card's width, and "card_in_plate"
## a card sized to fit inside a plate of that height.
func _follows(key: String, c: Control, role: String) -> Control:
    if not _board_rows.has(key):
        _board_rows[key] = []
    (_board_rows[key] as Array).append({"node": c, "role": role,
        "aspect": 1.0 if c.custom_minimum_size.y <= 0.0
            else c.custom_minimum_size.x / c.custom_minimum_size.y})
    return c


func _pv_zone(player: int) -> Control:
    var zone := PanelContainer.new()
    var v := BoardArt.back(zone, "panel_companion", UiTheme.GOLD, 2)
    v.add_child(BoardArt.caption(
        "Your Companion Zone" if player == 0 else "Opponent's Companion Zone", 10))
    var row := UiTheme.hbox(6)
    row.alignment = BoxContainer.ALIGNMENT_CENTER
    row.custom_minimum_size = Vector2(0, Layout.num(BOARD, "companion_strip_h"))
    _follows("companion_strip_h", row, "h")
    for i in 2:
        row.add_child(_pv_card("companion", "board_card_w"))
    row.add_child(_grab("board_card_w", "h", 1.0, "a card standing on the board"))
    v.add_child(row)
    return zone


func _pv_decks(player: int) -> Control:
    var row := UiTheme.hbox(6)
    row.alignment = BoxContainer.ALIGNMENT_CENTER
    var h := Layout.num(BOARD, "deck_plate_h")
    row.custom_minimum_size = Vector2(0, h + 4.0)
    _follows("deck_plate_h", row, "h4")
    var order: Array = ["hit", "hero", "exhaust", "wound"]
    if player == 1:
        order.reverse()
    for kind in order:
        if String(kind) == "hero":
            row.add_child(_pv_card("hero", "deck_plate_h", true))
            continue
        var plate := PanelContainer.new()
        var pv := BoardArt.back(plate, "deck_" + String(kind), UiTheme.GOLD_DIM, 1)
        plate.custom_minimum_size = Vector2(
            h * float(BoardArt.PILE_ASPECT.get(String(kind), 2.0)), h)
        plate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        _follows("deck_plate_h", plate, "plate")
        pv.add_child(UiTheme.label("0", 20, UiTheme.PARCHMENT, HORIZONTAL_ALIGNMENT_CENTER))
        row.add_child(plate)
    return row


func _pv_middle() -> Control:
    var row := UiTheme.hbox(6)
    row.custom_minimum_size = Vector2(0, Layout.num(BOARD, "middle_h"))
    _follows("middle_h", row, "h")

    var seq := PanelContainer.new()
    var sv := BoardArt.back(seq, "panel_sequence", UiTheme.GOLD, 2)
    seq.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var steps := UiTheme.hbox(6)
    for i in 3:
        steps.add_child(_pv_card("skill", "seq_card_w"))
    steps.add_child(_grab("seq_card_w", "h", 1.0, "a card in the Action Sequence"))
    sv.add_child(steps)
    row.add_child(seq)

    row.add_child(_grab("location_w", "h", -1.0, "the Location plate"))

    var loc := PanelContainer.new()
    var lv := BoardArt.back(loc, "panel_location", UiTheme.GOLD, 2)
    loc.custom_minimum_size = Vector2(Layout.num(BOARD, "location_w"), 0)
    _follows("location_w", loc, "w")
    lv.add_child(BoardArt.caption("Location", 10))
    lv.add_child(_pv_card("location", "board_card_w"))
    row.add_child(loc)
    return row


func _pv_hand() -> Control:
    var zone := PanelContainer.new()
    var v := BoardArt.back(zone, "panel_hand", UiTheme.GOLD, 2)
    var row := UiTheme.hbox(6)
    row.custom_minimum_size = Vector2(0, Layout.num(BOARD, "hand_strip_h"))
    _follows("hand_strip_h", row, "h")
    for i in 3:
        row.add_child(_pv_card("skill", "hand_card_w"))
    row.add_child(_grab("hand_card_w", "h", 1.0, "a card in your hand"))
    v.add_child(row)
    return zone


## A real card at whatever width the number being edited gives it.
func _pv_card(type: String, key: String, from_height: bool = false) -> Control:
    var width := Layout.num(BOARD, key)
    if from_height:
        width = minf(Layout.num(BOARD, "board_card_w"),
            width * CardView.BASE_WIDTH / CardView.BASE_HEIGHT)
    var def := _sample(type)
    var holder := Control.new()
    holder.custom_minimum_size = Vector2(width, width * CardView.BASE_HEIGHT / CardView.BASE_WIDTH)
    holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
    if from_height:
        _follows("deck_plate_h", holder, "card_in_plate")
    else:
        _follows(key, holder, "card")
    if def != null:
        var view := CardView.create(def, width)
        view.mouse_filter = Control.MOUSE_FILTER_IGNORE
        holder.add_child(view)
    return holder


## One card of a type, for the board to stand something real in its zones.
func _sample(type: String) -> CardDef:
    if _samples.has(type):
        return _samples[type]
    for d in app.catalog.all_defs():
        var card: CardDef = d
        if card.has_type(type):
            _samples[type] = card
            return card
    _samples[type] = null
    return null


var _samples: Dictionary = {}


## A bar that resizes what it sits against.
##
## The number it edits is in pixels, and so is the drag, so the bar moves with
## the pointer exactly. `sign` is which way the zone grows: a bar under a zone
## grows it downwards, a bar above one grows it upwards.
func _grab(key: String, axis: String, sign: float, what: String) -> Control:
    var bar := UiTheme.panel(Color(UiTheme.GOLD.r, UiTheme.GOLD.g, UiTheme.GOLD.b, 0.55),
        UiTheme.GOLD, 1, 2)
    if axis == "v":
        bar.custom_minimum_size = Vector2(0, 7)
        bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    else:
        bar.custom_minimum_size = Vector2(7, 0)
        bar.size_flags_vertical = Control.SIZE_EXPAND_FILL
    bar.mouse_filter = Control.MOUSE_FILTER_STOP
    bar.mouse_default_cursor_shape = Control.CURSOR_VSIZE if axis == "v" \
        else Control.CURSOR_HSIZE
    bar.tooltip_text = "Drag to resize %s (%s, now %d)" % [
        what, key.replace("_", " "), int(Layout.num(BOARD, key))]
    bar.gui_input.connect(func(e): _grab_input(e, key, axis, sign))
    return bar


func _grab_input(event: InputEvent, key: String, axis: String, sign: float) -> void:
    if not (event is InputEventMouseButton) \
            or (event as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
        return
    if (event as InputEventMouseButton).pressed:
        _grab_key = key
        _grab_axis = axis
        _grab_sign = sign
    accept_event()


## A drag that has started is followed here rather than on the bar itself: the
## bar moves as the zone resizes, and the pointer would soon be off it.
func _input(event: InputEvent) -> void:
    if _grab_key == "":
        return
    if event is InputEventMouseButton \
            and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
            and not (event as InputEventMouseButton).pressed:
        _grab_key = ""
        # The card faces are drawn at a fixed size, so they are only redrawn
        # once the drag is over rather than on every pixel of it.
        _rebuild_board()
        get_viewport().set_input_as_handled()
        return
    if not (event is InputEventMouseMotion):
        return
    # The pointer's own movement, added up as it goes, rather than measured
    # from where the press landed: the bar moves as the zone resizes, so where
    # it started is not where it is.
    var moved: Vector2 = (event as InputEventMouseMotion).relative
    var by: float = (moved.y if _grab_axis == "v" else moved.x) * _grab_sign
    Layout.set_num(BOARD, _grab_key, Layout.num(BOARD, _grab_key) + by)
    _apply_board_sizes()
    var spin = _spins.get("%s/%s" % [BOARD, _grab_key])
    if spin != null and is_instance_valid(spin):
        (spin as SpinBox).set_value_no_signal(Layout.num(BOARD, _grab_key))
    get_viewport().set_input_as_handled()


## Move every control that follows a board number to the number's new value,
## without rebuilding anything.
func _apply_board_sizes() -> void:
    var tall := CardView.BASE_HEIGHT / CardView.BASE_WIDTH
    for key in _board_rows:
        var value := Layout.num(BOARD, String(key))
        for entry in _board_rows[key]:
            var e: Dictionary = entry
            var node := e["node"] as Control
            if node == null or not is_instance_valid(node):
                continue
            match String(e["role"]):
                "h":
                    node.custom_minimum_size.y = value
                "h4":
                    node.custom_minimum_size.y = value + 4.0
                "plate":
                    node.custom_minimum_size = Vector2(value * float(e["aspect"]), value)
                "w":
                    node.custom_minimum_size.x = value
                "card":
                    node.custom_minimum_size = Vector2(value, value * tall)
                "card_in_plate":
                    var w := minf(Layout.num(BOARD, "board_card_w"), value / tall)
                    node.custom_minimum_size = Vector2(w, w * tall)


func _step_card(by: int) -> void:
    if _card_ids.is_empty():
        return
    _card_index = wrapi(_card_index + by, 0, _card_ids.size())
    _rebuild_all()


## Rebuild the previewed card and the boxes over it. The card is rebuilt rather
## than nudged because that is what the rest of the game does with it: if a
## value only looked right when applied by halves, it would not be right.
func _rebuild_card() -> void:
    for c in _preview_holder.get_children():
        _preview_holder.remove_child(c)
        c.queue_free()
    if _card_ids.is_empty():
        return
    var def := app.catalog.get_def(String(_card_ids[_card_index]))
    _card_label.text = def.name if def != null else "?"
    # Each frame has its own group of slots, so stepping to a card of another
    # type moves the editing to that frame's group.
    var group := CardView.frame_group(def)
    if group != "":
        _group = group
    if not Layout.keys_of(_group).has(_selected):
        _selected = String(Layout.keys_of(_group)[0])
    _card = CardView.create(def, PREVIEW_W)
    _card.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _preview_holder.add_child(_card)

    _overlay = Control.new()
    _overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
    _overlay.mouse_filter = Control.MOUSE_FILTER_PASS
    _preview_holder.add_child(_overlay)
    for key in Layout.keys_of(_group):
        _overlay.add_child(_box(String(key)))
    _refresh_fields()


func _box(key: String) -> Control:
    var r := Layout.rect(_group, key)
    var chosen := key == _selected
    var colour := UiTheme.GOLD if chosen else UiTheme.GOLD_DIM

    var holder := Control.new()
    holder.anchor_left = r.position.x
    holder.anchor_top = r.position.y
    holder.anchor_right = r.end.x
    holder.anchor_bottom = r.end.y
    holder.offset_left = 0
    holder.offset_top = 0
    holder.offset_right = 0
    holder.offset_bottom = 0
    holder.mouse_filter = Control.MOUSE_FILTER_STOP
    holder.tooltip_text = "%s — drag to move" % key

    var frame := UiTheme.panel(Color(colour.r, colour.g, colour.b, 0.14 if chosen else 0.05),
        colour, 2 if chosen else 1, 2)
    frame.set_anchors_preset(Control.PRESET_FULL_RECT)
    frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
    holder.add_child(frame)

    if chosen:
        var tag := UiTheme.label(key, 10, UiTheme.GOLD)
        tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
        tag.position = Vector2(2, -14)
        holder.add_child(tag)

        # The corner handle resizes; anywhere else in the box moves it.
        var grip := UiTheme.panel(UiTheme.GOLD, UiTheme.INK, 1, 2)
        grip.custom_minimum_size = Vector2(12, 12)
        grip.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
        grip.offset_left = -12
        grip.offset_top = -12
        grip.offset_right = 0
        grip.offset_bottom = 0
        grip.mouse_filter = Control.MOUSE_FILTER_STOP
        grip.tooltip_text = "Drag to resize %s" % key
        grip.gui_input.connect(func(e): _handle_input(e, key, "resize"))
        holder.add_child(grip)

    holder.gui_input.connect(func(e): _handle_input(e, key, "move"))
    return holder


func _handle_input(event: InputEvent, key: String, mode: String) -> void:
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
        if event.pressed:
            if _selected != key:
                _selected = key
                _rebuild_all()
                return
            _drag_mode = mode
            _drag_from = _preview_holder.get_local_mouse_position()
            _drag_rect = Layout.rect(_group, key)
        else:
            _drag_mode = ""
        accept_event()
    elif event is InputEventMouseMotion and _drag_mode != "":
        var size := _preview_holder.size
        if size.x <= 0.0 or size.y <= 0.0:
            return
        var moved: Vector2 = _preview_holder.get_local_mouse_position() - _drag_from
        var by := Vector2(moved.x / size.x, moved.y / size.y)
        var r := _drag_rect
        if _drag_mode == "move":
            r.position += by
        else:
            r.size += by
        _apply(key, r)
        accept_event()


## Keep a box on the card and big enough to see, whatever the drag asked for.
func _apply(key: String, r: Rect2) -> void:
    r.size.x = clampf(r.size.x, 0.02, 1.0)
    r.size.y = clampf(r.size.y, 0.01, 1.0)
    r.position.x = clampf(r.position.x, 0.0, 1.0 - r.size.x)
    r.position.y = clampf(r.position.y, 0.0, 1.0 - r.size.y)
    Layout.set_rect(_group, key, r)
    _rebuild_card()


func _unhandled_key_input(event: InputEvent) -> void:
    if not (event is InputEventKey) or not event.pressed:
        return
    var by := Vector2.ZERO
    match (event as InputEventKey).keycode:
        KEY_LEFT: by = Vector2(-NUDGE, 0)
        KEY_RIGHT: by = Vector2(NUDGE, 0)
        KEY_UP: by = Vector2(0, -NUDGE)
        KEY_DOWN: by = Vector2(0, NUDGE)
        _: return
    var r := Layout.rect(_group, _selected)
    if (event as InputEventKey).shift_pressed:
        r.size += by
    else:
        r.position += by
    _apply(_selected, r)
    accept_event()


# ----------------------------------------------------------------- controls ---

func _build_controls() -> Control:
    var column := UiTheme.vbox(8)
    column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    column.add_child(UiTheme.heading("Layout"))
    column.add_child(UiTheme.wrapped(
        "Positions, sizes and stacking order the interface reads. Saving writes "
        + "them to data/layout.json, which the game loads at launch. That file is "
        + "part of the project, so committing it is what carries a change to "
        + "everyone else — until then it is only on this machine.",
        12, UiTheme.TEXT_DIM))
    _status = UiTheme.wrapped("In force: %s" % Layout.source, 11, UiTheme.TEXT_DIM)
    column.add_child(_status)

    var scroll_box := UiTheme.vbox(10)
    _stack_box = UiTheme.vbox(4)
    _stack_panel_box = _stack_panel()
    scroll_box.add_child(_stack_panel_box)
    # Filled from the previewed card's own group, so stepping from a Hero to a
    # Skill lists that frame's slots rather than the Hero's.
    _rect_box = UiTheme.vbox(6)
    scroll_box.add_child(_rect_box)
    scroll_box.add_child(UiTheme.separator())
    _number_boxes = {}
    for group in Layout.number_groups():
        var heading := UiTheme.label(_group_title(String(group)), 14, UiTheme.GOLD)
        scroll_box.add_child(heading)
        var box := UiTheme.vbox(4)
        for key in Layout.keys_of(String(group)):
            box.add_child(_number_row(String(group), String(key)))
        scroll_box.add_child(box)
        _number_boxes[String(group)] = [heading, box]
    var scroll := UiTheme.scroll(scroll_box)
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    column.add_child(scroll)

    var buttons := UiTheme.hbox(8)
    var save := UiTheme.primary_button("Save layout",
        "Writes data/layout.json. The game reads it at launch.")
    save.pressed.connect(_save)
    buttons.add_child(save)
    var reload := UiTheme.button("Reload saved", "Discards changes not yet saved.")
    reload.pressed.connect(func():
        Layout.load_saved()
        _rebuild_all()
        _status.text = "Reloaded. In force: %s" % Layout.source)
    buttons.add_child(reload)
    var reset := UiTheme.button("Reset all", "Back to the values the game shipped with.")
    reset.pressed.connect(func():
        Layout.reset_all()
        _rebuild_all()
        _status.text = "Reset to the shipped values. Save to keep them.")
    buttons.add_child(reset)
    var copy := UiTheme.button("Copy as code", "Puts the values on the clipboard as GDScript.")
    copy.pressed.connect(func():
        DisplayServer.clipboard_set(Layout.as_code())
        app.toast("The layout is on the clipboard as GDScript."))
    buttons.add_child(copy)
    column.add_child(buttons)
    return column


var _stack_box: VBoxContainer
var _rect_box: VBoxContainer
## group -> [heading, rows], so the list on the right shows what is being laid
## out rather than everything at once.
var _number_boxes: Dictionary = {}
var _stack_panel_box: Control


## The pieces of a card, front to back, with the frame among them: art moved
## behind the frame is drawn behind it and shows through what it leaves open.
func _stack_panel() -> Control:
    var p := UiTheme.panel(UiTheme.BG_PANEL, UiTheme.GOLD_DIM, 1, 4)
    var v := UiTheme.vbox(4)
    var head := UiTheme.hbox(8)
    head.add_child(UiTheme.label("Stacking order — front at the top", 14, UiTheme.GOLD))
    if Layout.layers_changed(_group):
        head.add_child(UiTheme.label("changed", 10, UiTheme.GOLD))
    var gap := Control.new()
    gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    head.add_child(gap)
    var undo := UiTheme.button("Reset order")
    undo.pressed.connect(func():
        Layout.reset_layers(_group)
        _rebuild_all())
    head.add_child(undo)
    v.add_child(head)
    v.add_child(_stack_box)
    _fill_stack()
    p.add_child(v)
    return p


func _fill_stack() -> void:
    for c in _stack_box.get_children():
        _stack_box.remove_child(c)
        c.queue_free()
    var order := Layout.layer_order(_group)
    order.reverse()  # front first, the way a layers list reads
    for i in order.size():
        var key := String(order[i])
        var row := UiTheme.hbox(6)
        var chosen := key == _selected
        var name_btn := UiTheme.button("%s%s" % ["▸ " if chosen else "", key],
            "Select this piece.")
        name_btn.custom_minimum_size = Vector2(120, 0)
        name_btn.pressed.connect(func():
            _selected = key
            _rebuild_all())
        row.add_child(name_btn)

        var up := UiTheme.button("▲", "Bring forward, in front of the piece above.")
        up.disabled = i == 0
        up.pressed.connect(func():
            Layout.move_layer(_group, key, 1)
            _rebuild_all())
        row.add_child(up)
        var down := UiTheme.button("▼", "Send back, behind the piece below.")
        down.disabled = i == order.size() - 1
        down.pressed.connect(func():
            Layout.move_layer(_group, key, -1)
            _rebuild_all())
        row.add_child(down)

        var note := UiTheme.label(String(Layout.LAYER_LABELS.get(key, "")), 11, UiTheme.TEXT_DIM)
        note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        note.clip_text = true
        row.add_child(note)
        _stack_box.add_child(row)


## The stack and the boxes both describe the same card, so a change to either
## rebuilds both.
func _rebuild_all() -> void:
    if _mode == "board":
        _rebuild_board()
    else:
        _rebuild_card()
    _fill_rects()
    _fill_stack()


func _fill_rects() -> void:
    if _rect_box == null:
        return
    for c in _rect_box.get_children():
        _rect_box.remove_child(c)
        c.queue_free()
    _fields.clear()
    for key in Layout.keys_of(_group):
        _rect_box.add_child(_rect_row(String(key)))


func _group_title(group: String) -> String:
    return group.replace("_", " ").capitalize()


func _rect_row(key: String) -> Control:
    var p := UiTheme.panel(UiTheme.BG_PANEL,
        UiTheme.GOLD if key == _selected else UiTheme.GOLD_DIM, 1, 4)
    var v := UiTheme.vbox(4)
    var head := UiTheme.hbox(8)
    var pick := UiTheme.button(key, "Select this box on the card.")
    pick.pressed.connect(func():
        _selected = key
        _rebuild_all())
    head.add_child(pick)
    if Layout.is_changed(_group, key):
        head.add_child(UiTheme.label("changed", 10, UiTheme.GOLD))
    var gap := Control.new()
    gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    head.add_child(gap)
    var undo := UiTheme.button("Reset")
    undo.pressed.connect(func():
        Layout.reset(_group, key)
        _rebuild_card())
    head.add_child(undo)
    v.add_child(head)

    var row := UiTheme.hbox(4)
    var r := Layout.rect(_group, key)
    for part in [["x", r.position.x], ["y", r.position.y], ["w", r.size.x], ["h", r.size.y]]:
        row.add_child(UiTheme.label(String(part[0]), 11, UiTheme.TEXT_DIM))
        var edit := LineEdit.new()
        edit.text = "%.3f" % float(part[1])
        edit.custom_minimum_size = Vector2(62, 0)
        edit.add_theme_font_size_override("font_size", 12)
        var which := String(part[0])
        edit.text_submitted.connect(func(t): _set_part(key, which, t))
        edit.focus_exited.connect(func(): _set_part(key, which, edit.text))
        row.add_child(edit)
        _fields["%s_%s" % [key, which]] = edit
    v.add_child(row)
    p.add_child(v)
    return p


func _set_part(key: String, part: String, text: String) -> void:
    if not text.is_valid_float():
        return
    var r := Layout.rect(_group, key)
    match part:
        "x": r.position.x = float(text)
        "y": r.position.y = float(text)
        "w": r.size.x = float(text)
        "h": r.size.y = float(text)
    _apply(key, r)


func _number_row(group: String, key: String) -> Control:
    var row := UiTheme.hbox(8)
    var label := UiTheme.label(key.replace("_", " "), 12)
    label.custom_minimum_size = Vector2(170, 0)
    row.add_child(label)

    var bounds := Layout.limits(group, key)
    var spin := SpinBox.new()
    spin.min_value = bounds.x
    spin.max_value = bounds.y
    spin.step = 1.0
    spin.value = Layout.num(group, key)
    spin.custom_minimum_size = Vector2(110, 0)
    _spins["%s/%s" % [group, key]] = spin
    spin.value_changed.connect(func(v):
        Layout.set_num(group, key, v)
        _after_number(group))
    row.add_child(spin)

    var undo := UiTheme.button("Reset")
    undo.pressed.connect(func():
        Layout.reset(group, key)
        spin.set_value_no_signal(Layout.num(group, key))
        _after_number(group))
    row.add_child(undo)

    var note := UiTheme.wrapped(Layout.describe(group, key), 11, UiTheme.TEXT_DIM)
    note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(note)
    return row


## A board number changes the board; a card number changes the card. Either
## way only the one being looked at is rebuilt.
func _after_number(group: String) -> void:
    if group == BOARD:
        _rebuild_board()
    else:
        _rebuild_card()


func _refresh_fields() -> void:
    for key in Layout.keys_of(_group):
        var r := Layout.rect(_group, String(key))
        for part in [["x", r.position.x], ["y", r.position.y], ["w", r.size.x], ["h", r.size.y]]:
            var edit = _fields.get("%s_%s" % [key, String(part[0])])
            if edit is LineEdit and not (edit as LineEdit).has_focus():
                (edit as LineEdit).text = "%.3f" % float(part[1])


func _save() -> void:
    var r := Layout.save()
    if not bool(r.get("ok", false)):
        app.toast(String(r.get("error", "Could not save the layout.")), true)
        return
    if bool(r.get("in_project", false)):
        _status.text = ("Saved to %s. It is in force here now; commit that file to "
            + "carry the change to anyone else.") % String(r["path"])
    else:
        _status.text = ("Saved to %s. This build cannot write to the project, so the "
            + "layout went beside the save files and applies only on this machine.") \
            % String(r["path"])
    app.toast("Layout saved.")
