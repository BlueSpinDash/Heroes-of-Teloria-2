extends Control

## Deck builder: Hero selection, quantities, the Energy curve, and live
## legality and ownership feedback.

var app: App
var deck: Dictionary = {}
var _name_edit: LineEdit
var _hero_picker: OptionButton
var _heroes: Array = []
var _search: LineEdit
var _type_filter: OptionButton
var _affinity_filter: OptionButton
var _available: VBoxContainer
var _contents: VBoxContainer
var _status: Label
var _curve_holder: VBoxContainer
var _preview: PanelContainer
var _preview_holder: VBoxContainer


func setup(application: App, args: Dictionary = {}) -> void:
    app = application
    if args.has("deck_id"):
        deck = app.profile.deck_by_id(String(args["deck_id"])).duplicate(true)
    if deck.is_empty():
        deck = {"deck_id": Ids.unique("deck"), "name": "New deck", "hero": "", "cards": {}, "starter": false}

    var root := UiTheme.vbox(8)
    root.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(root)

    root.add_child(_header())
    var cols := UiTheme.hbox(12)
    cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
    root.add_child(cols)

    var left := UiTheme.vbox(6)
    left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    left.size_flags_vertical = Control.SIZE_EXPAND_FILL
    left.add_child(_filters())
    _available = UiTheme.vbox(3)
    left.add_child(UiTheme.scroll(_available))
    cols.add_child(left)

    var right := UiTheme.vbox(6)
    right.custom_minimum_size = Vector2(380, 0)
    right.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _status = UiTheme.wrapped("", 12, UiTheme.TEXT)
    right.add_child(_status)
    _curve_holder = UiTheme.vbox(2)
    right.add_child(_curve_holder)
    right.add_child(UiTheme.separator())
    _contents = UiTheme.vbox(3)
    right.add_child(UiTheme.scroll(_contents))
    cols.add_child(right)

    _preview = UiTheme.panel(UiTheme.BG_PANEL, UiTheme.GOLD_DIM, 1, 6)
    _preview.custom_minimum_size = Vector2(320, 0)
    _preview_holder = UiTheme.vbox(4)
    _preview.add_child(_preview_holder)
    _preview_holder.add_child(UiTheme.label("Preview", 14, UiTheme.GOLD))
    _preview_holder.add_child(UiTheme.wrapped("Select a card to see its face.", 12, UiTheme.TEXT_DIM))
    cols.add_child(_preview)

    _refresh_available()
    _refresh_contents()


func _header() -> Control:
    var row := UiTheme.hbox(8)
    row.add_child(UiTheme.label("Deck name:", 13))
    _name_edit = LineEdit.new()
    _name_edit.text = String(deck.get("name", "New deck"))
    _name_edit.add_theme_font_size_override("font_size", 14)
    _name_edit.custom_minimum_size = Vector2(200, 0)
    _name_edit.text_changed.connect(func(t): deck["name"] = t)
    row.add_child(_name_edit)

    row.add_child(UiTheme.label("Hero:", 13))
    _hero_picker = OptionButton.new()
    _hero_picker.add_theme_font_size_override("font_size", 13)
    _heroes = []
    for h in app.catalog.heroes():
        var owned := app.profile.owned_count((h as CardDef).id) > 0
        _heroes.append(h)
        _hero_picker.add_item("%s%s" % [(h as CardDef).name, "" if owned else "  (not owned)"], _heroes.size() - 1)
    var current := String(deck.get("hero", ""))
    for i in _heroes.size():
        if (_heroes[i] as CardDef).id == current:
            _hero_picker.select(i)
    if current == "" and not _heroes.is_empty():
        _hero_picker.select(0)
        deck["hero"] = (_heroes[0] as CardDef).id
    _hero_picker.item_selected.connect(func(i):
        deck["hero"] = (_heroes[i] as CardDef).id
        _show_preview((_heroes[i] as CardDef).id)
        _refresh_contents())
    row.add_child(_hero_picker)

    var gap := Control.new()
    gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(gap)

    var save := UiTheme.primary_button("Save deck")
    save.pressed.connect(_save)
    row.add_child(save)
    var back := UiTheme.button("Back to decks")
    back.pressed.connect(func(): app.goto("decks"))
    row.add_child(back)
    return row


