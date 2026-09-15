extends Control

## Collection: search, filter and inspect every card, with owned counts.

var app: App
var _search: LineEdit
var _type: OptionButton
var _affinity: OptionButton
var _rarity: OptionButton
var _cost: OptionButton
var _ownership: OptionButton
var _grid: GridContainer
var _summary: Label
var _inspect_holder: VBoxContainer
var _page: int = 0
var _page_label: Label
var _matches: Array = []

const PAGE_SIZE := 12


func setup(application: App, _args: Dictionary = {}) -> void:
    app = application
    var root := UiTheme.vbox(8)
    root.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(root)

    root.add_child(UiTheme.heading("Collection"))
    root.add_child(_filter_row())
    _summary = UiTheme.label("", 12, UiTheme.TEXT_DIM)
    root.add_child(_summary)

    var cols := UiTheme.hbox(12)
    cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
    root.add_child(cols)

    var left := UiTheme.vbox(8)
    left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    left.size_flags_vertical = Control.SIZE_EXPAND_FILL
    cols.add_child(left)

    _grid = GridContainer.new()
    _grid.columns = 4
    _grid.add_theme_constant_override("h_separation", 10)
    _grid.add_theme_constant_override("v_separation", 10)
    left.add_child(UiTheme.scroll(_grid))

    var pager := UiTheme.hbox(8)
    var prev := UiTheme.button("Previous")
    prev.pressed.connect(func():
        _page = max(0, _page - 1)
        _render())
    pager.add_child(prev)
    _page_label = UiTheme.label("", 12, UiTheme.TEXT_DIM)
    pager.add_child(_page_label)
    var next := UiTheme.button("Next")
    next.pressed.connect(func():
        _page += 1
        _render())
    pager.add_child(next)
    left.add_child(pager)

    var inspect := UiTheme.panel(UiTheme.BG_PANEL, UiTheme.GOLD_DIM, 1, 6)
    inspect.custom_minimum_size = Vector2(330, 0)
    _inspect_holder = UiTheme.vbox(6)
    inspect.add_child(_inspect_holder)
    cols.add_child(inspect)
    _clear_inspect()

    _refilter()


func _filter_row() -> Control:
    var row := UiTheme.hbox(8)
    _search = LineEdit.new()
    _search.placeholder_text = "Search name, rules text or id"
    _search.add_theme_font_size_override("font_size", 13)
    _search.custom_minimum_size = Vector2(240, 0)
    _search.text_changed.connect(func(_t): _refilter())
    row.add_child(_search)

    _type = _picker(["Any type", "Hero", "Companion", "Skill", "Equipment", "Location", "Ta'ahma"])
    row.add_child(_type)
    var aff_items: Array = ["Any Affinity", "Neutral"]
    for a in EffectSchema.AFFINITIES:
        aff_items.append(String(a).capitalize())
    _affinity = _picker(aff_items)
    row.add_child(_affinity)
    _rarity = _picker(["Any rarity", "Common", "Uncommon", "Rare", "Legendary"])
    row.add_child(_rarity)
    _cost = _picker(["Any cost", "0", "1", "2", "3", "4", "5 or more", "X"])
    row.add_child(_cost)
    _ownership = _picker(["All cards", "Owned", "Not owned", "At my cap"])
    row.add_child(_ownership)

    var clear := UiTheme.button("Clear")
    clear.pressed.connect(func():
        _search.text = ""
        for p in [_type, _affinity, _rarity, _cost, _ownership]:
            (p as OptionButton).select(0)
        _refilter())
    row.add_child(clear)
    return row


func _picker(items: Array) -> OptionButton:
    var o := OptionButton.new()
    o.add_theme_font_size_override("font_size", 13)
    for i in items.size():
        o.add_item(String(items[i]), i)
    o.select(0)
    o.item_selected.connect(func(_i): _refilter())
    return o


func _refilter() -> void:
    _page = 0
    _matches = []
    var query := _search.text.strip_edges().to_lower()
    for def in app.catalog.all_defs():
        if not _passes(def, query):
            continue
        _matches.append(def)
    var owned_shown := 0
    for def in _matches:
        owned_shown += app.profile.owned_count((def as CardDef).id)
    _summary.text = "%d of %d definitions match. You own %d cop%s of them." % [
        _matches.size(), app.catalog.size(), owned_shown, "y" if owned_shown == 1 else "ies"]
    _render()


