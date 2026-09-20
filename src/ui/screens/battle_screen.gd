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
## The card's own target block, which may narrow the list further than its
## kind does — a Ta'ahma written for one named character, for instance.
var _target_filter: Dictionary = {}
var _as_reaction: bool = false
var _choice_selection: Array = []
## Targets already chosen by dropping a card onto them, so the X-cost prompt
## does not ask for them a second time.
var _pending_targets: Array = []
var _targets_prechosen: bool = false

# Drag and drop.
var _drop_targets: Array = []
## The zones among those targets: the ones that are a region rather than a
## single card, so a drop lands anywhere inside them.
var _drop_zones: Array = []
var _dragging: bool = false

# AI turn handling.
var _thinker: AiThinker = null
var _ai_pause: float = 0.0
## How long the movement just replayed still has to run. The opponent waits it
## out, so a round's worth of cards changing hands is watched rather than
## skipped past. Your own input is never held: this only paces the opponent.
var _replay_hold: float = 0.0
## However much happens at once, the opponent is never held longer than this.
const MAX_REPLAY_HOLD := 6.0
## The beat between one card of the Action Sequence resolving and the next, on
## top of whatever its own animation takes. The Sequence is the heart of a
## round, so it is watched a card at a time rather than happening all at once.
const RESOLVE_STEP_PAUSE := 0.45
var _resolve_pause: float = 0.0

# Layout metrics, budgeted against the window rather than left to grow. The
# board is painted art, so each zone is sized to the plate behind it. These are
# editable: the Layout screen changes them and writes them to data/layout.json.
var HAND_CARD_W: float = Layout.num("battle_board", "hand_card_w")
var HAND_STRIP_H: float = Layout.num("battle_board", "hand_strip_h")
var COMPANION_STRIP_H: float = Layout.num("battle_board", "companion_strip_h")
var DECK_PLATE_H: float = Layout.num("battle_board", "deck_plate_h")
var MIDDLE_H: float = Layout.num("battle_board", "middle_h")
## Cards standing on the board and in the Action Sequence. They are drawn small
## the way cards on a table are; resting the pointer on one brings it up at a
## readable size.
var BOARD_CARD_W: float = Layout.num("battle_board", "board_card_w")
var SEQ_CARD_W: float = Layout.num("battle_board", "seq_card_w")
var LOCATION_W: float = Layout.num("battle_board", "location_w")
## The opponent's hand is face down, so its cards are drawn smaller than yours:
## there is nothing on them to read, only how many there are.
var OPP_HAND_CARD_W: float = Layout.num("battle_board", "opp_hand_card_w")
## What a plated zone costs around the strip inside it: its border, its inset
## and the caption line it shows while it is empty.
const ZONE_CHROME := 24.0

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
var _location_zone: BattleDropTarget
var _location_holder: VBoxContainer
var _opp_piles: HBoxContainer
var _own_piles: HBoxContainer
var _own_companion_zone: BattleDropTarget
var _opp_companion_zone: BattleDropTarget
## How much Energy each player has, on their own side of the field.
var _energy_gauges: Dictionary = {}
## The opponent's hand, drawn as the card backs it is made of.
var _opp_hand_row: HBoxContainer
var _opp_hand_strip: Control
## The room kept at each end of a deck row for its gauge, so the plates
## between them stay centred on the board.
const GAUGE_CELL_W := 148.0
## The strips whose height has to give way when the window cannot hold the
## board at the size the layout asks for.
var _companion_strips: Array = []
var _deck_rows: Array = []
var _middle_row: Control = null
var _hand_zone: Control = null
var _board_clip: Control = null
var _centre: VBoxContainer = null
## How much of its asked-for size the board actually gets, 0.45 to 1.0.
var _fit: float = 1.0

## Board chips by instance id, so effects know where things are on screen.
var _chips: Dictionary = {}
var _pile_chips: Dictionary = {}

## Cosmetic feedback for events that have already resolved.
var _effects: BoardEffects
var _events_seen: int = 0

## A full-size card face, shown while the pointer rests on a small one.
var _zoom: CardZoom

## The zone boundaries, banded over the board while a card is being dragged.
var _zone_bounds: ZoneBounds

## Announces each phase, and each step of the Resolve Phase.
var _banner: PhaseBanner


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
    # The Action Sequence resolves a card at a time while this screen is
    # showing it. The engine does exactly what it did before and in the same
    # order; it just hands control back between steps so each one can be
    # watched. Nothing else in the game sets this, so the AI's rollouts still
    # run straight through.
    st.watch_resolve = true
    # Everything already in the log happened before this screen opened, so it
    # is not replayed as animation.
    _events_seen = st.events.size()
    _build()
    _refresh()


