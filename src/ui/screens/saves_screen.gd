extends Control

## Save selection: choose a game to continue, or start a new one.
##
## A new save picks the Affinity it begins in, and that Affinity's starter deck
## is the whole of its collection. Everything else in the catalog is earned, so
## the shop and the packs are the progression rather than decoration on a
## collection the save already has.
##
## Nothing here writes to disk until the player chooses to. Browsing the list,
## opening the Affinity picker and backing out again all leave every save
## exactly as it was.

var app: App

## The slot a new save is being started in, or 0 when the list is showing.
var _choosing_slot: int = 0
var _name_edit: LineEdit
var _root: VBoxContainer


func setup(application: App, _args: Dictionary = {}) -> void:
    app = application
    _root = UiTheme.vbox(10)
    _root.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(_root)
    _show_list()


func _clear() -> void:
    for c in _root.get_children():
        _root.remove_child(c)
        c.queue_free()


# ---------------------------------------------------------------- the list ---

func _show_list() -> void:
    _choosing_slot = 0
    _clear()
    _root.add_child(UiTheme.heading("Saves"))
    _root.add_child(UiTheme.wrapped(
        "Each save is its own game, with its own collection, decks and gold. "
        + "A new save begins with one Affinity's starter deck and nothing else.",
        12, UiTheme.TEXT_DIM))

    if app.store.last_load_problem != "":
        _root.add_child(UiTheme.wrapped(app.store.last_load_problem, 12, UiTheme.DANGER))

    var grid := GridContainer.new()
    grid.columns = 3
    grid.add_theme_constant_override("h_separation", 12)
    grid.add_theme_constant_override("v_separation", 12)
    for row in app.store.list_slots():
        grid.add_child(_slot_tile(row as Dictionary))
    _root.add_child(UiTheme.scroll(grid))

    _root.add_child(UiTheme.label(
        "Saves are files in %s. Export one from Settings to move it between devices."
        % ProjectSettings.globalize_path(SaveStore.SLOT_DIR), 11, UiTheme.TEXT_DIM))


func _slot_tile(row: Dictionary) -> Control:
    var target := int(row.get("slot", 0))
    var used := bool(row.get("used", false))
    var problem := String(row.get("problem", ""))
    var affinity := String(row.get("affinity", ""))
    var colour := UiTheme.affinity_color(affinity) if used and problem == "" else UiTheme.GOLD_DIM
    var live := used and app.slot == target

    var p := UiTheme.panel(UiTheme.BG_PANEL, UiTheme.GOLD if live else colour, 2, 6)
    p.custom_minimum_size = Vector2(430, 168)
    var v := UiTheme.vbox(5)

    var title := UiTheme.hbox(8)
    title.add_child(UiTheme.label("Slot %d" % target, 12, UiTheme.TEXT_DIM))
    if used and problem == "":
        title.add_child(UiTheme.label("%s %s" % [
            String(UiTheme.AFFINITY_GLYPH.get(affinity, "◇")),
            String(row.get("display_name", "Save"))], 17, colour))
    elif used:
        title.add_child(UiTheme.label("Unreadable save", 17, UiTheme.DANGER))
    else:
        title.add_child(UiTheme.label("Empty", 17, UiTheme.TEXT_DIM))
    if live:
        var gap := Control.new()
        gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        title.add_child(gap)
        title.add_child(UiTheme.label("playing now", 11, UiTheme.GOLD))
    v.add_child(title)

    if problem != "":
        v.add_child(UiTheme.wrapped(
            problem + " Its backup is still on disk; nothing has been deleted.",
            12, UiTheme.DANGER))
    elif used:
        v.add_child(UiTheme.label("%s — %s" % [affinity.capitalize(),
            _when(String(row.get("saved_at", "")))], 12, UiTheme.TEXT))
        var facts := UiTheme.hbox(8)
        facts.add_child(UiTheme.stat_chip("Gold", str(int(row.get("gold", 0))), UiTheme.GOLD))
        facts.add_child(UiTheme.stat_chip("Cards", str(int(row.get("copies", 0)))))
        facts.add_child(UiTheme.stat_chip("Decks", str(int(row.get("decks", 0)))))
        facts.add_child(UiTheme.stat_chip("Matches", str(int(row.get("matches", 0)))))
        v.add_child(facts)
        if bool(row.get("in_match", false)):
            v.add_child(UiTheme.label("A match is in progress.", 11, UiTheme.GOLD))
    else:
        v.add_child(UiTheme.wrapped(
            "Start a new game here. You choose the Affinity it begins in.",
            12, UiTheme.TEXT_DIM))

    var gap2 := Control.new()
    gap2.size_flags_vertical = Control.SIZE_EXPAND_FILL
    v.add_child(gap2)

    var buttons := UiTheme.hbox(8)
    if used and problem == "":
        var play := UiTheme.primary_button("Continue" if not live else "Back to the game")
        play.pressed.connect(func(): _continue(target))
        buttons.add_child(play)
        var del := UiTheme.button("Delete",
            "Moves this save to its backup file. Nothing is erased from disk.")
        del.pressed.connect(func(): _delete(target))
        buttons.add_child(del)
    elif not used:
        var make := UiTheme.primary_button("New save")
        make.pressed.connect(func(): _show_picker(target))
        buttons.add_child(make)
    v.add_child(buttons)

    p.add_child(v)
    return p


