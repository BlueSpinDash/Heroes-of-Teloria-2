extends Control

## Shop: balance, booster price, slot odds, purchase and reveal.
##
## A purchase is committed to the save before anything is revealed, so a reload
## mid-reveal resumes the same cards and can never reroll, charge twice or
## grant twice.

var app: App
var _reveal_holder: VBoxContainer
var _stats_row: HBoxContainer
var _buy_button: Button


func setup(application: App, _args: Dictionary = {}) -> void:
    app = application
    var root := UiTheme.vbox(12)
    root.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(root)

    root.add_child(UiTheme.heading("Shop"))

    _stats_row = UiTheme.hbox(10)
    root.add_child(_stats_row)
    _refresh_stats()

    var odds := UiTheme.panel(UiTheme.BG_PANEL, UiTheme.GOLD_DIM, 1, 6)
    var ov := UiTheme.vbox(3)
    ov.add_child(UiTheme.label("What a booster contains", 15, UiTheme.GOLD))
    for line in app.economy.slot_descriptions():
        ov.add_child(UiTheme.label(String(line), 12, UiTheme.TEXT))
    ov.add_child(UiTheme.label(
        "Each slot is drawn uniformly and independently from its rarity pool, so the same card "
        + "can appear twice in one booster.", 12, UiTheme.TEXT_DIM))
    var dust: Array = []
    for r in ["common", "uncommon", "rare", "legendary"]:
        dust.append("%s %d gold" % [String(r).capitalize(), app.economy.dust_for(String(r))])
    ov.add_child(UiTheme.label(
        "Copies beyond your collection cap convert to gold: " + ", ".join(dust) + ".",
        12, UiTheme.TEXT_DIM))
    ov.add_child(UiTheme.label(
        "Caps: three copies of an ordinary card, one of a Hero, named character or Unique card.",
        12, UiTheme.TEXT_DIM))
    odds.add_child(ov)
    root.add_child(odds)

    var buy_row := UiTheme.hbox(8)
    _buy_button = UiTheme.primary_button("Buy a booster (%d gold)" % app.economy.booster_price)
    _buy_button.disabled = not app.profile.can_afford(app.economy.booster_price)
    _buy_button.pressed.connect(_buy)
    buy_row.add_child(_buy_button)
    var collection := UiTheme.button("Open collection")
    collection.pressed.connect(func(): app.goto("collection"))
    buy_row.add_child(collection)
    root.add_child(buy_row)

    _reveal_holder = UiTheme.vbox(8)
    root.add_child(UiTheme.scroll(_reveal_holder))

    # A purchase that was never acknowledged resumes here rather than vanishing.
    var pending = app.profile.pending_reveal()
    if pending is Dictionary:
        _show_opening(pending, true)


## The balance and opened count change with every purchase, so they are
## rebuilt rather than left showing the figures from when the screen opened.
func _refresh_stats() -> void:
    for c in _stats_row.get_children():
        c.queue_free()
    _stats_row.add_child(UiTheme.stat_chip("Balance", str(app.profile.gold), UiTheme.GOLD))
    _stats_row.add_child(UiTheme.stat_chip("Booster", "%d gold" % app.economy.booster_price))
    _stats_row.add_child(UiTheme.stat_chip("Cards", str(app.economy.cards_per_booster)))
    _stats_row.add_child(UiTheme.stat_chip("Opened", str(app.profile.pack_openings().size())))
    if _buy_button != null:
        _buy_button.disabled = not app.profile.can_afford(app.economy.booster_price)


func _buy() -> void:
    var res := app.profile.open_pack(app.catalog, app.economy)
    if not bool(res["ok"]):
        app.toast(String(res["error"]), true)
        return
    # Commit the whole transaction before anything is revealed.
    var err := app.save_profile()
    if err != "":
        return
    _refresh_stats()
    _show_opening(res["opening"], bool(res.get("resumed", false)))


func _show_opening(opening: Dictionary, resumed: bool) -> void:
    for c in _reveal_holder.get_children():
        c.queue_free()

    var header := UiTheme.hbox(8)
    header.add_child(UiTheme.label(
        "Booster #%d%s" % [int(opening.get("index", 0)), "  (resumed)" if resumed else ""],
        16, UiTheme.GOLD))
    var gap := Control.new()
    gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    header.add_child(gap)
    var done := UiTheme.button("Done")
    done.pressed.connect(func():
        app.profile.acknowledge_reveal()
        app.save_profile()
        app.goto("shop"))
    header.add_child(done)
    _reveal_holder.add_child(header)

    if resumed:
        _reveal_holder.add_child(UiTheme.wrapped(
            "This booster was already purchased and its cards are already in your collection. "
            + "Reloading shows the same result; it is never rerolled or charged again.",
            12, UiTheme.TEXT_DIM))

    var row := UiTheme.hbox(10)
    row.custom_minimum_size = Vector2(0, 300)
    for entry in opening.get("cards", []):
        var e: Dictionary = entry
        var def := app.catalog.get_def(String(e.get("def_id", "")))
        if def == null:
            continue
        var view := CardView.create(def, 190.0)
        if int(e.get("added", 0)) > 0:
            view.add_badge("Added to collection", UiTheme.GOOD)
        else:
            view.add_badge("Over cap — %d gold" % int(e.get("gold", 0)), UiTheme.GOLD)
        view.add_badge("Slot %d" % int(e.get("slot", 0)), UiTheme.TEXT_DIM)
        row.add_child(view)
    # A scroll inside a scroll needs an explicit height, or it collapses to
    # nothing and the revealed cards are never seen.
    var strip := UiTheme.scroll(row, true)
    strip.custom_minimum_size = Vector2(0, 312)
    strip.size_flags_vertical = Control.SIZE_FILL
    _reveal_holder.add_child(strip)

    if int(opening.get("duplicate_gold", 0)) > 0:
        _reveal_holder.add_child(UiTheme.label(
            "Duplicates past your caps converted to %d gold." % int(opening.get("duplicate_gold", 0)),
            13, UiTheme.GOLD))
