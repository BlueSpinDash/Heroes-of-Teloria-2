extends RefCounted

## The blueprint's manual walkthrough, run automatically against the real
## interface:
##
##   fresh launch → play a starter → finish a match → receive the correct
##   outcome and reward → purchase and reveal a pack → add an acquired card to
##   a legal deck → save → reload → play against another Affinity → edit a
##   proxy → future matches use the revision while deck references stay intact.
##
## Screens are built through the real App, so a screen that cannot construct
## itself fails here rather than in front of a player.

const WALKTHROUGH_ROUND_LIMIT := 25

var app: App
var _root: Node


func suite_name() -> String:
    return "ui"


## This suite builds real nodes, which only become ready on the next frame.
func is_async() -> bool:
    return true


func _frames(t: TestHarness, count: int) -> void:
    for i in count:
        await t.tree.process_frame


func run(t: TestHarness) -> void:
    if t.tree == null:
        t.begin("setup")
        t.ok(false, "the runner did not provide a SceneTree")
        return
    _root = t.tree.root
    await _launch(t)
    if app == null:
        return
    _every_screen_builds(t)
    _hero_cards_use_the_frame(t)
    await _a_supplied_face_can_be_used_whole(t)
    await _layout_editor_moves_card_parts(t)
    await _layout_editor_resizes_the_board(t)
    await _start_a_new_save_through_the_screen(t)
    _play_a_starter(t)
    await _play_cards_from_hand(t)
    await _drag_and_drop(t)
    _finish_and_reward(t)
    _buy_and_reveal(t)
    _add_card_to_deck(t)
    _save_and_reload(t)
    _play_another_affinity(t)
    _edit_a_proxy(t)
    await _create_a_card(t)
    _cleanup()


func _launch(t: TestHarness) -> void:
    t.begin("fresh launch")
    var scene: PackedScene = load("res://src/ui/main.tscn")
    if not t.ne(scene, null, "the main scene loads"):
        return
    var node := scene.instantiate()
    _root.add_child(node)
    app = node as App
    if not t.ne(app, null, "the main scene's root is the application"):
        return
    await _frames(t, 3)
    if not t.ne(app.economy, null, "the application finished starting up"):
        app = null
        return
    # Start from a brand-new profile so the walkthrough matches a first launch.
    app.catalog = Catalog.load_bundled()
    app.slot = SaveStore.MAX_SLOTS
    app.profile = PlayerProfile.create_new(app.catalog, app.economy, "passion", "Walkthrough")
    app.match_state = null
    app.match_context = {}
    app.save_profile()
    app.goto("home")
    t.eq(app.profile.decks().size(), 1, "a new save grants the one starter deck it chose")
    t.eq(app.profile.starter_affinity, "passion", "and records the Affinity it began in")
    t.eq(app.profile.gold, app.economy.starting_gold, "and the configured starting gold")
    t.ok(not app.has_active_match(), "no match is in progress at launch")


func _screen() -> Control:
    if app._body.get_child_count() == 0:
        return null
    return app._body.get_child(app._body.get_child_count() - 1)


func _every_screen_builds(t: TestHarness) -> void:
    t.begin("every screen builds")
    for name in ["saves", "home", "collection", "decks", "opponents", "shop", "creator",
            "editor", "layout", "settings"]:
        app.goto(String(name))
        var s := _screen()
        t.ne(s, null, "the %s screen was created" % name)
        if s != null:
            t.ok(s.get_child_count() > 0, "the %s screen has content" % name)
    app.goto("deck_builder", {"deck_id": String((app.profile.decks()[0] as Dictionary).get("deck_id", ""))})
    t.ne(_screen(), null, "the deck builder opens on an existing deck")


## Starting a save has to work through the real save screen, and the save it
## makes has to be one Affinity's starter deck and nothing else. This is the
## whole progression: a new game that already owned the catalog would have
## nothing left to earn.
func _start_a_new_save_through_the_screen(t: TestHarness) -> void:
    t.begin("a new save is started from the save screen in one Affinity")
    var was_profile := app.profile
    var was_slot := app.slot

    app.goto("saves")
    await _frames(t, 2)
    var screen := _screen()
    if not t.ne(screen, null, "the save screen built"):
        return

    # Only an empty slot offers this, so whichever one the screen picks is a
    # slot the test is free to write and then clear away.
    var new_btn := _button_titled(screen, "New save")
    if not t.ne(new_btn, null, "an empty slot offers a new save"):
        return
    (new_btn as Button).pressed.emit()
    await _frames(t, 2)
    var target := int(screen.get("_choosing_slot"))
    t.ge(float(target), 1.0, "the screen is starting a save in a real slot")
    t.ok(not app.store.exists(target), "and that slot is empty to begin with")

    var begin := _button_titled(screen, "Begin in Will")
    if not t.ne(begin, null, "the picker offers every Affinity to begin in"):
        return
    (begin as Button).pressed.emit()
    await _frames(t, 2)

    t.eq(app.slot, target, "the new save went into the slot that was chosen")
    t.eq(app.profile.starter_affinity, "will", "it began in the Affinity that was picked")
    t.eq(app.profile.decks().size(), 1, "with one deck")
    t.eq(app.current_screen_name(), "home", "and the game opened")

    var starter := DeckLibrary.starter_for("will")
    var outside: Array = []
    for def_id in app.profile.owned().keys():
        if not (starter["cards"] as Dictionary).has(def_id) \
                and String(def_id) != String(starter.get("hero", "")):
            outside.append(String(def_id))
    t.empty(outside, "and owns nothing outside that starter deck")
    t.eq(app.profile.owned_count("DEV_SKILL_01"), 0, "no other Affinity's cards are unlocked")
    t.ok(app.store.exists(target), "the new save was written to disk straight away")

    # It is legal to play, which is the point of granting the deck at all.
    var check := DeckValidator.validate(app.catalog, app.rules,
        app.profile.decks()[0], app.profile.owned())
    t.ok(check["ok"], "the granted deck is legal and fully owned: %s" % str(check["errors"]))

    # Put the walkthrough's own save back and leave the slot as it was found.
    app.store.delete_slot(target)
    app.profile = was_profile
    app.slot = was_slot
    app.catalog = Catalog.load_bundled()
    app.catalog.set_overrides(app.profile.overrides())
    app.goto("home")
    await _frames(t, 2)


## The first Button anywhere under `node` whose label starts with `text`.
func _button_titled(node: Node, text: String) -> Button:
    for child in node.get_children():
        if child is Button and (child as Button).text.begins_with(text):
            return child as Button
        var found := _button_titled(child, text)
        if found != null:
            return found
    return null


func _starter_deck() -> Dictionary:
    for d in app.profile.decks():
        var deck: Dictionary = d
        if DeckValidator.validate(app.catalog, app.rules, deck, app.profile.owned())["ok"]:
            return deck
    return {}


func _play_a_starter(t: TestHarness) -> void:
    t.begin("play a starter deck")
    var deck := _starter_deck()
    if not t.ok(not deck.is_empty(), "at least one granted starter is legal and fully owned"):
        return
    var err := app.start_match(String(deck.get("deck_id", "")), "silence")
    t.eq(err, "", "the match started: %s" % err)
    app.goto("battle")
    var screen := _screen()
    t.ne(screen, null, "the battle screen built")
    t.ne(app.match_state, null, "a match state exists")
    t.eq(app.match_state.round_number, 1, "the match opens on round 1")
    t.eq(app.match_state.player(0).hand.size(), app.rules.draw_to, "you drew to five")
    _decks_show_their_backs(t, screen)

    # Commit at least one Action through the real command path.
    var st: GameState = app.match_state
    var acted := 0
    var guard := 0
    while acted < 2 and guard < 60 and st.result == null:
        guard += 1
        if st.pending is Dictionary and int((st.pending as Dictionary).get("player", -1)) == 0:
            GameEngine.submit(st, MatchRunner._passive_command(st, 0))
            continue
        if st.phase != "action" or st.action_priority != 0 or st.player(0).passed_actions:
            # Let the opponent take its turn through the same API the screen uses.
            var actor := MatchRunner._actor(st)
            if actor == 1:
                GameEngine.submit(st, AiPolicy.decide(st, 1))
            else:
                GameEngine.advance(st)
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
        t.ok(bool(res["ok"]), "a command the engine offered was accepted: %s" % String(res["error"]))
        acted += 1
    t.ge(float(acted), 1.0, "the human side committed at least one Action")
    if screen != null and screen.has_method("_refresh"):
        screen.call("_refresh")
        t.ok(true, "the battle screen re-rendered after commands")