## The board is one painted field. Every zone on it is a plate sliced from the
## same artwork, laid out as two mirrored halves around a shared middle, with
## the hand pinned along the bottom.
func _build() -> void:
    # The painted board itself, dimmed, behind everything. Its ornate frame and
    # banners are what the edges of the screen show.
    var field := BoardArt.plate("board_full", BoardArt.FIELD_TINT)
    field.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(field)

    var root := UiTheme.vbox(3)
    root.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(root)

    _top = UiTheme.hbox(10)
    root.add_child(_top)

    var cols := UiTheme.hbox(8)
    cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
    root.add_child(cols)

    # The board does not scroll. Every zone is sized to hold a whole card, so
    # nothing on the table is ever half a card with the rest below the fold —
    # a card you have to scroll to see is a card you cannot play from.
    #
    # It sits inside a plain Control rather than directly in the row, so the
    # board's own height is not allowed to push anything: the hand keeps the
    # room it needs and the board is fitted to what is left over.
    var board_clip := Control.new()
    board_clip.clip_contents = true
    board_clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    board_clip.size_flags_vertical = Control.SIZE_EXPAND_FILL
    cols.add_child(board_clip)

    var centre := UiTheme.vbox(2)
    centre.set_anchors_preset(Control.PRESET_FULL_RECT)
    board_clip.add_child(centre)
    _board_clip = board_clip
    _centre = centre

    # Two mirrored halves. The rules give the two players one Action Sequence
    # and one Location between them, not one apiece, so those sit once in the
    # shared middle rather than being mirrored with everything else.
    centre.add_child(_make_opponent_hand())
    centre.add_child(_make_companion_zone(1))
    centre.add_child(_make_deck_row(1))
    centre.add_child(_make_middle())
    centre.add_child(_make_deck_row(0))
    centre.add_child(_make_companion_zone(0))

    var log_panel := UiTheme.panel(UiTheme.BG_PANEL.darkened(0.2), UiTheme.GOLD_DIM, 1, 6)
    log_panel.custom_minimum_size = Vector2(268, 0)
    _log_box = UiTheme.vbox(1)
    log_panel.add_child(UiTheme.scroll(_log_box))
    cols.add_child(log_panel)

    # The hand is pinned along the bottom, and what the game is asking of you
    # is written directly above it: the prompt and its buttons belong with the
    # cards they are talking about, and a strip of their own would be a strip
    # taken off the board.
    _hand_row = UiTheme.hbox(6)
    var hand_zone := PanelContainer.new()
    var hand_box := BoardArt.back(hand_zone, "panel_hand", UiTheme.GOLD, 2)

    var action_bar := UiTheme.hbox(10)
    # One line, always. A prompt that wraps to two lines would take that line
    # off the hand below it, and the hand is the part that has to be right.
    # The whole text is in the line's tooltip when it is too long to fit.
    action_bar.custom_minimum_size = Vector2(0, 32)
    _controls = UiTheme.hbox(8)
    action_bar.add_child(_controls)
    _prompt = UiTheme.label("", 12, UiTheme.GOLD)
    _prompt.autowrap_mode = TextServer.AUTOWRAP_OFF
    _prompt.clip_text = true
    _prompt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    _prompt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    action_bar.add_child(_prompt)
    hand_box.add_child(action_bar)

    var hand_scroll := UiTheme.scroll(_hand_row, true)
    hand_scroll.custom_minimum_size = Vector2(0, HAND_STRIP_H)
    hand_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    hand_scroll.size_flags_vertical = Control.SIZE_FILL
    hand_box.add_child(hand_scroll)
    hand_zone.size_flags_vertical = Control.SIZE_SHRINK_END
    _hand_zone = hand_zone
    root.add_child(hand_zone)

    # Added last so they draw over the board. None of them takes input.
    _zone_bounds = ZoneBounds.new()
    add_child(_zone_bounds)
    _effects = BoardEffects.new()
    add_child(_effects)
    _banner = PhaseBanner.new()
    add_child(_banner)
    _zoom = CardZoom.new()
    add_child(_zoom)


## The opponent's hand, at the top of the board, mirroring yours at the bottom.
##
## Their cards are face down, because only how many they hold is public — but
## how many they hold matters constantly, and a row of card backs says it at a
## glance in a way a number never did. It is the same plate as your own hand,
## the other way up.
func _make_opponent_hand() -> Control:
    var zone := PanelContainer.new()
    zone.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    var box := BoardArt.back(zone, "panel_hand", UiTheme.GOLD_DIM, 2)
    _opp_hand_row = UiTheme.hbox(4)
    _opp_hand_row.alignment = BoxContainer.ALIGNMENT_CENTER
    var scroll := UiTheme.scroll(_opp_hand_row, true)
    scroll.custom_minimum_size = Vector2(0, OPP_HAND_CARD_W * CardView.BASE_HEIGHT
        / CardView.BASE_WIDTH)
    scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    box.add_child(scroll)
    _opp_hand_strip = scroll
    return zone


## The shared middle: the Action Sequence, with the Location plate beside it,
## the way the two sit side by side on the painted board.
func _make_middle() -> Control:
    var row := UiTheme.hbox(6)
    row.custom_minimum_size = Vector2(0, MIDDLE_H)
    row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    _middle_row = row
    var seq := _make_sequence_zone()
    seq.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(seq)
    var loc := _make_location_zone()
    loc.custom_minimum_size = Vector2(LOCATION_W, 0)
    row.add_child(loc)
    return row


## One player's decks and Hero, on the plates painted for them. Player 0 reads
## Hit, Hero, Exhaust, Wound from the left; the opponent's row is mirrored.
func _make_deck_row(player: int) -> Control:
    var row := UiTheme.hbox(6)
    row.alignment = BoxContainer.ALIGNMENT_CENTER
    row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    if player == 0:
        _own_piles = row
    else:
        _opp_piles = row

    # Each player's Energy stands at the outer edge of their own deck row, on
    # their own half of the field: yours on the left, your opponent's on the
    # right, so the two are never mistaken for each other. The plates stay
    # centred because the far side of the row is padded to match.
    var gauge := EnergyGauge.create(_gauge_gem_w(),
        "Your Energy" if player == 0 else "Opponent's Energy")
    _energy_gauges[player] = gauge
    var gauge_cell := UiTheme.hbox(0)
    gauge_cell.custom_minimum_size = Vector2(GAUGE_CELL_W, 0)
    gauge_cell.alignment = BoxContainer.ALIGNMENT_BEGIN if player == 0 \
        else BoxContainer.ALIGNMENT_END
    gauge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    gauge_cell.add_child(gauge)
    var pad := Control.new()
    pad.custom_minimum_size = Vector2(GAUGE_CELL_W, 0)
    pad.mouse_filter = Control.MOUSE_FILTER_IGNORE

    var outer := UiTheme.hbox(6)
    outer.custom_minimum_size = Vector2(0, DECK_PLATE_H + 4.0)
    outer.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    if player == 0:
        outer.add_child(gauge_cell)
        outer.add_child(row)
        outer.add_child(pad)
    else:
        outer.add_child(pad)
        outer.add_child(row)
        outer.add_child(gauge_cell)
    _deck_rows.append(outer)
    return outer


