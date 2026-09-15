extends Control

## The battle screen.
##
## It renders the one authoritative match state and submits validated commands.
## It never resolves anything itself: every outcome comes back from the engine.
## The human is player 0 and the AI is player 1, and both go through the same
## legal-command API.

var app: App
var st: GameState

# Interaction state.
var _mode: String = "idle"          # idle | pick_card_target | pick_attack_target
var _pending_card: String = ""
var _pending_attacker: String = ""
var _pending_x: int = 0
var _target_kind: String = ""
var _as_reaction: bool = false
var _choice_selection: Array = []

# AI turn handling.
var _thinker: AiThinker = null
var _ai_pause: float = 0.0

# Layout handles.
var _top: HBoxContainer
var _sequence_row: HBoxContainer
var _opp_board: HBoxContainer
var _own_board: HBoxContainer
var _hand_row: HBoxContainer
var _controls: HBoxContainer
var _prompt: Label
var _log_box: VBoxContainer
var _location_holder: HBoxContainer
var _chain_label: Label
var _x_spin: SpinBox


func setup(application: App, _args: Dictionary = {}) -> void:
    app = application
    if app.match_state == null and not app.resume_match():
        var v := UiTheme.vbox(10)
        v.set_anchors_preset(Control.PRESET_FULL_RECT)
        v.add_child(UiTheme.heading("No match in progress"))
        var b := UiTheme.button("Choose an opponent")
        b.pressed.connect(func(): app.goto("opponents"))
        v.add_child(b)
        add_child(v)
        return
    st = app.match_state
    _build()
    _refresh()


## A horizontally scrolling strip of a fixed height, so the board and the
## Sequence never squeeze the hand off the bottom of the screen.
func _fixed_scroll(child: Control, height: int) -> ScrollContainer:
    var s := UiTheme.scroll(child, true)
    s.custom_minimum_size = Vector2(0, height)
    s.size_flags_vertical = Control.SIZE_FILL
    return s


func _build() -> void:
    var root := UiTheme.vbox(6)
    root.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(root)

    _top = UiTheme.hbox(10)
    root.add_child(_top)

    var cols := UiTheme.hbox(10)
    cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
    root.add_child(cols)

    var centre := UiTheme.vbox(6)
    centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    centre.size_flags_vertical = Control.SIZE_EXPAND_FILL
    cols.add_child(centre)

    centre.add_child(UiTheme.label("Opponent's Companions", 12, UiTheme.TEXT_DIM))
    _opp_board = UiTheme.hbox(6)
    centre.add_child(_fixed_scroll(_opp_board, 118))

    var mid := UiTheme.hbox(10)
    mid.size_flags_vertical = Control.SIZE_FILL
    mid.add_child(UiTheme.label("Location:", 12, UiTheme.TEXT_DIM))
    _location_holder = UiTheme.hbox(6)
    mid.add_child(_location_holder)
    centre.add_child(mid)

    centre.add_child(UiTheme.separator())
    var seq_head := UiTheme.hbox(8)
    seq_head.add_child(UiTheme.label("Action Sequence (resolves left to right)", 12, UiTheme.GOLD))
    _chain_label = UiTheme.label("", 11, UiTheme.TEXT_DIM)
    seq_head.add_child(_chain_label)
    centre.add_child(seq_head)
    _sequence_row = UiTheme.hbox(6)
    centre.add_child(_fixed_scroll(_sequence_row, 128))
    centre.add_child(UiTheme.separator())

    centre.add_child(UiTheme.label("Your Companions", 12, UiTheme.TEXT_DIM))
    _own_board = UiTheme.hbox(6)
    centre.add_child(_fixed_scroll(_own_board, 118))

    _prompt = UiTheme.wrapped("", 13, UiTheme.GOLD)
    centre.add_child(_prompt)

    _controls = UiTheme.hbox(8)
    centre.add_child(_controls)

    centre.add_child(UiTheme.label("Your hand", 12, UiTheme.TEXT_DIM))
    _hand_row = UiTheme.hbox(6)
    var hand_scroll := UiTheme.scroll(_hand_row, true)
    hand_scroll.custom_minimum_size = Vector2(0, 268)
    centre.add_child(hand_scroll)

    var log_panel := UiTheme.panel(UiTheme.BG_PANEL, UiTheme.GOLD_DIM, 1, 6)
    log_panel.custom_minimum_size = Vector2(330, 0)
    _log_box = UiTheme.vbox(1)
    log_panel.add_child(UiTheme.scroll(_log_box))
    cols.add_child(log_panel)