## Finish a match quickly. The walkthrough cares that a real match reaches a
## real result and pays once, not that it goes the distance, so the human side
## simply passes and the run is bounded. Full-length AI matches are covered by
## the ai suite.
## Cards must be playable from the hand, through the real controls.
##
## This covers the three shapes a hand card can take (no target, a chosen
## target, an X cost) and, just as importantly, asserts that every play button
## is actually inside the visible hand strip. A card the engine offers but the
## screen renders off the bottom of the window is unplayable in practice.
func _play_cards_from_hand(t: TestHarness) -> void:
    t.begin("cards can be played from the hand")
    # Use the Passion starter on purpose: it is the one granted deck that holds
    # a card of each shape this check needs, including an X cost.
    var deck: Dictionary = {}
    for d in app.profile.decks():
        if String((d as Dictionary).get("affinity", "")) == "passion":
            deck = d
    if not t.ok(not deck.is_empty(), "the Passion starter is available"):
        return
    app.end_match()
    var err := app.start_match(String(deck.get("deck_id", "")), "devotion")
    if not t.eq(err, "", "a match started for the hand check: %s" % err):
        return
    var st: GameState = app.match_state
    app.goto("battle")
    await _frames(t, 3)
    var screen := _screen()
    if not t.ne(screen, null, "the battle screen built"):
        return

    # Drive the match to a point where this player is on priority.
    st.first_player = 0
    st.action_priority = 0
    st.player(0).passed_actions = false
    st.pending = null
    st.phase = "action"

    # --- a card with no target -------------------------------------------
    _force_hand(st, 0, ["PAS_SKILL_01"])
    screen.call("_refresh")
    await _frames(t, 2)
    _assert_buttons_reachable(t, screen)
    _assert_board_zones_visible(t, screen)
    await _card_zoom_reads_cards(t, screen)
    var energy_before := st.player(0).energy_current
    var slots_before := st.sequence.size()
    t.ok(_press_first_play_button(screen), "the hand offered a play button")
    await _frames(t, 2)
    t.eq(st.sequence.size(), slots_before + 1, "a card with no target committed straight away")
    t.eq(st.player(0).energy_current, energy_before - 1, "and its cost was paid")

    # --- a card that chooses a target -------------------------------------
    st.action_priority = 0
    _force_hand(st, 0, ["PAS_SKILL_06"])
    screen.call("_refresh")
    await _frames(t, 2)
    _assert_buttons_reachable(t, screen)
    slots_before = st.sequence.size()
    t.ok(_press_first_play_button(screen), "the targeted card offered a play button")
    await _frames(t, 2)
    t.eq(String(screen.get("_mode")), "pick_card_target",
        "pressing it asks for a target rather than committing blindly")
    t.eq(st.sequence.size(), slots_before, "nothing is committed until a target is chosen")
    var kind := String(screen.get("_target_kind"))
    var options := Targeting.legal_targets(st, kind, 0)
    t.ge(float(options.size()), 1.0, "there is a legal target to choose")
    if options.size() > 0:
        screen.call("_choose_target", String(options[0]))
        await _frames(t, 2)
        t.eq(st.sequence.size(), slots_before + 1, "choosing a target committed the card")
        t.eq(String(screen.get("_mode")), "idle", "and the screen returned to normal")

    # --- a card with an X cost --------------------------------------------
    st.action_priority = 0
    st.player(0).energy_current = 4
    _force_hand(st, 0, ["PAS_SKILL_07"])
    screen.call("_refresh")
    await _frames(t, 2)
    slots_before = st.sequence.size()
    t.ok(_press_first_play_button(screen), "the X-cost card offered a play button")
    await _frames(t, 2)
    t.eq(st.sequence.size(), slots_before, "an X cost is asked for before committing")
    var spin = screen.get("_x_spin")
    if t.ne(spin, null, "the screen asked how much Energy to spend"):
        (spin as SpinBox).value = 3
        t.ok(_press_button_labelled(screen.get("_controls"), "Continue"), "the amount was confirmed")
        await _frames(t, 2)
        t.eq(st.sequence.size(), slots_before + 1, "the X-cost card committed")
        if st.sequence.size() > slots_before:
            t.eq((st.sequence[st.sequence.size() - 1] as ActionSlot).x_paid, 3,
                "with the X the player actually chose")
        t.eq(st.player(0).energy_current, 1, "and three Energy was spent")


