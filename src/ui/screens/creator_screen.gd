extends Control

## The card creator: make a card of your own, and let the card tell you what it
## costs.
##
## Nothing here is typed as free text except the name, the flavour and the art
## file. Everything that decides what the card does is picked from what the
## engine can actually perform, every choice has a price, and the printed
## Energy cost is what those prices add up to — so a card cannot be made
## cheaper than what is on it. The rules text is generated from the same
## structured data as every shipped card, and the result is validated by the
## same validator, so a created card can never promise something the engine
## will not do.
##
## The card editor next door changes cards that already exist. This one makes
## new ones, and they belong to this save.

var app: App

## The design being built. See `CardForge.blank_design`.
var _design: Dictionary = {}
## The id being edited, or "" while making a new card.
var _editing: String = ""

var _fields: VBoxContainer
var _features_box: VBoxContainer
var _preview_holder: VBoxContainer
var _ledger: VBoxContainer
var _messages: VBoxContainer
var _made_box: VBoxContainer
var _art_edit: LineEdit
var _dialog: FileDialog


func setup(application: App, args: Dictionary = {}) -> void:
    app = application
    _design = CardForge.blank_design("skill", _default_affinity())

    var root := UiTheme.vbox(8)
    root.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(root)

    root.add_child(UiTheme.heading("Card creator"))
    root.add_child(UiTheme.wrapped(
        "Pick what the card is and what it does. Every choice has a price, and the card's "
        + "Energy cost is what those prices come to — so it is worth what is on it. Rarity "
        + "follows the same total. A created card is marked CUSTOM on its face, goes into this "
        + "save's collection, and can be put in a deck like any other.", 12, UiTheme.TEXT_DIM))

    var cols := UiTheme.hbox(12)
    cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
    root.add_child(cols)

    _fields = UiTheme.vbox(6)
    _fields.custom_minimum_size = Vector2(330, 0)
    cols.add_child(UiTheme.scroll(_fields))

    _features_box = UiTheme.vbox(4)
    _features_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var features_scroll := UiTheme.scroll(_features_box)
    features_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    cols.add_child(features_scroll)

    var right := UiTheme.vbox(8)
    right.custom_minimum_size = Vector2(330, 0)
    _preview_holder = UiTheme.vbox(6)
    right.add_child(_preview_holder)
    _ledger = UiTheme.vbox(2)
    right.add_child(_ledger)
    _messages = UiTheme.vbox(3)
    right.add_child(_messages)
    _made_box = UiTheme.vbox(3)
    right.add_child(_made_box)
    cols.add_child(UiTheme.scroll(right))

    _dialog = FileDialog.new()
    _dialog.access = FileDialog.ACCESS_FILESYSTEM
    _dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
    _dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Images"])
    _dialog.size = Vector2i(760, 520)
    _dialog.file_selected.connect(func(path): import_art(String(path)))
    add_child(_dialog)

    var start := String(args.get("def_id", ""))
    if start != "" and app.catalog.is_custom(start):
        _load_for_editing(start)
    else:
        _rebuild()


func _default_affinity() -> String:
    var aff := app.profile.starter_affinity
    return aff if EffectSchema.AFFINITIES.has(aff) else "passion"


# -------------------------------------------------------------------- fields ---

func _rebuild() -> void:
    _build_fields()
    _build_features()
    _refresh()


