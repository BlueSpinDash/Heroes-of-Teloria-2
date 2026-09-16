class_name CardView
extends PanelContainer

## One card face, following the established template direction:
## type banner at the top, Energy bubble at the upper left of the portrait,
## Attack and Defense bubbles for characters, art in the middle, name banner
## below the art, rules text below that, Affinity centred along the bottom.
##
## Cost, stats and rules text are always real controls. The art is decoration
## and never the only place a number appears.

signal pressed(def_id: String)

## Set by the battle screen to make this card draggable. Null leaves it
## click-only, which every card also remains.
var drag_payload = null

## Standard trading-card proportions: 2.5 by 3.5 inches, so 5:7.
const BASE_WIDTH := 300.0
const BASE_HEIGHT := 420.0
## How much of the foot of a card a badge covers.
const BADGE_H := 22.0

## Painted frames, by the card type they belong to. A card of a type with a
## frame is drawn on it, with every live value placed over the region the
## template painted for it, instead of being laid out from scratch.
const FRAMES := {"hero": "res://assets/frames/hero_frame.png"}

## Where each live value sits on the Hero frame. These are editable: the Layout
## screen moves them and writes them back to `data/layout.json`.
static func slot(key: String) -> Rect2:
    return Layout.rect("hero_card", key)



var def: CardDef = null
var card_width: float = BASE_WIDTH
var clickable: bool = false
var _badge_row: HBoxContainer = null


static func create(card: CardDef, width: float = BASE_WIDTH, can_click: bool = false) -> CardView:
    var v := CardView.new()
    v.card_width = width
    v.clickable = can_click
    v.set_card(card)
    return v


func set_card(card: CardDef) -> void:
    def = card
    for c in get_children():
        c.queue_free()
    if def == null:
        return
    var frame := _frame_for(def)
    if frame != "":
        _build_framed(frame)
    else:
        _build()


## The painted frame this card is drawn on, or "" for the plain face.
##
## A card can opt out with `"frame": "plain"` in its data, which is how a card
## that was finished before its type had a frame keeps the look it shipped
## with.
static func _frame_for(card: CardDef) -> String:
    if card.frame == "plain":
        return ""
    for type in FRAMES:
        if card.has_type(String(type)):
            var path := String(FRAMES[type])
            if ResourceLoader.exists(path):
                return path
    return ""


