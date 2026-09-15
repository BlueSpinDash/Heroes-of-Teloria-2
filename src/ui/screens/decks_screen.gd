extends Control

## Deck list: create, edit, duplicate, delete, import and export.

var app: App
var _path_edit: LineEdit


func setup(application: App, _args: Dictionary = {}) -> void:
    app = application
    var root := UiTheme.vbox(10)
    root.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(root)

    var head := UiTheme.hbox(8)
    head.add_child(UiTheme.heading("Decks"))
    var gap := Control.new()
    gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    head.add_child(gap)
    var new_deck := UiTheme.primary_button("New deck")
    new_deck.pressed.connect(func(): app.goto("deck_builder", {"new": true}))
    head.add_child(new_deck)
    root.add_child(head)

    root.add_child(UiTheme.wrapped(
        "Saving a deck never consumes cards: the same owned copies can back several decks. "
        + "A deck that is not legal can still be saved, but cannot enter a normal match.",
        12, UiTheme.TEXT_DIM))

    var list := UiTheme.vbox(8)
    for deck in app.profile.decks():
        list.add_child(_deck_row(deck))
    root.add_child(UiTheme.scroll(list))

    var io := UiTheme.hbox(8)
    _path_edit = LineEdit.new()
    _path_edit.text = "user://deck_export.json"
    _path_edit.add_theme_font_size_override("font_size", 12)
    _path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    io.add_child(_path_edit)
    var import_btn := UiTheme.button("Import deck from JSON")
    import_btn.pressed.connect(_import)
    io.add_child(import_btn)
    root.add_child(io)


func _deck_row(deck: Dictionary) -> Control:
    var check := DeckValidator.validate(app.catalog, app.rules, deck, app.profile.owned())
    var stats := DeckValidator.stats(app.catalog, deck)
    var colour := UiTheme.GOOD if check["ok"] else UiTheme.DANGER
    var p := UiTheme.panel(UiTheme.BG_PANEL, colour, 1, 6)
    var v := UiTheme.vbox(5)

    var title := UiTheme.hbox(8)
    title.add_child(UiTheme.label(String(deck.get("name", "Deck")), 17, UiTheme.GOLD))
    var hero := app.catalog.get_def(String(deck.get("hero", "")))
    title.add_child(UiTheme.label("Hero: %s" % (hero.name if hero != null else "none chosen"),
        12, UiTheme.TEXT_DIM))
    if bool(deck.get("starter", false)):
        title.add_child(UiTheme.label("granted starter", 11, UiTheme.TEXT_DIM))
    var gap := Control.new()
    gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    title.add_child(gap)
    title.add_child(UiTheme.label("%d / %d cards" % [int(stats["total"]), app.rules.hit_deck_size],
        13, colour))
    v.add_child(title)

    var mix := UiTheme.hbox(6)
    var aff: Dictionary = stats["by_affinity"]
    var keys: Array = aff.keys()
    keys.sort()
    for k in keys:
        mix.add_child(UiTheme.label("%s %s %d" % [
            String(UiTheme.AFFINITY_GLYPH.get(String(k), "◇")), String(k).capitalize(), int(aff[k])],
            11, UiTheme.affinity_color(String(k))))
    mix.add_child(UiTheme.label("• %d Reaction cards" % int(stats["reactions"]), 11, UiTheme.TEXT_DIM))
    v.add_child(mix)

    if not check["ok"]:
        for e in check["errors"]:
            v.add_child(UiTheme.wrapped("• %s" % String(e), 11, UiTheme.DANGER))

    var row := UiTheme.hbox(6)
    var deck_id := String(deck.get("deck_id", ""))
    var edit := UiTheme.button("Edit")
    edit.pressed.connect(func(): app.goto("deck_builder", {"deck_id": deck_id}))
    row.add_child(edit)
    var dup := UiTheme.button("Duplicate")
    dup.pressed.connect(func():
        var new_id := app.profile.duplicate_deck(deck_id)
        app.save_profile()
        app.toast("Deck duplicated.")
        app.goto("deck_builder", {"deck_id": new_id}))
    row.add_child(dup)
    var export_btn := UiTheme.button("Export")
    export_btn.pressed.connect(func(): _export(deck))
    row.add_child(export_btn)
    var play := UiTheme.button("Play with this deck")
    play.disabled = not check["ok"]
    play.pressed.connect(func(): app.goto("opponents"))
    row.add_child(play)
    var del := UiTheme.button("Delete")
    del.pressed.connect(func(): _delete(deck_id, String(deck.get("name", "Deck"))))
    row.add_child(del)
    v.add_child(row)

    p.add_child(v)
    return p


var _pending_delete := ""


func _delete(deck_id: String, name: String) -> void:
    if _pending_delete != deck_id:
        _pending_delete = deck_id
        app.toast("Press Delete again to remove '%s'. This cannot be undone." % name, true)
        return
    app.profile.delete_deck(deck_id)
    app.save_profile()
    app.toast("Deleted '%s'." % name)
    app.goto("decks")


func _export(deck: Dictionary) -> void:
    var path := _path_edit.text.strip_edges()
    var payload := {
        "format": "heroes_of_teloria_deck", "version": 1,
        "name": String(deck.get("name", "Deck")), "hero": String(deck.get("hero", "")),
        "cards": (deck.get("cards", {}) as Dictionary).duplicate(),
    }
    var f := FileAccess.open(path, FileAccess.WRITE)
    if f == null:
        app.toast("Could not write %s." % path, true)
        return
    f.store_string(JSON.stringify(payload, "  "))
    f.close()
    app.toast("Deck exported to %s" % path)


func _import() -> void:
    var path := _path_edit.text.strip_edges()
    if not FileAccess.file_exists(path):
        app.toast("No file at %s." % path, true)
        return
    var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
    if not (parsed is Dictionary):
        app.toast("That file is not a deck export.", true)
        return
    var d: Dictionary = parsed
    if String(d.get("format", "")) != "heroes_of_teloria_deck":
        app.toast("That file is not a Heroes of Teloria deck export.", true)
        return
    if not (d.get("cards", null) is Dictionary):
        app.toast("That deck export has no card list.", true)
        return
    var deck := {
        "deck_id": Ids.unique("deck"),
        "name": String(d.get("name", "Imported deck")),
        "hero": String(d.get("hero", "")),
        "cards": (d["cards"] as Dictionary).duplicate(),
        "starter": false,
    }
    # Imports are revalidated against the current catalog, and a deck that is
    # not legal is still saved so nothing is lost.
    var check := DeckValidator.validate(app.catalog, app.rules, deck, app.profile.owned())
    app.profile.save_deck(deck)
    app.save_profile()
    if check["ok"]:
        app.toast("Deck imported and legal.")
    else:
        app.toast("Deck imported but not legal: %s" % String((check["errors"] as Array)[0]), true)
    app.goto("decks")