func _build_fields() -> void:
    for c in _fields.get_children():
        c.queue_free()

    _fields.add_child(UiTheme.label("What it is", 14, UiTheme.GOLD))
    if _editing != "":
        _fields.add_child(UiTheme.label("Editing %s" % _editing, 11, UiTheme.TEXT_DIM))
    _fields.add_child(_type_row())
    _fields.add_child(_line_row("Name", "name"))
    _fields.add_child(_line_row("Flavour", "flavor"))

    _fields.add_child(UiTheme.label("Affinity", 14, UiTheme.GOLD))
    _fields.add_child(UiTheme.wrapped(
        "One is included. A second costs %d points, because the card then counts for both chains."
        % CardForge.SECOND_AFFINITY_PRICE, 11, UiTheme.TEXT_DIM))
    _fields.add_child(_affinity_grid())

    var card_type := String(_design.get("type", "skill"))
    if card_type == "skill":
        _fields.add_child(UiTheme.label("Timing and tags", 14, UiTheme.GOLD))
        _fields.add_child(_reaction_row())
        _fields.add_child(_tag_row(["martial", "magic", "melee", "ranged"]))
    elif card_type == "equipment":
        _fields.add_child(UiTheme.label("Kind of Equipment", 14, UiTheme.GOLD))
        _fields.add_child(_tag_row(["ammunition", "consumable"]))

    var stat_rows := _stat_rows(card_type)
    if not stat_rows.is_empty():
        _fields.add_child(UiTheme.label("Statistics", 14, UiTheme.GOLD))
        for row in stat_rows:
            _fields.add_child(row)

    _fields.add_child(UiTheme.label("Art", 14, UiTheme.GOLD))
    _fields.add_child(_art_row())
    _fields.add_child(UiTheme.wrapped(
        "Import an image and it is copied into this save's own art folder, so the card keeps it. "
        + "Without one the card uses its generated sigil and still plays.", 11, UiTheme.TEXT_DIM))

    _fields.add_child(UiTheme.separator())
    _fields.add_child(_action_row())


func _type_row() -> Control:
    var o := OptionButton.new()
    o.add_theme_font_size_override("font_size", 13)
    for i in CardForge.TYPES.size():
        var t := String(CardForge.TYPES[i])
        o.add_item(String(TextGen.TYPE_LABEL.get(t, t.capitalize())), i)
        if t == String(_design.get("type", "")):
            o.select(i)
    o.item_selected.connect(func(i):
        var chosen := String(CardForge.TYPES[i])
        if chosen == String(_design.get("type", "")):
            return
        # The features of one card type mean nothing on another, so they are
        # dropped rather than silently carried over and refused on save.
        _design["type"] = chosen
        _design["features"] = []
        _design["reaction"] = false
        _design["tags"] = []
        _rebuild())
    return _labelled("Card type", o)


func _line_row(caption: String, key: String) -> Control:
    var e := LineEdit.new()
    e.text = String(_design.get(key, ""))
    e.add_theme_font_size_override("font_size", 13)
    e.text_changed.connect(func(text):
        _design[key] = String(text)
        _refresh())
    return _labelled(caption, e)


func _affinity_grid() -> Control:
    var grid := GridContainer.new()
    grid.columns = 4
    for a in EffectSchema.AFFINITIES:
        var aff := String(a)
        var c := CheckBox.new()
        c.text = aff.capitalize()
        c.add_theme_font_size_override("font_size", 11)
        c.button_pressed = (_design.get("affinities", []) as Array).has(aff)
        c.toggled.connect(func(pressed): _toggle_affinity(aff, pressed))
        grid.add_child(c)
    return grid


func _toggle_affinity(aff: String, pressed: bool) -> void:
    var list: Array = (_design.get("affinities", []) as Array).duplicate()
    if pressed and not list.has(aff):
        list.append(aff)
    elif not pressed:
        list.erase(aff)
    # Two is the limit, so the third press pushes the oldest off rather than
    # being saved and rejected later.
    var over := list.size() > 2
    if over:
        list.remove_at(0)
    _design["affinities"] = list
    if over:
        _build_fields()
    _refresh()


func _reaction_row() -> Control:
    var c := CheckBox.new()
    c.text = "Playable as a Reaction  (+%d)" % CardForge.REACTION_PRICE
    c.add_theme_font_size_override("font_size", 12)
    c.button_pressed = bool(_design.get("reaction", false))
    c.toggled.connect(func(pressed):
        _design["reaction"] = pressed
        _refresh())
    return c


func _tag_row(options: Array) -> Control:
    var box := UiTheme.hbox(4)
    for opt in options:
        var tag := String(opt)
        var c := CheckBox.new()
        c.text = tag.capitalize()
        c.add_theme_font_size_override("font_size", 11)
        c.button_pressed = (_design.get("tags", []) as Array).has(tag)
        c.toggled.connect(func(pressed):
            var list: Array = (_design.get("tags", []) as Array).duplicate()
            if pressed and not list.has(tag):
                list.append(tag)
            elif not pressed:
                list.erase(tag)
            _design["tags"] = list
            _refresh())
        box.add_child(c)
    return _labelled("Tags", box)


