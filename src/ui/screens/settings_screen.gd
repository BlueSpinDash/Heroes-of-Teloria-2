extends Control

## Settings and help: a compact rules reference, save export and import,
## accessibility, and developer controls.

var app: App
var _path_edit: LineEdit
var _sim_output: Label


func setup(application: App, _args: Dictionary = {}) -> void:
    app = application
    var root := UiTheme.vbox(12)
    root.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(root)
    root.add_child(UiTheme.heading("Settings and help"))

    var cols := UiTheme.hbox(14)
    cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
    root.add_child(cols)

    var left := UiTheme.vbox(10)
    left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    cols.add_child(UiTheme.scroll(left))

    var right := UiTheme.vbox(10)
    right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    cols.add_child(UiTheme.scroll(right))

    left.add_child(_rules_reference())
    right.add_child(_save_section())
    right.add_child(_accessibility_section())
    right.add_child(_developer_section())


func _section(title: String) -> Array:
    var p := UiTheme.panel(UiTheme.BG_PANEL, UiTheme.GOLD_DIM, 1, 6)
    var v := UiTheme.vbox(5)
    v.add_child(UiTheme.label(title, 16, UiTheme.GOLD))
    p.add_child(v)
    return [p, v]


func _rules_reference() -> Control:
    var pair := _section("Rules reference")
    var v: VBoxContainer = pair[1]
    var entries := [
        ["The round", "Draw, Action, Resolve, Round End. In the Draw Phase each player draws until "
            + "holding five cards; holding five or more you draw nothing and discard nothing."],
        ["Action Phase", "Players alternate committing one Action at a time to the right end of "
            + "the shared Action Sequence. Passing is permanent for normal Actions that round, but "
            + "you may still play Reactions while the Sequence resolves."],
        ["Resolve Phase", "The Sequence resolves left to right. Before each step there is a "
            + "Reaction window: the opponent of that step's controller responds first, then "
            + "opportunities alternate, and two passes in a row close the window."],
        ["Energy", "You have one Energy pool and one maximum. Your Hero's printed maximum starts "
            + "it and each Companion in play adds its printed Energy. Costs are paid when you "
            + "commit, refunds cap at your maximum, and Round End refreshes you to full."],
        ["Attacks", "A Hero or eligible Companion may commit one attack per round, paying its "
            + "attack cost and choosing its target then. Damage is Attack minus Defense at "
            + "resolution. Any positive damage destroys a Companion; zero damage does not. "
            + "Drag the character onto what it attacks, or use its Attack button."],
        ["Hero damage", "There is no Hero health. Damage moves that many random cards to your "
            + "Wound Deck, from Exhaust first and then from Hit, without reshuffling."],
        ["Losing", "You lose when Hit plus Exhaust cannot supply a required draw, a required "
            + "removal, or the full amount of Hero damage. Empty decks alone are not a loss."],
        ["Persistent cards", "A character may hold one Equipment and one Ta'ahma. Replacing one "
            + "sends the old card to Exhaust; destroying it sends it to Wound. Only one Location "
            + "is active at a time."],
        ["Affinity chains", "Consecutive Affinity-bearing Actions form a chain. A card with no "
            + "Affinity breaks the chain and cannot start one. Chains award nothing by themselves: "
            + "individual cards state their own requirements and rewards."],
        ["Deck rules", "One Hero outside a Hit Deck of exactly 45 cards, at most three copies of a "
            + "card name, one copy of a named character or a Unique card, no sideboard, and no "
            + "Affinity restriction."],
    ]
    for e in entries:
        v.add_child(UiTheme.label(String(e[0]), 13, UiTheme.TEXT))
        v.add_child(UiTheme.wrapped(String(e[1]), 12, UiTheme.TEXT_DIM))
        v.add_child(UiTheme.spacer(2))
    v.add_child(UiTheme.wrapped(
        "Some timing details are provisional prototype defaults rather than settled rules. "
        + "They are listed in PROVISIONAL_RULES.md and can be changed in data/rules_profile.json.",
        12, UiTheme.GOLD))
    return pair[0]


