class_name App
extends Control

## Application root: owns the shared services, the current screen and the
## active match, and is the only place that writes the save file.
##
## Screens render state and submit validated commands. They never hold their
## own copy of the rules.

var catalog: Catalog
var rules: RulesProfile
var economy: EconomyConfig
var store: SaveStore
var profile: PlayerProfile

## The live match, if one is in progress.
var match_state: GameState = null
var match_context: Dictionary = {}

var _body: Control
var _header: Control
var _gold_label: Label
var _toast: Label
var _toast_timer: float = 0.0
var _current_name: String = ""

const SCREENS := {
    "home": "res://src/ui/screens/home_screen.gd",
    "collection": "res://src/ui/screens/collection_screen.gd",
    "decks": "res://src/ui/screens/decks_screen.gd",
    "deck_builder": "res://src/ui/screens/deck_builder_screen.gd",
    "opponents": "res://src/ui/screens/opponents_screen.gd",
    "battle": "res://src/ui/screens/battle_screen.gd",
    "results": "res://src/ui/screens/results_screen.gd",
    "shop": "res://src/ui/screens/shop_screen.gd",
    "editor": "res://src/ui/screens/editor_screen.gd",
    "settings": "res://src/ui/screens/settings_screen.gd",
}


func _ready() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)
    _load_services()
    _build_chrome()
    goto("home")


func _load_services() -> void:
    rules = RulesProfile.load_from()
    economy = EconomyConfig.load_from()
    catalog = Catalog.load_bundled()
    store = SaveStore.new()
    var raw := store.load_raw()
    if raw.is_empty():
        profile = PlayerProfile.create_new(catalog, economy)
        save_profile()
    else:
        profile = PlayerProfile.new(raw)
    catalog.set_overrides(profile.overrides())
    var errs := catalog.validate_all()
    if not errs.is_empty():
        push_warning("Catalog reported %d problem(s); the first is: %s" % [errs.size(), String(errs[0])])


func save_profile() -> String:
    var err := store.commit(profile.to_dict())
    if err != "":
        toast("Save failed: %s" % err, true)
    return err


# ------------------------------------------------------------------- chrome ---

func _build_chrome() -> void:
    var bg := ColorRect.new()
    bg.color = UiTheme.BG
    bg.set_anchors_preset(Control.PRESET_FULL_RECT)
    bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(bg)

    var root := UiTheme.vbox(0)
    root.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(root)

    _header = _make_header()
    root.add_child(_header)
    root.add_child(UiTheme.separator())

    var body_holder := MarginContainer.new()
    body_holder.add_theme_constant_override("margin_left", 16)
    body_holder.add_theme_constant_override("margin_right", 16)
    body_holder.add_theme_constant_override("margin_top", 10)
    body_holder.add_theme_constant_override("margin_bottom", 8)
    body_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
    root.add_child(body_holder)

    _body = Control.new()
    _body.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    body_holder.add_child(_body)

    _toast = UiTheme.label("", 13, UiTheme.GOLD)
    _toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    root.add_child(_toast)


func _make_header() -> Control:
    var bar := UiTheme.panel(UiTheme.BG_PANEL)
    var row := UiTheme.hbox(10)
    row.add_child(UiTheme.label("HEROES OF TELORIA", 18, UiTheme.GOLD))
    row.add_child(UiTheme.label("prototype", 11, UiTheme.TEXT_DIM))

    var gap := Control.new()
    gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(gap)

    for entry in [["Home", "home"], ["Collection", "collection"], ["Decks", "decks"],
            ["Play", "opponents"], ["Shop", "shop"], ["Editor", "editor"], ["Settings", "settings"]]:
        var b := UiTheme.button(String(entry[0]))
        var target := String(entry[1])
        b.pressed.connect(func(): goto(target))
        row.add_child(b)

    _gold_label = UiTheme.label("", 15, UiTheme.GOLD)
    row.add_child(UiTheme.stat_chip("Gold", "0", UiTheme.GOLD))
    bar.add_child(row)
    return bar


func _refresh_header() -> void:
    # The gold chip is rebuilt rather than mutated so the caption stays put.
    var row: HBoxContainer = (_header.get_child(0) as HBoxContainer)
    var chip := row.get_child(row.get_child_count() - 1)
    row.remove_child(chip)
    chip.queue_free()
    row.add_child(UiTheme.stat_chip("Gold", str(profile.gold), UiTheme.GOLD))


