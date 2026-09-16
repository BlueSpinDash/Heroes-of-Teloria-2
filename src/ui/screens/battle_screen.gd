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
## Targets already chosen by dropping a card onto them, so the X-cost prompt
## does not ask for them a second time.
var _pending_targets: Array = []
var _targets_prechosen: bool = false

# Drag and drop.
var _drop_targets: Array = []
var _dragging: bool = false

# AI turn handling.
var _thinker: AiThinker = null
var _ai_pause: float = 0.0

# Layout metrics. The hand strip is pinned to the bottom of the screen, so its
# height is budgeted rather than left to grow: card face, the Commit button
# above it, and room for the horizontal scrollbar.
const HAND_CARD_W := 128.0
const HAND_STRIP_H := 250.0
## Tall enough for a character chip carrying an action button, so nothing in a
## Companion Zone is ever clipped off the bottom.
const COMPANION_STRIP_H := 110.0

# Layout handles.
var _top: HBoxContainer
var _sequence_row: HBoxContainer
var _opp_board: HBoxContainer
var _own_board: HBoxContainer
var _hand_row: HBoxContainer
var _controls: HBoxContainer
var _prompt: Label
var _log_box: VBoxContainer
var _chain_label: Label
var _x_spin: SpinBox
var _sequence_zone: BattleDropTarget
var _terrain_zone: BattleDropTarget
var _terrain_holder: HBoxContainer
var _opp_piles: GridContainer
var _own_piles: GridContainer
var _opp_hero_holder: HBoxContainer
var _own_hero_holder: HBoxContainer
var _own_companion_zone: BattleDropTarget
var _opp_companion_zone: BattleDropTarget

## Board chips by instance id, so effects know where things are on screen.
var _chips: Dictionary = {}
var _pile_chips: Dictionary = {}

## Cosmetic feedback for events that have already resolved.
var _effects: BoardEffects
var _events_seen: int = 0


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
    # Everything already in the log happened before this screen opened, so it
    # is not replayed as animation.
    _events_seen = st.events.size()
    _build()
    _refresh()


## A horizontally scrolling strip of a fixed height, so the board and the
## Sequence never squeeze the hand off the bottom of the screen.
func _build() -> void:
    var root := UiTheme.vbox(4)
    root.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(root)

    _top = UiTheme.hbox(10)
    root.add_child(_top)

    var cols := UiTheme.hbox(10)
    cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
    root.add_child(cols)

    var centre := UiTheme.vbox(4)
    centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    var centre_scroll := ScrollContainer.new()
    centre_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    centre_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    centre_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    centre_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
    centre_scroll.add_child(centre)
    cols.add_child(centre_scroll)

    # The board reads as two mirrored halves around a shared middle. The rules
    # give both players one Action Sequence and one Terrain between them, so
    # those two appear once, in the centre, rather than being mirrored.

    # Each half is one row: the player's Hero, their three decks, and their
    # Companion Zone. The opponent's row is mirrored, so the two Companion
    # Zones face each other across the shared middle.
    centre.add_child(_make_half_row(1))
    centre.add_child(_make_terrain_zone())
    centre.add_child(_make_sequence_zone())
    centre.add_child(_make_half_row(0))

    var log_panel := UiTheme.panel(UiTheme.BG_PANEL, UiTheme.GOLD_DIM, 1, 6)
    log_panel.custom_minimum_size = Vector2(300, 0)
    _log_box = UiTheme.vbox(1)
    log_panel.add_child(UiTheme.scroll(_log_box))
    cols.add_child(log_panel)

    # The prompt, the controls and the hand are pinned below the scrolling
    # board. However tall the board grows, they stay on screen, so the cards
    # you can play are always reachable.
    var action_bar := UiTheme.hbox(10)
    _controls = UiTheme.hbox(8)
    action_bar.add_child(_controls)
    _prompt = UiTheme.wrapped("", 12, UiTheme.GOLD)
    _prompt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _prompt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    action_bar.add_child(_prompt)
    root.add_child(action_bar)

    _hand_row = UiTheme.hbox(6)
    var hand_zone := UiTheme.panel(UiTheme.ZONE_BG, UiTheme.GOLD_DIM, 2, 4)
    var hand_scroll := UiTheme.scroll(_hand_row, true)
    hand_scroll.custom_minimum_size = Vector2(0, HAND_STRIP_H)
    hand_scroll.size_flags_vertical = Control.SIZE_FILL
    hand_zone.add_child(hand_scroll)
    hand_zone.size_flags_vertical = Control.SIZE_SHRINK_END
    root.add_child(hand_zone)

    # Added last so it draws over the board. It never takes input.
    _effects = BoardEffects.new()
    add_child(_effects)


