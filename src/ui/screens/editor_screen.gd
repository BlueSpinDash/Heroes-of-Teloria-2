extends Control

## Card editor: change a definition's supported fields, preview the result,
## validate it, save it as an override, restore the bundled version, and
## import or export overrides.
##
## Rules text is never typed by hand. It is regenerated from the effect data
## every time the card is previewed or saved, so the editor cannot claim an
## effect the engine will not perform.

var app: App
var working: CardDef = null
var _picker: OptionButton
var _search: LineEdit
var _ids: Array = []
var _fields: VBoxContainer
var _preview_holder: VBoxContainer
var _messages: VBoxContainer
var _effects_edit: TextEdit
var _path_edit: LineEdit


func setup(application: App, args: Dictionary = {}) -> void:
    app = application
    var root := UiTheme.vbox(8)
    root.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(root)

    root.add_child(UiTheme.heading("Card editor"))
    root.add_child(UiTheme.wrapped(
        "Name, art, flavour, cost, stats, tags, Affinity, rarity and the structured effect data "
        + "can all be changed here without touching engine code. A genuinely new mechanic — an "
        + "instruction outside the effect vocabulary — needs the engine extended first; see "
        + "docs/EFFECT_SCHEMA.md.", 12, UiTheme.TEXT_DIM))

    root.add_child(_selector())

    var cols := UiTheme.hbox(12)
    cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
    root.add_child(cols)

    _fields = UiTheme.vbox(6)
    _fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    cols.add_child(UiTheme.scroll(_fields))

    var right := UiTheme.vbox(8)
    right.custom_minimum_size = Vector2(340, 0)
    _preview_holder = UiTheme.vbox(6)
    right.add_child(_preview_holder)
    _messages = UiTheme.vbox(3)
    right.add_child(_messages)
    cols.add_child(UiTheme.scroll(right))

    var start_id := String(args.get("def_id", ""))
    if start_id == "":
        start_id = String(_ids[0]) if not _ids.is_empty() else ""
    _select(start_id)


func _selector() -> Control:
    var row := UiTheme.hbox(8)
    _search = LineEdit.new()
    _search.placeholder_text = "Filter cards"
    _search.add_theme_font_size_override("font_size", 13)
    _search.custom_minimum_size = Vector2(200, 0)
    _search.text_changed.connect(func(_t): _rebuild_picker())
    row.add_child(_search)

    _picker = OptionButton.new()
    _picker.add_theme_font_size_override("font_size", 13)
    _picker.custom_minimum_size = Vector2(320, 0)
    _picker.item_selected.connect(func(i):
        if i >= 0 and i < _ids.size():
            _select(String(_ids[i])))
    row.add_child(_picker)

    var gap := Control.new()
    gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(gap)

    _path_edit = LineEdit.new()
    _path_edit.text = "user://card_overrides.json"
    _path_edit.add_theme_font_size_override("font_size", 12)
    _path_edit.custom_minimum_size = Vector2(220, 0)
    row.add_child(_path_edit)
    var exp := UiTheme.button("Export overrides")
    exp.pressed.connect(_export_overrides)
    row.add_child(exp)
    var imp := UiTheme.button("Import overrides")
    imp.pressed.connect(_import_overrides)
    row.add_child(imp)

    _rebuild_picker()
    return row


func _rebuild_picker() -> void:
    _picker.clear()
    _ids = []
    var query := _search.text.strip_edges().to_lower()
    for def in app.catalog.all_defs():
        var d: CardDef = def
        if query != "" and not ("%s %s" % [d.name.to_lower(), d.id.to_lower()]).contains(query):
            continue
        _ids.append(d.id)
        _picker.add_item("%s — %s%s" % [d.id, d.name,
            "  (edited)" if app.catalog.is_overridden(d.id) else ""], _ids.size() - 1)
        if _ids.size() >= 200:
            break


func _select(def_id: String) -> void:
    var base := app.catalog.get_def(def_id)
    if base == null:
        return
    working = base.duplicate_def()
    for i in _ids.size():
        if String(_ids[i]) == def_id:
            _picker.select(i)
    _build_fields()
    _refresh_preview()


# ------------------------------------------------------------------- fields ---