## How wide the Energy gem is drawn: as tall as the deck plates beside it will
## allow, so the gauge reads as part of that row rather than sitting over it.
func _gauge_gem_w() -> float:
    return (DECK_PLATE_H * _fit - 6.0) / EnergyGauge.GEM_RATIO


## The caption over each Companion Zone, kept so it can step aside once there
## are Companions standing in the zone: the cards say what the zone is, and the
## board has no height to spare for a line that repeats them.
var _zone_captions: Dictionary = {}


func _make_companion_zone(player: int) -> Control:
    var target := BattleDropTarget.new()
    # A zone is exactly as tall as the cards standing in it. Left to expand, an
    # empty zone would take the room the hand needs and the cards you can play
    # would be the thing that falls off the screen.
    target.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    var v := BoardArt.back(target, "panel_companion", UiTheme.GOLD, 2)
    var caption := BoardArt.caption(
        "Your Companion Zone" if player == 0 else "Opponent's Companion Zone", 10)
    _zone_captions[player] = caption
    v.add_child(caption)
    var row := UiTheme.hbox(8)
    row.alignment = BoxContainer.ALIGNMENT_CENTER
    # It scrolls sideways when a player fields more Companions than the zone is
    # wide, and never vertically: the strip is as tall as a whole card.
    var row_scroll := UiTheme.scroll(row, true)
    row_scroll.custom_minimum_size = Vector2(0, COMPANION_STRIP_H)
    row_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    row_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    _companion_strips.append(row_scroll)
    v.add_child(row_scroll)
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


## The Location plate. Its painted caption reads "Terrain", so it is cropped
## out of the artwork and the game's own word is drawn here instead.
func _make_location_zone() -> Control:
    _location_zone = BattleDropTarget.new()
    var v := BoardArt.back(_location_zone, "panel_location", UiTheme.GOLD, 2)
    _location_zone.drop_hint = "Play here"
    _location_zone.accepts_check = func(payload): return _accepts_on_location(payload)
    _location_zone.dropped.connect(func(payload): _drop_on_location(payload))
    v.add_child(BoardArt.caption("Location", 12))
    _location_holder = UiTheme.vbox(2)
    _location_holder.alignment = BoxContainer.ALIGNMENT_CENTER
    _location_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
    v.add_child(_location_holder)
    return _location_zone


func _make_sequence_zone() -> Control:
    _sequence_zone = BattleDropTarget.new()
    var v := BoardArt.back(_sequence_zone, "panel_sequence", UiTheme.GOLD, 2)
    _sequence_zone.drop_hint = "Commit to the Action Sequence"
    _sequence_zone.accepts_check = func(payload): return _accepts_on_sequence(payload)
    _sequence_zone.dropped.connect(func(payload): _drop_on_sequence(payload))
    # No caption: the plate behind this zone has ACTION SEQUENCE painted across
    # it in letters a foot high. Repeating it in a caption would cost the zone a
    # line of height, and height here is a card's worth of legibility.
    var head := UiTheme.hbox(8)
    head.alignment = BoxContainer.ALIGNMENT_CENTER
    _chain_label = UiTheme.label("", 10, UiTheme.GOLD)
    head.add_child(_chain_label)
    v.add_child(head)
    _sequence_row = UiTheme.hbox(8)
    var seq_scroll := UiTheme.scroll(_sequence_row, true)
    seq_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    seq_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    v.add_child(seq_scroll)
    return _sequence_zone


func _process(delta: float) -> void:
    _update_drag_state()
    if st == null or st.result != null:
        return
    # Whatever just happened finishes being shown before anything else starts.
    # Only the match is held: your own cards stay live throughout, because
    # input does not come through here.
    if _replay_hold > 0.0:
        _replay_hold -= delta
        return
    # The Action Sequence resolves one card at a time, with a beat between, so
    # a round can be followed rather than reconstructed from the log.
    if st.phase == "resolve" and st.pending == null:
        _resolve_pause -= delta
        if _resolve_pause <= 0.0:
            _resolve_pause = RESOLVE_STEP_PAUSE
            GameEngine.advance(st)
            _after_command()
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
## lights up, and every zone that would take it is banded from edge to edge, so
## it reads as the region it is rather than as a row of anchor points. Nothing
## is rebuilt mid-drag, only restyled, so the drag itself is never interrupted.
func _update_drag_state() -> void:
    var vp := get_viewport()
    if vp == null:
        return
    var now := vp.gui_is_dragging()
    if now == _dragging:
        return
    _dragging = now
    if now and _zoom != null and is_instance_valid(_zoom):
        _zoom.dismiss()
    var payload = vp.gui_get_drag_data() if now else null
    for tgt in _drop_targets:
        if tgt is BattleDropTarget and is_instance_valid(tgt):
            var target := tgt as BattleDropTarget
            target.set_highlight(now and target.can_accept(payload))
    if _zone_bounds != null and is_instance_valid(_zone_bounds):
        _zone_bounds.show_zones(_bands_for(payload) if now else [])