# --------------------------------------------------------------- AI driving ---

func _process(delta: float) -> void:
    if st == null or st.result != null:
        return
    var actor := MatchRunner._actor(st)
    if actor != 1:
        _thinker = null
        return
    if _thinker == null:
        _thinker = AiThinker.new(st, 1)
        _ai_pause = 0.35  # a beat so the player can read what just happened
        return
    if _ai_pause > 0.0:
        _ai_pause -= delta
        return
    _thinker.step(int(app.rules.prov("ai_think_budget_ms", 45)))
    if not _thinker.done():
        return
    var cmd := _thinker.result()
    _thinker = null
    if cmd.is_empty():
        return
    var res := GameEngine.submit(st, cmd)
    if not bool(res["ok"]):
        # The opponent must never be able to hang the match on a rejected
        # command; fall back to a legal pass.
        var fallback := MatchRunner._passive_command(st, 1)
        if not fallback.is_empty():
            GameEngine.submit(st, fallback)
    _after_command()


func _after_command() -> void:
    app.persist_match()
    if st.result != null:
        app.goto("results")
        return
    _refresh()


# ------------------------------------------------------------------ refresh ---

func _refresh() -> void:
    if st == null:
        return
    _refresh_top()
    _refresh_boards()
    _refresh_sequence()
    _refresh_hand()
    _refresh_controls()
    _refresh_log()


func _refresh_top() -> void:
    for c in _top.get_children():
        c.queue_free()
    _top.add_child(UiTheme.stat_chip("Round", str(st.round_number)))
    _top.add_child(UiTheme.stat_chip("Phase", st.phase.capitalize()))
    var priority := "You" if st.action_priority == 0 else "Opponent"
    _top.add_child(UiTheme.stat_chip("Priority", priority if st.phase == "action" else "—"))

    for i in [0, 1]:
        var p := st.player(i)
        var hero := st.def_of(p.hero_iid)
        var who := "You" if i == 0 else "Opponent"
        var panel := UiTheme.panel(UiTheme.BG_PANEL,
            UiTheme.GOLD if i == 0 else UiTheme.GOLD_DIM, 1, 5)
        var v := UiTheme.vbox(2)
        v.add_child(UiTheme.label("%s — %s" % [who, hero.name if hero != null else "?"],
            13, UiTheme.GOLD if i == 0 else UiTheme.TEXT))
        var row := UiTheme.hbox(6)
        row.add_child(UiTheme.label("Hero %d/%d" % [
            st.current_attack(p.hero_iid), st.current_defense(p.hero_iid)], 12, UiTheme.TEXT))
        row.add_child(UiTheme.label("Energy %d/%d" % [p.energy_current, st.energy_max(i)],
            12, UiTheme.ENERGY.lightened(0.4)))
        row.add_child(UiTheme.label("Hit %d" % p.hit.size(), 11, UiTheme.TEXT_DIM))
        row.add_child(UiTheme.label("Exhaust %d" % p.exhaust.size(), 11, UiTheme.TEXT_DIM))
        row.add_child(UiTheme.label("Wound %d" % p.wound.size(), 11, UiTheme.DANGER))
        row.add_child(UiTheme.label("Hand %d" % p.hand.size(), 11, UiTheme.TEXT_DIM))
        if p.passed_actions:
            row.add_child(UiTheme.label("passed", 11, UiTheme.GOLD))
        v.add_child(row)
        var shield := st.inst(p.hero_iid).shield_total()
        if shield > 0:
            v.add_child(UiTheme.label("Prevents the next %d damage" % shield, 11, UiTheme.GOOD))
        panel.add_child(v)
        _top.add_child(panel)

    var quit_btn := UiTheme.button("Concede", "Ends the match immediately. A concession pays no gold.")
    quit_btn.pressed.connect(func():
        GameEngine.submit(st, {"cmd": "concede", "player": 0})
        _after_command())
    _top.add_child(quit_btn)


