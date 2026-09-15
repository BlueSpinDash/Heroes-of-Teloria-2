extends SceneTree

## Drives the real application through every screen and saves a screenshot of
## each, so the interface can be checked without a person at the keyboard.
##
##   xvfb-run -a godot --path . --script tools/ui_drive.gd
##
## Screenshots land in build/screens/.

const OUT_DIR := "res://build/screens"

var app: App
var problems: Array = []


func _initialize() -> void:
    _run()


func _run() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
    var scene: PackedScene = load("res://src/ui/main.tscn")
    var node := scene.instantiate()
    root.add_child(node)
    app = node as App
    await _settle(8)

    # A clean profile, so the walkthrough starts where a new player would.
    app.catalog = Catalog.load_bundled()
    app.profile = PlayerProfile.create_new(app.catalog, app.economy)
    app.save_profile()
    app.goto("home")
    await _shot("01_home")

    app.goto("collection")
    await _settle(3)
    await _shot("02_collection")

    app.goto("decks")
    await _shot("03_decks")

    var starter: Dictionary = app.profile.decks()[1]
    app.goto("deck_builder", {"deck_id": String(starter.get("deck_id", ""))})
    await _settle(4)
    await _shot("04_deck_builder")

    app.goto("opponents")
    await _shot("05_opponents")

    # Play a real match: start it, then drive a few human Actions.
    var err := app.start_match(String(starter.get("deck_id", "")), "silence")
    if err != "":
        problems.append("start_match failed: %s" % err)
    app.goto("battle")
    await _settle(4)
    await _shot("06_battle_round1")

    await _play_some_actions()
    await _shot("07_battle_sequence")

    # Finish the match quickly so the results screen has real content.
    GameEngine.submit(app.match_state, {"cmd": "concede", "player": 0})
    app.goto("results")
    await _settle(3)
    await _shot("08_results")
    app.end_match()

    app.goto("shop")
    await _settle(2)
    var shop := app._body.get_child(0)
    if shop.has_method("_buy"):
        shop.call("_buy")
    await _settle(4)
    await _shot("09_shop_reveal")

    app.goto("editor", {"def_id": "PAS_SKILL_01"})
    await _settle(4)
    await _shot("10_card_editor")

    app.goto("settings")
    await _settle(3)
    await _shot("11_settings")

    if problems.is_empty():
        print("UI walkthrough completed with no reported problems.")
    else:
        print("UI walkthrough reported %d problem(s):" % problems.size())
        for p in problems:
            print("  ✗ ", p)
    quit(1 if not problems.is_empty() else 0)


## Commit a few legal Actions as the human, letting the AI answer in between.
func _play_some_actions() -> void:
    var st: GameState = app.match_state
    var acted := 0
    var guard := 0
    while acted < 3 and guard < 200 and st.result == null:
        guard += 1
        await _settle(2)
        if st.pending is Dictionary and int((st.pending as Dictionary).get("player", -1)) == 0:
            GameEngine.submit(st, MatchRunner._passive_command(st, 0))
            _refresh_battle()
            continue
        if st.phase != "action" or st.action_priority != 0 or st.player(0).passed_actions:
            continue
        var legal := GameEngine.legal_commands(st, 0)
        var choice: Dictionary = {}
        for c in legal:
            if String((c as Dictionary).get("cmd", "")) != "pass_actions":
                choice = c
                break
        if choice.is_empty():
            break
        var res := GameEngine.submit(st, AiThinker._strip(choice))
        if not bool(res["ok"]):
            problems.append("a command the engine offered was then refused: %s" % String(res["error"]))
            break
        acted += 1
        _refresh_battle()


func _refresh_battle() -> void:
    var screen := app._body.get_child(0)
    if screen != null and screen.has_method("_refresh"):
        screen.call("_refresh")


func _settle(frames: int) -> void:
    for i in frames:
        await process_frame


func _shot(name: String) -> void:
    await _settle(3)
    var img := root.get_texture().get_image()
    if img == null:
        problems.append("no frame captured for %s" % name)
        return
    var path := "%s/%s.png" % [OUT_DIR, name]
    var err := img.save_png(path)
    if err != OK:
        problems.append("could not save %s (error %d)" % [path, err])
    else:
        print("captured ", name, "  %dx%d" % [img.get_width(), img.get_height()])