## A timestamp in a form worth reading. The save stores ISO-8601 UTC.
func _when(stamp: String) -> String:
    if stamp == "":
        return "never saved"
    return "saved %s" % stamp.replace("T", " at ").trim_suffix("Z")


func _continue(target: int) -> void:
    if app.slot == target and app.has_save():
        app.goto("home")
        return
    var err := app.load_save(target)
    if err != "":
        app.toast(err, true)
        _show_list()
        return
    app.toast("Playing %s." % app.profile.display_name)
    app.goto("home")


var _delete_armed: int = 0


func _delete(target: int) -> void:
    if _delete_armed != target:
        _delete_armed = target
        app.toast("Press Delete again to remove slot %d. Its backup file is kept." % target, true)
        return
    _delete_armed = 0
    var err := app.store.delete_slot(target)
    if err != "":
        app.toast(err, true)
        return
    if app.slot == target:
        app.close_save()
        return
    app.toast("Slot %d deleted. Its backup file is still on disk." % target)
    _show_list()


# ------------------------------------------------------- the new-save picker ---

func _show_picker(target: int) -> void:
    _choosing_slot = target
    _clear()
    _root.add_child(UiTheme.heading("New save — slot %d" % target))
    _root.add_child(UiTheme.wrapped(
        "Choose the Affinity you begin in. You start with that starter deck and "
        + "exactly the cards it needs — nothing else in the collection is unlocked. "
        + "Everything else is won with gold and opened from packs, and you can play "
        + "against all seven Affinities from the start.",
        12, UiTheme.TEXT))

    var name_row := UiTheme.hbox(8)
    name_row.add_child(UiTheme.label("Name this save:", 13))
    _name_edit = LineEdit.new()
    _name_edit.placeholder_text = "optional"
    _name_edit.custom_minimum_size = Vector2(260, 0)
    _name_edit.add_theme_font_size_override("font_size", 14)
    name_row.add_child(_name_edit)
    var back := UiTheme.button("Back")
    back.pressed.connect(_show_list)
    name_row.add_child(back)
    _root.add_child(name_row)

    var grid := GridContainer.new()
    grid.columns = 3
    grid.add_theme_constant_override("h_separation", 12)
    grid.add_theme_constant_override("v_separation", 12)
    for deck in DeckLibrary.starters():
        grid.add_child(_affinity_tile(deck as Dictionary))
    _root.add_child(UiTheme.scroll(grid))


func _affinity_tile(deck: Dictionary) -> Control:
    var affinity := String(deck.get("affinity", ""))
    var colour := UiTheme.affinity_color(affinity)
    var p := UiTheme.panel(UiTheme.BG_PANEL, colour, 2, 6)
    p.custom_minimum_size = Vector2(430, 190)
    var v := UiTheme.vbox(5)

    var title := UiTheme.hbox(8)
    title.add_child(UiTheme.label("%s %s" % [
        String(UiTheme.AFFINITY_GLYPH.get(affinity, "◇")), affinity.capitalize()], 18, colour))
    var gap := Control.new()
    gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    title.add_child(gap)
    var hero := app.catalog.get_def(String(deck.get("hero", "")))
    title.add_child(UiTheme.label("Hero: %s" % (hero.name if hero != null else "?"),
        12, UiTheme.TEXT_DIM))
    v.add_child(title)

    v.add_child(UiTheme.label(String(deck.get("plan", "")), 13, UiTheme.GOLD))
    v.add_child(UiTheme.wrapped(String(deck.get("description", "")), 12, UiTheme.TEXT))

    var grant := DeckLibrary.starter_grant_for(affinity)
    var copies := 0
    for id in grant:
        copies += int(grant[id])
    v.add_child(UiTheme.label("You would start with %d cards across %d definitions."
        % [copies, grant.size()], 11, UiTheme.TEXT_DIM))

    var gap2 := Control.new()
    gap2.size_flags_vertical = Control.SIZE_EXPAND_FILL
    v.add_child(gap2)

    var begin := UiTheme.primary_button("Begin in %s" % affinity.capitalize())
    begin.pressed.connect(func(): _begin(affinity))
    v.add_child(begin)

    p.add_child(v)
    return p


func _begin(affinity: String) -> void:
    var chosen := _name_edit.text.strip_edges() if _name_edit != null else ""
    var err := app.start_new_save(_choosing_slot, affinity, chosen)
    if err != "":
        app.toast(err, true)
        _show_list()
        return
    app.toast("New save started in %s." % affinity.capitalize())
    app.goto("home")