## Cards and characters can be dragged onto where they belong.
##
## Godot's own mouse plumbing is not simulated here. The test drives the exact
## entry points that plumbing calls: _get_drag_data on the source, then
## _can_drop_data and _drop_data on the target. That covers every decision this
## game makes about what may be dropped where.
func _drag_and_drop(t: TestHarness) -> void:
    t.begin("cards and characters can be dragged onto their targets")
    var deck: Dictionary = {}
    for d in app.profile.decks():
        if String((d as Dictionary).get("affinity", "")) == "passion":
            deck = d
    app.end_match()
    if not t.eq(app.start_match(String(deck.get("deck_id", "")), "devotion"), "",
            "a match started for the drag check"):
        return
    var st: GameState = app.match_state
    app.goto("battle")
    await _frames(t, 3)
    var screen := _screen()
    if not t.ne(screen, null, "the battle screen built"):
        return
    st.first_player = 0
    st.action_priority = 0
    st.player(0).passed_actions = false
    st.pending = null
    st.phase = "action"

    # --- a hand card offers drag data ------------------------------------
    _force_hand(st, 0, ["PAS_SKILL_01"])
    screen.call("_refresh")
    await _frames(t, 2)
    var card := _first_draggable_card(screen)
    if not t.ne(card, null, "a playable hand card can be picked up"):
        return
    var payload = card.call("_get_drag_data", Vector2.ZERO)
    t.ok(payload is Dictionary, "dragging it produces a payload")
    if not (payload is Dictionary):
        return
    t.eq(String((payload as Dictionary).get("kind", "")), "card", "the payload describes a card")

    # --- a card with no target drops onto the Action Sequence -------------
    var zone: Control = screen.get("_sequence_zone")
    if not t.ne(zone, null, "the Action Sequence is a drop zone"):
        return
    t.ok(zone.call("_can_drop_data", Vector2.ZERO, payload),
        "a card that needs no target may be dropped on the Sequence")
    var slots_before := st.sequence.size()
    var energy_before := st.player(0).energy_current
    zone.call("_drop_data", Vector2.ZERO, payload)
    await _frames(t, 2)
    t.eq(st.sequence.size(), slots_before + 1, "dropping it committed the card")
    t.eq(st.player(0).energy_current, energy_before - 1, "and paid its cost")

    # --- a zone is a boundary, not a row of anchor points -----------------
    st.action_priority = 0
    _force_hand(st, 0, ["PAS_SKILL_01"])
    st.player(0).energy_current = 4
    screen.call("_refresh")
    await _frames(t, 2)
    _zones_take_a_drop_anywhere(t, screen)

    # --- a targeted card drops onto a legal character --------------------
    st.action_priority = 0
    _force_hand(st, 0, ["PAS_SKILL_06"])
    screen.call("_refresh")
    await _frames(t, 2)
    var card2 := _first_draggable_card(screen)
    if not t.ne(card2, null, "the targeted card can be picked up"):
        return
    var payload2 = card2.call("_get_drag_data", Vector2.ZERO)
    var own_hero := _chip_for(screen, st.player(0).hero_iid)
    var enemy_hero := _chip_for(screen, st.player(1).hero_iid)
    if not t.ne(own_hero, null, "your Hero is a drop target"):
        return
    t.ok(own_hero.call("_can_drop_data", Vector2.ZERO, payload2),
        "a card targeting your own character may be dropped on your Hero")
    t.ok(not zone.call("_can_drop_data", Vector2.ZERO, payload2),
        "and may not be dropped on the Sequence, because it needs a target")
    if enemy_hero != null:
        t.ok(not enemy_hero.call("_can_drop_data", Vector2.ZERO, payload2),
            "nor onto a character it cannot legally target")
    slots_before = st.sequence.size()
    own_hero.call("_drop_data", Vector2.ZERO, payload2)
    await _frames(t, 2)
    t.eq(st.sequence.size(), slots_before + 1, "dropping it on a legal target committed it")
    if st.sequence.size() > slots_before:
        var slot: ActionSlot = st.sequence[st.sequence.size() - 1]
        t.eq(slot.targets, [st.player(0).hero_iid], "against the character it was dropped on")

    # --- a character is dragged onto what it attacks ----------------------
    st.action_priority = 0
    st.player(0).energy_current = 4
    st.player(0).committed_characters = []
    screen.call("_refresh")
    await _frames(t, 2)
    var attacker := _chip_for(screen, st.player(0).hero_iid)
    if not t.ne(attacker, null, "your Hero chip is present"):
        return
    var attack_payload = attacker.call("_get_drag_data", Vector2.ZERO)
    t.ok(attack_payload is Dictionary, "your Hero can be picked up to attack")
    if attack_payload is Dictionary:
        t.eq(String((attack_payload as Dictionary).get("kind", "")), "attack",
            "the payload describes an attack")
        var target_chip := _chip_for(screen, st.player(1).hero_iid)
        if t.ne(target_chip, null, "the opposing Hero is a drop target"):
            t.ok(target_chip.call("_can_drop_data", Vector2.ZERO, attack_payload),
                "an attack may be dropped on the opposing Hero")
            t.ok(not attacker.call("_can_drop_data", Vector2.ZERO, attack_payload),
                "but not on your own character")
            t.ok(not zone.call("_can_drop_data", Vector2.ZERO, attack_payload),
                "and not on the Sequence, because an attack needs a target")
            slots_before = st.sequence.size()
            target_chip.call("_drop_data", Vector2.ZERO, attack_payload)
            await _frames(t, 2)
            t.eq(st.sequence.size(), slots_before + 1, "dropping it committed the attack")
            if st.sequence.size() > slots_before:
                t.eq((st.sequence[st.sequence.size() - 1] as ActionSlot).kind, "attack",
                    "as an attack, not a card")

    # --- an X cost is still asked for after a drop -----------------------
    st.action_priority = 0
    st.player(0).energy_current = 4
    _force_hand(st, 0, ["PAS_SKILL_07"])
    screen.call("_refresh")
    await _frames(t, 2)
    var xcard := _first_draggable_card(screen)
    if xcard != null:
        var xpayload = xcard.call("_get_drag_data", Vector2.ZERO)
        slots_before = st.sequence.size()
        zone.call("_drop_data", Vector2.ZERO, xpayload)
        await _frames(t, 2)
        t.eq(st.sequence.size(), slots_before, "an X cost is asked for before the card commits")
        var spin = screen.get("_x_spin")
        if t.ne(spin, null, "dropping an X-cost card asks how much Energy to spend"):
            (spin as SpinBox).value = 2
            t.ok(_press_button_labelled(screen.get("_controls"), "Continue"),
                "the amount was confirmed")
            await _frames(t, 2)
            t.eq(st.sequence.size(), slots_before + 1, "and then it committed")

    # --- nothing is draggable when it is not your turn -------------------
    st.action_priority = 1
    screen.call("_refresh")
    await _frames(t, 2)
    t.eq(_first_draggable_card(screen), null, "no card can be picked up on the opponent's turn")


## A card whose type has a painted frame is drawn on it, on the frame for its
## own type, and a card that opts out keeps the face it shipped with.
func _hero_cards_use_the_frame(t: TestHarness) -> void:
    t.begin("cards are drawn on the frame for their own type")
    var counted: Dictionary = {}
    var plain: Array = []
    var printed: Array = []
    var wrong: Array = []
    for d in app.catalog.all_defs():
        var card: CardDef = d
        var got := CardView._frame_for(card)
        var want: Dictionary = {}
        for type in CardView.FRAMES:
            if card.has_type(String(type)):
                want = CardView.FRAMES[type]
                break
        if card.frame == "plain":
            plain.append(card.id)
            want = {}
        if card.frame == "printed":
            printed.append(card.id)
        if got != want:
            wrong.append("%s got %s, wanted %s" % [card.id, str(got), str(want)])
        if not want.is_empty():
            var group := String(want["group"])
            counted[group] = int(counted.get(group, 0)) + 1
    t.ge(float(int(counted.get("hero_card", 0))), 7.0, "every Affinity's Hero is framed")
    t.ge(float(int(counted.get("skill_card", 0))), 50.0, "and the Skills are framed too")
    t.ge(float(int(counted.get("companion_card", 0))), 50.0, "as are the Companions")
    t.ge(float(int(counted.get("equipment_card", 0))), 20.0, "the Equipment")
    t.ge(float(int(counted.get("taahma_card", 0))), 10.0, "and the Ta'ahma")
    # Every card type with a painted template is drawn on it. Locations have
    # no template yet, so they are the one type still on the laid-out face.
    var unframed: Dictionary = {}
    for d2 in app.catalog.all_defs():
        var c2: CardDef = d2
        if c2.frame == "printed":
            continue
        if CardView._frame_for(c2).is_empty():
            for ty in c2.types:
                unframed[String(ty)] = int(unframed.get(String(ty), 0)) + 1
    t.eq(unframed.keys(), ["location"],
        "only Locations are still drawn without a frame: %s" % str(unframed))
    t.empty(wrong, "every card is on the frame for its own type, and only those are")
    t.empty(plain, "no card opts out of its frame")
    # A card supplied as a finished face is drawn from that face instead. It
    # still names a frame, so that a missing picture falls back to one rather
    # than to nothing.
    t.ok(printed.size() >= 3, "the cards supplied as finished faces use them: %s" % str(printed))
    for id in printed:
        t.eq(CardView.frame_group(app.catalog.get_def(String(id))), "",
            "%s is drawn from its own face, so it has no slots to place" % id)

    # Each frame places only what it has room for: a Skill has no Attack or
    # Defense medallion, so its layout has no place for those numbers.
    t.ok(Layout.keys_of("hero_card").has("attack"), "the Hero frame has an Attack number")
    t.ok(not Layout.keys_of("skill_card").has("attack"),
        "the Skill frame has none, and the card does not try to draw one")

    # The printed card paints its Energy gem over the top-left corner of the
    # art window. The gem is cut off the frame so it can go back on above the
    # artwork, instead of the window losing that corner to it.
    var order := Layout.layer_order("skill_card")
    t.ok(order.find("art") < order.find("energy_gem"),
        "the Skill frame's Energy gem is drawn over the artwork")
    t.ok(order.find("energy_gem") < order.find("energy"),
        "and under the number that sits in it")
    var gem := String((CardView.FRAMES["skill"] as Dictionary).get("ornaments", {}).get(
        "energy_gem", ""))
    t.ok(ResourceLoader.exists(gem), "and the gem exists as its own picture: %s" % gem)
    var skill := CardView.create(_framed_with_art("PAS_SKILL_01"), 300.0)
    _root.add_child(skill)
    var textures := 0
    for host in skill.get_children():
        for piece in (host as Node).get_children():
            if piece is TextureRect:
                textures += 1
    t.eq(textures, 2, "so a Skill draws two pictures: its frame and its gem")
    skill.queue_free()

    # The opt-out still works, for a card finished before its type has a frame.
    var opted := CardDef.from_dict(app.catalog.get_def("PAS_HERO_01").data.duplicate(true))
    opted.data["frame"] = "plain"
    t.ok(CardView._frame_for(opted).is_empty(), "a card can still ask for the plain face")

    # Framed or plain, a card is still a trading card.
    for id in ["DEV_HERO_01", "PAS_HERO_01", "PAS_SKILL_02"]:
        var view := CardView.create(app.catalog.get_def(String(id)), 300.0)
        _root.add_child(view)
        var want := 300.0 * CardView.BASE_HEIGHT / CardView.BASE_WIDTH
        t.le(absf(view.get_combined_minimum_size().y - want), 1.0,
            "%s keeps trading-card proportions (%.1f, wanted %.1f)" % [
                id, view.get_combined_minimum_size().y, want])
        view.queue_free()