## The zones a payload could be dropped into, as bands to draw. A zone that is
## scrolled out of sight is banded only as far as it is actually visible.
func _bands_for(payload) -> Array:
    var bands: Array = []
    for z in _drop_zones:
        if not (z is BattleDropTarget) or not is_instance_valid(z):
            continue
        var zone := z as BattleDropTarget
        if not zone.can_accept(payload):
            continue
        var rect := ZoneBounds.visible_rect(zone)
        if rect.size.x <= 0.0 or rect.size.y <= 0.0:
            continue
        bands.append({"rect": rect, "hint": zone.drop_hint})
    return bands


func _after_command() -> void:
    app.persist_match()
    if st.result != null:
        app.goto("results")
        return
    _refresh()


# ------------------------------------------------------------------ refresh ---

## Make the board fit the room it has.
##
## The layout numbers say how big each zone would like to be. When the window
## cannot hold all of them — a small screen, or the Layout screen having been
## told to make them bigger — every card on the table is drawn proportionally
## smaller instead, so the hand below always stays on screen. A hand you cannot
## reach is a game you cannot play, and twice now a taller board has pushed it
## off the bottom.
func _fit_board() -> void:
    if _board_clip == null or _centre == null:
        return
    var have := _board_clip.size.y
    if have <= 0.0:
        # First pass, before the screen has been laid out. The design height
        # less the chrome around the board is the best guess available.
        have = 833.0 - 46.0 - 210.0
    # What the board is asking for is measured rather than estimated: the zones
    # know their own minimums, including the chrome around them, and reading
    # them back at the fit they were last drawn at recovers what they would
    # want at full size.
    var measured := 0.0
    for row in _centre.get_children():
        measured += (row as Control).get_combined_minimum_size().y
    measured += 2.0 * float(max(0, _centre.get_child_count() - 1))
    var want := measured / maxf(_fit, 0.05)
    _fit = 1.0 if want <= 0.0 else clampf(have / want, 0.45, 1.0)

    for strip in _companion_strips:
        (strip as Control).custom_minimum_size = Vector2(0, COMPANION_STRIP_H * _fit)
    for row in _deck_rows:
        (row as Control).custom_minimum_size = Vector2(0, (DECK_PLATE_H + 4.0) * _fit)
    if _middle_row != null:
        _middle_row.custom_minimum_size = Vector2(0, MIDDLE_H * _fit)


## What a card standing on the board is actually drawn at, once the board has
## been fitted to the window.
func _board_card_w() -> float:
    return BOARD_CARD_W * _fit


func _seq_card_w() -> float:
    return SEQ_CARD_W * _fit


func _deck_plate_h() -> float:
    return DECK_PLATE_H * _fit


func _refresh() -> void:
    if st == null:
        return
    _fit_board()
    # Chips are rebuilt every refresh, so the lookups that depend on them are
    # rebuilt first.
    _chips = {}
    _pile_chips = {}
    _drop_targets = []
    _drop_zones = []
    # The thing being read is about to be freed, so nothing is being read.
    if _zoom != null and is_instance_valid(_zoom):
        _zoom.dismiss()
    for zone in [_sequence_zone, _location_zone, _own_companion_zone]:
        if zone != null:
            _drop_targets.append(zone)
            _drop_zones.append(zone)

    _refresh_top()
    _refresh_opp_hand()
    _refresh_piles()
    _refresh_boards()
    _refresh_location()
    _refresh_sequence()
    _refresh_hand()
    _refresh_controls()
    _refresh_log()
    # The cards that just went into the zones would otherwise stand between a
    # drop and the zone under them, so the zones are reopened now that they are
    # filled.
    for z in _drop_zones:
        (z as BattleDropTarget).open_to_drops()
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
        # Neither Energy nor hand size is written here any more. Both are on
        # the board itself: Energy in the gem on each player's side of the
        # field, and a hand as the cards it is actually made of.
        var row := UiTheme.hbox(6)
        row.add_child(UiTheme.label("You" if i == 0 else "Opponent", 13,
            UiTheme.GOLD if i == 0 else UiTheme.TEXT))
        row.add_child(UiTheme.label(hero.name if hero != null else "?", 12, UiTheme.TEXT_DIM))
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
    # Mirrored: your row reads Hit, Hero, Exhaust, Wound from the left, so the
    # opponent's reads the same order from their side of the board.
    _fill_piles(_own_piles, 0, ["hit", "hero", "exhaust", "wound"])
    _fill_piles(_opp_piles, 1, ["wound", "exhaust", "hero", "hit"])
    _refresh_energy()


## The opponent's hand: one card back per card they hold, and the plate alone
## when they hold none. Nothing here reads their cards — the backs are all the
## screen is ever given.
func _refresh_opp_hand() -> void:
    if _opp_hand_row == null or not is_instance_valid(_opp_hand_row):
        return
    for c in _opp_hand_row.get_children():
        _opp_hand_row.remove_child(c)
        c.queue_free()
    var held := st.player(1).hand.size()
    if held <= 0:
        _opp_hand_row.add_child(BoardArt.caption("your opponent holds no cards", 10))
        return
    var width := OPP_HAND_CARD_W * _fit
    if _opp_hand_strip != null and is_instance_valid(_opp_hand_strip):
        _opp_hand_strip.custom_minimum_size = Vector2(0,
            width * CardView.BASE_HEIGHT / CardView.BASE_WIDTH)
    for i in held:
        var back := CardView.face_down(width)
        if back == null:
            break
        back.mouse_filter = Control.MOUSE_FILTER_IGNORE
        back.tooltip_text = "Your opponent holds %d card%s." % [held,
            "" if held == 1 else "s"]
        _opp_hand_row.add_child(back)