func _refresh_boards() -> void:
    _fill_board(_opp_board, 1)
    _fill_board(_own_board, 0)
    for c in _location_holder.get_children():
        c.queue_free()
    if st.location_iid == "":
        _location_holder.add_child(UiTheme.label("none", 12, UiTheme.TEXT_DIM))
    else:
        var d := st.def_of(st.location_iid)
        var owner := st.inst(st.location_iid).owner
        var chip := UiTheme.panel(UiTheme.FRAME["location"], UiTheme.GOLD, 1, 4)
        var lv := UiTheme.vbox(0)
        lv.add_child(UiTheme.label("%s (P%d)" % [d.name, owner + 1], 12, UiTheme.TEXT))
        lv.add_child(UiTheme.label(d.text, 10, UiTheme.TEXT_DIM))
        chip.add_child(lv)
        _location_holder.add_child(chip)
        if _mode == "pick_card_target" and _target_kind == "location":
            _location_holder.add_child(_target_button(st.location_iid))


func _fill_board(row: HBoxContainer, player: int) -> void:
    for c in row.get_children():
        c.queue_free()
    var p := st.player(player)
    row.add_child(_character_chip(p.hero_iid, player, true))
    if p.companions.is_empty():
        row.add_child(UiTheme.label("no Companions", 11, UiTheme.TEXT_DIM))
    for iid in p.companions:
        row.add_child(_character_chip(String(iid), player, false))


func _character_chip(iid: String, player: int, is_hero: bool) -> Control:
    var d := st.def_of(iid)
    var ci := st.inst(iid)
    var committed := st.player(player).committed_characters.has(iid)
    var in_sequence := st.sequence_members.has(iid)
    var border := UiTheme.GOLD if in_sequence else (UiTheme.GOLD_DIM if not committed else UiTheme.TEXT_DIM)
    var p := UiTheme.panel(UiTheme.BG_RAISED, border, 2 if in_sequence else 1, 5)
    p.custom_minimum_size = Vector2(170, 0)
    var v := UiTheme.vbox(2)
    v.add_child(UiTheme.label("%s%s" % ["Hero: " if is_hero else "", d.name], 12, UiTheme.TEXT))
    var stats := UiTheme.hbox(5)
    stats.add_child(UiTheme.label("%d ATK" % st.current_attack(iid), 12, UiTheme.ATTACK.lightened(0.4)))
    stats.add_child(UiTheme.label("%d DEF" % st.current_defense(iid), 12, UiTheme.DEFENSE.lightened(0.4)))
    if d.attack_cost > 0:
        stats.add_child(UiTheme.label("%dE to attack" % d.attack_cost, 10, UiTheme.TEXT_DIM))
    v.add_child(stats)

    var notes: Array = []
    if not d.affinities.is_empty():
        notes.append(UiTheme.affinity_line(d))
    if committed:
        notes.append("already committed this round")
    if in_sequence:
        notes.append("in the Action Sequence")
    if ci.deployed_round == st.round_number and not is_hero:
        notes.append("deployed this round, cannot attack")
    if ci.shield_total() > 0:
        notes.append("prevents %d damage" % ci.shield_total())
    for a_iid in st.attachments_of(iid):
        var ad := st.def_of(String(a_iid))
        notes.append("%s: %s" % [UiTheme.primary_type(ad).capitalize(), ad.name])
    for n in notes:
        v.add_child(UiTheme.label(String(n), 10, UiTheme.TEXT_DIM))

    # Action affordances.
    if _mode == "pick_attack_target" and player == 1:
        v.add_child(_target_button(iid))
    elif _mode == "pick_card_target" and Targeting.legal_targets(st, _target_kind, 0).has(iid):
        v.add_child(_target_button(iid))
    elif _mode == "idle" and player == 0 and _can_act() \
            and GameEngine._attack_candidates(st, 0).has(iid):
        var b := UiTheme.button("Attack with this", "Costs %d Energy." % d.attack_cost)
        b.disabled = st.player(0).energy_current < d.attack_cost
        b.pressed.connect(func(): _begin_attack(iid))
        v.add_child(b)
    p.add_child(v)
    return p