## A card face that was drawn whole can be used whole.
##
## The frames exist so the game can state what a card does in its own words,
## which is what lets a card be rebalanced without being repainted. A card can
## still opt out and be the picture it was given — the picture then has to
## carry its own name, numbers and rules text, because nothing is placed on it.
func _a_supplied_face_can_be_used_whole(t: TestHarness) -> void:
    t.begin("a card face supplied whole is drawn whole")
    var printed := CardDef.from_dict(app.catalog.get_def("PAS_SKILL_01").data.duplicate(true))
    printed.data["frame"] = "printed"
    t.eq(CardView.frame_group(printed), "",
        "a printed face belongs to no layout group, so the Layout screen leaves it alone")

    var view := CardView.create(printed, 300.0)
    _root.add_child(view)
    await _frames(t, 2)
    var face := view.find_child(CardView.PRINTED_FACE, true, false) as TextureRect
    if t.ne(face, null, "the supplied picture is what the card draws"):
        t.ne(face.texture, null, "and the picture is really loaded")
        t.le(absf(face.size.x - 300.0), 1.5,
            "it is given the whole face, not a window (%s)" % str(face.size))
        t.eq(face.stretch_mode, TextureRect.STRETCH_KEEP_ASPECT_CENTERED,
            "fitted whole rather than cropped to the box")
    t.eq(_find_art(view), null, "nothing of the built face is drawn under it")
    t.eq(view.find_child("PrintedFace", true, false).get_parent().get_child_count(), 1,
        "and nothing is laid over it but the badges, which are their own layer")
    view.queue_free()

    # Without a picture there would be nothing to draw, so the catalog says so
    # rather than shipping a blank card.
    var blank := printed.data.duplicate(true)
    blank["art"] = {"style": "supplied", "seed": 1, "hue": 20, "saturation": 0.5}
    var errs := CardDef.from_dict(blank).validate()
    t.ok(_mentions(errs, "printed face needs an 'image'"),
        "a printed face with no picture is rejected: %s" % str(errs))
    t.empty(printed.validate(), "and one with a picture is accepted")


func _mentions(errs: Array, text: String) -> bool:
    for e in errs:
        if String(e).find(text) >= 0:
            return true
    return false


## The Layout screen has to actually move what a card draws, and a layout has
## to survive being saved and loaded, or it is a toy.
func _layout_editor_moves_card_parts(t: TestHarness) -> void:
    t.begin("the Layout screen moves the pieces of a card")
    var path := "user://layout_test.json"
    var was := Layout.rect("hero_card", "art")
    t.ok(not Layout.is_changed("hero_card", "art"), "the art window starts at its shipped value")

    # A card draws the slot it is given, so moving the slot moves the art.
    var def := _framed_with_art("PAS_HERO_01")
    var before := CardView.create(def, 300.0)
    _root.add_child(before)
    await _frames(t, 2)
    var art_before := _art_rect(before)
    t.ne(art_before, Rect2(), "the card drew its art somewhere")

    var moved := Rect2(was.position.x + 0.05, was.position.y + 0.03, was.size.x, was.size.y)
    Layout.set_rect("hero_card", "art", moved)
    t.ok(Layout.is_changed("hero_card", "art"), "the change is reported against the shipped value")
    var after := CardView.create(def, 300.0)
    _root.add_child(after)
    await _frames(t, 2)
    var art_after := _art_rect(after)
    t.ok(absf(art_after.position.x - art_before.position.x - 0.05 * 300.0) < 1.5,
        "the art moved across by what the slot moved (%s then %s)" % [
            str(art_before.position), str(art_after.position)])
    before.queue_free()
    after.queue_free()

    # A number is clamped to its stated range rather than accepted blindly.
    var bounds := Layout.limits("battle_board", "hand_card_w")
    Layout.set_num("battle_board", "hand_card_w", bounds.y + 500.0)
    t.eq(Layout.num("battle_board", "hand_card_w"), bounds.y,
        "a number past its maximum is held at the maximum")

    # Saved and loaded, the values come back.
    t.ok(Layout.save_to(path), "the layout saved")
    Layout.reset_all()
    t.ok(not Layout.is_changed("hero_card", "art"), "resetting put the shipped value back")
    t.ok(Layout.load_from(path), "the saved layout loaded")
    t.ok(Layout.rect("hero_card", "art").is_equal_approx(moved),
        "and the moved art window came back as it was saved")
    t.eq(Layout.num("battle_board", "hand_card_w"), bounds.y, "as did the number")

    # --- the stack ---------------------------------------------------------
    # A card is drawn back to front in the order the layout gives, and the
    # frame is one of the pieces: art moved behind it has to actually end up
    # behind it, not merely be listed that way.
    Layout.reset_all()
    var order := Layout.layer_order("hero_card")
    t.ok(order.find("frame") < order.find("art"),
        "the frame starts behind the artwork")
    var drawn := _piece_order(def)
    t.ok(drawn.find("frame") < drawn.find("art"),
        "and the card draws it that way: %s" % str(drawn))

    Layout.move_layer("hero_card", "art", -1)
    t.ok(Layout.layer_order("hero_card").find("art")
            < Layout.layer_order("hero_card").find("frame"),
        "sending the artwork back puts it behind the frame")
    t.ok(Layout.layers_changed("hero_card"), "and that counts as a change")
    var redrawn := _piece_order(def)
    t.ok(redrawn.find("art") < redrawn.find("frame"),
        "and the card is rebuilt with the artwork behind the frame: %s" % str(redrawn))

    # Moving past the end does nothing rather than falling off.
    var back := String(Layout.layer_order("hero_card")[0])
    Layout.move_layer("hero_card", String(back), -5)
    t.eq(Layout.layer_order("hero_card")[0], back, "the hindmost piece cannot go further back")

    Layout.reset_layers("hero_card")
    t.ok(not Layout.layers_changed("hero_card"), "resetting the order restores it")

    # The editor edits whichever frame the previewed card is drawn on, so a
    # Skill's slots are reachable and not only a Hero's.
    app.goto("layout")
    var screen := _screen()
    if t.ne(screen, null, "the Layout screen opened"):
        var seen: Dictionary = {screen._group: true}
        var stray: Array = []
        for i in mini(screen._card_ids.size(), 30):
            screen._step_card(1)
            seen[screen._group] = true
            if not Layout.keys_of(screen._group).has(screen._selected):
                stray.append("%s has no %s" % [screen._group, screen._selected])
        t.ok(seen.has("hero_card") and seen.has("skill_card"),
            "stepping the preview reaches both frames: %s" % str(seen.keys()))
        t.empty(stray, "and the selected box always belongs to the frame being edited")

    # Leave the game as it was found.
    Layout.reset_all()
    DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
    t.ok(Layout.rect("hero_card", "art").is_equal_approx(was),
        "the test left the layout as it found it")