func _stat_rows(card_type: String) -> Array:
    var rows: Array = []
    if card_type == "companion":
        rows.append(_stat_row("Attack", "attack", 0, 12,
            int(CardForge.STAT_PRICE["attack"])))
        rows.append(_stat_row("Defense", "defense", 0, 12,
            int(CardForge.STAT_PRICE["defense"])))
        rows.append(_stat_row("Adds to maximum Energy", "energy_contribution", 0, 3,
            int(CardForge.STAT_PRICE["energy_contribution"])))
        rows.append(_attack_cost_row())
    elif card_type == "equipment" or card_type == "taahma":
        rows.append(_stat_row("Gives its host Attack", "attack", 0, 8,
            int(CardForge.STAT_PRICE["equip_attack"])))
        rows.append(_stat_row("Gives its host Defense", "defense", 0, 8,
            int(CardForge.STAT_PRICE["equip_defense"])))
    return rows


func _stat_row(caption: String, key: String, low: int, high: int, price: int) -> Control:
    var e := SpinBox.new()
    e.min_value = low
    e.max_value = high
    e.value = int(_design.get(key, 0))
    e.value_changed.connect(func(v):
        _design[key] = int(v)
        _refresh())
    return _labelled("%s  (%d each)" % [caption, price], e)


func _attack_cost_row() -> Control:
    var o := OptionButton.new()
    o.add_theme_font_size_override("font_size", 13)
    var values := [0, 1, 2]
    for i in values.size():
        var v := int(values[i])
        var price := int(CardForge.ATTACK_COST_PRICE.get(v, 0))
        var note := "included"
        if price > 0:
            note = "+%d" % price
        elif price < 0:
            note = "%d" % price
        o.add_item("%d Energy  (%s)" % [v, note], i)
        if v == int(_design.get("attack_cost", 1)):
            o.select(i)
    o.item_selected.connect(func(i):
        _design["attack_cost"] = int(values[i])
        _refresh())
    return _labelled("Its attack costs", o)


func _art_row() -> Control:
    var box := UiTheme.hbox(4)
    _art_edit = LineEdit.new()
    _art_edit.add_theme_font_size_override("font_size", 12)
    _art_edit.placeholder_text = "no art yet"
    _art_edit.text = String((_design.get("art", {}) as Dictionary).get("image", ""))
    _art_edit.editable = false
    _art_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    box.add_child(_art_edit)
    var pick := UiTheme.small_button("Import art…")
    pick.pressed.connect(func(): _dialog.popup_centered_ratio(0.7))
    box.add_child(pick)
    var clear := UiTheme.small_button("Clear")
    clear.pressed.connect(func():
        _design["art"] = {}
        _art_edit.text = ""
        _refresh())
    box.add_child(clear)
    return box


func _action_row() -> Control:
    var row := UiTheme.hbox(6)
    var forge := UiTheme.primary_button(
        "Save changes" if _editing != "" else "Forge card")
    forge.pressed.connect(_forge)
    row.add_child(forge)
    if _editing != "":
        var fresh := UiTheme.button("Start a new card")
        fresh.pressed.connect(func():
            _editing = ""
            _design = CardForge.blank_design("skill", _default_affinity())
            _rebuild())
        row.add_child(fresh)
        var del := UiTheme.button("Delete this card")
        del.pressed.connect(_delete)
        row.add_child(del)
    return row


func _labelled(caption: String, control: Control) -> Control:
    var row := UiTheme.hbox(6)
    var l := UiTheme.label(caption, 12, UiTheme.TEXT_DIM)
    l.custom_minimum_size = Vector2(150, 0)
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    row.add_child(l)
    control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(control)
    return row


# ------------------------------------------------------------------ features ---

func _build_features() -> void:
    for c in _features_box.get_children():
        c.queue_free()
    var card_type := String(_design.get("type", "skill"))
    _features_box.add_child(UiTheme.label("What it does", 14, UiTheme.GOLD))
    _features_box.add_child(UiTheme.wrapped(
        "Every feature here is something the engine already performs, so the card's rules text "
        + "is generated rather than written. Features that ask you to choose a target must agree "
        + "on what they ask for: a card asks once.", 11, UiTheme.TEXT_DIM))

    for fid in CardForge.features_for(card_type):
        _features_box.add_child(_feature_row(String(fid)))


