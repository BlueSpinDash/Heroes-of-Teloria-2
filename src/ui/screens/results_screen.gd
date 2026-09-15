extends Control

## Results: the outcome, the gold earned exactly once, a rematch and a way back.

var app: App


func setup(application: App, _args: Dictionary = {}) -> void:
    app = application
    var root := UiTheme.vbox(14)
    root.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(root)

    if app.match_state == null or app.match_state.result == null:
        root.add_child(UiTheme.heading("No finished match"))
        root.add_child(UiTheme.label("There is no completed match to show.", 14, UiTheme.TEXT_DIM))
        var back := UiTheme.button("Back to home")
        back.pressed.connect(func(): app.goto("home"))
        root.add_child(back)
        return

    var res: Dictionary = app.match_state.result
    var outcome := app.outcome_for_player()
    var sandbox := bool(app.match_context.get("sandbox", false))
    var match_id := String(app.match_context.get("match_id", app.match_state.match_id))

    # Paying is idempotent by match id: reopening this screen or reloading the
    # game cannot pay twice.
    var award := app.profile.award_match(match_id, outcome, app.economy,
        String(app.match_context.get("opponent", "")), sandbox)
    if not bool(award["already_paid"]):
        app.save_profile()

    var title := {"win": "Victory", "loss": "Defeat", "draw": "A draw", "concede": "You conceded"}
    var colour := UiTheme.GOOD if outcome == "win" else (
        UiTheme.GOLD if outcome == "draw" else UiTheme.DANGER)
    root.add_child(UiTheme.heading(String(title.get(outcome, "Match over")), 30))
    root.add_child(UiTheme.label(_reason_for_player(res, outcome), 15, colour))

    var facts := UiTheme.hbox(10)
    facts.add_child(UiTheme.stat_chip("Rounds", str(app.match_state.round_number)))
    facts.add_child(UiTheme.stat_chip("Your deck", String(app.match_context.get("deck_name", "?"))))
    facts.add_child(UiTheme.stat_chip("Opponent", String(app.match_context.get("opponent", "?")).capitalize()))
    root.add_child(facts)

    var reward := UiTheme.panel(UiTheme.BG_PANEL, UiTheme.GOLD_DIM, 1, 6)
    var rv := UiTheme.vbox(4)
    if sandbox:
        rv.add_child(UiTheme.label("Sandbox match — no gold awarded.", 15, UiTheme.TEXT_DIM))
        rv.add_child(UiTheme.label("Sandbox play is for testing and is kept out of the economy.",
            12, UiTheme.TEXT_DIM))
    else:
        rv.add_child(UiTheme.label("Gold earned: %d" % int(award["gold"]), 18, UiTheme.GOLD))
        if bool(award["already_paid"]):
            rv.add_child(UiTheme.label(
                "This match was already paid; reopening these results does not pay again.",
                12, UiTheme.TEXT_DIM))
        else:
            rv.add_child(UiTheme.label("Your balance is now %d gold." % app.profile.gold,
                12, UiTheme.TEXT_DIM))
    reward.add_child(rv)
    root.add_child(reward)

    var log_panel := UiTheme.panel(UiTheme.BG_PANEL, UiTheme.GOLD_DIM, 1, 6)
    var lv := UiTheme.vbox(2)
    lv.add_child(UiTheme.label("How it ended", 14, UiTheme.GOLD))
    lv.add_child(UiTheme.label("In the log below you are P1 and your opponent is P2.",
        11, UiTheme.TEXT_DIM))
    var lines := app.match_state.log_lines(14)
    for line in lines:
        lv.add_child(UiTheme.wrapped(String(line), 11, UiTheme.TEXT_DIM))
    log_panel.add_child(lv)
    root.add_child(log_panel)

    var row := UiTheme.hbox(8)
    var rematch := UiTheme.primary_button("Rematch", "Starts a new match with a new match id.")
    rematch.pressed.connect(_rematch)
    row.add_child(rematch)
    var decks := UiTheme.button("Back to decks")
    decks.pressed.connect(func():
        app.end_match()
        app.goto("decks"))
    row.add_child(decks)
    var opponents := UiTheme.button("Choose another opponent")
    opponents.pressed.connect(func():
        app.end_match()
        app.goto("opponents"))
    row.add_child(opponents)
    var home := UiTheme.button("Home")
    home.pressed.connect(func():
        app.end_match()
        app.goto("home"))
    row.add_child(home)
    root.add_child(row)


## The engine records results in neutral terms. The results screen is read by
## one specific player, so it says who that is.
func _reason_for_player(res: Dictionary, outcome: String) -> String:
    var reason := String(res.get("reason", ""))
    var loser := int(res.get("loser", -1))
    if bool(res.get("conceded", false)):
        return "You conceded the match." if loser == 0 else "Your opponent conceded the match."
    if int(res.get("winner", -1)) == -1:
        return reason
    if loser == 0:
        return "You lost: %s" % reason.trim_prefix("P1 loses: ").trim_prefix("P2 loses: ")
    if loser == 1:
        return "Your opponent lost: %s" % reason.trim_prefix("P1 loses: ").trim_prefix("P2 loses: ")
    return reason


func _rematch() -> void:
    var deck_id := String(app.match_context.get("deck_id", ""))
    var opponent := String(app.match_context.get("opponent", ""))
    var sandbox := bool(app.match_context.get("sandbox", false))
    app.end_match()
    var err := app.start_match(deck_id, opponent, sandbox)
    if err != "":
        app.toast(err, true)
        app.goto("opponents")
        return
    app.goto("battle")