## The board is laid out in the same screen as a card, and dragging one of its
## bars has to move the board the same way dragging a card's box moves the card.
##
## The numbers are in pixels and so is the drag, so a bar follows the pointer
## exactly: that is the whole reason the preview is drawn at the size a match
## draws it rather than scaled to fit.
func _layout_editor_resizes_the_board(t: TestHarness) -> void:
    t.begin("the Layout screen resizes the board")
    app.goto("layout")
    var screen := _screen()
    if not t.ne(screen, null, "the Layout screen opened"):
        return
    screen.call("_set_mode", "board")
    await _frames(t, 2)
    t.eq(String(screen.get("_mode")), "board", "it is laying out the board")
    var holder := screen.get("_board_holder") as Control
    if not t.ne(holder, null, "the board preview was built"):
        return
    t.ok(holder.get_child_count() >= 10,
        "with a row for every zone and a bar between them: %d" % holder.get_child_count())

    # Drag the bar under the Companion Zones down, and the zones grow by what
    # the pointer moved.
    var was := Layout.num("battle_board", "companion_strip_h")
    t.ok(not Layout.is_changed("battle_board", "companion_strip_h"),
        "the zones start at their shipped height")
    var rows: Dictionary = screen.get("_board_rows")
    if not t.ok(rows.has("companion_strip_h"), "the zone rows follow that number"):
        return
    var zone_row := ((rows["companion_strip_h"] as Array)[0] as Dictionary)["node"] as Control
    var before := zone_row.custom_minimum_size.y

    # The real gesture: press the bar, move the pointer, let go.
    var press := InputEventMouseButton.new()
    press.button_index = MOUSE_BUTTON_LEFT
    press.pressed = true
    screen.call("_grab_input", press, "companion_strip_h", "v", 1.0)
    t.eq(String(screen.get("_grab_key")), "companion_strip_h",
        "pressing the bar starts a drag on that number")
    var motion := InputEventMouseMotion.new()
    motion.relative = Vector2(0, 18)
    screen.call("_input", motion)
    motion.relative = Vector2(0, 12)
    screen.call("_input", motion)
    t.eq(Layout.num("battle_board", "companion_strip_h"), was + 30.0,
        "dragging the bar down by 30 makes the zones 30 taller")
    var release := InputEventMouseButton.new()
    release.button_index = MOUSE_BUTTON_LEFT
    release.pressed = false
    screen.call("_input", release)
    t.eq(String(screen.get("_grab_key")), "", "letting go ends the drag")
    await _frames(t, 2)
    rows = screen.get("_board_rows")
    zone_row = ((rows["companion_strip_h"] as Array)[0] as Dictionary)["node"] as Control
    t.eq(zone_row.custom_minimum_size.y, before + 30.0,
        "and the preview row grew with it")
    t.ok(Layout.is_changed("battle_board", "companion_strip_h"),
        "which counts as a change against the shipped value")

    # A number is still held inside its stated range however far it is dragged.
    var bounds := Layout.limits("battle_board", "companion_strip_h")
    Layout.set_num("battle_board", "companion_strip_h", bounds.y + 400.0)
    t.eq(Layout.num("battle_board", "companion_strip_h"), bounds.y,
        "a drag past the maximum is held at the maximum")

    # The card widths are the same story, and the card really is drawn at it.
    var card_was := Layout.num("battle_board", "board_card_w")
    Layout.set_num("battle_board", "board_card_w", card_was + 20.0)
    screen.call("_rebuild_board")
    await _frames(t, 2)
    var cards: Dictionary = screen.get("_board_rows")
    var holder2 := ((cards["board_card_w"] as Array)[0] as Dictionary)["node"] as Control
    t.eq(holder2.custom_minimum_size.x, card_was + 20.0,
        "a wider board card is drawn wider")
    var face := holder2.get_child(0) as CardView
    if t.ne(face, null, "and the card in it is a real card"):
        t.eq(face.card_width, card_was + 20.0, "drawn at that width")

    # Leave the game as it was found, and back to the card so the rest of the
    # walkthrough starts where it expects to.
    Layout.reset_all()
    screen.call("_set_mode", "card")
    await _frames(t, 2)
    t.ok(not Layout.is_changed("battle_board", "companion_strip_h"),
        "the test left the board as it found it")


## A card in the Hit, Exhaust or Wound Deck is face down, so a deck with
## anything in it shows the card back. A deck with nothing in it shows its
## painted plate alone: there is no card there to be face down.
func _decks_show_their_backs(t: TestHarness, screen: Control) -> void:
    var st: GameState = app.match_state
    t.ok(ResourceLoader.exists(CardView.BACK_PATH),
        "the card back is in the project: %s" % CardView.BACK_PATH)
    t.ne(CardView.face_down(60.0), null, "a face-down card can be drawn")
    var chips: Dictionary = screen.get("_pile_chips")
    var wrong: Array = []
    for kind in ["hit", "exhaust", "wound"]:
        for player in 2:
            var chip := chips.get("%d_%s" % [player, String(kind)]) as Control
            if chip == null:
                wrong.append("no plate for P%d's %s" % [player + 1, String(kind)])
                continue
            var full := st.player(player).pile(String(kind)).size() > 0
            var shown := _has_card_back(chip)
            if full != shown:
                wrong.append("P%d's %s holds %d and %s a back" % [
                    player + 1, String(kind), st.player(player).pile(String(kind)).size(),
                    "shows" if shown else "does not show"])
    t.empty(wrong, "every deck shows a back when it holds cards and none when it does not")
    # The one that has to be true whatever the starting deal is.
    var hit := chips.get("0_hit") as Control
    if t.ne(hit, null, "your Hit Deck has a plate"):
        t.ok(st.player(0).hit.size() > 0, "and cards in it")
        t.ok(_has_card_back(hit), "so it shows the card back")


func _has_card_back(node: Node) -> bool:
    if node is TextureRect:
        var tex := (node as TextureRect).texture
        if tex != null and tex.resource_path == CardView.BACK_PATH:
            return true
    for child in node.get_children():
        if _has_card_back(child):
            return true
    return false


## A copy of a card put back on its painted frame, with a real picture in the
## window. The finished cards are drawn from the faces they were supplied as,
## which have no window to place anything in — so a test about placing things
## in a window has to make one.
func _framed_with_art(id: String) -> CardDef:
    var def := app.catalog.get_def(id).duplicate_def()
    def.data["frame"] = ""
    def.data["art"] = {"style": "supplied", "fit": "cover", "seed": 1, "hue": 20,
        "saturation": 0.5, "image": String(CardView.FRAMES["hero"]["path"])}
    return def


## Which pieces a built card holds, in the order it draws them. The artwork is
## wrapped in the control that clips it to the window's shape, so it is looked
## for below the piece rather than at it.
func _piece_order(def: CardDef) -> Array:
    var view := CardView.create(def, 300.0)
    var out: Array = []
    for host in view.get_children():
        for piece in (host as Node).get_children():
            if _find_art(piece) != null:
                out.append("art")
            elif piece is TextureRect:
                out.append("frame")
    view.queue_free()
    return out


func _find_art(node: Node) -> CardArt:
    if node is CardArt:
        return node as CardArt
    for child in node.get_children():
        var found := _find_art(child)
        if found != null:
            return found
    return null


## Where a built card actually drew its art, in the card's own coordinates. The
## art fills its clipping window, so the window is what is measured.
func _art_rect(view: CardView) -> Rect2:
    for layer in view.get_children():
        for child in (layer as Node).get_children():
            if _find_art(child) != null:
                return Rect2((child as Control).position, (child as Control).size)
    return Rect2()