func _build_fields() -> void:
    for c in _fields.get_children():
        c.queue_free()
    if working == null:
        return

    _fields.add_child(UiTheme.label("Identity", 14, UiTheme.GOLD))
    _fields.add_child(UiTheme.label(
        "%s • revision %d • %s" % [working.id, working.revision,
            "edited" if app.catalog.is_overridden(working.id) else "bundled"], 11, UiTheme.TEXT_DIM))
    _fields.add_child(_text_field("Display name", "name"))
    _fields.add_child(_text_field("Flavour text", "flavor"))
    _fields.add_child(_bool_field("Finished card (not a proxy)", "authored"))
    _fields.add_child(UiTheme.wrapped(
        "Marking a card finished sets it aside from the proxy generator, so regenerating the "
        + "catalog never overwrites it.", 11, UiTheme.TEXT_DIM))

    _fields.add_child(UiTheme.label("Classification", 14, UiTheme.GOLD))
    _fields.add_child(_choice_field("Rarity", "rarity", EffectSchema.RARITIES))
    _fields.add_child(_bool_field("Unique (one copy per deck)", "unique"))
    _fields.add_child(_multi_field("Affinities", "affinities", EffectSchema.AFFINITIES))
    _fields.add_child(_multi_field("Tags", "tags", EffectSchema.TAGS))

    _fields.add_child(UiTheme.label("Cost and statistics", 14, UiTheme.GOLD))
    _fields.add_child(_cost_field())
    if working.has_type("hero"):
        _fields.add_child(_int_field("Maximum Energy", "hero_max_energy", 1, 12))
    if working.is_character():
        _fields.add_child(_int_field("Attack", "attack", 0, 20))
        _fields.add_child(_int_field("Defense", "defense", 0, 20))
        _fields.add_child(_int_field("Attack cost", "attack_cost", 0, 10))
    if working.has_type("companion"):
        _fields.add_child(_int_field("Adds to maximum Energy", "energy_contribution", 0, 10))
    if working.has_type("equipment"):
        _fields.add_child(_int_field("Printed Attack modifier", "attack", 0, 20))
        _fields.add_child(_int_field("Printed Defense modifier", "defense", 0, 20))

    _fields.add_child(UiTheme.label("Art", 14, UiTheme.GOLD))
    _fields.add_child(_art_text_field("Art file", "image"))
    _fields.add_child(UiTheme.wrapped(
        "A bare filename is looked for in assets/art/. Leave it empty to use the generated "
        + "placeholder sigil. A missing file is not an error: the card falls back and still plays.",
        11, UiTheme.TEXT_DIM))
    _fields.add_child(_art_choice_field("Fit", "fit", ["cover", "contain"]))
    _fields.add_child(_art_field("Placeholder hue", "hue", 0, 359))
    _fields.add_child(_art_field("Placeholder seed", "seed", 0, 99999))

    _fields.add_child(UiTheme.label("Structured effects", 14, UiTheme.GOLD))
    _fields.add_child(UiTheme.wrapped(
        "Effects are validated data, never code. Edit the JSON below and press Preview: the rules "
        + "text is regenerated from what you write, and anything the interpreter cannot run is "
        + "rejected.", 11, UiTheme.TEXT_DIM))
    _effects_edit = TextEdit.new()
    _effects_edit.text = JSON.stringify(working.effects, "  ")
    _effects_edit.custom_minimum_size = Vector2(0, 150)
    _effects_edit.add_theme_font_size_override("font_size", UiTheme.fs(11))
    _fields.add_child(_effects_edit)

    var row := UiTheme.hbox(8)
    var preview := UiTheme.button("Preview and validate")
    preview.pressed.connect(_apply_effects_then_preview)
    row.add_child(preview)
    var save := UiTheme.primary_button("Save changes")
    save.pressed.connect(_save)
    row.add_child(save)
    var restore := UiTheme.button("Restore bundled version")
    restore.disabled = not app.catalog.is_overridden(working.id)
    restore.pressed.connect(_restore)
    row.add_child(restore)
    _fields.add_child(row)


func _labelled(caption: String, control: Control) -> Control:
    var row := UiTheme.hbox(6)
    var l := UiTheme.label(caption, 12, UiTheme.TEXT_DIM)
    l.custom_minimum_size = Vector2(170, 0)
    row.add_child(l)
    control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(control)
    return row


func _text_field(caption: String, key: String) -> Control:
    var e := LineEdit.new()
    e.text = String(working.data.get(key, ""))
    e.add_theme_font_size_override("font_size", 13)
    e.text_changed.connect(func(t):
        working.data[key] = t
        _refresh_preview())
    return _labelled(caption, e)


func _int_field(caption: String, key: String, low: int, high: int) -> Control:
    var e := SpinBox.new()
    e.min_value = low
    e.max_value = high
    e.value = int(working.data.get(key, 0))
    e.value_changed.connect(func(v):
        working.data[key] = int(v)
        _refresh_preview())
    return _labelled(caption, e)


func _art_field(caption: String, key: String, low: int, high: int) -> Control:
    var e := SpinBox.new()
    e.min_value = low
    e.max_value = high
    var art: Dictionary = working.data.get("art", {})
    e.value = int(art.get(key, 0))
    e.value_changed.connect(func(v):
        var a: Dictionary = working.data.get("art", {}).duplicate()
        a[key] = int(v)
        working.data["art"] = a
        _refresh_preview())
    return _labelled(caption, e)