func _filters() -> Control:
    var row := UiTheme.hbox(6)
    _search = LineEdit.new()
    _search.placeholder_text = "Search card names"
    _search.add_theme_font_size_override("font_size", 13)
    _search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _search.text_changed.connect(func(_t): _refresh_available())
    row.add_child(_search)

    _type_filter = OptionButton.new()
    _type_filter.add_theme_font_size_override("font_size", 12)
    for i in ["Any type", "Companion", "Skill", "Equipment", "Location", "Ta'ahma"].size():
        _type_filter.add_item(["Any type", "Companion", "Skill", "Equipment", "Location", "Ta'ahma"][i], i)
    _type_filter.select(0)
    _type_filter.item_selected.connect(func(_i): _refresh_available())
    row.add_child(_type_filter)

    _affinity_filter = OptionButton.new()
    _affinity_filter.add_theme_font_size_override("font_size", 12)
    var items: Array = ["Any Affinity", "Neutral"]
    for a in EffectSchema.AFFINITIES:
        items.append(String(a).capitalize())
    for i in items.size():
        _affinity_filter.add_item(String(items[i]), i)
    _affinity_filter.select(0)
    _affinity_filter.item_selected.connect(func(_i): _refresh_available())
    row.add_child(_affinity_filter)

    var owned_only := CheckBox.new()
    owned_only.text = "Owned only"
    owned_only.button_pressed = true
    owned_only.add_theme_font_size_override("font_size", 12)
    owned_only.toggled.connect(func(_p): _refresh_available())
    _owned_only = owned_only
    row.add_child(owned_only)
    return row


var _owned_only: CheckBox


func _refresh_available() -> void:
    for c in _available.get_children():
        c.queue_free()
    var query := _search.text.strip_edges().to_lower()
    var shown := 0
    for def in app.catalog.deck_eligible():
        var d: CardDef = def
        if query != "" and not ("%s %s" % [d.name.to_lower(), d.id.to_lower()]).contains(query):
            continue
        var t := _type_filter.get_selected_id()
        if t > 0 and not d.has_type(["", "companion", "skill", "equipment", "location", "taahma"][t]):
            continue
        var a := _affinity_filter.get_selected_id()
        if a == 1 and not d.affinities.is_empty():
            continue
        if a > 1 and not d.has_affinity(String(EffectSchema.AFFINITIES[a - 2])):
            continue
        if _owned_only.button_pressed and app.profile.owned_count(d.id) <= 0:
            continue
        _available.add_child(_card_row(d, true))
        shown += 1
        if shown >= 80:
            _available.add_child(UiTheme.label(
                "Showing the first 80 matches — narrow the search to see more.", 11, UiTheme.TEXT_DIM))
            break
    if shown == 0:
        _available.add_child(UiTheme.label("No cards match those filters.", 12, UiTheme.TEXT_DIM))


func _card_row(d: CardDef, with_add: bool) -> Control:
    var used := int((deck.get("cards", {}) as Dictionary).get(d.id, 0))
    var owned := app.profile.owned_count(d.id)
    var limit: int = 1 if (d.unique or d.is_named_character()) else app.rules.copy_limit_by_name
    var p := UiTheme.panel(UiTheme.BG_RAISED if used > 0 else UiTheme.BG_PANEL,
        UiTheme.GOLD_DIM if used > 0 else Color(0, 0, 0, 0), 1, 4)
    var row := UiTheme.hbox(6)

    var cost := UiTheme.label(UiTheme.cost_text(d), 14, UiTheme.GOLD)
    cost.custom_minimum_size = Vector2(18, 0)
    row.add_child(cost)

    var name_btn := Button.new()
    name_btn.text = d.name
    name_btn.flat = true
    name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
    name_btn.add_theme_font_size_override("font_size", UiTheme.fs(12))
    name_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    name_btn.tooltip_text = d.text
    name_btn.pressed.connect(func(): _show_preview(d.id))
    row.add_child(name_btn)

    var aff := "neutral" if d.affinities.is_empty() else String(d.affinities[0])
    row.add_child(UiTheme.label(String(UiTheme.AFFINITY_GLYPH.get(aff, "◇")), 12,
        UiTheme.affinity_color(aff)))
    row.add_child(UiTheme.label(UiTheme.primary_type(d).substr(0, 4).capitalize(), 10, UiTheme.TEXT_DIM))
    row.add_child(UiTheme.label("%d/%d owned" % [owned, app.catalog.collection_cap(d.id)], 10,
        UiTheme.TEXT_DIM if owned > 0 else UiTheme.DANGER))

    var minus := UiTheme.button("−")
    minus.custom_minimum_size = Vector2(28, 26)
    minus.disabled = used <= 0
    minus.pressed.connect(func(): _change(d, -1))
    row.add_child(minus)
    var count := UiTheme.label(str(used), 13, UiTheme.GOLD if used > 0 else UiTheme.TEXT_DIM)
    count.custom_minimum_size = Vector2(16, 0)
    count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    row.add_child(count)
    var plus := UiTheme.button("+")
    plus.custom_minimum_size = Vector2(28, 26)
    plus.disabled = used >= limit
    plus.tooltip_text = "Deck limit %d; you own %d." % [limit, owned]
    plus.pressed.connect(func(): _change(d, 1))
    row.add_child(plus)

    p.add_child(row)
    return p