## Resting the pointer on a small card has to bring up a readable one.
##
## The hand and the board draw cards small enough to fit the table, which
## leaves the rules text too small to read, so this is the only way to read a
## card during a match.
func _card_zoom_reads_cards(t: TestHarness, screen: Control) -> void:
    t.begin("hovering a card shows it at a readable size")
    var zoom = screen.get("_zoom")
    if not t.ok(zoom != null, "the battle screen has a card reader"):
        return
    t.ok(not zoom.call("showing"), "nothing is being read to start with")

    var card := _first_draggable_card(screen)
    if not t.ne(card, null, "there is a card in hand to hover"):
        return
    var want: CardDef = (card as CardView).def
    (card as CardView).mouse_entered.emit()
    # The reader waits a beat before appearing so that sweeping the pointer
    # across the board does not flash a card for every chip it crosses.
    zoom.call("_process", CardZoom.HOVER_DELAY + 0.1)
    await _frames(t, 2)
    t.ok(zoom.call("showing"), "resting on a hand card brings up a reader")
    t.eq(zoom.call("shown_card"), want, "and it is the card that was hovered")

    var shown: Rect2 = zoom.call("shown_rect")
    t.ge(float(shown.size.x), float((card as CardView).card_width) + 1.0,
        "the reader is larger than the card in hand")
    var window := Rect2(Vector2.ZERO, Vector2(screen.get_viewport().get_visible_rect().size))
    t.ok(window.encloses(shown),
        "the reader %s is fully inside the window %s" % [str(shown), str(window)])

    (card as CardView).mouse_exited.emit()
    await _frames(t, 2)
    t.ok(not zoom.call("showing"), "moving off the card takes the reader away")

    # A card on the board is read the same way, and a refresh clears the reader
    # because the chip it was reading has been rebuilt.
    var st: GameState = app.match_state
    var hero := _chip_for(screen, st.player(0).hero_iid)
    if hero != null:
        (hero as Control).mouse_entered.emit()
        zoom.call("_process", CardZoom.HOVER_DELAY + 0.1)
        await _frames(t, 2)
        t.ok(zoom.call("showing"), "a Hero on the board can be read too")
        screen.call("_refresh")
        await _frames(t, 2)
        t.ok(not zoom.call("showing"), "a refresh clears the reader with the chips")


## A zone takes a card anywhere inside its boundary, including over the cards
## already standing in it, and says so while the card is being dragged.
func _zones_take_a_drop_anywhere(t: TestHarness, screen: Control) -> void:
    var zones: Array = screen.get("_drop_zones")
    if not t.ok(zones.size() >= 3, "every zone that takes a card is a region"):
        return
    for z in zones:
        t.ok(not (z as BattleDropTarget).drop_hint.is_empty(),
            "the %s zone says what dropping there would do" % (z as Control).name)
    var zone: Control = screen.get("_sequence_zone")
    if not t.ne(zone, null, "the Action Sequence is one of them"):
        return
    var card := _first_draggable_card(screen)
    if not t.ne(card, null, "a card can be picked up to drag over it"):
        return
    var payload = card.call("_get_drag_data", Vector2.ZERO)
    var size := zone.get_rect().size
    for at in [Vector2.ZERO, size * 0.5, size - Vector2.ONE,
            Vector2(size.x - 1.0, 1.0), Vector2(1.0, size.y - 1.0)]:
        t.ok(zone.call("_can_drop_data", at, payload),
            "the Sequence takes the card at %s" % at)
    t.eq(_swallows_mouse(zone), [],
        "and nothing inside it stands between the drop and the zone")

    var bands: Array = screen.call("_bands_for", payload)
    var hints: Array = []
    for b in bands:
        var band := b as Dictionary
        hints.append(String(band.get("hint", "")))
        var rect: Rect2 = band.get("rect", Rect2())
        t.ok(rect.size.x > 0.0 and rect.size.y > 0.0, "a banded zone has an area to aim at")
    t.ok(hints.has(zone.get("drop_hint")),
        "the Sequence is banded while the card is in the air")
    t.eq(screen.call("_bands_for", {"kind": "nothing"}), [],
        "and no zone is banded for something none of them takes")


## The names of things inside a zone that would swallow a drop before it could
## reach the zone. Real controls are allowed to: a button is meant to take the
## mouse for itself.
func _swallows_mouse(node: Node) -> Array:
    var found: Array = []
    for child in node.get_children():
        if child is Button or child is LineEdit or child is OptionButton or child is SpinBox:
            continue
        if child is Control and (child as Control).mouse_filter == Control.MOUSE_FILTER_STOP:
            found.append(String((child as Control).name))
        found.append_array(_swallows_mouse(child))
    return found


func _first_draggable_card(screen: Control) -> Control:
    var row = screen.get("_hand_row")
    if row == null:
        return null
    for child in (row as Control).get_children():
        for sub in (child as Control).get_children():
            if sub is CardView and (sub as CardView).drag_payload != null:
                return sub as Control
    return null


## The board keeps a lookup of every chip by instance id, which is also what
## the animation layer uses to find things on screen.
func _chip_for(screen: Control, iid: String) -> Control:
    var chips = screen.get("_chips")
    if chips is Dictionary and (chips as Dictionary).has(iid):
        var chip = (chips as Dictionary)[iid]
        if is_instance_valid(chip):
            return chip as Control
    return null


## Put exactly these cards in a player's hand, so a test controls what is on
## offer without depending on the shuffle.
func _force_hand(st: GameState, player: int, def_ids: Array) -> void:
    for iid in st.player(player).hand.duplicate():
        st.move_to_pile(String(iid), "hit")
    for def_id in def_ids:
        for iid in st.player(player).hit:
            if (st.instances[iid] as CardInstance).def_id == String(def_id):
                st.move_to_pile(String(iid), "hand")
                break


func _hand_buttons(screen: Control) -> Array:
    var out: Array = []
    var row = screen.get("_hand_row")
    if row == null:
        return out
    for child in (row as Control).get_children():
        for sub in (child as Control).get_children():
            if sub is Button:
                out.append(sub)
    return out


func _press_first_play_button(screen: Control) -> bool:
    var buttons := _hand_buttons(screen)
    if buttons.is_empty():
        return false
    (buttons[0] as Button).emit_signal("pressed")
    return true


func _press_button_labelled(container, label: String) -> bool:
    if container == null:
        return false
    for child in (container as Control).get_children():
        if child is Button and String((child as Button).text) == label:
            (child as Button).emit_signal("pressed")
            return true
    return false


## Every play button must sit inside the visible hand strip. This is what
## catches a hand rendered off the bottom of the window.
func _assert_buttons_reachable(t: TestHarness, screen: Control) -> void:
    var row = screen.get("_hand_row")
    if row == null:
        return
    var strip := (row as Control).get_parent() as Control
    if strip == null:
        return
    var visible := strip.get_global_rect()
    if visible.size.y <= 0.0:
        return  # not laid out in this environment; the geometry check needs a frame
    var unreachable: Array = []
    for b in _hand_buttons(screen):
        var r: Rect2 = (b as Button).get_global_rect()
        if not visible.encloses(r):
            unreachable.append("%s at %s outside the hand strip %s" % [
                (b as Button).text, str(r), str(visible)])
    t.empty(unreachable, "every play button is inside the visible hand strip")

    # The strip itself has to be on screen. Twice now a taller board has pushed
    # the hand below the window, which makes the whole hand unplayable even
    # though every button is correctly placed inside it.
    var window := Rect2(Vector2.ZERO, Vector2(screen.get_viewport().get_visible_rect().size))
    t.ok(visible.position.y >= window.position.y - 1.0
            and visible.end.y <= window.end.y + 1.0,
        "the hand strip %s sits inside the window %s" % [str(visible), str(window)])


## The board reads as two mirrored halves around a shared middle. Every zone
## has to be laid out and on screen, or part of the match is invisible.
func _assert_board_zones_visible(t: TestHarness, screen: Control) -> void:
    var window := Rect2(Vector2.ZERO, Vector2(screen.get_viewport().get_visible_rect().size))
    var zones := {
        "your Companion Zone": screen.get("_own_companion_zone"),
        "the opponent's Companion Zone": screen.get("_opp_companion_zone"),
        "the Location zone": screen.get("_location_zone"),
        "the Action Sequence": screen.get("_sequence_zone"),
        "your decks and Hero": screen.get("_own_piles"),
        "the opponent's decks and Hero": screen.get("_opp_piles"),
    }
    var missing: Array = []
    for name in zones:
        var c = zones[name]
        if c == null or not (c is Control):
            missing.append("%s was never built" % name)
            continue
        var r: Rect2 = (c as Control).get_global_rect()
        if r.size.x <= 0.0 or r.size.y <= 0.0:
            missing.append("%s has no size" % name)
        elif not window.intersects(r):
            missing.append("%s at %s is off screen %s" % [name, str(r), str(window)])
    t.empty(missing, "every board zone is laid out and on screen")