## Each player's Energy, on their own side of the field. Both are always shown:
## what your opponent can still afford decides what you can safely do.
func _refresh_energy() -> void:
    for player in [0, 1]:
        var gauge = _energy_gauges.get(player, null)
        if gauge == null or not is_instance_valid(gauge):
            continue
        (gauge as EnergyGauge).set_gem_width(_gauge_gem_w())
        (gauge as EnergyGauge).set_energy(st.player(player).energy_current,
            st.energy_max(player))


func _fill_piles(row: HBoxContainer, player: int, order: Array) -> void:
    for c in row.get_children():
        row.remove_child(c)
        c.queue_free()
    for kind in order:
        if String(kind) == "hero":
            row.add_child(_character_chip(st.player(player).hero_iid, player, true))
        else:
            row.add_child(_pile_chip(player, String(kind)))


const PILE_LABEL := {"hit": "Hit Deck", "exhaust": "Exhaust Deck", "wound": "Wound Deck"}


## A deck, on the plate painted for it. The plate already carries the deck's
## name, so the only thing drawn over it is how many cards are in it.
func _pile_chip(player: int, kind: String) -> Control:
    var p := st.player(player)
    var count := p.pile(kind).size()
    var chip := PanelContainer.new()
    var v := BoardArt.back(chip, "deck_" + kind, UiTheme.GOLD_DIM, 1)
    chip.custom_minimum_size = Vector2(
        _deck_plate_h() * float(BoardArt.PILE_ASPECT.get(kind, 2.0)), _deck_plate_h())
    chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    var key := "%d_%s" % [player, kind]
    chip.set_meta("pile", key)
    _pile_chips[key] = chip
    # A deck with cards in it shows the top one, face down, standing on its
    # painted plate. An empty deck shows the plate alone: there is no card
    # there to be face down.
    var ink: Color = UiTheme.DANGER.lightened(0.35) if kind == "wound" \
        else UiTheme.PARCHMENT
    var row := UiTheme.hbox(4)
    row.size_flags_vertical = Control.SIZE_EXPAND_FILL
    var back := CardView.face_down(_deck_back_w(), count, ink) if count > 0 else null
    if back != null:
        row.add_child(back)
    else:
        # Nothing in the deck: the plate's own caption is all there is to see,
        # so the count goes where the cards would have been.
        var empty := UiTheme.label("0", 22, ink.darkened(0.25),
            HORIZONTAL_ALIGNMENT_CENTER)
        empty.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
        empty.add_theme_constant_override("shadow_offset_x", 1)
        empty.add_theme_constant_override("shadow_offset_y", 1)
        empty.custom_minimum_size = Vector2(_deck_back_w(), 0)
        empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        row.add_child(empty)
    var gap := Control.new()
    gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row.add_child(gap)
    v.add_child(row)
    chip.tooltip_text = "%s: %d card%s" % [String(PILE_LABEL.get(kind, kind)), count,
        "" if count == 1 else "s"]
    return chip


## How wide a face-down card on a deck plate is: as tall as the plate's inside
## allows, so the deck reads as cards rather than as a picture on a picture.
func _deck_back_w() -> float:
    return (_deck_plate_h() - 16.0) * CardView.BASE_WIDTH / CardView.BASE_HEIGHT


func _refresh_boards() -> void:
    _fill_board(_opp_board, 1)
    _fill_board(_own_board, 0)


func _refresh_location() -> void:
    for c in _location_holder.get_children():
        _location_holder.remove_child(c)
        c.queue_free()
    if st.location_iid == "":
        _location_holder.add_child(BoardArt.caption("none in play", 10))
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
    # The Location in play is a card, so it is drawn as one, with only whose it
    # is written under it.
    var lv := UiTheme.vbox(2)
    var face := CardView.create(d, _board_card_w())
    face.mouse_filter = Control.MOUSE_FILTER_IGNORE
    face.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
    lv.add_child(face)
    var whose := UiTheme.label("played by %s" % ("you" if owner == 0 else "your opponent"),
        9, UiTheme.GOLD_DIM, HORIZONTAL_ALIGNMENT_CENTER)
    whose.clip_text = true
    lv.add_child(whose)
    chip.tooltip_text = "%s\n%s" % [d.name, d.text]
    chip.add_child(lv)
    chip.claim_mouse()
    _readable(chip, d)
    _location_holder.add_child(chip)
    if _mode == "pick_card_target" and _target_kind == "location":
        _location_holder.add_child(_target_button(st.location_iid))


func _fill_board(row: HBoxContainer, player: int) -> void:
    for c in row.get_children():
        row.remove_child(c)
        c.queue_free()
    var p := st.player(player)
    if _zone_captions.has(player):
        (_zone_captions[player] as Control).visible = p.companions.is_empty()
    if p.companions.is_empty():
        row.add_child(UiTheme.label(
            "no Companions" if player == 0 else "no Companions", 11, UiTheme.TEXT_DIM))
    for iid in p.companions:
        row.add_child(_character_chip(String(iid), player, false))


