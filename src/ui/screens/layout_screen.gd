extends Control

## Move the pieces of a card, and the metrics of the board, by eye.
##
## Everything here edits `Layout`, which the interface reads. The card preview
## is a real CardView, not a mock, so what is dragged is exactly what a player
## sees. Saving writes `data/layout.json`, which is repository content when the
## game is running from source: the change is a real change to the game, not a
## setting that lives only on this machine.

var app: App

const GROUP := "hero_card"
## The size the preview card is drawn at. Large enough to place a footer line.
const PREVIEW_W := 460.0
## How far a nudge moves a slot, as a fraction of the card.
const NUDGE := 0.002

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


func setup(application: App, _args: Dictionary = {}) -> void:
    app = application
    for d in app.catalog.all_defs():
        if (d as CardDef).has_type("hero"):
            _card_ids.append((d as CardDef).id)
    _card_ids.sort()

    var root := UiTheme.hbox(12)
    root.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(root)
    root.add_child(_build_preview())
    root.add_child(_build_controls())
    _rebuild_card()


# ------------------------------------------------------------------ preview ---

func _build_preview() -> Control:
    var column := UiTheme.vbox(8)
    column.custom_minimum_size = Vector2(PREVIEW_W + 40, 0)

    var picker := UiTheme.hbox(8)
    picker.add_child(UiTheme.label("Previewing:", 13))
    var prev := UiTheme.button("<", "The previous Hero.")
    prev.pressed.connect(func(): _step_card(-1))
    picker.add_child(prev)
    _card_label = UiTheme.label("", 13, UiTheme.GOLD)
    picker.add_child(_card_label)
    var next := UiTheme.button(">", "The next Hero.")
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


func _step_card(by: int) -> void:
    if _card_ids.is_empty():
        return
    _card_index = wrapi(_card_index + by, 0, _card_ids.size())
    _rebuild_card()


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
    _card = CardView.create(def, PREVIEW_W)
    _card.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _preview_holder.add_child(_card)

    _overlay = Control.new()
    _overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
    _overlay.mouse_filter = Control.MOUSE_FILTER_PASS
    _preview_holder.add_child(_overlay)
    for key in Layout.keys_of(GROUP):
        _overlay.add_child(_box(String(key)))
    _refresh_fields()


func _box(key: String) -> Control:
    var r := Layout.rect(GROUP, key)
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
            _drag_rect = Layout.rect(GROUP, key)
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
    Layout.set_rect(GROUP, key, r)
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
    var r := Layout.rect(GROUP, _selected)
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
    scroll_box.add_child(_stack_panel())
    for key in Layout.keys_of(GROUP):
        scroll_box.add_child(_rect_row(String(key)))
    scroll_box.add_child(UiTheme.separator())
    for group in Layout.number_groups():
        scroll_box.add_child(UiTheme.label(_group_title(String(group)), 14, UiTheme.GOLD))
        for key in Layout.keys_of(String(group)):
            scroll_box.add_child(_number_row(String(group), String(key)))
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


## The pieces of a card, front to back, with the frame among them: art moved
## behind the frame is drawn behind it and shows through what it leaves open.
func _stack_panel() -> Control:
    var p := UiTheme.panel(UiTheme.BG_PANEL, UiTheme.GOLD_DIM, 1, 4)
    var v := UiTheme.vbox(4)
    var head := UiTheme.hbox(8)
    head.add_child(UiTheme.label("Stacking order — front at the top", 14, UiTheme.GOLD))
    if Layout.layers_changed(GROUP):
        head.add_child(UiTheme.label("changed", 10, UiTheme.GOLD))
    var gap := Control.new()
    gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    head.add_child(gap)
    var undo := UiTheme.button("Reset order")
    undo.pressed.connect(func():
        Layout.reset_layers(GROUP)
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
    var order := Layout.layer_order(GROUP)
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
            Layout.move_layer(GROUP, key, 1)
            _rebuild_all())
        row.add_child(up)
        var down := UiTheme.button("▼", "Send back, behind the piece below.")
        down.disabled = i == order.size() - 1
        down.pressed.connect(func():
            Layout.move_layer(GROUP, key, -1)
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
    _rebuild_card()
    _fill_stack()


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
    if Layout.is_changed(GROUP, key):
        head.add_child(UiTheme.label("changed", 10, UiTheme.GOLD))
    var gap := Control.new()
    gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    head.add_child(gap)
    var undo := UiTheme.button("Reset")
    undo.pressed.connect(func():
        Layout.reset(GROUP, key)
        _rebuild_card())
    head.add_child(undo)
    v.add_child(head)

    var row := UiTheme.hbox(4)
    var r := Layout.rect(GROUP, key)
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
    var r := Layout.rect(GROUP, key)
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
    spin.value_changed.connect(func(v):
        Layout.set_num(group, key, v)
        _rebuild_card())
    row.add_child(spin)

    var undo := UiTheme.button("Reset")
    undo.pressed.connect(func():
        Layout.reset(group, key)
        spin.value = Layout.num(group, key)
        _rebuild_card())
    row.add_child(undo)

    var note := UiTheme.wrapped(Layout.describe(group, key), 11, UiTheme.TEXT_DIM)
    note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(note)
    return row


func _refresh_fields() -> void:
    for key in Layout.keys_of(GROUP):
        var r := Layout.rect(GROUP, String(key))
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