func _feature_row(fid: String) -> Control:
    var spec: Dictionary = CardForge.FEATURES[fid]
    var panel := UiTheme.panel(UiTheme.BG_PANEL, UiTheme.GOLD_DIM, 1, 4)
    var col := UiTheme.vbox(2)
    panel.add_child(col)

    var head := UiTheme.hbox(6)
    var check := CheckBox.new()
    check.text = String(spec["label"])
    check.add_theme_font_size_override("font_size", 12)
    check.button_pressed = _has_feature(fid)
    head.add_child(check)
    var gap := Control.new()
    gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    head.add_child(gap)

    var amount_spin: SpinBox = null
    if CardForge.takes_amount(fid):
        var amount_spec := CardForge.feature_amount_spec(fid)
        head.add_child(UiTheme.label(String(amount_spec.get("caption", "Amount")), 11,
            UiTheme.TEXT_DIM))
        amount_spin = SpinBox.new()
        amount_spin.min_value = int(amount_spec.get("min", 1))
        amount_spin.max_value = int(amount_spec.get("max", 1))
        amount_spin.value = _feature_amount(fid)
        amount_spin.value_changed.connect(func(v):
            _set_feature_amount(fid, int(v))
            _refresh())
        head.add_child(amount_spin)

    var price_text := "%d" % int(spec["price"])
    if CardForge.takes_amount(fid):
        price_text = "%d each" % int(spec["price"])
    var price := UiTheme.label(price_text, 11, UiTheme.GOLD)
    price.custom_minimum_size = Vector2(56, 0)
    price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    head.add_child(price)
    col.add_child(head)
    col.add_child(UiTheme.wrapped(String(spec["help"]), 11, UiTheme.TEXT_DIM))

    check.toggled.connect(func(pressed):
        _set_feature(fid, pressed, int(amount_spin.value) if amount_spin != null else 1)
        _refresh())
    return panel


func _has_feature(fid: String) -> bool:
    for f in _design.get("features", []):
        if String((f as Dictionary).get("id", "")) == fid:
            return true
    return false


func _feature_amount(fid: String) -> int:
    for f in _design.get("features", []):
        var feature: Dictionary = f
        if String(feature.get("id", "")) == fid:
            return int(feature.get("amount", 1))
    return int(CardForge.feature_amount_spec(fid).get("default", 1))


func _set_feature(fid: String, on: bool, amount: int) -> void:
    var out: Array = []
    for f in _design.get("features", []):
        if String((f as Dictionary).get("id", "")) != fid:
            out.append((f as Dictionary).duplicate())
    if on:
        out.append({"id": fid, "amount": amount})
    _design["features"] = out


func _set_feature_amount(fid: String, amount: int) -> void:
    var list: Array = (_design.get("features", []) as Array).duplicate(true)
    for f in list:
        var feature: Dictionary = f
        if String(feature.get("id", "")) == fid:
            feature["amount"] = amount
    _design["features"] = list


# ------------------------------------------------------- preview and ledger ---