## A Hero or a Companion on the board, drawn as the card it is.
##
## A character in play is a card on a table, so that is what it looks like:
## its own painted face, small, with the few things that are true of this copy
## rather than of the card underneath it written below. Resting the pointer on
## it brings it up at a readable size, the way picking a card up would.
func _character_chip(iid: String, player: int, is_hero: bool) -> Control:
    var d := st.def_of(iid)
    var ci := st.inst(iid)
    var committed := st.player(player).committed_characters.has(iid)
    var in_sequence := st.sequence_members.has(iid)
    var border := UiTheme.GOLD if in_sequence else (
        UiTheme.GOLD_DIM if not committed else UiTheme.TEXT_DIM)

    var p := BattleDropTarget.new()
    p.style(Color(0, 0, 0, 0.25), border, 2 if in_sequence else 1, 4)
    var v := UiTheme.vbox(2)
    v.alignment = BoxContainer.ALIGNMENT_BEGIN
    p.add_child(v)
    p.set_meta("iid", iid)
    _chips[iid] = p
    p.accepts_check = func(payload): return _accepts_on_character(iid, payload)
    p.dropped.connect(func(payload): _drop_on_character(iid, payload))
    # Your own characters can be picked up and dragged onto what they attack.
    if player == 0 and _can_act() and GameEngine._attack_candidates(st, 0).has(iid) \
            and st.player(0).energy_current >= d.attack_cost:
        p.drag_payload = {"kind": "attack", "attacker": iid,
            "label": "%s attacks" % d.name}
        p.tooltip_text = "Drag onto the character it should attack."
    _drop_targets.append(p)

    var width := _board_card_w()
    if is_hero:
        width = minf(width, _deck_plate_h() * CardView.BASE_WIDTH / CardView.BASE_HEIGHT)
    var face := CardView.create(d, width)
    face.mouse_filter = Control.MOUSE_FILTER_IGNORE
    face.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

    # A card on the board is small, so it carries one badge: whichever of these
    # a player most needs at a glance. The rest is in the tooltip, and resting
    # the pointer on the card brings it up at a readable size.
    var live_attack := st.current_attack(iid)
    var live_defense := st.current_defense(iid)
    if live_attack != d.attack or live_defense != d.defense:
        face.add_badge("%d/%d" % [live_attack, live_defense], UiTheme.GOLD)
    elif ci.shield_total() > 0:
        face.add_badge("-%d" % ci.shield_total(), UiTheme.DEFENSE.lightened(0.4))
    elif in_sequence:
        face.add_badge("acting", UiTheme.GOLD)
    elif committed:
        face.add_badge("spent", UiTheme.TEXT_DIM)
    elif ci.deployed_round == st.round_number and not is_hero:
        face.add_badge("new", UiTheme.TEXT_DIM)
    elif not st.attachments_of(iid).is_empty():
        face.add_badge("+%d" % st.attachments_of(iid).size(), UiTheme.GOLD_DIM)
    v.add_child(face)

    var notes: Array = ["%d Attack, %d Defense now" % [live_attack, live_defense]]
    if ci.shield_total() > 0:
        notes.append("prevents the next %d damage" % ci.shield_total())
    if committed:
        notes.append("already committed this round")
    if in_sequence:
        notes.append("in the Action Sequence")
    if ci.deployed_round == st.round_number and not is_hero:
        notes.append("deployed this round, cannot attack")
    if d.attack_cost > 0:
        notes.append("%d Energy to attack" % d.attack_cost)
    for a_iid in st.attachments_of(iid):
        var ad := st.def_of(String(a_iid))
        notes.append("%s: %s" % [UiTheme.primary_type(ad).capitalize(), ad.name])
    if not notes.is_empty():
        var hint := p.tooltip_text
        p.tooltip_text = "%s\n%s%s" % [d.name, "\n".join(notes),
            "\n" + hint if hint != "" else ""]

    # Attacking is a drag: pick the character up and drop it on what it should
    # hit. The only buttons left on the board are the ones that answer a
    # question the game asked, such as choosing a target for a card that is
    # already mid-flight.
    if _mode == "pick_attack_target" and player == 1:
        v.add_child(_target_button(iid))
    elif _mode == "pick_card_target" \
            and Targeting.legal_targets(st, _target_kind, 0, _target_filter).has(iid):
        v.add_child(_target_button(iid))
    p.claim_mouse()
    _readable(p, d)
    return p


## How tall a card is when it is drawn this wide.
func _card_h(width: float) -> float:
    return width * CardView.BASE_HEIGHT / CardView.BASE_WIDTH