func _passes(def: CardDef, query: String) -> bool:
    if query != "":
        var haystack := "%s %s %s" % [def.name.to_lower(), def.text.to_lower(), def.id.to_lower()]
        if not haystack.contains(query):
            return false
    var t := _type.get_selected_id()
    if t > 0:
        var wanted: String = ["", "hero", "companion", "skill", "equipment", "location", "taahma"][t]
        if not def.has_type(wanted):
            return false
    var a := _affinity.get_selected_id()
    if a == 1:
        if not def.affinities.is_empty():
            return false
    elif a > 1:
        if not def.has_affinity(String(EffectSchema.AFFINITIES[a - 2])):
            return false
    var r := _rarity.get_selected_id()
    if r > 0 and def.rarity != ["", "common", "uncommon", "rare", "legendary"][r]:
        return false
    var c := _cost.get_selected_id()
    if c > 0:
        if c == 7:
            if def.cost_kind() != "x":
                return false
        elif def.cost_kind() == "x":
            return false
        elif c == 6:
            if def.fixed_cost() < 5:
                return false
        elif def.fixed_cost() != c - 1:
            return false
    var o := _ownership.get_selected_id()
    var have := app.profile.owned_count(def.id)
    if o == 1 and have <= 0:
        return false
    if o == 2 and have > 0:
        return false
    if o == 3 and have < app.catalog.collection_cap(def.id):
        return false
    return true


func _render() -> void:
    for c in _grid.get_children():
        c.queue_free()
    var pages: int = max(1, int(ceil(float(_matches.size()) / float(PAGE_SIZE))))
    _page = clamp(_page, 0, pages - 1)
    _page_label.text = "Page %d of %d" % [_page + 1, pages]
    var start := _page * PAGE_SIZE
    for i in range(start, min(start + PAGE_SIZE, _matches.size())):
        var def: CardDef = _matches[i]
        var view := CardView.create(def, 196.0, true)
        var have := app.profile.owned_count(def.id)
        var cap := app.catalog.collection_cap(def.id)
        view.add_badge("Owned %d / %d" % [have, cap],
            UiTheme.GOOD if have > 0 else UiTheme.TEXT_DIM)
        if app.catalog.is_overridden(def.id):
            view.add_badge("Edited", UiTheme.GOLD)
        view.pressed.connect(_inspect)
        _grid.add_child(view)


func _clear_inspect() -> void:
    for c in _inspect_holder.get_children():
        c.queue_free()
    _inspect_holder.add_child(UiTheme.label("Card details", 15, UiTheme.GOLD))
    _inspect_holder.add_child(UiTheme.wrapped(
        "Select a card to see its full definition, including the fields the card editor can change.",
        12, UiTheme.TEXT_DIM))


func _inspect(def_id: String) -> void:
    var def := app.catalog.get_def(def_id)
    if def == null:
        return
    for c in _inspect_holder.get_children():
        c.queue_free()
    _inspect_holder.add_child(CardView.create(def, 300.0))

    var rows: Array = [
        ["Identifier", def.id],
        ["Revision", str(def.revision)],
        ["Types", ", ".join(def.types)],
        ["Tags", UiTheme.tag_line(def) if not def.tags.is_empty() else "none"],
        ["Affinity", UiTheme.affinity_line(def)],
        ["Rarity", UiTheme.rarity_line(def)],
        ["Owned", "%d of a maximum %d" % [app.profile.owned_count(def.id), app.catalog.collection_cap(def.id)]],
        ["Deck limit", "1 copy" if (def.unique or def.is_named_character()) else "3 copies"],
        ["Behaviour", ", ".join(def.patterns)],
    ]
    if def.is_named_character():
        rows.append(["Named character", def.character_id])
    if def.is_character():
        rows.append(["Attack cost", "%d Energy" % def.attack_cost])
    if def.has_type("companion"):
        rows.append(["Adds to max Energy", str(def.energy_contribution)])
    if def.allows_reaction_timing():
        rows.append(["Timing", "Reaction, %s the Action" % def.reaction_window()])
    else:
        rows.append(["Timing", "Action"])
    for row in rows:
        var h := UiTheme.hbox(6)
        h.add_child(UiTheme.label(String(row[0]), 11, UiTheme.TEXT_DIM))
        var val := UiTheme.wrapped(String(row[1]), 11, UiTheme.TEXT)
        h.add_child(val)
        _inspect_holder.add_child(h)

    if def.flavor != "":
        _inspect_holder.add_child(UiTheme.wrapped(def.flavor, 11, UiTheme.TEXT_DIM))

    var edit := UiTheme.button("Edit this card")
    edit.pressed.connect(func(): app.goto("editor", {"def_id": def.id}))
    _inspect_holder.add_child(edit)