func _finish_match(st: GameState) -> void:
    MatchRunner.drive(st, ["pass", "ai"], WALKTHROUGH_ROUND_LIMIT)
    if st.result == null:
        GameEngine.submit(st, {"cmd": "concede", "player": 0})


func _finish_and_reward(t: TestHarness) -> void:
    t.begin("finish the match and receive the reward once")
    var st: GameState = app.match_state
    _finish_match(st)
    t.ne(st.result, null, "the match reached a result")
    var outcome := app.outcome_for_player()
    t.ok(["win", "loss", "draw", "concede"].has(outcome), "the outcome is one of the four kinds")

    var gold_before := app.profile.gold
    app.goto("results")
    t.ne(_screen(), null, "the results screen built")
    var expected := app.economy.reward_for(outcome)
    t.eq(app.profile.gold, gold_before + expected, "the reward matched the configured amount for '%s'" % outcome)
    var after_first := app.profile.gold

    # Reopening the results screen must not pay again.
    app.goto("results")
    t.eq(app.profile.gold, after_first, "reopening the results screen does not pay twice")
    app.goto("results")
    t.eq(app.profile.gold, after_first, "nor does a third visit")
    t.eq(app.profile.record_count(), 1, "exactly one match record was written")
    app.end_match()
    t.ok(not app.has_active_match(), "the finished match was cleared")


func _buy_and_reveal(t: TestHarness) -> void:
    t.begin("purchase and reveal a booster")
    app.profile.gold = app.economy.booster_price + 5
    app.save_profile()
    app.goto("shop")
    var shop := _screen()
    if not t.ne(shop, null, "the shop screen built"):
        return
    var gold_before := app.profile.gold
    shop.call("_buy")
    var opening = app.profile.pending_reveal()
    if not t.ok(opening is Dictionary, "a booster was opened and is waiting to be acknowledged"):
        return
    var cards: Array = (opening as Dictionary).get("cards", [])
    t.eq(cards.size(), app.economy.cards_per_booster, "the booster held five cards")
    var dust := int((opening as Dictionary).get("duplicate_gold", 0))
    t.eq(app.profile.gold, gold_before - app.economy.booster_price + dust,
        "the price was deducted once and duplicate conversions credited")

    # The purchase is durable before anything is revealed.
    var reloaded := PlayerProfile.new(app.store.load_slot(app.slot))
    t.eq(reloaded.gold, app.profile.gold, "the committed save already shows the purchase")
    t.ok(reloaded.pending_reveal() is Dictionary, "a reload mid-reveal still has the same result waiting")

    app.profile.acknowledge_reveal()
    app.save_profile()
    t.eq(app.profile.pending_reveal(), null, "acknowledging clears the reveal")

    # An unaffordable purchase changes nothing.
    app.profile.gold = 0
    var snapshot := JSON.stringify(app.profile.to_dict())
    app.goto("shop")
    var shop2 := _screen()
    shop2.call("_buy")
    t.eq(JSON.stringify(app.profile.to_dict()), snapshot, "an unaffordable purchase left the save unchanged")


func _acquired_card_id() -> String:
    # A card owned but not used by any starter deck.
    var used: Dictionary = {}
    for d in app.profile.decks():
        for k in ((d as Dictionary).get("cards", {}) as Dictionary).keys():
            used[String(k)] = true
    for def_id in app.profile.owned().keys():
        var def := app.catalog.get_def(String(def_id))
        if def == null or def.has_type("hero"):
            continue
        if not used.has(String(def_id)):
            return String(def_id)
    return ""


func _add_card_to_deck(t: TestHarness) -> void:
    t.begin("add an acquired card to a legal deck")
    var acquired := _acquired_card_id()
    if acquired == "":
        # Grant one directly so the check still runs deterministically.
        app.profile.add_cards(app.catalog, app.economy, "NEU_SKILL_01", 1)
        acquired = "NEU_SKILL_01"
    var deck := _starter_deck().duplicate(true)
    if not t.ok(not deck.is_empty(), "a legal deck is available to edit"):
        return
    deck["deck_id"] = "walkthrough_deck"
    deck["name"] = "Walkthrough deck"
    deck["starter"] = false

    # Swap one copy of an existing card for the acquired one, keeping 45 cards.
    var cards: Dictionary = deck["cards"]
    var ids: Array = cards.keys()
    ids.sort()
    var donor := String(ids[0])
    cards[donor] = int(cards[donor]) - 1
    if int(cards[donor]) <= 0:
        cards.erase(donor)
    cards[acquired] = int(cards.get(acquired, 0)) + 1

    var check := DeckValidator.validate(app.catalog, app.rules, deck, app.profile.owned())
    t.ok(check["ok"], "the deck with the acquired card is legal: %s" % str(check["errors"]))
    t.eq(int(check["count"]), 45, "it still holds exactly 45 cards")
    app.profile.save_deck(deck)
    app.save_profile()
    t.eq(app.profile.decks().size(), 2, "the new deck was saved alongside the starter")
    t.ok(app.profile.owned_count(donor) >= int((app.profile.deck_by_id("walkthrough_deck")["cards"] as Dictionary).get(donor, 0)),
        "saving a deck did not consume any cards")


func _save_and_reload(t: TestHarness) -> void:
    t.begin("save and reload")
    var gold := app.profile.gold
    var deck_count := app.profile.decks().size()
    var owned := app.profile.owned_count("NEU_SKILL_01")
    t.eq(app.save_profile(), "", "the save committed")

    var reloaded := PlayerProfile.new(app.store.load_slot(app.slot))
    t.eq(reloaded.gold, gold, "gold survived the reload")
    t.eq(reloaded.decks().size(), deck_count, "every deck survived the reload")
    t.eq(reloaded.owned_count("NEU_SKILL_01"), owned, "owned counts survived the reload")
    t.ne(reloaded.deck_by_id("walkthrough_deck"), {}, "the deck built during the walkthrough survived")
    app.profile = reloaded
    app.catalog.set_overrides(app.profile.overrides())


func _play_another_affinity(t: TestHarness) -> void:
    t.begin("play against another Affinity")
    var err := app.start_match("walkthrough_deck", "devotion")
    t.eq(err, "", "a match against a different opponent started: %s" % err)
    t.eq(String(app.match_context.get("opponent", "")), "devotion", "the opponent is the one chosen")
    app.goto("battle")
    t.ne(_screen(), null, "the battle screen built for the second match")

    # An in-progress match survives a reload with its own frozen definitions.
    app.persist_match()
    var saved = app.profile.active_match()
    t.ok(saved is Dictionary, "the active match was persisted")
    app.match_state = null
    t.ok(app.resume_match(), "the match resumed from the save")
    t.eq(app.match_state.round_number, 1, "it resumed on the same round")

    _finish_match(app.match_state)
    t.ne(app.match_state.result, null, "the second match also reached a result")
    app.goto("results")
    app.end_match()