## Draw the card on its painted frame.
##
## The frame carries everything that is the same on every card of its type —
## the type banner, the stat captions, the ornament — so all this adds is the
## values that differ, each anchored over the region the template painted for
## it. Anchors are fractions of the card, so the whole face scales together.
func _build_framed(frame_path: String) -> void:
    var scale_factor := card_width / BASE_WIDTH
    custom_minimum_size = Vector2(card_width, BASE_HEIGHT * scale_factor)
    size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    clip_contents = true
    mouse_filter = Control.MOUSE_FILTER_STOP if clickable else Control.MOUSE_FILTER_PASS
    tooltip_text = "%s — %s" % [def.name, def.text if def.text != "" else "No rules text."]

    var blank := UiTheme.panel_style(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0)
    blank.content_margin_left = 0
    blank.content_margin_right = 0
    blank.content_margin_top = 0
    blank.content_margin_bottom = 0
    add_theme_stylebox_override("panel", blank)

    var frame := TextureRect.new()
    frame.texture = load(frame_path)
    frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    frame.stretch_mode = TextureRect.STRETCH_SCALE
    frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(frame)

    var layer := Control.new()
    layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(layer)

    # Real art covers the window. A card with none keeps the silhouette the
    # template painted there, which is a better placeholder than a sigil.
    if ArtLibrary.texture_for(def.art) != null:
        var art := CardArt.new()
        art.setup(def.art)
        art.mouse_filter = Control.MOUSE_FILTER_IGNORE
        _anchor(art, slot("art"))
        layer.add_child(art)

    layer.add_child(_slot(str(def.hero_max_energy), slot("energy"),
        int(Layout.num("card_text", "stat_size") * scale_factor), Color.WHITE, true))
    layer.add_child(_slot(str(def.attack), slot("attack"),
        int(Layout.num("card_text", "stat_size") * scale_factor), Color.WHITE, true))
    layer.add_child(_slot(str(def.defense), slot("defense"),
        int(Layout.num("card_text", "stat_size") * scale_factor), Color.WHITE, true))
    # The name banner is a fixed painted width, so the name is set to fit it
    # rather than clipped: a Hero's name is the one thing on the card that
    # must always read in full.
    var name_slot: Rect2 = slot("name")
    layer.add_child(_slot(def.name, name_slot,
        _fit_font_size(def.name, int(Layout.num("card_text", "name_size") * scale_factor),
            name_slot.size.x * card_width),
        UiTheme.INK))
    # The banner and the footer lines are small painted spaces, so they carry
    # the short form: the Affinity, the card's id, its rarity. The rest of what
    # a card is stays in its tooltip and in the collection.
    # The Affinity ribbon is small and bronze, so its word is set in the
    # Affinity's own colour and outlined, the way the stat numbers are.
    var small := int(Layout.num("card_text", "small_size") * scale_factor)
    layer.add_child(_slot(UiTheme.affinity_line(def).to_upper(), slot("affinity"),
        small, UiTheme.affinity_color(
            String(def.affinities[0]) if not def.affinities.is_empty() else "neutral"
        ).lightened(0.45), true))
    layer.add_child(_slot(def.id, slot("set"), small,
        UiTheme.PARCHMENT_DARK))
    layer.add_child(_slot(UiTheme.rarity_line(def), slot("rarity"),
        small, UiTheme.RARITY_COLOR.get(def.rarity, UiTheme.PARCHMENT_DARK)))

    # The rules panel takes the meta line and the rules text together, the way
    # the plain face does, so nothing a card says is left off the frame. The
    # panel is a fixed painted space, so a long rule is set smaller to fit it
    # rather than running off the bottom of the card.
    var rules_slot: Rect2 = slot("rules")
    var rules_w := rules_slot.size.x * card_width
    var rules_h := rules_slot.size.y * card_width * BASE_HEIGHT / BASE_WIDTH
    var rules := UiTheme.vbox(int(2 * scale_factor))
    rules.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var meta := _meta_line()
    var meta_size := int(Layout.num("card_text", "meta_size") * scale_factor)
    if meta != "":
        var meta_label := UiTheme.wrapped(meta, meta_size, UiTheme.PARCHMENT_DARK.darkened(0.55))
        meta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        rules.add_child(meta_label)
        rules_h -= _wrapped_height(meta, meta_size, rules_w) + 2.0 * scale_factor
    var body_text := def.text if def.text.strip_edges() != "" else "No rules text."
    var body_label := UiTheme.wrapped(body_text,
        _fit_wrapped_font_size(body_text,
            int(Layout.num("card_text", "rules_size") * scale_factor), rules_w, rules_h), UiTheme.INK)
    body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    body_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
    rules.add_child(body_label)
    _anchor(rules, slot("rules"))
    layer.add_child(rules)

    _add_badge_layer(scale_factor)


## One value, centred over the region the template painted for it.
func _slot(text: String, where: Rect2, font_size: int, colour: Color,
        outlined: bool = false) -> Label:
    var l := UiTheme.label(text, font_size, colour, HORIZONTAL_ALIGNMENT_CENTER)
    l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    l.clip_text = true
    l.mouse_filter = Control.MOUSE_FILTER_IGNORE
    if outlined:
        # A number sits on cut stone, which is busy: an outline keeps it read.
        l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
        l.add_theme_constant_override("outline_size", maxi(2, int(font_size / 6)))
    _anchor(l, where)
    return l


