extends Control

## Opponent selection: the seven Affinity opponents, each with an accurate
## description of what its deck actually tries to do.

var app: App
var _deck_picker: OptionButton
var _decks: Array = []


func setup(application: App, _args: Dictionary = {}) -> void:
    app = application
    var root := UiTheme.vbox(10)
    root.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(root)

    root.add_child(UiTheme.heading("Choose an opponent"))

    var deck_row := UiTheme.hbox(8)
    deck_row.add_child(UiTheme.label("Your deck:", 14))
    _deck_picker = OptionButton.new()
    _deck_picker.add_theme_font_size_override("font_size", 14)
    _decks = app.profile.decks()
    var default_index := 0
    for i in _decks.size():
        var d: Dictionary = _decks[i]
        var check := DeckValidator.validate(app.catalog, app.rules, d, app.profile.owned())
        var suffix := "" if check["ok"] else "  (not legal)"
        _deck_picker.add_item("%s%s" % [String(d.get("name", "Deck")), suffix], i)
        if check["ok"] and default_index == 0:
            default_index = i
    if _decks.is_empty():
        _deck_picker.add_item("No decks saved", 0)
    _deck_picker.select(default_index)
    _deck_picker.item_selected.connect(func(_i): _refresh_legality())
    deck_row.add_child(_deck_picker)

    var edit := UiTheme.button("Deck builder")
    edit.pressed.connect(func(): app.goto("decks"))
    deck_row.add_child(edit)
    root.add_child(deck_row)

    _legality = UiTheme.wrapped("", 12, UiTheme.TEXT_DIM)
    root.add_child(_legality)
    root.add_child(UiTheme.separator())

    var grid := GridContainer.new()
    grid.columns = 2
    grid.add_theme_constant_override("h_separation", 12)
    grid.add_theme_constant_override("v_separation", 12)
    for deck in DeckLibrary.ai_decks():
        grid.add_child(_opponent_tile(deck))
    root.add_child(UiTheme.scroll(grid))
    _refresh_legality()


var _legality: Label


func _refresh_legality() -> void:
    var deck := _selected_deck()
    if deck.is_empty():
        _legality.text = "Save a deck before playing a match."
        _legality.add_theme_color_override("font_color", UiTheme.DANGER)
        return
    var check := DeckValidator.validate(app.catalog, app.rules, deck, app.profile.owned())
    if check["ok"]:
        _legality.text = "%s is legal: one Hero and %d cards, all owned." % [
            String(deck.get("name", "Deck")), int(check["count"])]
        _legality.add_theme_color_override("font_color", UiTheme.GOOD)
    else:
        _legality.text = "%s cannot enter a match — %s" % [
            String(deck.get("name", "Deck")), " ".join(check["errors"])]
        _legality.add_theme_color_override("font_color", UiTheme.DANGER)


func _selected_deck() -> Dictionary:
    if _decks.is_empty():
        return {}
    var idx: int = clamp(_deck_picker.get_selected_id(), 0, _decks.size() - 1)
    return _decks[idx]


func _opponent_tile(deck: Dictionary) -> Control:
    var affinity := String(deck.get("affinity", ""))
    var colour := UiTheme.affinity_color(affinity)
    var p := UiTheme.panel(UiTheme.BG_PANEL, colour, 2, 6)
    p.custom_minimum_size = Vector2(420, 150)
    var v := UiTheme.vbox(6)

    var title := UiTheme.hbox(8)
    title.add_child(UiTheme.label("%s %s" % [
        String(UiTheme.AFFINITY_GLYPH.get(affinity, "◇")), String(deck.get("name", "Opponent"))],
        18, colour))
    var gap := Control.new()
    gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    title.add_child(gap)
    var hero_def := app.catalog.get_def(String(deck.get("hero", "")))
    title.add_child(UiTheme.label("Hero: %s" % (hero_def.name if hero_def != null else "?"),
        12, UiTheme.TEXT_DIM))
    v.add_child(title)

    v.add_child(UiTheme.label(String(deck.get("plan", "")), 13, UiTheme.GOLD))
    v.add_child(UiTheme.wrapped(String(deck.get("description", "")), 12, UiTheme.TEXT))

    var facts := UiTheme.hbox(8)
    facts.add_child(UiTheme.label("45 cards", 11, UiTheme.TEXT_DIM))
    facts.add_child(UiTheme.label("• %d carry %s" % [
        int(deck.get("on_affinity_cards", 0)), affinity.capitalize()], 11, UiTheme.TEXT_DIM))
    if hero_def != null:
        facts.add_child(UiTheme.label("• Hero %d/%d, %d max Energy" % [
            hero_def.attack, hero_def.defense, hero_def.hero_max_energy], 11, UiTheme.TEXT_DIM))
    v.add_child(facts)

    var row := UiTheme.hbox(8)
    var play := UiTheme.primary_button("Play")
    play.pressed.connect(func(): _start(affinity, false))
    row.add_child(play)
    var sandbox := UiTheme.button("Developer sandbox",
        "Plays with every card unlocked. Sandbox matches award no gold.")
    sandbox.pressed.connect(func(): _start(affinity, true))
    row.add_child(sandbox)
    v.add_child(row)

    p.add_child(v)
    return p


func _start(affinity: String, sandbox: bool) -> void:
    if app.has_active_match():
        app.toast("Finish or abandon the match in progress first.", true)
        return
    var deck := _selected_deck()
    if deck.is_empty():
        app.toast("Save a deck first.", true)
        return
    var err := app.start_match(String(deck.get("deck_id", "")), affinity, sandbox)
    if err != "":
        app.toast(err, true)
        return
    app.goto("battle")