func _target_button(iid: String) -> Button:
    var b := UiTheme.button("Choose as target")
    b.pressed.connect(func(): _choose_target(iid))
    return b


func _refresh_sequence() -> void:
    for c in _sequence_row.get_children():
        c.queue_free()
    if st.sequence.is_empty():
        _sequence_row.add_child(UiTheme.label("empty — no Actions committed yet", 11, UiTheme.TEXT_DIM))
        _chain_label.text = ""
        return
    for i in st.sequence.size():
        var slot: ActionSlot = st.sequence[i]
        var is_current := (st.phase == "resolve" and i == st.current_step)
        var border := UiTheme.GOLD if is_current else (
            UiTheme.TEXT_DIM if slot.resolved else UiTheme.GOLD_DIM)
        var p := UiTheme.panel(UiTheme.BG_RAISED if is_current else UiTheme.BG_PANEL, border,
            2 if is_current else 1, 4)
        p.custom_minimum_size = Vector2(190, 0)
        var v := UiTheme.vbox(1)
        v.add_child(UiTheme.label("%d. %s" % [i + 1, "resolved" if slot.resolved else (
            "resolving now" if is_current else "waiting")], 10,
            UiTheme.TEXT_DIM if slot.resolved else UiTheme.GOLD))
        v.add_child(UiTheme.wrapped(GameEngine.describe_slot(st, slot), 11,
            UiTheme.TEXT if slot.controller == 0 else UiTheme.TEXT_DIM))
        if slot.affinities.is_empty():
            v.add_child(UiTheme.label("no Affinity — breaks the chain", 10, UiTheme.TEXT_DIM))
        else:
            var bits: Array = []
            for a in slot.affinities:
                bits.append("%s %s" % [String(UiTheme.AFFINITY_GLYPH.get(String(a), "◇")),
                    String(a).capitalize()])
            v.add_child(UiTheme.label(" ".join(bits), 10,
                UiTheme.affinity_color(String(slot.affinities[0]))))
        if slot.x_paid > 0:
            v.add_child(UiTheme.label("X = %d" % slot.x_paid, 10, UiTheme.GOLD))
        for r in slot.reactions:
            var rd := st.def_of(String((r as Dictionary).get("iid", "")))
            v.add_child(UiTheme.label("Reaction (%s): %s%s" % [
                String((r as Dictionary).get("window", "before")),
                rd.name if rd != null else "?",
                "" if not bool((r as Dictionary).get("resolved", false)) else " ✓"],
                10, UiTheme.GOLD))
        p.add_child(v)
        _sequence_row.add_child(p)
    var idx: int = st.current_step if st.phase == "resolve" else st.sequence.size() - 1
    _chain_label.text = AffinityChain.describe(st, idx)