func _target_button(iid: String) -> Button:
    var b := UiTheme.small_button("Choose as target")
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
        # Whose step it is is read off the panel rather than written under it:
        # the Sequence is a row of small cards and every line of text under one
        # is a line the cards themselves lose.
        var tint := UiTheme.BG_RAISED if is_current else UiTheme.BG_PANEL
        if slot.controller != 0:
            tint = tint.darkened(0.25)
        var p := UiTheme.panel(tint, border, 2 if is_current else 1, 4)
        # Nothing is written above or below the card: the row reads left to
        # right, the panel is tinted for whose step it is, and the card itself
        # prints its own Affinity. Every line here is height the card loses.
        var v := UiTheme.vbox(1)
        # A step stands for the card that was committed, or for the character
        # that is attacking. Either way it is a card, so it is drawn as one and
        # the step says only what the step is.
        var source := slot.card_iid if slot.kind == "card" else slot.attacker_iid
        var sd := st.def_of(source) if source != "" else null
        if sd != null:
            var face := CardView.create(sd, _seq_card_w())
            face.mouse_filter = Control.MOUSE_FILTER_IGNORE
            face.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
            if slot.kind == "attack":
                face.add_badge("attack", UiTheme.ATTACK.lightened(0.4))
            if slot.x_paid > 0:
                face.add_badge("X%d" % slot.x_paid, UiTheme.GOLD)
            v.add_child(face)
        else:
            v.add_child(UiTheme.wrapped(GameEngine.describe_slot(st, slot), 10,
                UiTheme.TEXT_DIM))
        var extra: Array = [GameEngine.describe_slot(st, slot)]
        if slot.affinities.is_empty():
            extra.append("No Affinity — this step breaks the chain.")
        for r in slot.reactions:
            var rd := st.def_of(String((r as Dictionary).get("iid", "")))
            var reactor := st.def_of(String((r as Dictionary).get("attacker", "")))
            var who_r := rd.name if rd != null else (
                reactor.name if reactor != null else "a character")
            extra.append("Reaction (%s): %s%s" % [
                String((r as Dictionary).get("window", "before")), who_r,
                "" if not bool((r as Dictionary).get("resolved", false)) else " ✓"])

        p.add_child(v)
        p.tooltip_text = "\n".join(extra)
        if sd != null:
            _readable(p, sd)
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
        _readable(view, d, true)
        if playable:
            view.add_badge("Eligible", UiTheme.GOOD)
            view.drag_payload = {"kind": "card", "iid": card_iid,
                "as_reaction": reaction_window, "label": d.name}
            view.tooltip_text = ("Drag %s onto its target, or into the Action Sequence "
                + "if it needs none.") % d.name
            _hand_row.add_child(view)
        else:
            view.add_badge(why if why != "" else "Not playable now", UiTheme.TEXT_DIM)
            view.tooltip_text = why
            view.modulate = Color(1, 1, 1, 0.6)
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
        _prompt.text = "Resolving the Action Sequence, one card at a time."
    else:
        _prompt.text = "%s Phase." % st.phase.capitalize()
    _prompt.tooltip_text = _prompt.text


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
        "choose_card_type":
            var sd := st.def_of(String(p.get("source", "")))
            _prompt.text = "Name a Card Type for %s." % (sd.name if sd != null else "this card")
            for card_type in EffectSchema.CARD_TYPES:
                var name := String(card_type)
                var b := UiTheme.button(UiTheme.TYPE_LABEL.get(name, name.capitalize()))
                b.pressed.connect(func():
                    var r := GameEngine.submit(st, {"cmd": "choose_card_type", "player": 0,
                        "card_type": name})
                    if not bool(r["ok"]):
                        app.toast(String(r["error"]), true)
                        return
                    _after_command())
                _controls.add_child(b)
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
    return ("Drag a card from your hand onto its target, or anywhere into the Action "
        + "Sequence if it needs none. Drag your Hero or a Companion onto the character "
        + "it should attack.")


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
    # A Location card played from hand goes here.
    if d.has_type("location") and not (d.target_spec is Dictionary):
        return true
    # So does a card that targets whatever Location is already in play.
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
        _play_dragged(card_iid, [], as_reaction)  # a Location played from hand
        return
    var legal := Targeting.legal_targets(st, "location", 0)
    if legal.is_empty():
        app.toast("There is no Location in play to target.", true)
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

## Make a small thing on the board readable: resting the pointer on it brings
## up the same card at a size meant for reading.
##
## Everything on the board stands for a card, so everything on the board can be
## read this way — a card in hand, a Hero or Companion in play, a step in the
## Action Sequence, the Location.
func _readable(control: Control, def: CardDef, above: bool = false) -> void:
    if def == null or _zoom == null:
        return
    control.mouse_entered.connect(func():
        if not _dragging and is_instance_valid(_zoom):
            _zoom.request(def, control.get_global_rect(), above))
    control.mouse_exited.connect(func():
        if is_instance_valid(_zoom):
            _zoom.dismiss())


## Where something is on screen.
##
## A card that has already left the board has no chip any more by the time the
## effect plays, so it starts from the zone it left rather than from nowhere.
func _screen_pos_of(iid: String) -> Vector2:
    if _chips.has(iid) and is_instance_valid(_chips[iid]):
        return (_chips[iid] as Control).get_global_rect().get_center()
    var owner := _owner_of(iid, -1)
    if owner == 0 and _own_companion_zone != null:
        return _own_companion_zone.get_global_rect().get_center()
    if owner == 1 and _opp_companion_zone != null:
        return _opp_companion_zone.get_global_rect().get_center()
    return get_global_rect().get_center()


func _pile_pos(player: int, kind: String) -> Vector2:
    var key := "%d_%s" % [player, kind]
    if _pile_chips.has(key) and is_instance_valid(_pile_chips[key]):
        return (_pile_chips[key] as Control).get_global_rect().get_center()
    return get_global_rect().get_center()


func _owner_of(iid: String, fallback: int) -> int:
    var ci := st.inst(iid)
    return ci.owner if ci != null else fallback


## Where a player's hand is on screen. Yours is the strip along the bottom; the
## opponent's is the row of backs beside their name, which is the only place
## their hand exists as far as this screen is concerned.
func _hand_pos(player: int) -> Vector2:
    if player == 0 and _hand_row != null and is_instance_valid(_hand_row):
        var r := _hand_row.get_global_rect()
        if r.size.x > 0.0:
            return Vector2(r.position.x + minf(r.size.x * 0.5, 240.0),
                r.position.y + r.size.y * 0.5)
    if player == 1 and _top != null and is_instance_valid(_top):
        return _top.get_global_rect().get_center()
    return get_global_rect().get_center()


## Where a zone is on screen, for a card arriving somewhere that has no chip of
## its own yet.
func _zone_pos(zone: Control) -> Vector2:
    if zone != null and is_instance_valid(zone):
        return zone.get_global_rect().get_center()
    return get_global_rect().get_center()