## The largest size at or below `base` at which `text` fits across `width`.
##
## Measured with the font the label itself will use, so the answer holds
## whatever theme is in force.
func _fit_font_size(text: String, base: int, width: float, floor_size: int = 8) -> int:
    var font := get_theme_font("font", "Label")
    if font == null:
        font = ThemeDB.fallback_font
    if font == null or text == "" or width <= 0.0:
        return base
    var size := base
    while size > floor_size and font.get_string_size(
            text, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.fs(size)).x > width:
        size -= 1
    return size


## How tall `text` is when wrapped to `width` at `size`.
func _wrapped_height(text: String, size: int, width: float) -> float:
    var font := get_theme_font("font", "Label")
    if font == null:
        font = ThemeDB.fallback_font
    if font == null or text == "" or width <= 0.0:
        return 0.0
    return font.get_multiline_string_size(
        text, HORIZONTAL_ALIGNMENT_CENTER, width, UiTheme.fs(size)).y


## The largest size at or below `base` at which `text`, wrapped to `width`,
## fits inside `height`.
func _fit_wrapped_font_size(text: String, base: int, width: float, height: float,
        floor_size: int = 6) -> int:
    if height <= 0.0:
        return base
    var size := base
    while size > floor_size and _wrapped_height(text, size, width) > height:
        size -= 1
    return size


static func _anchor(c: Control, where: Rect2) -> void:
    c.anchor_left = where.position.x
    c.anchor_top = where.position.y
    c.anchor_right = where.end.x
    c.anchor_bottom = where.end.y
    c.offset_left = 0.0
    c.offset_top = 0.0
    c.offset_right = 0.0
    c.offset_bottom = 0.0