func _refresh_hand() -> void:
    for c in _hand_row.get_children():
        c.queue_free()
    var reaction_window := _is_reaction_window_for_player()
    if st.player(0).hand.is_empty():
        _hand_row.add_child(UiTheme.label("your hand is empty", 11, UiTheme.TEXT_DIM))
    for iid in st.player(0).hand:
        var d := st.def_of(String(iid))
        var view := CardView.create(d, 168.0)
        var playable := false
        var why := ""
        if reaction_window:
            playable = d.allows_reaction_timing()
            why = "Playable now as a Reaction." if playable else "Not a Reaction card."
        elif _can_act():
            playable = d.allows_action_timing()
            why = "" if playable else "Reaction only; wait for a Reaction window."
        elif st.player(0).passed_actions:
            why = "You passed this round."
        elif st.phase == "action":
            why = "Not your turn yet."
        else:
            why = "Wait for the %s Phase to finish." % st.phase.capitalize()
        if playable:
            var cost: int = d.fixed_cost() if d.cost_kind() == "fixed" else d.x_min()
            if st.player(0).energy_current < cost:
                playable = false
                why = "Costs %d Energy; you have %d." % [cost, st.player(0).energy_current]
        if playable and d.target_spec is Dictionary:
            var kind := String((d.target_spec as Dictionary).get("kind", ""))
            var optional := bool((d.target_spec as Dictionary).get("optional", false))
            if not optional and Targeting.legal_targets(st, kind, 0).is_empty():
                playable = false
                why = "Needs a target and there is none available."

        if playable:
            view.add_badge("Eligible", UiTheme.GOOD)
            var b := UiTheme.button("Play as Reaction" if reaction_window else "Commit")
            b.pressed.connect(func(): _begin_play(String(iid), reaction_window))
            var holder := UiTheme.vbox(2)
            holder.add_child(view)
            holder.add_child(b)
            _hand_row.add_child(holder)
        else:
            view.add_badge(why if why != "" else "Not playable now", UiTheme.TEXT_DIM)
            view.modulate = Color(1, 1, 1, 0.65)
            _hand_row.add_child(view)


func _refresh_controls() -> void:
    for c in _controls.get_children():
        c.queue_free()
    _prompt.text = ""
    if st.result != null:
        return

    # A pending required choice always takes precedence.
    if st.pending is Dictionary:
        var p: Dictionary = st.pending
        if int(p.get("player", -1)) == 0:
            _build_choice_controls(p)
            return
        _prompt.text = "Waiting for your opponent to answer a required choice."
        return

    if st.phase == "action":
        if st.player(0).passed_actions:
            _prompt.text = "You have passed for this round. You can still play Reactions while the Sequence resolves."
        elif st.action_priority == 0:
            _prompt.text = _mode_prompt()
        else:
            _prompt.text = "Your opponent is choosing an Action."
        if _mode != "idle":
            var cancel := UiTheme.button("Cancel")
            cancel.pressed.connect(_cancel)
            _controls.add_child(cancel)
        if _mode == "pick_card_target":
            var d := st.def_of(_pending_card)
            if d != null and d.target_spec is Dictionary \
                    and bool((d.target_spec as Dictionary).get("optional", false)):
                var skip := UiTheme.button("Commit without a target")
                skip.pressed.connect(func(): _submit_card([]))
                _controls.add_child(skip)
        if _mode == "idle" and _can_act():
            var pass_btn := UiTheme.button("Pass Actions",
                "Permanent for this round's normal Actions. Reactions are still available.")
            pass_btn.pressed.connect(func():
                var r := GameEngine.submit(st, {"cmd": "pass_actions", "player": 0})
                if not bool(r["ok"]):
                    app.toast(String(r["error"]), true)
                    return
                _after_command())
            _controls.add_child(pass_btn)
    elif st.phase == "resolve":
        _prompt.text = "Resolving the Action Sequence."
    else:
        _prompt.text = "%s Phase." % st.phase.capitalize()