func _art_text_field(caption: String, key: String) -> Control:
    var e := LineEdit.new()
    var art: Dictionary = working.data.get("art", {})
    e.text = String(art.get(key, ""))
    e.placeholder_text = "for example  passion_hero_01.png"
    e.add_theme_font_size_override("font_size", 13)
    e.text_changed.connect(func(t):
        var a: Dictionary = (working.data.get("art", {}) as Dictionary).duplicate()
        if t.strip_edges() == "":
            a.erase(key)
        else:
            a[key] = t.strip_edges()
        working.data["art"] = a
        ArtLibrary.clear_cache()
        _refresh_preview())
    return _labelled(caption, e)


func _art_choice_field(caption: String, key: String, options: Array) -> Control:
    var o := OptionButton.new()
    o.add_theme_font_size_override("font_size", 13)
    var art: Dictionary = working.data.get("art", {})
    for i in options.size():
        o.add_item(String(options[i]).capitalize(), i)
        if String(options[i]) == String(art.get(key, "cover")):
            o.select(i)
    o.item_selected.connect(func(i):
        var a: Dictionary = (working.data.get("art", {}) as Dictionary).duplicate()
        a[key] = String(options[i])
        working.data["art"] = a
        _refresh_preview())
    return _labelled(caption, o)


func _bool_field(caption: String, key: String) -> Control:
    var c := CheckBox.new()
    c.button_pressed = bool(working.data.get(key, false))
    c.add_theme_font_size_override("font_size", 12)
    c.toggled.connect(func(p):
        working.data[key] = p
        _refresh_preview())
    return _labelled(caption, c)


func _choice_field(caption: String, key: String, options: Array) -> Control:
    var o := OptionButton.new()
    o.add_theme_font_size_override("font_size", 13)
    for i in options.size():
        o.add_item(String(options[i]).capitalize(), i)
        if String(options[i]) == String(working.data.get(key, "")):
            o.select(i)
    o.item_selected.connect(func(i):
        working.data[key] = String(options[i])
        _refresh_preview())
    return _labelled(caption, o)


func _multi_field(caption: String, key: String, options: Array) -> Control:
    var box := UiTheme.hbox(4)
    var current: Array = working.data.get(key, [])
    for opt in options:
        var c := CheckBox.new()
        c.text = String(opt).capitalize()
        c.add_theme_font_size_override("font_size", 11)
        c.button_pressed = current.has(String(opt))
        var name := String(opt)
        c.toggled.connect(func(pressed):
            var list: Array = (working.data.get(key, []) as Array).duplicate()
            if pressed and not list.has(name):
                list.append(name)
            elif not pressed:
                list.erase(name)
            working.data[key] = list
            _refresh_preview())
        box.add_child(c)
    return _labelled(caption, box)


func _cost_field() -> Control:
    var box := UiTheme.hbox(6)
    var kinds := ["none", "fixed", "x"]
    var o := OptionButton.new()
    o.add_theme_font_size_override("font_size", 13)
    for i in kinds.size():
        o.add_item(String(kinds[i]).capitalize(), i)
        if kinds[i] == working.cost_kind():
            o.select(i)
    var amount := SpinBox.new()
    amount.min_value = 0
    amount.max_value = 12
    amount.value = working.fixed_cost() if working.cost_kind() == "fixed" else working.x_min()
    o.item_selected.connect(func(i):
        var kind := String(kinds[i])
        if kind == "none":
            working.data["cost"] = {"kind": "none"}
        elif kind == "fixed":
            working.data["cost"] = {"kind": "fixed", "amount": int(amount.value)}
        else:
            working.data["cost"] = {"kind": "x", "min": int(amount.value)}
        _refresh_preview())
    amount.value_changed.connect(func(v):
        var kind := working.cost_kind()
        if kind == "fixed":
            working.data["cost"] = {"kind": "fixed", "amount": int(v)}
        elif kind == "x":
            working.data["cost"] = {"kind": "x", "min": int(v)}
        _refresh_preview())
    box.add_child(o)
    box.add_child(amount)
    return _labelled("Play cost", box)


# ------------------------------------------------------ preview and saving ---

func _apply_effects_then_preview() -> void:
    var parsed = JSON.parse_string(_effects_edit.text)
    if not (parsed is Array):
        _show_messages(["The effects field must be a JSON array, for example []."], true)
        return
    working.data["effects"] = parsed
    _refresh_preview()