func _save_section() -> Control:
    var pair := _section("Save, export and import")
    var v: VBoxContainer = pair[1]
    v.add_child(UiTheme.wrapped(
        "Your progress is stored in this browser or on this device only. Exporting writes a save "
        + "file you can keep as a backup or move to another device. Nothing is synchronised to a "
        + "server.", 12, UiTheme.TEXT_DIM))

    _path_edit = LineEdit.new()
    _path_edit.text = "user://heroes_of_teloria_export.json"
    _path_edit.add_theme_font_size_override("font_size", 12)
    _path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    v.add_child(_path_edit)
    v.add_child(UiTheme.label("Save folder: %s" % ProjectSettings.globalize_path("user://"),
        11, UiTheme.TEXT_DIM))

    var row := UiTheme.hbox(8)
    var export_btn := UiTheme.button("Export save", "Writes the save in this slot to that path.")
    export_btn.pressed.connect(_export)
    row.add_child(export_btn)
    var import_btn := UiTheme.button("Import save",
        "Reads that file into this slot. The save already here is kept as its backup.")
    import_btn.pressed.connect(_import)
    row.add_child(import_btn)
    var switch_btn := UiTheme.button("Switch save", "Go back to the save list.")
    switch_btn.pressed.connect(func(): app.goto("saves"))
    row.add_child(switch_btn)
    v.add_child(row)
    v.add_child(UiTheme.label("Importing writes into slot %d, the save you are playing."
        % app.slot, 11, UiTheme.TEXT_DIM))

    if app.store.last_load_problem != "":
        v.add_child(UiTheme.wrapped("Last load: %s" % app.store.last_load_problem, 12, UiTheme.DANGER))
    return pair[0]


func _export() -> void:
    var path := _path_edit.text.strip_edges()
    if path == "":
        app.toast("Enter a file path to export to.", true)
        return
    var err := app.store.export_to(path, app.profile.to_dict())
    if err != "":
        app.toast(err, true)
        return
    if OS.has_feature("web"):
        _browser_download(path)
    app.toast("Exported to %s" % path)


## In a web build the virtual filesystem is not reachable from the desktop, so
## the export is handed to the browser as a download instead.
func _browser_download(path: String) -> void:
    if not ClassDB.class_exists("JavaScriptBridge"):
        return
    var bytes := FileAccess.get_file_as_bytes(path)
    if bytes.is_empty():
        return
    JavaScriptBridge.download_buffer(bytes, "heroes_of_teloria_save.json", "application/json")


func _import() -> void:
    var path := _path_edit.text.strip_edges()
    var read := app.store.read_import(path)
    if not bool(read["ok"]):
        app.toast(String(read["error"]), true)
        return
    # The previous save is rotated to the backup by the commit itself, so the
    # old progress stays recoverable.
    app.profile = PlayerProfile.new(read["data"])
    app.catalog = Catalog.load_bundled()
    app.catalog.set_overrides(app.profile.overrides())
    app.match_state = null
    app.match_context = {}
    var err := app.save_profile()
    if err != "":
        return
    app.toast("Save imported into slot %d. The save that was there is kept as its backup."
        % app.slot)
    app.goto("home")


func _accessibility_section() -> Control:
    var pair := _section("Accessibility")
    var v: VBoxContainer = pair[1]
    v.add_child(UiTheme.wrapped(
        "Affinity, rarity and legality are always spelled out in text as well as colour. In a "
        + "match you can drag a card onto its target, or do exactly the same thing by clicking: "
        + "every action has a button. Dragging is never required.", 12, UiTheme.TEXT_DIM))

    var row := UiTheme.hbox(8)
    row.add_child(UiTheme.label("Text size:", 13))
    for entry in [["Normal", 1.0], ["Large", 1.2], ["Larger", 1.45]]:
        var b := UiTheme.button(String(entry[0]))
        var scale_value := float(entry[1])
        b.pressed.connect(func():
            UiTheme.text_scale = scale_value
            app.profile.set_setting("text_scale", scale_value)
            app.save_profile()
            app.goto("settings"))
        row.add_child(b)
    v.add_child(row)
    v.add_child(UiTheme.label("Current: %d%%" % int(UiTheme.text_scale * 100.0), 12, UiTheme.TEXT_DIM))
    return pair[0]