## One player's half of the board: Hero, decks, Companion Zone. Player 0 reads
## left to right; player 1 is mirrored so the two zones meet in the middle.
func _make_half_row(player: int) -> Control:
    var row := UiTheme.hbox(6)

    var hero_holder := UiTheme.hbox(0)
    hero_holder.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

    var piles := GridContainer.new()
    piles.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
    piles.columns = 2
    piles.add_theme_constant_override("h_separation", 6)
    piles.add_theme_constant_override("v_separation", 6)

    var zone := _make_companion_zone(player)
    zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    if player == 0:
        _own_hero_holder = hero_holder
        _own_piles = piles
        row.add_child(hero_holder)
        row.add_child(piles)
        row.add_child(zone)
    else:
        _opp_hero_holder = hero_holder
        _opp_piles = piles
        row.add_child(zone)
        row.add_child(piles)
        row.add_child(hero_holder)
    return row


func _make_companion_zone(player: int) -> Control:
    var target := BattleDropTarget.new()
    target.style(UiTheme.ZONE_BG, UiTheme.ZONE_BORDER, 2, 6)
    var v := UiTheme.vbox(1)
    v.add_child(UiTheme.label(
        ("Your Companion Zone" if player == 0 else "Opponent's Companion Zone").to_upper(),
        10, UiTheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
    var row := UiTheme.hbox(6)
    var row_scroll := UiTheme.scroll(row, true)
    row_scroll.custom_minimum_size = Vector2(0, COMPANION_STRIP_H)
    row_scroll.size_flags_vertical = Control.SIZE_FILL
    v.add_child(row_scroll)
    target.add_child(v)
    if player == 0:
        _own_board = row
        _own_companion_zone = target
        target.drop_hint = "Deploy here"
        target.accepts_check = func(payload): return _accepts_on_companion_zone(payload)
        target.dropped.connect(func(payload): _drop_on_sequence(payload))
    else:
        _opp_board = row
        _opp_companion_zone = target
    return target


func _make_terrain_zone() -> Control:
    _terrain_zone = BattleDropTarget.new()
    _terrain_zone.style(UiTheme.ZONE_BG, UiTheme.ZONE_BORDER, 2, 6)
    _terrain_zone.drop_hint = "Play here"
    _terrain_zone.accepts_check = func(payload): return _accepts_on_location(payload)
    _terrain_zone.dropped.connect(func(payload): _drop_on_location(payload))
    var v := UiTheme.vbox(1)
    v.add_child(UiTheme.label("TERRAIN — SHARED, ONE ACTIVE AT A TIME", 10, UiTheme.GOLD,
        HORIZONTAL_ALIGNMENT_CENTER))
    _terrain_holder = UiTheme.hbox(6)
    _terrain_holder.alignment = BoxContainer.ALIGNMENT_CENTER
    v.add_child(_terrain_holder)
    _terrain_zone.add_child(v)
    return _terrain_zone


func _make_sequence_zone() -> Control:
    _sequence_zone = BattleDropTarget.new()
    _sequence_zone.style(UiTheme.ZONE_BG.lightened(0.04), UiTheme.GOLD, 2, 6)
    _sequence_zone.drop_hint = "Commit to the Action Sequence"
    _sequence_zone.accepts_check = func(payload): return _accepts_on_sequence(payload)
    _sequence_zone.dropped.connect(func(payload): _drop_on_sequence(payload))
    var v := UiTheme.vbox(1)
    var head := UiTheme.hbox(8)
    head.alignment = BoxContainer.ALIGNMENT_CENTER
    head.add_child(UiTheme.label("ACTION SEQUENCE — RESOLVES LEFT TO RIGHT", 10, UiTheme.GOLD))
    _chain_label = UiTheme.label("", 10, UiTheme.TEXT_DIM)
    head.add_child(_chain_label)
    v.add_child(head)
    _sequence_row = UiTheme.hbox(6)
    var seq_scroll := UiTheme.scroll(_sequence_row, true)
    seq_scroll.custom_minimum_size = Vector2(0, 96)
    seq_scroll.size_flags_vertical = Control.SIZE_FILL
    v.add_child(seq_scroll)
    _sequence_zone.add_child(v)
    return _sequence_zone


func _process(delta: float) -> void:
    _update_drag_state()
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


## While a card or character is being dragged, every place it could legally go
## lights up. Nothing is rebuilt mid-drag, only restyled, so the drag itself is
## never interrupted.
func _update_drag_state() -> void:
    var vp := get_viewport()
    if vp == null:
        return
    var now := vp.gui_is_dragging()
    if now == _dragging:
        return
    _dragging = now
    var payload = vp.gui_get_drag_data() if now else null
    for tgt in _drop_targets:
        if tgt is BattleDropTarget and is_instance_valid(tgt):
            var target := tgt as BattleDropTarget
            target.set_highlight(now and target.can_accept(payload))


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
    # Chips are rebuilt every refresh, so the lookups that depend on them are
    # rebuilt first.
    _chips = {}
    _pile_chips = {}
    _drop_targets = []
    for zone in [_sequence_zone, _terrain_zone, _own_companion_zone]:
        if zone != null:
            _drop_targets.append(zone)

    _refresh_top()
    _refresh_piles()
    _refresh_boards()
    _refresh_terrain()
    _refresh_sequence()
    _refresh_hand()
    _refresh_controls()
    _refresh_log()
    # Positions are only known once the new layout has been measured.
    call_deferred("_play_new_events")


func _refresh_top() -> void:
    for c in _top.get_children():
        _top.remove_child(c)
        c.queue_free()
    _top.add_child(UiTheme.stat_chip("Round", str(st.round_number)))
    _top.add_child(UiTheme.stat_chip("Phase", st.phase.capitalize()))
    var priority := "You" if st.action_priority == 0 else "Opponent"
    _top.add_child(UiTheme.stat_chip("Priority", priority if st.phase == "action" else "—"))

    for i in [1, 0]:
        var p := st.player(i)
        var hero := st.def_of(p.hero_iid)
        var panel := UiTheme.panel(UiTheme.BG_PANEL,
            UiTheme.GOLD if i == 0 else UiTheme.GOLD_DIM, 1, 5)
        var row := UiTheme.hbox(6)
        row.add_child(UiTheme.label("You" if i == 0 else "Opponent", 13,
            UiTheme.GOLD if i == 0 else UiTheme.TEXT))
        row.add_child(UiTheme.label(hero.name if hero != null else "?", 12, UiTheme.TEXT_DIM))
        row.add_child(UiTheme.label("Energy %d/%d" % [p.energy_current, st.energy_max(i)],
            12, UiTheme.ENERGY.lightened(0.4)))
        row.add_child(UiTheme.label("Hand %d" % p.hand.size(), 11, UiTheme.TEXT_DIM))
        if i == 1:
            # The opponent's hand is face down: only its size is public.
            for _b in min(p.hand.size(), 10):
                var back := UiTheme.panel(UiTheme.FRAME["hero"], UiTheme.GOLD_DIM, 1, 3)
                back.custom_minimum_size = Vector2(14, 20)
                back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
                row.add_child(back)
        if p.passed_actions:
            row.add_child(UiTheme.label("passed", 11, UiTheme.GOLD))
        panel.add_child(row)
        _top.add_child(panel)

    var gap := Control.new()
    gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _top.add_child(gap)
    var quit_btn := UiTheme.button("Concede", "Ends the match immediately. A concession pays no gold.")
    quit_btn.pressed.connect(func():
        GameEngine.submit(st, {"cmd": "concede", "player": 0})
        _after_command())
    _top.add_child(quit_btn)


func _refresh_piles() -> void:
    _fill_piles(_opp_piles, _opp_hero_holder, 1)
    _fill_piles(_own_piles, _own_hero_holder, 0)


func _fill_piles(grid: GridContainer, hero_holder: HBoxContainer, player: int) -> void:
    for c in grid.get_children():
        grid.remove_child(c)
        c.queue_free()
    for c in hero_holder.get_children():
        hero_holder.remove_child(c)
        c.queue_free()
    # Hit and Exhaust on the top row, Wound below: the three places a card can
    # sit once it leaves the deck, in the order the rules move it through them.
    for kind in ["hit", "exhaust", "wound"]:
        grid.add_child(_pile_chip(player, kind))
    hero_holder.add_child(_character_chip(st.player(player).hero_iid, player, true))


const PILE_LABEL := {"hit": "Hit Deck", "exhaust": "Exhaust Deck", "wound": "Wound Deck"}


func _pile_chip(player: int, kind: String) -> Control:
    var p := st.player(player)
    var count := p.pile(kind).size()
    var colour := UiTheme.PILE_HIT
    if kind == "exhaust":
        colour = UiTheme.PILE_EXHAUST
    elif kind == "wound":
        colour = UiTheme.PILE_WOUND
    var chip := UiTheme.panel(colour, UiTheme.GOLD_DIM, 2, 5)
    chip.custom_minimum_size = Vector2(118, 60)
    var key := "%d_%s" % [player, kind]
    chip.set_meta("pile", key)
    _pile_chips[key] = chip
    var v := UiTheme.vbox(0)
    v.add_child(UiTheme.label(String(PILE_LABEL.get(kind, kind)).to_upper(), 9,
        UiTheme.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
    v.add_child(UiTheme.label(str(count), 20,
        UiTheme.DANGER if kind == "wound" else UiTheme.TEXT, HORIZONTAL_ALIGNMENT_CENTER))
    chip.add_child(v)
    chip.tooltip_text = "%s: %d card%s" % [String(PILE_LABEL.get(kind, kind)), count,
        "" if count == 1 else "s"]
    return chip


func _refresh_boards() -> void:
    _fill_board(_opp_board, 1)
    _fill_board(_own_board, 0)


func _refresh_terrain() -> void:
    for c in _terrain_holder.get_children():
        _terrain_holder.remove_child(c)
        c.queue_free()
    if st.location_iid == "":
        _terrain_holder.add_child(UiTheme.label("no Terrain in play", 11, UiTheme.TEXT_DIM))
        return
    var d := st.def_of(st.location_iid)
    var owner := st.inst(st.location_iid).owner
    var chip := BattleDropTarget.new()
    chip.style(UiTheme.FRAME["location"], UiTheme.GOLD, 1, 4)
    chip.set_meta("iid", st.location_iid)
    chip.accepts_check = func(payload): return _accepts_on_location(payload)
    chip.dropped.connect(func(payload): _drop_on_location(payload))
    _chips[st.location_iid] = chip
    _drop_targets.append(chip)
    var lv := UiTheme.hbox(6)
    lv.add_child(UiTheme.label("%s (P%d)" % [d.name, owner + 1], 12, UiTheme.TEXT))
    var txt := UiTheme.label(d.text, 10, UiTheme.TEXT_DIM)
    txt.clip_text = true
    lv.add_child(txt)
    chip.add_child(lv)
    chip.claim_mouse()
    _terrain_holder.add_child(chip)
    if _mode == "pick_card_target" and _target_kind == "location":
        _terrain_holder.add_child(_target_button(st.location_iid))


func _fill_board(row: HBoxContainer, player: int) -> void:
    for c in row.get_children():
        row.remove_child(c)
        c.queue_free()
    var p := st.player(player)
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

    var p := BattleDropTarget.new()
    p.style(UiTheme.BG_RAISED, border, 2 if in_sequence else 1, 5)
    p.custom_minimum_size = Vector2(170, 0)
    p.set_meta("iid", iid)
    _chips[iid] = p
    p.accepts_check = func(payload): return _accepts_on_character(iid, payload)
    p.dropped.connect(func(payload): _drop_on_character(iid, payload))
    # Your own characters can be picked up and dragged onto what they attack.
    if player == 0 and _can_act() and GameEngine._attack_candidates(st, 0).has(iid) \
            and st.player(0).energy_current >= d.attack_cost:
        p.drag_payload = {"kind": "attack", "attacker": iid,
            "label": "%s attacks" % d.name}
        p.tooltip_text = "Drag onto a target to attack, or use the button."
    _drop_targets.append(p)

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
    # One note at most, so a chip's height stays predictable and its action
    # button is never pushed out of the Companion Zone. The rest go in the
    # tooltip.
    if not notes.is_empty():
        v.add_child(UiTheme.label(String(notes[0]), 10, UiTheme.TEXT_DIM))
    if notes.size() > 1:
        v.add_child(UiTheme.label("+%d more — hover to read" % (notes.size() - 1),
            10, UiTheme.GOLD_DIM))
    if not notes.is_empty():
        var hint := p.tooltip_text
        p.tooltip_text = "%s\n%s%s" % [d.name, "\n".join(notes),
            "\n" + hint if hint != "" else ""]

    # Action affordances.
    if _mode == "pick_attack_target" and player == 1:
        v.add_child(_target_button(iid))
    elif _mode == "pick_card_target" and Targeting.legal_targets(st, _target_kind, 0).has(iid):
        v.add_child(_target_button(iid))
    elif _mode == "idle" and player == 0 and _can_act() \
            and GameEngine._attack_candidates(st, 0).has(iid):
        var b := UiTheme.button("Attack with this", "Costs %d Energy. You can also drag this character onto a target." % d.attack_cost)
        b.disabled = st.player(0).energy_current < d.attack_cost
        b.pressed.connect(func(): _begin_attack(iid))
        v.add_child(b)
    p.add_child(v)
    p.claim_mouse()
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
        var view := CardView.create(d, HAND_CARD_W, true)
        var playable := false
        var why := ""
        if reaction_window:
            playable = d.allows_reaction_timing()
            why = "Playable as a Reaction" if playable else "Not a Reaction card"
        elif _can_act():
            playable = d.allows_action_timing()
            why = "" if playable else "Reaction only"
        elif st.player(0).passed_actions:
            why = "You passed this round"
        elif st.phase == "action":
            why = "Not your turn yet"
        else:
            why = "Wait for the %s Phase" % st.phase.capitalize()
        if playable:
            var cost: int = d.fixed_cost() if d.cost_kind() == "fixed" else d.x_min()
            if st.player(0).energy_current < cost:
                playable = false
                why = "Needs %d Energy" % cost
        if playable and d.target_spec is Dictionary:
            var kind := String((d.target_spec as Dictionary).get("kind", ""))
            var optional := bool((d.target_spec as Dictionary).get("optional", false))
            if not optional and Targeting.legal_targets(st, kind, 0).is_empty():
                playable = false
                why = "No legal target"

        var card_iid := String(iid)
        if playable:
            view.add_badge("Eligible", UiTheme.GOOD)
            view.drag_payload = {"kind": "card", "iid": card_iid,
                "as_reaction": reaction_window, "label": d.name}
            view.tooltip_text = "Drag %s onto where it should go, or click it." % d.name
            view.pressed.connect(func(_id): _begin_play(card_iid, reaction_window))
            var b := UiTheme.primary_button("Play as Reaction" if reaction_window else "Commit")
            b.pressed.connect(func(): _begin_play(card_iid, reaction_window))
            # The button sits above the card so it is always the first thing in
            # the hand strip, never pushed below the visible area.
            var holder := UiTheme.vbox(2)
            holder.add_child(b)
            holder.add_child(view)
            _hand_row.add_child(holder)
        else:
            view.add_badge(why if why != "" else "Not playable now", UiTheme.TEXT_DIM)
            view.tooltip_text = why
            view.modulate = Color(1, 1, 1, 0.6)
            var holder2 := UiTheme.vbox(2)
            holder2.add_child(UiTheme.spacer(34))
            holder2.add_child(view)
            _hand_row.add_child(holder2)


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
    return ("Drag a card onto its target, or onto the Action Sequence if it needs none. "
        + "Clicking works too: use a card's Commit button, or Attack with this.")


func _refresh_log() -> void:
    for c in _log_box.get_children():
        c.queue_free()
    _log_box.add_child(UiTheme.label("Match log", 13, UiTheme.GOLD))
    _log_box.add_child(UiTheme.label("You are P1, your opponent is P2.", 10, UiTheme.TEXT_DIM))
    var lines := st.log_lines(70)
    for i in range(max(0, lines.size() - 45), lines.size()):
        _log_box.add_child(UiTheme.wrapped(String(lines[i]), 10, UiTheme.TEXT_DIM))


# ------------------------------------------------------------- interactions ---

## Can this hand card be played at all right now? Mirrors the check the hand
## uses to decide whether to offer a button, so dragging and clicking always
## agree about what is legal.
func _card_playable_now(iid: String, as_reaction: bool) -> bool:
    if st == null or st.result != null:
        return false
    var ci := st.inst(iid)
    if ci == null or ci.zone != "hand" or ci.owner != 0:
        return false
    var d := st.def_of(iid)
    if d == null:
        return false
    if as_reaction:
        if not _is_reaction_window_for_player() or not d.allows_reaction_timing():
            return false
    else:
        if not _can_act() or not d.allows_action_timing():
            return false
    var cost: int = d.fixed_cost() if d.cost_kind() == "fixed" else d.x_min()
    return st.player(0).energy_current >= cost


## Which instance a drop on this chip actually targets. Equipment and Ta'ahma
## are dropped onto the character wearing them.
func _resolve_drop_target(chip_iid: String, kind: String) -> String:
    var legal := Targeting.legal_targets(st, kind, 0)
    if legal.has(chip_iid):
        return chip_iid
    for a in st.attachments_of(chip_iid):
        if legal.has(String(a)):
            return String(a)
    return ""


func _accepts_on_character(iid: String, payload: Dictionary) -> bool:
    if st == null or st.result != null:
        return false
    match String(payload.get("kind", "")):
        "attack":
            if not _can_act():
                return false
            if not GameEngine._attack_candidates(st, 0).has(String(payload.get("attacker", ""))):
                return false
            return Targeting.legal_attack_targets(st, 0).has(iid)
        "card":
            var card_iid := String(payload.get("iid", ""))
            if not _card_playable_now(card_iid, bool(payload.get("as_reaction", false))):
                return false
            var d := st.def_of(card_iid)
            if d == null or not (d.target_spec is Dictionary):
                return false
            return _resolve_drop_target(iid, String((d.target_spec as Dictionary).get("kind", ""))) != ""
    return false


func _accepts_on_sequence(payload: Dictionary) -> bool:
    if String(payload.get("kind", "")) != "card":
        return false  # an attack has to be dragged onto what it attacks
    var card_iid := String(payload.get("iid", ""))
    if not _card_playable_now(card_iid, bool(payload.get("as_reaction", false))):
        return false
    var d := st.def_of(card_iid)
    if d == null:
        return false
    if not (d.target_spec is Dictionary):
        return true
    return bool((d.target_spec as Dictionary).get("optional", false))


func _accepts_on_location(payload: Dictionary) -> bool:
    if String(payload.get("kind", "")) != "card":
        return false
    var card_iid := String(payload.get("iid", ""))
    if not _card_playable_now(card_iid, bool(payload.get("as_reaction", false))):
        return false
    var d := st.def_of(card_iid)
    if d == null:
        return false
    # A Terrain card played from hand goes here.
    if d.has_type("location") and not (d.target_spec is Dictionary):
        return true
    # So does a card that targets whatever Terrain is already in play.
    if not (d.target_spec is Dictionary):
        return false
    if String((d.target_spec as Dictionary).get("kind", "")) != "location":
        return false
    return not Targeting.legal_targets(st, "location", 0).is_empty()


## Your own Companion Zone takes a Companion straight from your hand, which
## commits its deployment to the Sequence like any other Action.
func _accepts_on_companion_zone(payload: Dictionary) -> bool:
    if String(payload.get("kind", "")) != "card":
        return false
    var card_iid := String(payload.get("iid", ""))
    if not _card_playable_now(card_iid, bool(payload.get("as_reaction", false))):
        return false
    var d := st.def_of(card_iid)
    if d == null or not d.has_type("companion"):
        return false
    return not (d.target_spec is Dictionary)


# --------------------------------------------------------------- drop actions ---

func _drop_on_character(iid: String, payload: Dictionary) -> void:
    if String(payload.get("kind", "")) == "attack":
        var r := GameEngine.submit(st, {"cmd": "commit_attack", "player": 0,
            "attacker_iid": String(payload.get("attacker", "")), "target_iid": iid})
        if not bool(r["ok"]):
            app.toast(String(r["error"]), true)
            return
        _mode = "idle"
        _pending_attacker = ""
        _after_command()
        return
    var card_iid := String(payload.get("iid", ""))
    var d := st.def_of(card_iid)
    if d == null or not (d.target_spec is Dictionary):
        return
    var kind := String((d.target_spec as Dictionary).get("kind", ""))
    var resolved := _resolve_drop_target(iid, kind)
    if resolved == "":
        app.toast(Targeting.explain_invalid(st, kind, 0, iid), true)
        return
    _play_dragged(card_iid, [resolved], bool(payload.get("as_reaction", false)))


func _drop_on_sequence(payload: Dictionary) -> void:
    _play_dragged(String(payload.get("iid", "")), [], bool(payload.get("as_reaction", false)))


func _drop_on_location(payload: Dictionary) -> void:
    var card_iid := String(payload.get("iid", ""))
    var d := st.def_of(card_iid)
    if d == null:
        return
    var as_reaction := bool(payload.get("as_reaction", false))
    if d.has_type("location") and not (d.target_spec is Dictionary):
        _play_dragged(card_iid, [], as_reaction)  # a Terrain played from hand
        return
    var legal := Targeting.legal_targets(st, "location", 0)
    if legal.is_empty():
        app.toast("There is no Terrain in play to target.", true)
        return
    _play_dragged(card_iid, [String(legal[0])], as_reaction)


## Play a card whose target was already settled by where it was dropped. An X
## cost is still asked for, because only the player can decide that.
func _play_dragged(iid: String, targets: Array, as_reaction: bool) -> void:
    var d := st.def_of(iid)
    if d == null:
        return
    _pending_card = iid
    _as_reaction = as_reaction
    _pending_targets = targets.duplicate()
    _targets_prechosen = true
    if d.cost_kind() == "x":
        _pending_x = d.x_min()
        _ask_for_x(d)
        return
    _submit_card(targets)


# ------------------------------------------------------------------ effects ---

func _screen_pos_of(iid: String) -> Vector2:
    if _chips.has(iid) and is_instance_valid(_chips[iid]):
        return (_chips[iid] as Control).get_global_rect().get_center()
    return get_global_rect().get_center()


func _pile_pos(player: int, kind: String) -> Vector2:
    var key := "%d_%s" % [player, kind]
    if _pile_chips.has(key) and is_instance_valid(_pile_chips[key]):
        return (_pile_chips[key] as Control).get_global_rect().get_center()
    return get_global_rect().get_center()


func _owner_of(iid: String, fallback: int) -> int:
    var ci := st.inst(iid)
    return ci.owner if ci != null else fallback


## Show what the engine just did. Purely cosmetic: the state is already final
## by the time any of this is drawn, and play never waits for it.
func _play_new_events() -> void:
    if st == null or _effects == null or not is_instance_valid(_effects):
        return
    var i := _events_seen
    _events_seen = st.events.size()
    var delay := 0.0
    var shown := 0
    while i < st.events.size() and shown < 24:
        var e: Dictionary = st.events[i]
        i += 1
        var kind := String(e.get("kind", ""))
        match kind:
            "hero_damaged":
                var pi := int(e.get("player", 0))
                var amount := int(e.get("amount", 0))
                _effects.float_text(_screen_pos_of(st.player(pi).hero_iid),
                    "-%d" % amount, UiTheme.DAMAGE_TEXT, 30, delay)
                var from_exhaust := int(e.get("from_exhaust", 0))
                for k in min(from_exhaust, 4):
                    _effects.fly_card(_pile_pos(pi, "exhaust"), _pile_pos(pi, "wound"),
                        "Wounded", UiTheme.DAMAGE_TEXT, delay + 0.07 * float(k))
                var from_hit := int(e.get("from_hit", 0))
                for k in min(from_hit, 4):
                    _effects.fly_card(_pile_pos(pi, "hit"), _pile_pos(pi, "wound"),
                        "Wounded", UiTheme.DAMAGE_TEXT, delay + 0.07 * float(k + from_exhaust))
                delay += 0.3
                shown += 1
            "companion_damaged":
                var target := String(e.get("target", ""))
                _effects.float_text(_screen_pos_of(target), "-%d" % int(e.get("amount", 0)),
                    UiTheme.DAMAGE_TEXT, 26, delay)
                delay += 0.2
                shown += 1
            "no_damage":
                var t2 := String(e.get("target", ""))
                if t2 != "":
                    _effects.float_text(_screen_pos_of(t2), "0", UiTheme.TEXT_DIM, 22, delay)
                    delay += 0.15
                    shown += 1
            "destroyed":
                var iid := String(e.get("iid", ""))
                _effects.fly_card(_screen_pos_of(iid),
                    _pile_pos(_owner_of(iid, int(e.get("owner", 0))), "wound"),
                    "Destroyed", UiTheme.DAMAGE_TEXT, delay)
                delay += 0.2
                shown += 1
            "to_exhaust", "replaced", "attachment_released", "hand_exhausted":
                var iid2 := String(e.get("iid", ""))
                _effects.fly_card(_screen_pos_of(iid2), _pile_pos(_owner_of(iid2, 0), "exhaust"),
                    "Exhausted", UiTheme.TEXT_DIM, delay)
                delay += 0.12
                shown += 1
            "energy_gained":
                var gained := int(e.get("gained", 0))
                if gained > 0:
                    _effects.float_text(_screen_pos_of(st.player(int(e.get("player", 0))).hero_iid),
                        "+%d Energy" % gained, UiTheme.ENERGY_TEXT, 20, delay)
                    delay += 0.15
                    shown += 1
            "energy_drained":
                _effects.float_text(_screen_pos_of(st.player(int(e.get("player", 0))).hero_iid),
                    "-%d Energy" % int(e.get("amount", 0)), UiTheme.ENERGY_TEXT.darkened(0.2),
                    20, delay)
                delay += 0.15
                shown += 1
            "shield_added":
                _effects.float_text(_screen_pos_of(String(e.get("iid", ""))),
                    "Shield %d" % int(e.get("amount", 0)), UiTheme.HEAL_TEXT, 20, delay)
                delay += 0.15
                shown += 1
            "stat_modified":
                _effects.float_text(_screen_pos_of(String(e.get("iid", ""))), "!",
                    UiTheme.GOLD, 20, delay)
                delay += 0.1
                shown += 1
            "deployed":
                var iid3 := String(e.get("iid", ""))
                _effects.float_text(_screen_pos_of(iid3), "Enters play", UiTheme.HEAL_TEXT, 18, delay)
                delay += 0.15
                shown += 1


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
    _pending_targets = []
    _targets_prechosen = false
    _refresh()


func _begin_play(iid: String, as_reaction: bool) -> void:
    var d := st.def_of(iid)
    if d == null:
        return
    _pending_card = iid
    _as_reaction = as_reaction
    _pending_targets = []
    _targets_prechosen = false
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
        if _targets_prechosen:
            _submit_card(_pending_targets)
        else:
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
    _pending_targets = []
    _targets_prechosen = false
    _after_command()