func _refresh() -> void:
    var priced := CardForge.price(_design)
    var preview_id := _editing
    if preview_id == "":
        preview_id = CardForge.next_id(String(_design.get("type", "skill")),
            app.catalog.customs)
    var raw := CardForge.build(_design, preview_id)
    var def := CardDef.from_dict(raw)
    if def.name.strip_edges() == "":
        def.data["name"] = "Unnamed card"

    for c in _preview_holder.get_children():
        c.queue_free()
    _preview_holder.add_child(UiTheme.label("Preview", 14, UiTheme.GOLD))
    _preview_holder.add_child(CardView.create(def, 300.0))

    for c in _ledger.get_children():
        c.queue_free()
    _ledger.add_child(UiTheme.label("What it costs", 14, UiTheme.GOLD))
    for line in priced["lines"]:
        var entry: Dictionary = line
        var row := UiTheme.hbox(4)
        var what := UiTheme.wrapped(String(entry["label"]), 11, UiTheme.TEXT)
        what.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.add_child(what)
        var pts := int(entry["points"])
        row.add_child(UiTheme.label("%s%d" % ["+" if pts >= 0 else "", pts], 11,
            UiTheme.GOLD if pts >= 0 else UiTheme.GOOD))
        _ledger.add_child(row)
    if (priced["lines"] as Array).is_empty():
        _ledger.add_child(UiTheme.wrapped("Nothing on it yet.", 11, UiTheme.TEXT_DIM))
    _ledger.add_child(UiTheme.separator())
    _ledger.add_child(UiTheme.label("%d points → %d Energy, %s" % [
        int(priced["points"]), int(priced["cost"]),
        String(priced["rarity"]).capitalize()], 12, UiTheme.GOLD))
    _ledger.add_child(UiTheme.wrapped(
        "%d points make 1 Energy, and part of a point is still paid for."
        % CardForge.POINTS_PER_ENERGY, 11, UiTheme.TEXT_DIM))

    # Both kinds of problem are reported: what the creator itself objects to,
    # and anything the real validator finds in the definition that was built.
    var errs := CardForge.design_errors(_design, app.catalog, _editing)
    errs.append_array(def.validate())
    _show_messages(errs)
    _build_made_list()


func _show_messages(errs: Array) -> void:
    for c in _messages.get_children():
        c.queue_free()
    if errs.is_empty():
        _messages.add_child(UiTheme.label("This card is ready to forge.", 12, UiTheme.GOOD))
        return
    _messages.add_child(UiTheme.label("%d thing(s) to fix:" % errs.size(), 12, UiTheme.DANGER))
    for e in errs:
        _messages.add_child(UiTheme.wrapped("• %s" % String(e), 11, UiTheme.DANGER))


func _build_made_list() -> void:
    for c in _made_box.get_children():
        c.queue_free()
    var ids: Array = app.catalog.customs.keys()
    ids.sort()
    _made_box.add_child(UiTheme.label("Cards you have made (%d)" % ids.size(), 14, UiTheme.GOLD))
    if ids.is_empty():
        _made_box.add_child(UiTheme.wrapped("None yet.", 11, UiTheme.TEXT_DIM))
        return
    for cid in ids:
        var def := app.catalog.get_def(String(cid))
        if def == null:
            continue
        var b := UiTheme.small_button("%s — %s" % [def.name, UiTheme.cost_text(def)])
        var target := String(cid)
        b.pressed.connect(func(): _load_for_editing(target))
        _made_box.add_child(b)


# ------------------------------------------------------------------- actions ---

## Copy an image into this save's own art folder and point the card at it.
##
## The file is copied rather than referenced where it sits, so moving or
## deleting the original later cannot blank the card.
func import_art(path: String) -> String:
    var src := path.strip_edges()
    if src == "":
        return "No file chosen."
    var bytes := FileAccess.get_file_as_bytes(src)
    if bytes.is_empty():
        app.toast("Could not read %s." % src, true)
        return "Could not read %s." % src
    DirAccess.make_dir_recursive_absolute("user://custom_art")
    var ext := src.get_extension().to_lower()
    if ext == "":
        ext = "png"
    var stem := String(_design.get("name", "")).strip_edges().to_snake_case()
    if stem == "":
        stem = "custom"
    var dest := "user://custom_art/%s_%d.%s" % [stem, Time.get_ticks_msec(), ext]
    var out := FileAccess.open(dest, FileAccess.WRITE)
    if out == null:
        app.toast("Could not write into this save's art folder.", true)
        return "Could not write %s." % dest
    out.store_buffer(bytes)
    out.close()

    var art: Dictionary = (_design.get("art", {}) as Dictionary).duplicate()
    art["image"] = dest
    art["fit"] = "cover"
    _design["art"] = art
    ArtLibrary.clear_cache()
    if _art_edit != null:
        _art_edit.text = dest
    _refresh()
    return ""


func _load_for_editing(def_id: String) -> void:
    var raw: Dictionary = app.catalog.customs.get(def_id, {})
    if raw.is_empty():
        return
    _editing = def_id
    _design = design_from(raw)
    _rebuild()