func _change(d: CardDef, delta: int) -> void:
    var cards: Dictionary = deck["cards"]
    var used := int(cards.get(d.id, 0)) + delta
    var limit: int = 1 if (d.unique or d.is_named_character()) else app.rules.copy_limit_by_name
    used = clamp(used, 0, limit)
    if used <= 0:
        cards.erase(d.id)
    else:
        cards[d.id] = used
    _refresh_available()
    _refresh_contents()


func _refresh_contents() -> void:
    for c in _contents.get_children():
        c.queue_free()
    for c in _curve_holder.get_children():
        c.queue_free()

    var check := DeckValidator.validate(app.catalog, app.rules, deck, app.profile.owned())
    var stats := DeckValidator.stats(app.catalog, deck)
    var total := int(stats["total"])
    if check["ok"]:
        _status.text = "Legal: one Hero and %d cards, every copy owned." % total
        _status.add_theme_color_override("font_color", UiTheme.GOOD)
    else:
        _status.text = "%d / %d cards. %s" % [total, app.rules.hit_deck_size,
            " ".join(check["errors"])]
        _status.add_theme_color_override("font_color", UiTheme.DANGER)

    # Energy curve.
    _curve_holder.add_child(UiTheme.label("Energy curve", 12, UiTheme.GOLD))
    var curve: Dictionary = stats["curve"]
    var keys: Array = curve.keys()
    keys.sort()
    var peak := 1
    for k in keys:
        peak = max(peak, int(curve[k]))
    for k in keys:
        var bar_row := UiTheme.hbox(4)
        bar_row.add_child(UiTheme.label(String(k), 11, UiTheme.TEXT_DIM))
        var bar := ColorRect.new()
        bar.color = UiTheme.GOLD_DIM
        bar.custom_minimum_size = Vector2(float(int(curve[k])) / float(peak) * 200.0, 10)
        bar_row.add_child(bar)
        bar_row.add_child(UiTheme.label(str(int(curve[k])), 11, UiTheme.TEXT_DIM))
        _curve_holder.add_child(bar_row)

    _contents.add_child(UiTheme.label("Deck contents (%d)" % total, 13, UiTheme.GOLD))
    var cards: Dictionary = deck.get("cards", {})
    var ids: Array = cards.keys()
    ids.sort_custom(func(a, b):
        var da := app.catalog.get_def(String(a))
        var db := app.catalog.get_def(String(b))
        if da == null or db == null:
            return String(a) < String(b)
        var ca: int = da.fixed_cost() if da.cost_kind() == "fixed" else 99
        var cb: int = db.fixed_cost() if db.cost_kind() == "fixed" else 99
        if ca != cb:
            return ca < cb
        return da.name < db.name)
    for def_id in ids:
        var d := app.catalog.get_def(String(def_id))
        if d == null:
            _contents.add_child(UiTheme.label("Unknown card %s" % String(def_id), 11, UiTheme.DANGER))
            continue
        _contents.add_child(_card_row(d, false))


func _show_preview(def_id: String) -> void:
    var d := app.catalog.get_def(def_id)
    if d == null:
        return
    for c in _preview_holder.get_children():
        c.queue_free()
    _preview_holder.add_child(UiTheme.label("Preview", 14, UiTheme.GOLD))
    _preview_holder.add_child(CardView.create(d, 300.0))


func _save() -> void:
    deck["name"] = _name_edit.text.strip_edges()
    if deck["name"] == "":
        deck["name"] = "Unnamed deck"
    var check := DeckValidator.validate(app.catalog, app.rules, deck, app.profile.owned())
    app.profile.save_deck(deck)
    var err := app.save_profile()
    if err != "":
        return
    if check["ok"]:
        app.toast("Saved '%s'. It is legal and ready to play." % String(deck["name"]))
    else:
        app.toast("Saved '%s' as a draft. It cannot enter a match yet: %s" % [
            String(deck["name"]), String((check["errors"] as Array)[0])], true)
    app.goto("decks")
