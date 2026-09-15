extends Control

## Home: continue a match, play, and reach every other screen.

var app: App


func setup(application: App, _args: Dictionary = {}) -> void:
    app = application
    var root := UiTheme.vbox(14)
    root.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(root)

    root.add_child(UiTheme.heading("Teloria awaits", 26))
    root.add_child(UiTheme.wrapped(
        "Build a deck, choose an Affinity opponent, play a full match, earn gold for winning, "
        + "then buy and open packs to improve your decks. Everything here is placeholder proxy "
        + "content: names, art and numbers are meant to be replaced.", 14, UiTheme.TEXT_DIM))

    var stats := UiTheme.hbox(10)
    stats.add_child(UiTheme.stat_chip("Gold", str(app.profile.gold), UiTheme.GOLD))
    stats.add_child(UiTheme.stat_chip("Cards owned", str(_total_owned())))
    stats.add_child(UiTheme.stat_chip("Distinct", "%d / %d" % [app.profile.distinct_owned(), app.catalog.size()]))
    stats.add_child(UiTheme.stat_chip("Decks", str(app.profile.decks().size())))
    stats.add_child(UiTheme.stat_chip("Matches", str(app.profile.record_count())))
    stats.add_child(UiTheme.stat_chip("Wins", str(app.profile.wins()), UiTheme.GOOD))
    root.add_child(stats)
    root.add_child(UiTheme.separator())

    if app.has_active_match():
        var resume_panel := UiTheme.panel(UiTheme.BG_PANEL, UiTheme.GOLD, 1, 6)
        var rv := UiTheme.vbox(6)
        rv.add_child(UiTheme.label("A match is in progress", 16, UiTheme.GOLD))
        var ctx := _saved_context()
        rv.add_child(UiTheme.label("%s against the %s opponent." % [
            String(ctx.get("deck_name", "Your deck")), String(ctx.get("opponent", "?")).capitalize()],
            13, UiTheme.TEXT_DIM))
        var rrow := UiTheme.hbox(8)
        var cont := UiTheme.primary_button("Continue match")
        cont.pressed.connect(func():
            if app.match_state != null or app.resume_match():
                app.goto("battle")
            else:
                app.toast("That match could not be resumed.", true))
        rrow.add_child(cont)
        var abandon := UiTheme.button("Abandon match", "Ends the match without a reward.")
        abandon.pressed.connect(func():
            app.end_match()
            app.toast("The match was abandoned. No gold was awarded.")
            app.goto("home"))
        rrow.add_child(abandon)
        rv.add_child(rrow)
        resume_panel.add_child(rv)
        root.add_child(resume_panel)

    var grid := GridContainer.new()
    grid.columns = 3
    grid.add_theme_constant_override("h_separation", 12)
    grid.add_theme_constant_override("v_separation", 12)
    root.add_child(grid)

    var entries := [
        ["Play a match", "opponents", "Choose one of the seven Affinity opponents."],
        ["Decks", "decks", "Create, edit, duplicate, import and export decks."],
        ["Collection", "collection", "Search and filter every card you own."],
        ["Shop", "shop", "Spend gold on boosters and see the slot odds."],
        ["Card editor", "editor", "Change a card's supported fields and preview it."],
        ["Settings and help", "settings", "Rules reference, save export and import."],
    ]
    for e in entries:
        grid.add_child(_tile(String(e[0]), String(e[1]), String(e[2])))

    root.add_child(UiTheme.spacer(4))
    root.add_child(UiTheme.wrapped(
        "Saves live in this browser or on this device only. Use Settings to export a save file "
        + "if you want to move or recover your progress. Nothing is synchronised to a server.",
        12, UiTheme.TEXT_DIM))


func _tile(title: String, target: String, blurb: String) -> Control:
    var p := UiTheme.panel(UiTheme.BG_PANEL, UiTheme.GOLD_DIM, 1, 6)
    p.custom_minimum_size = Vector2(260, 96)
    var v := UiTheme.vbox(6)
    v.add_child(UiTheme.label(title, 17, UiTheme.GOLD))
    v.add_child(UiTheme.wrapped(blurb, 12, UiTheme.TEXT_DIM))
    var b := UiTheme.button("Open")
    b.pressed.connect(func(): app.goto(target))
    v.add_child(b)
    p.add_child(v)
    return p


func _total_owned() -> int:
    var n := 0
    for k in app.profile.owned().keys():
        n += int(app.profile.owned()[k])
    return n


func _saved_context() -> Dictionary:
    if not app.match_context.is_empty():
        return app.match_context
    var saved = app.profile.active_match()
    if saved is Dictionary:
        return (saved as Dictionary).get("context", {})
    return {}