func _build() -> void:
    var scale_factor := card_width / BASE_WIDTH
    custom_minimum_size = Vector2(card_width, BASE_HEIGHT * scale_factor)
    size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    clip_contents = true
    mouse_filter = Control.MOUSE_FILTER_STOP if clickable else Control.MOUSE_FILTER_PASS
    tooltip_text = "%s — %s" % [def.name, def.text if def.text != "" else "No rules text."]

    var frame := UiTheme.frame_color(def)
    add_theme_stylebox_override("panel", UiTheme.panel_style(frame, UiTheme.GOLD, 2, 8))

    # The face is laid out inside a plain Control rather than directly in the
    # PanelContainer, so its contents cannot push the card taller than the
    # trading-card ratio. Anything that will not fit is clipped, and the card's
    # tooltip still carries the full rules text.
    var face := Control.new()
    face.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(face)
    var root := UiTheme.vbox(int(4 * scale_factor))
    root.set_anchors_preset(Control.PRESET_FULL_RECT)
    face.add_child(root)

    root.add_child(_banner(UiTheme.type_banner(def), int(14 * scale_factor)))

    # --- stat bubbles in a left gutter, portrait to their right --------------
    # The template runs the Energy, Attack and Defense bubbles down the left of
    # the card rather than over the artwork, so they get their own column here
    # and never sit on top of a character's face.
    var art_row := UiTheme.hbox(int(4 * scale_factor))
    art_row.custom_minimum_size = Vector2(0, 168 * scale_factor)
    art_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    root.add_child(art_row)

    var bubbles := UiTheme.vbox(int(4 * scale_factor))
    bubbles.custom_minimum_size = Vector2(50 * scale_factor, 0)
    bubbles.mouse_filter = Control.MOUSE_FILTER_IGNORE
    art_row.add_child(bubbles)

    var art_holder := Control.new()
    art_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    art_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
    art_row.add_child(art_holder)

    var art := CardArt.new()
    art.setup(def.art)
    art.set_anchors_preset(Control.PRESET_FULL_RECT)
    art.mouse_filter = Control.MOUSE_FILTER_IGNORE
    art_holder.add_child(art)

    var energy_caption := "Max Energy" if def.has_type("hero") else "Energy"
    var energy_value := str(def.hero_max_energy) if def.has_type("hero") else UiTheme.cost_text(def)
    bubbles.add_child(_bubble(energy_value, energy_caption, UiTheme.ENERGY, scale_factor))

    # Skills never display Attack/Defense; characters always do; Equipment
    # shows its printed modifiers when it has any.
    if def.is_character():
        bubbles.add_child(_bubble(str(def.attack), "Attack", UiTheme.ATTACK, scale_factor))
        bubbles.add_child(_bubble(str(def.defense), "Defense", UiTheme.DEFENSE, scale_factor))
    elif def.has_type("equipment") and (def.attack != 0 or def.defense != 0):
        if def.attack != 0:
            bubbles.add_child(_bubble("%+d" % def.attack, "Attack", UiTheme.ATTACK, scale_factor))
        if def.defense != 0:
            bubbles.add_child(_bubble("%+d" % def.defense, "Defense", UiTheme.DEFENSE, scale_factor))

    # --- name banner ---------------------------------------------------------
    root.add_child(_banner(def.name, int(17 * scale_factor), true))

    # --- rules text ----------------------------------------------------------
    var text_panel := UiTheme.panel(UiTheme.PARCHMENT, UiTheme.GOLD_DIM, 1, 4)
    text_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
    var text_box := UiTheme.vbox(int(2 * scale_factor))
    var meta := _meta_line()
    if meta != "":
        var meta_label := UiTheme.wrapped(meta, int(11 * scale_factor), UiTheme.GOLD_DIM)
        meta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        text_box.add_child(meta_label)
    var body := def.text if def.text.strip_edges() != "" else "No rules text."
    var body_label := UiTheme.wrapped(body, int(13 * scale_factor), UiTheme.INK)
    body_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    body_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
    text_box.add_child(body_label)
    text_panel.add_child(text_box)
    root.add_child(text_panel)

    # --- Affinity, centred along the bottom ---------------------------------
    var aff_row := UiTheme.hbox(6)
    aff_row.alignment = BoxContainer.ALIGNMENT_CENTER
    var aff_colour := UiTheme.affinity_color(
        String(def.affinities[0]) if not def.affinities.is_empty() else "neutral")
    aff_row.add_child(UiTheme.label(UiTheme.affinity_line(def), int(13 * scale_factor), aff_colour))
    root.add_child(aff_row)

    # --- footer --------------------------------------------------------------
    var footer := UiTheme.hbox(4)
    var id_label := UiTheme.label("%s%s" % ["" if def.authored else "PROXY • ", def.id],
        int(10 * scale_factor), UiTheme.PARCHMENT_DARK)
    id_label.clip_text = true
    footer.add_child(id_label)
    var gap := Control.new()
    gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    footer.add_child(gap)
    var restriction := ""
    if def.is_named_character():
        restriction = " • NAMED"
    elif def.unique:
        restriction = " • UNIQUE"
    var rarity_label := UiTheme.label(UiTheme.rarity_line(def) + restriction, int(10 * scale_factor),
        UiTheme.RARITY_COLOR.get(def.rarity, UiTheme.TEXT_DIM))
    rarity_label.clip_text = true
    footer.add_child(rarity_label)
    root.add_child(footer)

    _add_badge_layer(scale_factor)

    if clickable:
        # Every control inside the face is decoration. With them transparent to
        # the mouse, the card itself is what gets hovered, clicked and dragged,
        # rather than whichever label happens to be under the pointer.
        _ignore_mouse_below(self)
        mouse_filter = Control.MOUSE_FILTER_STOP
        gui_input.connect(_on_gui_input)