func _build_choice_controls(p: Dictionary) -> void:
    match String(p.get("kind", "")):
        "reaction_window":
            var slot_index := int(p.get("slot", 0))
            var slot: ActionSlot = st.sequence[slot_index] if slot_index < st.sequence.size() else null
            _prompt.text = "Reaction window before step %d%s. Play a Reaction from your hand, or pass." % [
                slot_index + 1,
                ": %s" % GameEngine.describe_slot(st, slot) if slot != null else ""]
            if _mode == "pick_card_target":
                _prompt.text = _mode_prompt()
                var cancel := UiTheme.button("Cancel")
                cancel.pressed.connect(_cancel)
                _controls.add_child(cancel)
            var pass_btn := UiTheme.primary_button("Pass Reaction")
            pass_btn.pressed.connect(func():
                var r := GameEngine.submit(st, {"cmd": "pass_reaction", "player": 0})
                if not bool(r["ok"]):
                    app.toast(String(r["error"]), true)
                    return
                _after_command())
            _controls.add_child(pass_btn)
        "choose_cards":
            var purpose := String(p.get("purpose", ""))
            var verb := "return to your hand" if purpose == "recover" else "Exhaust"
            var want := int(p.get("count", 0))
            var pool := GameEngine._choice_pool(st, p)
            # Drop anything selected for an earlier prompt that is not on offer now.
            var kept: Array = []
            for sel in _choice_selection:
                if pool.has(String(sel)):
                    kept.append(String(sel))
            _choice_selection = kept
            _prompt.text = "Choose up to %d card(s) to %s. Selected %d." % [
                want, verb, _choice_selection.size()]
            for iid in pool:
                var d := st.def_of(String(iid))
                var chosen := _choice_selection.has(String(iid))
                var b := UiTheme.button("%s%s" % ["✓ " if chosen else "", d.name if d != null else String(iid)])
                b.pressed.connect(func():
                    if _choice_selection.has(String(iid)):
                        _choice_selection.erase(String(iid))
                    elif _choice_selection.size() < want:
                        _choice_selection.append(String(iid))
                    _refresh_controls())
                _controls.add_child(b)
            var confirm := UiTheme.primary_button("Confirm")
            confirm.pressed.connect(func():
                var r := GameEngine.submit(st, {"cmd": "choose_cards", "player": 0,
                    "iids": _choice_selection.duplicate()})
                if not bool(r["ok"]):
                    app.toast(String(r["error"]), true)
                    return
                _choice_selection = []
                _after_command())
            _controls.add_child(confirm)
        "choose_deploy":
            _prompt.text = "You may put a Companion from your hand into play."
            for iid in GameEngine._deployable_from_hand(st, 0):
                var d := st.def_of(String(iid))
                var b := UiTheme.button("Deploy %s" % (d.name if d != null else String(iid)))
                b.pressed.connect(func():
                    var r := GameEngine.submit(st, {"cmd": "choose_deploy", "player": 0,
                        "card_iid": String(iid)})
                    if not bool(r["ok"]):
                        app.toast(String(r["error"]), true)
                        return
                    _after_command())
                _controls.add_child(b)
            var skip := UiTheme.button("Deploy nothing")
            skip.pressed.connect(func():
                GameEngine.submit(st, {"cmd": "choose_deploy", "player": 0, "card_iid": ""})
                _after_command())
            _controls.add_child(skip)


func _mode_prompt() -> String:
    match _mode:
        "pick_card_target":
            var d := st.def_of(_pending_card)
            return "Choose a target for %s: %s." % [d.name if d != null else "the card",
                TextGen.TARGET_KIND_PHRASE.get(_target_kind, "a legal target")]
        "pick_attack_target":
            var a := st.def_of(_pending_attacker)
            return "Choose what %s attacks: the opposing Hero or one of its Companions." % [
                a.name if a != null else "your character"]
    return "Commit an Action, attack, or pass."