func toast(message: String, is_error: bool = false) -> void:
    _toast.text = message
    _toast.add_theme_color_override("font_color", UiTheme.DANGER if is_error else UiTheme.GOOD)
    _toast_timer = 6.0


func _process(delta: float) -> void:
    if _toast_timer > 0.0:
        _toast_timer -= delta
        if _toast_timer <= 0.0:
            _toast.text = ""


# --------------------------------------------------------------- navigation ---

func goto(screen_name: String, args: Dictionary = {}) -> void:
    if not SCREENS.has(screen_name):
        toast("Unknown screen '%s'." % screen_name, true)
        return
    _current_name = screen_name
    # Detach immediately rather than waiting for queue_free at end of frame, so
    # the body always holds exactly the screen that is showing.
    for c in _body.get_children():
        _body.remove_child(c)
        c.queue_free()
    var script: Script = load(String(SCREENS[screen_name]))
    if script == null:
        toast("Screen '%s' could not be loaded." % screen_name, true)
        return
    var screen: Control = script.new()
    screen.set_anchors_preset(Control.PRESET_FULL_RECT)
    screen.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    screen.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _body.add_child(screen)
    if screen.has_method("setup"):
        screen.call("setup", self, args)
    _refresh_header()


func current_screen_name() -> String:
    return _current_name


# --------------------------------------------------------------- match setup ---

## Start a match between a saved deck and an Affinity opponent.
func start_match(deck_id: String, opponent_affinity: String, sandbox: bool = false) -> String:
    var deck := profile.deck_by_id(deck_id)
    if deck.is_empty():
        return "That deck no longer exists."
    var owned = null if sandbox else profile.owned()
    var check := DeckValidator.validate(catalog, rules, deck, owned)
    if not check["ok"]:
        return "That deck cannot enter a match: %s" % String((check["errors"] as Array)[0])
    var ai_deck := DeckLibrary.ai_deck_for(opponent_affinity)
    if ai_deck.is_empty():
        return "No opponent deck exists for %s." % opponent_affinity

    var rng := RandomNumberGenerator.new()
    rng.randomize()
    var match_id := Ids.unique("match")
    match_state = GameEngine.start_match(catalog, rules, [deck, ai_deck], rng.randi() & 0x7FFFFFFF,
        match_id, ["You", String(ai_deck.get("name", "Opponent"))], [false, true],
        ["", opponent_affinity])
    match_context = {
        "deck_id": deck_id, "deck_name": String(deck.get("name", "Deck")),
        "opponent": opponent_affinity,
        "opponent_name": String(ai_deck.get("name", "Opponent")),
        "sandbox": sandbox, "match_id": match_id, "rewarded": false,
    }
    persist_match()
    return ""


## Keep the active match in the save so it survives a reload. The snapshot
## carries the card and rules versions it started with.
func persist_match() -> void:
    if match_state == null:
        profile.clear_active_match()
    else:
        var snapshot := match_state.to_dict(true)
        # The log is for reading, not for rules: keep the recent part so the
        # save stays a sensible size across a long match.
        var events: Array = snapshot.get("events", [])
        if events.size() > 400:
            snapshot["events"] = events.slice(events.size() - 400, events.size())
        profile.set_active_match({"context": match_context, "state": snapshot})
    save_profile()


func resume_match() -> bool:
    var saved = profile.active_match()
    if not (saved is Dictionary):
        return false
    var d: Dictionary = saved
    if not (d.get("state", null) is Dictionary):
        return false
    match_state = GameState.from_dict(d["state"])
    match_context = (d.get("context", {}) as Dictionary).duplicate(true)
    return true


func has_active_match() -> bool:
    return match_state != null or (profile.active_match() is Dictionary)


func end_match() -> void:
    match_state = null
    match_context = {}
    profile.clear_active_match()
    save_profile()


## The outcome from the human player's point of view.
func outcome_for_player() -> String:
    if match_state == null or match_state.result == null:
        return ""
    var res: Dictionary = match_state.result
    if bool(res.get("conceded", false)) and int(res.get("loser", -1)) == 0:
        return "concede"
    var winner := int(res.get("winner", -1))
    if winner == 0:
        return "win"
    if winner == -1:
        return "draw"
    return "loss"