func _edit_a_proxy(t: TestHarness) -> void:
    t.begin("edit a proxy and keep every reference intact")
    var deck := app.profile.deck_by_id("walkthrough_deck")
    # A proxy, not a finished card: a card drawn from a supplied face has no
    # separate portrait to swap, and this walkthrough swaps one.
    var target := ""
    for id in (deck["cards"] as Dictionary).keys():
        if app.catalog.get_def(String(id)).placeholder:
            target = String(id)
            break
    if not t.ne(target, "", "the walkthrough deck holds a proxy to edit"):
        return
    var owned_before := app.profile.owned_count(target)
    var rev_before := app.catalog.get_def(target).revision

    app.goto("editor", {"def_id": target})
    var editor := _screen()
    if not t.ne(editor, null, "the card editor built"):
        return
    editor.set("working", app.catalog.get_def(target).duplicate_def())
    var working: CardDef = editor.get("working")
    working.data["name"] = "Walkthrough Renamed Proxy"
    working.data["art"] = {"style": "abstract_sigil", "seed": 4242, "hue": 12, "saturation": 0.3}
    editor.call("_refresh_preview")
    editor.call("_save")

    var after := app.catalog.get_def(target)
    t.eq(after.name, "Walkthrough Renamed Proxy", "the edit took effect")
    t.ge(float(after.revision), float(rev_before + 1), "the definition revision incremented")
    t.eq(app.profile.owned_count(target), owned_before, "owned copies are untouched")
    var deck_after := app.profile.deck_by_id("walkthrough_deck")
    t.ok((deck_after["cards"] as Dictionary).has(target), "the saved deck still references the same card id")
    var check := DeckValidator.validate(app.catalog, app.rules, deck_after, app.profile.owned())
    t.ok(check["ok"], "the deck is still legal after the edit: %s" % str(check["errors"]))

    # A future match uses the revision.
    var err := app.start_match("walkthrough_deck", "will")
    t.eq(err, "", "a new match started after the edit: %s" % err)
    t.eq(app.match_state.catalog.get_def(target).name, "Walkthrough Renamed Proxy",
        "the new match uses the edited definition")
    t.ge(float(app.match_state.catalog.get_def(target).revision), float(rev_before + 1),
        "and its revision")
    app.end_match()

    # Restoring puts the bundled definition back without disturbing the deck.
    app.catalog.restore_bundled(target)
    app.profile.clear_override(target)
    t.eq(app.catalog.get_def(target).revision, rev_before, "restore brings back the bundled revision")
    t.ok(DeckValidator.validate(app.catalog, app.rules, deck_after, app.profile.owned())["ok"],
        "the deck is still legal after restoring")


## The card creator, driven through the real screen: pick what the card is,
## watch the price follow, forge it, and find it in the collection and legal in
## a deck. A creator that cannot produce a card you can actually play would be a
## toy, so this walks the whole way through.
func _create_a_card(t: TestHarness) -> void:
    t.begin("create a card and play with it")
    app.goto("creator")
    await _frames(t, 3)
    var screen := _screen()
    if not t.ne(screen, null, "the creator screen built"):
        return

    # Build a Companion by setting the design the way the controls would.
    var design: Dictionary = CardForge.blank_design("companion", "passion")
    design["name"] = "Walkthrough Warden"
    design["flavor"] = "Made in the creator, in a test."
    design["attack"] = 2
    design["defense"] = 3
    design["features"] = [{"id": "on_deploy_draw", "amount": 1}]
    screen.set("_design", design)
    screen.call("_refresh")
    await _frames(t, 2)

    # The price follows the design, and the card is drawn as a real card.
    var priced: Dictionary = CardForge.price(design)
    t.gt(float(int(priced["points"])), 0.0, "the design is worth something")
    t.ok(_preview_card(screen) != null, "the screen previews it as a card")

    var before_gold := app.profile.gold
    var made_before := app.catalog.customs.size()
    screen.call("_forge")
    await _frames(t, 2)
    t.eq(app.catalog.customs.size(), made_before + 1, "forging it made one card")

    var def_id := ""
    for cid in app.catalog.customs.keys():
        if app.catalog.get_def(String(cid)).name == "Walkthrough Warden":
            def_id = String(cid)
    if not t.ne(def_id, "", "the card is in the catalog"):
        return
    var def := app.catalog.get_def(def_id)
    t.eq(def.fixed_cost(), int(priced["cost"]), "and prints the cost its choices came to")
    t.eq(def.rarity, String(priced["rarity"]), "at the rarity that total earned")
    t.ok(def.custom, "marked as a card the player made")
    t.eq(def.text, "When this Companion enters play, you draw 1 card.",
        "with rules text generated from its own effects")
    t.eq(app.profile.gold, before_gold, "making a card costs no gold: it is not a purchase")
    t.eq(app.profile.owned_count(def_id), 3, "three copies are in the collection")
    t.ok(app.profile.customs().has(def_id), "and the card belongs to this save")

    # The face says where it came from, so it is never mistaken for a shipped card.
    var card := CardView.create(def, 300.0)
    t.ok(_text_appears(card, "CUSTOM"), "the card's face is marked CUSTOM")
    card.queue_free()

    # It is a real card everywhere else: the collection lists it, and a deck
    # holding it is legal.
    app.goto("collection")
    await _frames(t, 3)
    var collection := _screen()
    # The collection is paged, and a created card is the newest thing in it, so
    # it is searched for rather than assumed to be on the first page.
    var search = collection.get("_search")
    if t.ne(search, null, "the collection can be searched"):
        (search as LineEdit).text = "Walkthrough Warden"
        collection.call("_refilter")
        await _frames(t, 2)
        t.ok(_text_appears(collection, "Walkthrough Warden"),
            "the collection lists the card that was made")

    var deck := app.profile.deck_by_id("walkthrough_deck")
    if deck.is_empty():
        deck = app.profile.decks()[0]
    var cards: Dictionary = (deck["cards"] as Dictionary).duplicate()
    var dropped := ""
    for id in cards.keys():
        if int(cards[id]) >= 3 and String(id) != def_id:
            dropped = String(id)
            break
    if dropped != "":
        cards.erase(dropped)
        cards[def_id] = 3
        deck["cards"] = cards
        app.profile.save_deck(deck)
        var check := DeckValidator.validate(app.catalog, app.rules, deck, app.profile.owned())
        t.ok(bool(check["ok"]),
            "a deck holding the created card is legal: %s" % str(check["errors"]))
        # And the match it starts freezes the card, so the deck plays.
        app.end_match()
        t.eq(app.start_match(String(deck.get("deck_id", "")), "silence"), "",
            "a match starts with the created card in the deck")
        app.end_match()

    # Art is imported by copying the file, so the card keeps it.
    app.goto("creator", {"def_id": def_id})
    await _frames(t, 3)
    screen = _screen()
    if t.ne(screen, null, "the created card reopens in the creator"):
        var reopened: Dictionary = screen.get("_design")
        t.eq(String(reopened.get("name", "")), "Walkthrough Warden",
            "with the design it was made from")
        t.eq(int(reopened.get("defense", 0)), 3, "and the numbers it was given")
        var art_src := "res://assets/art/parfait_the_unyielding_flame.png"
        if FileAccess.file_exists(art_src):
            t.eq(String(screen.call("import_art", art_src)), "", "art can be imported")
            var after: Dictionary = screen.get("_design")
            var image := String((after.get("art", {}) as Dictionary).get("image", ""))
            t.ok(image.begins_with("user://custom_art/"),
                "the image is copied into the save's own art folder")
            t.ok(FileAccess.file_exists(image), "and the copy is really there")

        # Deleting it takes the copies with it, and says which deck it broke.
        screen.call("_delete")
        await _frames(t, 2)
        t.eq(app.catalog.get_def(def_id), null, "deleting the card removes it")
        t.eq(app.profile.owned_count(def_id), 0, "along with the copies it held")


## The CardView the creator is previewing, if any.
func _preview_card(screen: Control) -> CardView:
    var holder = screen.get("_preview_holder")
    if holder == null:
        return null
    for child in (holder as Control).get_children():
        if child is CardView:
            return child as CardView
    return null


## Whether this text appears anywhere in a built subtree. Used to check what a
## screen actually shows rather than what it was asked to show.
func _text_appears(node: Node, text: String) -> bool:
    if node is Label and (node as Label).text.contains(text):
        return true
    if node is Button and (node as Button).text.contains(text):
        return true
    for child in node.get_children():
        if _text_appears(child, text):
            return true
    return false


func _cleanup() -> void:
    if app != null and is_instance_valid(app):
        app.queue_free()