func _refresh_log() -> void:
    for c in _log_box.get_children():
        c.queue_free()
    _log_box.add_child(UiTheme.label("Match log", 13, UiTheme.GOLD))
    _log_box.add_child(UiTheme.label("You are P1, your opponent is P2.", 10, UiTheme.TEXT_DIM))
    var lines := st.log_lines(70)
    for i in range(max(0, lines.size() - 45), lines.size()):
        _log_box.add_child(UiTheme.wrapped(String(lines[i]), 10, UiTheme.TEXT_DIM))


# ------------------------------------------------------------- interactions ---

func _can_act() -> bool:
    return st.pending == null and st.phase == "action" \
        and st.action_priority == 0 and not st.player(0).passed_actions


func _is_reaction_window_for_player() -> bool:
    return st.pending is Dictionary \
        and String((st.pending as Dictionary).get("kind", "")) == "reaction_window" \
        and int((st.pending as Dictionary).get("player", -1)) == 0


func _cancel() -> void:
    _mode = "idle"
    _pending_card = ""
    _pending_attacker = ""
    _pending_x = 0
    _target_kind = ""
    _refresh()


func _begin_play(iid: String, as_reaction: bool) -> void:
    var d := st.def_of(iid)
    if d == null:
        return
    _pending_card = iid
    _as_reaction = as_reaction
    _pending_x = d.x_min() if d.cost_kind() == "x" else 0
    if d.cost_kind() == "x":
        _ask_for_x(d)
        return
    _continue_play(d)


func _ask_for_x(d: CardDef) -> void:
    for c in _controls.get_children():
        c.queue_free()
    _prompt.text = ("%s has an X cost. X is equal to the amount of Energy spent to play it, "
        + "and later refunds never change it.") % d.name
    _x_spin = SpinBox.new()
    _x_spin.min_value = d.x_min()
    _x_spin.max_value = st.player(0).energy_current
    _x_spin.value = d.x_min()
    _controls.add_child(UiTheme.label("X =", 13))
    _controls.add_child(_x_spin)
    var ok := UiTheme.primary_button("Continue")
    ok.pressed.connect(func():
        _pending_x = int(_x_spin.value)
        _continue_play(d))
    _controls.add_child(ok)
    var cancel := UiTheme.button("Cancel")
    cancel.pressed.connect(_cancel)
    _controls.add_child(cancel)


func _continue_play(d: CardDef) -> void:
    if d.target_spec is Dictionary:
        _target_kind = String((d.target_spec as Dictionary).get("kind", ""))
        _mode = "pick_card_target"
        _refresh()
        return
    _submit_card([])


func _begin_attack(attacker_iid: String) -> void:
    _pending_attacker = attacker_iid
    _mode = "pick_attack_target"
    _refresh()


func _choose_target(iid: String) -> void:
    if _mode == "pick_attack_target":
        var r := GameEngine.submit(st, {"cmd": "commit_attack", "player": 0,
            "attacker_iid": _pending_attacker, "target_iid": iid})
        if not bool(r["ok"]):
            app.toast(String(r["error"]), true)
            return
        _mode = "idle"
        _pending_attacker = ""
        _after_command()
        return
    if not Targeting.is_valid(st, _target_kind, 0, iid):
        app.toast(Targeting.explain_invalid(st, _target_kind, 0, iid), true)
        return
    _submit_card([iid])


func _submit_card(targets: Array) -> void:
    var cmd := {
        "cmd": "play_reaction" if _as_reaction else "commit_card",
        "player": 0, "card_iid": _pending_card, "targets": targets,
    }
    var d := st.def_of(_pending_card)
    if d != null and d.cost_kind() == "x":
        cmd["x"] = _pending_x
    var r := GameEngine.submit(st, cmd)
    if not bool(r["ok"]):
        app.toast(String(r["error"]), true)
        return
    _mode = "idle"
    _pending_card = ""
    _pending_x = 0
    _target_kind = ""
    _after_command()