## Read a design back out of a definition, so a created card can be opened and
## changed rather than only made once.
func design_from(raw: Dictionary) -> Dictionary:
    # A card made here carries the design it was made from, so reopening it is
    # exact. Anything else is read back out of the definition as best it can be.
    var stored := CardForge.design_in(raw)
    if not stored.is_empty():
        return stored
    var def := CardDef.from_dict(raw)
    var card_type := String(def.types[0]) if not def.types.is_empty() else "skill"
    var design := CardForge.blank_design(card_type, _default_affinity())
    design["name"] = def.name
    design["flavor"] = def.flavor
    design["affinities"] = def.affinities.duplicate()
    design["tags"] = def.tags.duplicate()
    design["attack_tags"] = def.attack_tags.duplicate()
    design["attack"] = int(raw.get("attack", 0))
    design["defense"] = int(raw.get("defense", 0))
    design["attack_cost"] = int(raw.get("attack_cost", 1))
    design["energy_contribution"] = int(raw.get("energy_contribution", 0))
    design["reaction"] = def.has_tag("reaction")
    design["art"] = (raw.get("art", {}) as Dictionary).duplicate(true)
    # A created card records which features it was made from in its pattern
    # tags, so it can be taken apart again rather than only made once.
    var features: Array = []
    for p in raw.get("patterns", []):
        var fid := String(p)
        if CardForge.FEATURES.has(fid):
            features.append({"id": fid,
                "amount": int(CardForge.feature_amount_spec(fid).get("default", 1))})
    design["features"] = features
    return design


func _forge() -> void:
    var errs := CardForge.design_errors(_design, app.catalog, _editing)
    if not errs.is_empty():
        _show_messages(errs)
        app.toast("Not forged: %s" % String(errs[0]), true)
        return

    var def_id := _editing
    if def_id == "":
        def_id = CardForge.next_id(String(_design.get("type", "skill")), app.catalog.customs)
    var raw := CardForge.build(_design, def_id)
    if _editing != "":
        var was: Dictionary = app.catalog.customs.get(def_id, {})
        raw["revision"] = int(was.get("revision", 1)) + 1

    var problems := app.catalog.put_custom(CardDef.from_dict(raw))
    if not problems.is_empty():
        _show_messages(problems)
        app.toast("Not forged: the card does not validate.", true)
        return

    app.profile.set_custom(def_id, app.catalog.customs[def_id])
    # Copies exist because the card was made. A created card is not a reward,
    # so nothing is converted to gold and nothing is drawn from a pack.
    app.profile.grant_custom_copies(def_id, app.catalog.collection_cap(def_id))
    app.save_profile()
    var made := app.catalog.get_def(def_id)
    var copies := app.profile.owned_count(def_id)
    app.toast("%s forged: %s, %s. %d cop%s in your collection." % [
        made.name, UiTheme.cost_text(made), made.rarity, copies,
        "y" if copies == 1 else "ies"])
    _editing = def_id
    _rebuild()
    _report_broken_decks()


func _delete() -> void:
    if _editing == "":
        return
    var gone := _editing
    var label := gone
    var def := app.catalog.get_def(gone)
    if def != null:
        label = def.name
    app.catalog.remove_custom(gone)
    app.profile.clear_custom(gone)
    app.save_profile()
    app.toast("%s was deleted, along with the copies of it you held." % label)
    _editing = ""
    _design = CardForge.blank_design("skill", _default_affinity())
    _rebuild()
    _report_broken_decks()


## A deck that a change here made illegal is reported, never edited: which card
## to drop is the player's decision, not the creator's.
func _report_broken_decks() -> void:
    var broken: Array = []
    for deck in app.profile.decks():
        var check := DeckValidator.validate(app.catalog, app.rules, deck, app.profile.owned())
        if not bool(check["ok"]):
            broken.append("%s — %s" % [String((deck as Dictionary).get("name", "Deck")),
                String((check["errors"] as Array)[0])])
    if broken.is_empty():
        return
    _messages.add_child(UiTheme.label("A saved deck is no longer legal:", 12, UiTheme.DANGER))
    for b in broken:
        _messages.add_child(UiTheme.wrapped("• %s" % String(b), 11, UiTheme.DANGER))
    _messages.add_child(UiTheme.wrapped(
        "Those decks were kept exactly as they were. Fix them in the deck builder.",
        11, UiTheme.TEXT_DIM))