func _refresh_preview() -> void:
    if working == null:
        return
    # A finished card is by definition no longer placeholder content.
    if bool(working.data.get("authored", false)):
        working.data["placeholder"] = false
    # Regenerate the rules text from the effect data, always.
    working.data["text"] = TextGen.render(working)
    working._has_aura = -1
    for c in _preview_holder.get_children():
        c.queue_free()
    _preview_holder.add_child(UiTheme.label("Preview", 14, UiTheme.GOLD))
    _preview_holder.add_child(CardView.create(working, 300.0))
    var art_status := ArtLibrary.describe(working.data.get("art", {}))
    var loaded := ArtLibrary.has_image(working.data.get("art", {})) \
        and ArtLibrary.texture_for(working.data.get("art", {})) != null
    _preview_holder.add_child(UiTheme.wrapped(art_status, 11,
        UiTheme.GOOD if loaded else UiTheme.TEXT_DIM))
    _show_messages(working.validate(), false)


func _show_messages(errs: Array, force_error: bool) -> void:
    for c in _messages.get_children():
        c.queue_free()
    if errs.is_empty() and not force_error:
        _messages.add_child(UiTheme.label("This definition validates.", 12, UiTheme.GOOD))
        return
    _messages.add_child(UiTheme.label("%d problem(s):" % errs.size(), 12, UiTheme.DANGER))
    for e in errs:
        _messages.add_child(UiTheme.wrapped("• %s" % String(e), 11, UiTheme.DANGER))


func _save() -> void:
    if working == null:
        return
    _apply_effects_then_preview()
    var errs := app.catalog.put_override(working)
    if not errs.is_empty():
        _show_messages(errs, true)
        app.toast("Not saved: the definition does not validate.", true)
        return
    app.profile.set_override(working.id, app.catalog.overrides[working.id])
    app.save_profile()
    # Owned copies and saved decks reference the card id, which never changes,
    # so both survive. Any deck the edit made illegal is reported, not deleted.
    var broken: Array = []
    for deck in app.profile.decks():
        var check := DeckValidator.validate(app.catalog, app.rules, deck, app.profile.owned())
        if not check["ok"]:
            broken.append("%s — %s" % [String((deck as Dictionary).get("name", "Deck")),
                String((check["errors"] as Array)[0])])
    app.toast("Saved. %s is now revision %d." % [working.name, app.catalog.get_def(working.id).revision])
    if not broken.is_empty():
        _messages.add_child(UiTheme.label("This edit made a saved deck illegal:", 12, UiTheme.DANGER))
        for b in broken:
            _messages.add_child(UiTheme.wrapped("• %s" % String(b), 11, UiTheme.DANGER))
        _messages.add_child(UiTheme.wrapped(
            "Those decks were kept exactly as they were. Fix them in the deck builder, or restore "
            + "the bundled card.", 11, UiTheme.TEXT_DIM))
    _select(working.id)


func _restore() -> void:
    var def_id := working.id
    app.catalog.restore_bundled(def_id)
    app.profile.clear_override(def_id)
    app.save_profile()
    app.toast("%s restored to its bundled definition." % def_id)
    _rebuild_picker()
    _select(def_id)


func _export_overrides() -> void:
    var path := _path_edit.text.strip_edges()
    var f := FileAccess.open(path, FileAccess.WRITE)
    if f == null:
        app.toast("Could not write %s." % path, true)
        return
    f.store_string(JSON.stringify({
        "format": "heroes_of_teloria_card_overrides", "version": 1,
        "overrides": app.profile.overrides()}, "  "))
    f.close()
    app.toast("Exported %d override(s) to %s." % [app.profile.overrides().size(), path])


func _import_overrides() -> void:
    var path := _path_edit.text.strip_edges()
    if not FileAccess.file_exists(path):
        app.toast("No file at %s." % path, true)
        return
    var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
    if not (parsed is Dictionary) or String((parsed as Dictionary).get("format", "")) != "heroes_of_teloria_card_overrides":
        app.toast("That file is not a card-override export.", true)
        return
    var incoming = (parsed as Dictionary).get("overrides", {})
    if not (incoming is Dictionary):
        app.toast("That export has no override list.", true)
        return
    # Imported definitions are data and are schema validated before use.
    var candidate := Catalog.load_bundled()
    candidate.set_overrides(incoming)
    var errs := candidate.validate_all()
    if not errs.is_empty():
        _show_messages(errs.slice(0, 8), true)
        app.toast("Import refused: %d definition problem(s)." % errs.size(), true)
        return
    for k in (incoming as Dictionary).keys():
        app.profile.set_override(String(k), (incoming as Dictionary)[k])
    app.catalog.set_overrides(app.profile.overrides())
    app.save_profile()
    app.toast("Imported %d override(s)." % (incoming as Dictionary).size())
    _rebuild_picker()
    _select(working.id if working != null else String(_ids[0]))