func _developer_section() -> Control:
    var pair := _section("Developer tools")
    var v: VBoxContainer = pair[1]
    v.add_child(UiTheme.wrapped(
        "These are diagnostics, not gameplay. Sandbox matches award no gold and are recorded "
        + "separately.", 12, UiTheme.TEXT_DIM))

    var facts := UiTheme.hbox(8)
    facts.add_child(UiTheme.stat_chip("Catalog", str(app.catalog.size())))
    facts.add_child(UiTheme.stat_chip("Rules profile", "%s (v%d)" % [app.rules.profile_id, app.rules.profile_version]))
    facts.add_child(UiTheme.stat_chip("Overrides", str(app.profile.overrides().size())))
    facts.add_child(UiTheme.stat_chip("Engine", Engine.get_version_info().string))
    v.add_child(facts)

    var row := UiTheme.hbox(8)
    var sim := UiTheme.button("Run a bounded AI simulation",
        "Plays two Affinity opponents against each other through the real engine.")
    sim.pressed.connect(_run_simulation)
    row.add_child(sim)
    var validate := UiTheme.button("Validate catalog")
    validate.pressed.connect(func():
        var errs := app.catalog.validate_all()
        if errs.is_empty():
            app.toast("All %d definitions validate." % app.catalog.size())
        else:
            app.toast("%d problem(s). First: %s" % [errs.size(), String(errs[0])], true))
    row.add_child(validate)
    v.add_child(row)

    _sim_output = UiTheme.wrapped("", 11, UiTheme.TEXT_DIM)
    v.add_child(_sim_output)

    var danger := UiTheme.button("Start this save over",
        "Begins slot %d again in %s, its starting Affinity. The previous save is kept as its backup."
        % [app.slot, app.profile.starter_affinity.capitalize()])
    danger.pressed.connect(_reset)
    v.add_child(danger)
    return pair[0]


var _reset_armed := false


func _reset() -> void:
    if not _reset_armed:
        _reset_armed = true
        app.toast("Press it again to start slot %d over. The previous save is kept as its backup."
            % app.slot, true)
        return
    _reset_armed = false
    var affinity := app.profile.starter_affinity
    var save_name := app.profile.display_name
    var target := app.slot
    app.profile = PlayerProfile.create_new(app.catalog, app.economy, affinity, save_name)
    app.catalog = Catalog.load_bundled()
    app.catalog.set_overrides(app.profile.overrides())
    app.match_state = null
    app.match_context = {}
    app.save_profile()
    app.toast("Slot %d started over in %s. The previous save is still in its backup file."
        % [target, affinity.capitalize()])
    app.goto("home")


func _run_simulation() -> void:
    var ai := DeckLibrary.ai_decks()
    if ai.size() < 2:
        app.toast("No AI decks are available.", true)
        return
    var started := Time.get_ticks_msec()
    var r := MatchRunner.simulate(app.catalog, app.rules, [ai[0], ai[1]], 20260915,
        [String(ai[0].get("affinity", "")), String(ai[1].get("affinity", ""))], ["ai", "ai"], 6)
    var lines: Array = [
        "%s vs %s — %d rounds, %d decisions, %d ms." % [
            String(ai[0].get("affinity", "")), String(ai[1].get("affinity", "")),
            int(r["rounds"]), int(r["decisions"]), Time.get_ticks_msec() - started],
        "Illegal commands: %d. Engine guards: %d." % [
            (r["illegal_commands"] as Array).size(), (r["engine_guards"] as Array).size()],
    ]
    if bool(r["hit_round_limit"]):
        lines.append("Stopped at the 6-round simulation limit. That is a test limit, not a defeat.")
    if r["result"] != null:
        lines.append("Result: %s" % String((r["result"] as Dictionary).get("reason", "")))
    var transcript := MatchRunner.transcript(r["state"])
    for i in range(max(0, transcript.size() - 8), transcript.size()):
        lines.append(String(transcript[i]))
    _sim_output.text = "\n".join(lines)