## Show what the engine just did. Purely cosmetic: the state is already final
## by the time any of this is drawn, and play never waits for it — but the
## opponent does, so a round's worth of movement is not skipped past before it
## has been seen.
func _play_new_events() -> void:
    if st == null or _effects == null or not is_instance_valid(_effects):
        return
    var i := _events_seen
    if i >= st.events.size():
        return
    _events_seen = st.events.size()
    var delay := 0.0
    ## Announcements queue rather than overwrite each other: a Draw Phase that
    ## runs straight into an Action Phase has to say both, in order.
    var banner_at := 0.0
    var shown := 0
    while i < st.events.size() and shown < 24:
        var e: Dictionary = st.events[i]
        i += 1
        var kind := String(e.get("kind", ""))
        match kind:
            "phase":
                if _banner != null and is_instance_valid(_banner):
                    _banner.phase(String(e.get("phase", "")), st.round_number, banner_at)
                    banner_at += PhaseBanner.length()
                    shown += 1
            "step_begin":
                # Which card is about to happen, said before it happens.
                var step_no := int(e.get("slot", 0)) + 1
                var what := String(e.get("message", ""))
                var colon := what.find(": ")
                if colon >= 0:
                    what = what.substr(colon + 2)
                if _banner != null and is_instance_valid(_banner):
                    _banner.step(step_no, st.sequence.size(), what, banner_at)
                    banner_at += PhaseBanner.length()
                    shown += 1
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
                # Out of the hand and onto the board: the card is one the
                # player has seen, so it flies face up.
                var iid3 := String(e.get("iid", ""))
                var owner3 := _owner_of(iid3, 0)
                var zone3: Control = _own_companion_zone if owner3 == 0 \
                    else _opp_companion_zone
                _effects.fly_card(_hand_pos(owner3), _zone_pos(zone3),
                    "Enters play", UiTheme.HEAL_TEXT, delay, st.def_of(iid3))
                delay += 0.3
                shown += 1
            "drew":
                # Off the top of the Hit Deck and into a hand. Face down: a
                # card is not a card anyone has seen until it is in a hand,
                # and the opponent's never is.
                var drew_p := int(e.get("player", 0))
                var drew_n: int = mini(int(e.get("count", 0)), 5)
                for k in drew_n:
                    _effects.fly_card(_pile_pos(drew_p, "hit"), _hand_pos(drew_p),
                        "" if k > 0 else "Drawn", UiTheme.GOLD,
                        delay + 0.13 * float(k))
                if drew_n > 0:
                    delay += 0.2 + 0.13 * float(drew_n)
                    shown += 1
            "milled":
                var mill_p := int(e.get("player", 0))
                var mill_n: int = mini(int(e.get("count", 0)), 5)
                for k in mill_n:
                    _effects.fly_card(_pile_pos(mill_p, "hit"),
                        _pile_pos(mill_p, "exhaust"), "" if k > 0 else "Exhausted",
                        UiTheme.TEXT_DIM, delay + 0.1 * float(k))
                if mill_n > 0:
                    delay += 0.2 + 0.1 * float(mill_n)
                    shown += 1
            "recovered":
                var rec_p := int(e.get("player", 0))
                _effects.fly_card(_pile_pos(rec_p, "exhaust"), _hand_pos(rec_p),
                    "Recovered", UiTheme.HEAL_TEXT, delay)
                delay += 0.25
                shown += 1
            "bounced":
                var iid4 := String(e.get("iid", ""))
                _effects.fly_card(_screen_pos_of(iid4), _hand_pos(_owner_of(iid4, 0)),
                    "To hand", UiTheme.GOLD, delay, st.def_of(iid4))
                delay += 0.3
                shown += 1
            "attached":
                var iid5 := String(e.get("iid", ""))
                _effects.fly_card(_hand_pos(_owner_of(iid5, 0)),
                    _screen_pos_of(String(e.get("host", ""))),
                    "Attached", UiTheme.GOLD, delay, st.def_of(iid5))
                delay += 0.3
                shown += 1
            "location_placed":
                var iid6 := String(e.get("iid", ""))
                _effects.fly_card(_hand_pos(_owner_of(iid6, 0)),
                    _zone_pos(_location_zone), "Location", UiTheme.GOLD, delay,
                    st.def_of(iid6))
                delay += 0.3
                shown += 1
            "committed", "committed_attack":
                # Into the Action Sequence. A committed card is face up, and
                # an attack is the character stepping forward.
                var iid7 := String(e.get("iid", e.get("attacker", "")))
                var from7 := _hand_pos(int(e.get("player", 0))) if kind == "committed" \
                    else _screen_pos_of(iid7)
                _effects.fly_card(from7, _zone_pos(_sequence_zone),
                    "Committed" if kind == "committed" else "Attacks",
                    UiTheme.GOLD, delay, st.def_of(iid7))
                delay += 0.28
                shown += 1
    if shown > 0:
        var run := maxf(delay + BoardEffects.fly_length(), banner_at)
        _replay_hold = minf(run, MAX_REPLAY_HOLD)


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
    _target_filter = {}
    _pending_targets = []
    _targets_prechosen = false
    _refresh()


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


## The rest of playing a card once its X cost has been settled. A card dropped
## on its target arrives here with that target already chosen; the branch below
## is for one played without a drop having picked anything, which the X prompt
## is the only remaining way to reach.
func _continue_play(d: CardDef) -> void:
    if d.target_spec is Dictionary:
        _target_kind = String((d.target_spec as Dictionary).get("kind", ""))
        _target_filter = d.target_spec
        _mode = "pick_card_target"
        _refresh()
        return
    _submit_card([])


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
    if not Targeting.is_valid(st, _target_kind, 0, iid, _target_filter):
        app.toast(Targeting.explain_invalid(st, _target_kind, 0, iid, _target_filter), true)
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
    _target_filter = {}
    _pending_targets = []
    _targets_prechosen = false
    _after_command()