static func _ignore_mouse_below(node: Node) -> void:
    for child in node.get_children():
        if child is Control:
            (child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
        _ignore_mouse_below(child)


func _banner(text: String, font_size: int, big: bool = false) -> PanelContainer:
    var p := UiTheme.panel(UiTheme.PARCHMENT, UiTheme.GOLD, 1, 3)
    var l := UiTheme.label(text, font_size, UiTheme.INK, HORIZONTAL_ALIGNMENT_CENTER)
    l.clip_text = not big
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if big else TextServer.AUTOWRAP_OFF
    l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    # Never let long text push the card past the width it was created at.
    l.custom_minimum_size = Vector2(0, 0)
    l.clip_text = l.clip_text or not big
    p.add_child(l)
    return p


func _bubble(value: String, caption: String, colour: Color, scale_factor: float) -> Control:
    var holder := UiTheme.vbox(0)
    holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var circle := PanelContainer.new()
    circle.add_theme_stylebox_override("panel",
        UiTheme.panel_style(colour, UiTheme.GOLD, 2, int(18 * scale_factor)))
    circle.custom_minimum_size = Vector2(42 * scale_factor, 36 * scale_factor)
    var v := UiTheme.label(value, int(19 * scale_factor), Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
    v.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    circle.add_child(v)
    holder.add_child(circle)
    holder.add_child(UiTheme.label(caption.to_upper(), int(9 * scale_factor),
        UiTheme.PARCHMENT, HORIZONTAL_ALIGNMENT_CENTER))
    return holder


## The line of extra facts a card carries above its rules text: its tags, what
## an attack costs, what a Companion adds to maximum Energy.
func _meta_line() -> String:
    var meta: Array = []
    var tags := UiTheme.tag_line(def)
    if tags != "":
        meta.append(tags)
    if def.is_character() and def.attack_cost > 0:
        var attack_line := "Attack: %d Energy" % def.attack_cost
        if not def.attack_tags.is_empty():
            var at_bits: Array = []
            for at in def.attack_tags:
                at_bits.append(String(at).capitalize())
            attack_line += " — " + " • ".join(at_bits)
        meta.append(attack_line)
    if def.has_type("companion") and def.energy_contribution > 0:
        meta.append("+%d max Energy" % def.energy_contribution)
    return " • ".join(meta)


## Badges overlay the bottom of the face rather than adding a row below it, so
## a card keeps its trading-card proportions however many it carries.
func _add_badge_layer(_scale_factor: float) -> void:
    var badge_layer := Control.new()
    badge_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(badge_layer)
    _badge_row = UiTheme.hbox(4)
    _badge_row.alignment = BoxContainer.ALIGNMENT_CENTER
    _badge_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _badge_row.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
    # A fixed height, not a scaled one: a badge has to stay readable on a card
    # small enough to fit a hand, and a scaled band would be too short for its
    # own text and spill past the clipped edge of the face.
    _badge_row.offset_top = -BADGE_H
    _badge_row.offset_bottom = 0
    badge_layer.add_child(_badge_row)


## Extra badges under the card, such as owned counts or deck quantities.
func add_badge(text: String, colour: Color = UiTheme.GOLD) -> void:
    if _badge_row == null:
        return
    var p := UiTheme.panel(UiTheme.BG_PANEL, colour, 1, 3)
    var l := UiTheme.label(text, 10, colour, HORIZONTAL_ALIGNMENT_CENTER)
    # Clipped so a long badge cannot widen the card it sits on. The full text
    # is still available as the card's tooltip.
    l.clip_text = true
    l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    p.add_child(l)
    _badge_row.add_child(p)


func _get_drag_data(_at_position: Vector2) -> Variant:
    if drag_payload == null or def == null:
        return null
    var ghost := CardView.create(def, card_width * 0.8)
    ghost.modulate = Color(1, 1, 1, 0.85)
    set_drag_preview(ghost)
    return drag_payload


func _on_gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and not event.pressed \
            and event.button_index == MOUSE_BUTTON_LEFT:
        pressed.emit(def.id)
        accept_event()
