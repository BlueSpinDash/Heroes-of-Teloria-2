class_name GameEngine
extends RefCounted

## The rules engine: setup, phase progression, command legality and
## resolution. Every mutation to a match goes through submit() or advance(),
## and a match is fully playable headlessly.
##
## The shared round is Draw, Action, Resolve, Round End. Both the human and
## the AI use the same legal-command API and the same validation.


# --------------------------------------------------------------------- setup ---

## Build a fresh match. Each deck is {"hero": def_id, "cards": {def_id: qty}}.
static func start_match(catalog: Catalog, rules: RulesProfile, decks: Array,
        seed_value: int, match_id: String, names: Array = ["You", "Opponent"],
        ai_flags: Array = [false, true], profiles: Array = ["", ""]) -> GameState:
    var st := GameState.new()
    st.match_id = match_id
    st.catalog = catalog
    st.rules = rules
    st.rules_stamp = rules.stamp()
    st.rng = HotRng.new(seed_value)
    st.round_number = 1
    st.phase = "draw"

    for i in 2:
        var p := PlayerState.new(i)
        p.display_name = String(names[i])
        p.is_ai = bool(ai_flags[i])
        p.affinity_profile = String(profiles[i])
        p.deck_id = String((decks[i] as Dictionary).get("deck_id", ""))
        st.players.append(p)

    for i in 2:
        var deck: Dictionary = decks[i]
        var hero_iid := _mint(st, String(deck.get("hero", "")), i)
        var hero_ci := st.inst(hero_iid)
        hero_ci.zone = "hero"
        st.player(i).hero_iid = hero_iid
        st.stamp_entry(hero_iid)

        var pile: Array = []
        var card_ids: Array = (deck.get("cards", {}) as Dictionary).keys()
        card_ids.sort()  # stable minting order regardless of dictionary order
        for def_id in card_ids:
            var qty := int((deck["cards"] as Dictionary)[def_id])
            for _c in qty:
                var iid := _mint(st, String(def_id), i)
                st.inst(iid).zone = "hit"
                pile.append(iid)
        st.player(i).hit = st.rng.shuffled("shuffle_p%d" % i, pile)

    # First Action priority: a seeded random choice in round one, then the
    # first player alternates each later round (provisional).
    st.first_player = st.rng.randi_range_in("first_priority", 0, 1)
    st.action_priority = st.first_player

    for i in 2:
        st.player(i).energy_current = st.energy_max(i)

    st.emit("match_started", {
        "match_id": match_id, "seed": seed_value, "first_player": st.first_player,
        "message": "Match begins. P%d has first Action priority. Round 1, Draw Phase." % (st.first_player + 1)})
    advance(st)
    return st


static func _mint(st: GameState, def_id: String, owner: int) -> String:
    var def := st.catalog.get_def(def_id)
    var rev := def.revision if def != null else 1
    var iid := Ids.next_in(st.counters, "c")
    var ci := CardInstance.new(iid, def_id, rev, owner)
    st.instances[iid] = ci
    return iid


# ----------------------------------------------------------------- advancing ---

## Drive the match forward until it needs a decision or reaches a result.
static func advance(st: GameState) -> void:
    var guard := 0
    while true:
        guard += 1
        if guard > 4096:
            st.emit("engine_guard", {
                "message": "Engine guard: phase progression exceeded 4096 steps and was halted. This is an engine limit, not a game rule."})
            return
        if st.result != null:
            return
        if st.pending != null:
            return
        if not st.deferred_choices.is_empty():
            st.pending = st.deferred_choices.pop_front()
            _announce_pending(st)
            if _auto_resolve_pending(st):
                continue
            return
        match st.phase:
            "draw":
                _do_draw_phase(st)
            "action":
                if _action_phase_complete(st):
                    _begin_resolve(st)
                else:
                    _set_action_priority(st)
                    return  # waiting for the player on priority
            "resolve":
                var step_before := st.current_step
                if not _resolve_tick(st):
                    return  # a Reaction window is open
                # One card at a time, when someone is watching. The step has
                # already happened and everything it did is in the event log;
                # this only hands control back so the interface can show it
                # before the next one starts.
                if st.watch_resolve and st.current_step > step_before \
                        and st.phase == "resolve":
                    return
            "round_end":
                _do_round_end(st)
            "ended":
                return
            _:
                return


static func _announce_pending(st: GameState) -> void:
    var p: Dictionary = st.pending
    match String(p.get("kind", "")):
        "choose_cards":
            var purpose := String(p.get("purpose", ""))
            var what := "Exhaust"
            if purpose == "recover":
                what = "return to hand"
            elif purpose == "equip":
                what = "attach to %s" % _label(st, String(p.get("host", "")))
            st.emit("choice_required", {
                "player": p.get("player"),
                "message": "P%d must choose up to %d card(s) to %s." % [
                    int(p.get("player", 0)) + 1, int(p.get("count", 0)), what]})
        "choose_deploy":
            st.emit("choice_required", {
                "player": p.get("player"),
                "message": "P%d may put a Companion from hand into play." % (int(p.get("player", 0)) + 1)})
        "choose_card_type":
            var sd := st.def_of(String(p.get("source", "")))
            st.emit("choice_required", {
                "player": p.get("player"),
                "message": "P%d must name a Card Type for %s." % [
                    int(p.get("player", 0)) + 1, sd.name if sd != null else "a card"]})
        "reaction_window":
            st.emit("reaction_window", {
                "player": p.get("player"), "slot": p.get("slot"),
                "message": "Reaction window for step %d: P%d may respond." % [
                    int(p.get("slot", 0)) + 1, int(p.get("player", 0)) + 1]})


## Close out a pending choice that has no legal answer, so the game never
## hangs waiting on a decision that cannot be made.
static func _auto_resolve_pending(st: GameState) -> bool:
    var p: Dictionary = st.pending
    match String(p.get("kind", "")):
        "choose_cards":
            var pool := _choice_pool(st, p)
            if pool.is_empty() or int(p.get("count", 0)) <= 0:
                st.pending = null
                return true
            if not bool(p.get("optional", false)) and pool.size() <= int(p.get("count", 0)):
                # Forced and fully determined: resolve it without a prompt.
                _apply_card_choice(st, p, pool)
                st.pending = null
                return true
        "choose_deploy":
            if _deployable_from_hand(st, int(p.get("player", 0))).is_empty():
                st.pending = null
                return true
        "choose_card_type":
            # The card that would remember the answer is gone, so there is
            # nothing to decide.
            if st.inst(String(p.get("source", ""))) == null:
                st.pending = null
                return true
        "reaction_window":
            var player := int(p.get("player", 0))
            if legal_reactions(st, player).is_empty():
                st.pending = null
                _register_reaction_pass(st, player, true)
                return true
    return false


# ----------------------------------------------------------------- draw phase ---

## Each player draws until holding five cards. A player already holding five
## or more draws nothing and does not discard down to five. Both required
## draws are evaluated before a winner is awarded.
static func _do_draw_phase(st: GameState) -> void:
    st.phase = "draw"
    st.emit("phase", {"phase": "draw", "message": "Round %d — Draw Phase." % st.round_number})
    var order := [st.first_player, st.opponent_of(st.first_player)]
    for pi in order:
        var need: int = st.rules.draw_to - st.player(pi).hand.size()
        if need <= 0:
            st.emit("draw_skipped", {
                "player": pi,
                "message": "P%d already holds %d cards and draws nothing." % [pi + 1, st.player(pi).hand.size()]})
            continue
        if not Mechanics.required_draw(st, pi, need):
            Mechanics.mark_failure(st, pi, "A required Draw Phase draw could not be completed from Hit plus Exhaust.")
        EffectRunner.process_trigger_queue(st, 1)
    if Mechanics.settle_failures(st):
        return
    _check_hand_overflow(st)
    st.phase = "action"
    st.action_priority = st.first_player
    for p in st.players:
        (p as PlayerState).passed_actions = false
    st.emit("phase", {
        "phase": "action",
        "message": "Round %d — Action Phase. P%d acts first." % [st.round_number, st.first_player + 1]})


## The intended maximum hand size is seven. The full required draw completes
## first, including loss checks, then the affected player chooses cards to
## Exhaust until at seven (provisional).
static func _check_hand_overflow(st: GameState) -> void:
    for pi in [st.first_player, st.opponent_of(st.first_player)]:
        var over: int = st.player(pi).hand.size() - st.rules.max_hand_size
        if over > 0:
            st.deferred_choices.append({
                "kind": "choose_cards", "purpose": "overflow", "from": "hand",
                "owner": pi, "player": pi, "count": over, "optional": false})


# --------------------------------------------------------------- action phase ---

static func _action_phase_complete(st: GameState) -> bool:
    return st.player(0).passed_actions and st.player(1).passed_actions


static func _set_action_priority(st: GameState) -> void:
    if st.player(st.action_priority).passed_actions:
        st.action_priority = st.opponent_of(st.action_priority)


static func _begin_resolve(st: GameState) -> void:
    st.phase = "resolve"
    st.current_step = 0
    st.emit("phase", {
        "phase": "resolve",
        "message": "Round %d — Resolve Phase. %d Action%s in the Sequence." % [
            st.round_number, st.sequence.size(), "" if st.sequence.size() == 1 else "s"]})


# -------------------------------------------------------------- resolve phase ---

## One tick of the Resolve Phase. Returns false when a Reaction window is
## waiting on a player.
static func _resolve_tick(st: GameState) -> bool:
    if st.current_step >= st.sequence.size():
        st.phase = "round_end"
        return true
    var slot: ActionSlot = st.sequence[st.current_step]
    if not slot.window_done:
        _open_or_continue_reaction_window(st)
        return st.pending == null
    _resolve_step(st, slot)
    st.current_step += 1
    return true


## The Reaction window before a step. The opponent of the step's controller
## gets the first opportunity; opportunities alternate; two consecutive passes
## close the window and committing a Reaction resets the pass count.
static func _open_or_continue_reaction_window(st: GameState) -> void:
    var slot: ActionSlot = st.sequence[st.current_step]
    if st.reaction_window == null:
        var first := st.opponent_of(slot.controller)
        st.reaction_window = {"slot": st.current_step, "player": first, "passes": 0}
        st.emit("step_begin", {
            "slot": st.current_step,
            "message": "Step %d of %d: %s" % [st.current_step + 1, st.sequence.size(), describe_slot(st, slot)]})
    var window: Dictionary = st.reaction_window
    st.pending = {
        "kind": "reaction_window", "slot": int(window["slot"]),
        "player": int(window["player"]), "passes": int(window["passes"]),
    }
    _announce_pending(st)
    if _auto_resolve_pending(st):
        st.pending = null
        # _register_reaction_pass already advanced the window; loop again.
        if st.reaction_window != null or not slot.window_done:
            _open_or_continue_reaction_window(st)


static func _register_reaction_pass(st: GameState, player: int, automatic: bool) -> void:
    if st.reaction_window == null:
        return
    var window: Dictionary = st.reaction_window
    window["passes"] = int(window["passes"]) + 1
    st.emit("reaction_pass", {
        "player": player, "automatic": automatic,
        "message": "P%d %s a Reaction." % [player + 1, "has no legal Reaction and passes" if automatic else "passes"]})
    var slot: ActionSlot = st.sequence[int(window["slot"])]
    if int(window["passes"]) >= st.rules.reaction_passes_to_close:
        slot.window_done = true
        st.reaction_window = null
        st.emit("reaction_window_closed", {
            "slot": slot.slot_id,
            "message": "Reaction window closes with %d Reaction(s) committed." % slot.reactions.size()})
    else:
        window["player"] = st.opponent_of(player)


## Resolve one step: before-Action Reactions in commitment order, the Action,
## then after-Action Reactions in commitment order.
static func _resolve_step(st: GameState, slot: ActionSlot) -> void:
    for r in slot.reactions_for("before"):
        _resolve_reaction(st, slot, r)
        if st.result != null:
            return
    if slot.kind == "attack":
        _resolve_attack(st, slot)
    else:
        _resolve_card_action(st, slot)
    if st.result != null:
        return
    for r in slot.reactions_for("after"):
        _resolve_reaction(st, slot, r)
        if st.result != null:
            return
    slot.resolved = true
    # A character's Sequence membership ends only after its own resolution
    # triggers have finished.
    if slot.kind == "attack" and slot.attacker_iid != "":
        st.sequence_members.erase(slot.attacker_iid)
        st.emit("left_sequence", {
            "iid": slot.attacker_iid,
            "message": "%s leaves the Action Sequence." % _label(st, slot.attacker_iid)})
    _expire_step_effects(st)
    Mechanics.settle_failures(st)


static func _expire_step_effects(st: GameState) -> void:
    for iid in st.instances.keys():
        (st.instances[iid] as CardInstance).expire("step")


static func _resolve_card_action(st: GameState, slot: ActionSlot) -> void:
    var iid := slot.card_iid
    var cd := st.def_of(iid)
    if cd == null:
        return
    st.emit("resolving", {
        "slot": slot.slot_id, "iid": iid,
        "message": "Resolving %s (P%d)." % [cd.name, slot.controller + 1]})

    var kind := ""
    if cd.target_spec is Dictionary:
        kind = String((cd.target_spec as Dictionary).get("kind", ""))
    var target_filter: Dictionary = cd.target_spec if cd.target_spec is Dictionary else {}
    var ctx := EffectRunner.make_ctx(iid, slot.controller, st.current_step,
        slot.targets, slot.x_paid, {"target_kind": kind, "target_filter": target_filter})

    # Persistent cards enter play as the step resolves.
    if cd.has_type("companion"):
        Mechanics.deploy_companion(st, iid, slot.controller)
        EffectRunner.process_trigger_queue(st, 1)
    elif cd.is_attachment():
        var hosts := Targeting.legal_targets(st, "own_character_host", slot.controller,
            target_filter)
        var host := ""
        for t in slot.targets:
            if hosts.has(String(t)):
                host = String(t)
                break
        if host == "":
            st.emit("attach_failed", {
                "iid": iid,
                "message": "%s has no legal host at resolution and goes to P%d's Exhaust Deck." % [cd.name, st.inst(iid).owner + 1]})
            Mechanics.exhaust_resolved(st, iid)
            _emit_card_resolved(st, slot)
            return
        Mechanics.attach_card(st, iid, host)
        EffectRunner.process_trigger_queue(st, 1)
    elif cd.has_type("location"):
        Mechanics.place_location(st, iid)
        EffectRunner.process_trigger_queue(st, 1)

    # One-shot effects (auras are skipped by the interpreter).
    EffectRunner.run_with_triggers(st, cd.effects, ctx)

    # Destination: persistent cards stay in play, everything else Exhausts.
    if not cd.is_persistent():
        Mechanics.exhaust_resolved(st, iid)
    _emit_card_resolved(st, slot)


static func _emit_card_resolved(st: GameState, slot: ActionSlot) -> void:
    var rd := st.def_of(slot.card_iid) if slot.card_iid != "" else null
    st.trigger_events.append({
        "kind": "card_resolved", "iid": slot.card_iid, "controller": slot.controller,
        "affinities": slot.affinities.duplicate(), "slot": st.current_step,
        "types": rd.types.duplicate() if rd != null else [],
        "attacker": slot.attacker_iid,
        "target": String(slot.targets[0]) if not slot.targets.is_empty() else "",
    })
    EffectRunner.process_trigger_queue(st, 1)


## Attack damage is max(0, current Attack − current Defense), using the
## modifiers active at resolution.
static func _resolve_attack(st: GameState, slot: ActionSlot) -> void:
    var attacker := slot.attacker_iid
    var aci := st.inst(attacker)
    var acd := st.def_of(attacker)
    if aci == null or acd == null or not ["hero", "companions"].has(aci.zone):
        st.emit("attack_fizzled", {
            "slot": slot.slot_id,
            "message": "The attacking character is no longer in play; the step finishes with no attack."})
        _emit_card_resolved(st, slot)
        return
    var target := String(slot.targets[0]) if not slot.targets.is_empty() else ""
    var legal := Targeting.legal_attack_targets(st, slot.controller)
    st.emit("resolving", {
        "slot": slot.slot_id,
        "message": "Resolving attack: %s (%d/%d) → %s." % [
            acd.name, st.current_attack(attacker), st.current_defense(attacker),
            _label(st, target) if target != "" else "no target"]})

    if target == "" or not legal.has(target):
        # No automatic retarget, no Energy refund, no restored allowance.
        st.emit("attack_no_target", {
            "slot": slot.slot_id,
            "message": "The declared target is no longer valid. The attack affects no target but still resolves."})
    else:
        _strike(st, attacker, target, slot.controller)

    st.trigger_events.append({
        "kind": "attack_resolved", "attacker": attacker, "controller": slot.controller, "target": target})
    EffectRunner.process_trigger_queue(st, 1)
    _emit_card_resolved(st, slot)


## A Companion let into the Sequence out of turn, striking as its Reaction.
static func _resolve_reaction_attack(st: GameState, r: Dictionary) -> void:
    var attacker := String(r.get("attacker", ""))
    var controller := int(r.get("controller", 0))
    var aci := st.inst(attacker)
    var acd := st.def_of(attacker)
    if aci == null or acd == null or not ["hero", "companions"].has(aci.zone):
        st.emit("attack_fizzled", {
            "message": "The reacting character is no longer in play; nothing happens."})
        return
    var target := String(r.get("targets", [])[0]) if not (r.get("targets", []) as Array).is_empty() else ""
    st.emit("resolving_reaction", {
        "iid": attacker, "window": r.get("window", "before"),
        "message": "Reaction resolves: %s (%d/%d) attacks %s." % [
            acd.name, st.current_attack(attacker), st.current_defense(attacker),
            _label(st, target) if target != "" else "no target"]})
    if target == "" or not Targeting.legal_attack_targets(st, controller).has(target):
        st.emit("attack_no_target", {
            "message": "The declared target is no longer valid. The Reaction attack affects no target."})
    else:
        _strike(st, attacker, target, controller)
    st.trigger_events.append({
        "kind": "attack_resolved", "attacker": attacker, "controller": controller,
        "target": target})
    EffectRunner.process_trigger_queue(st, 1)


## One character hitting another, wherever the attack came from.
static func _strike(st: GameState, attacker: String, target: String, controller: int) -> void:
    var acd := st.def_of(attacker)
    if acd == null:
        return
    var dmg: int = max(0, st.current_attack(attacker) - st.current_defense(target))
    # A card may have left a bonus for the next attack that qualifies. It is
    # added to the damage dealt, after Defense, and is claimed once.
    dmg += _claim_attack_bonus(st, attacker, controller)
    Mechanics.attack_damage(st, attacker, target, dmg, acd.name)
    EffectRunner.process_trigger_queue(st, 1)


## Take the first waiting bonus this attack qualifies for, if there is one.
##
## The bonus is spent whether or not the attack goes on to land: it was left
## for the next attack to resolve, and this is that attack.
static func _claim_attack_bonus(st: GameState, attacker: String, controller: int) -> int:
    if st.pending_attack_bonuses.is_empty():
        return 0
    var ad := st.def_of(attacker)
    if ad == null:
        return 0
    for i in st.pending_attack_bonuses.size():
        var bonus: Dictionary = st.pending_attack_bonuses[i]
        var want := String(bonus.get("affinity", ""))
        if want != "" and not ad.affinities.has(want):
            continue
        if not EffectRunner._scope_ok(st, String(bonus.get("scope", "either")),
                int(bonus.get("controller", 0)), controller):
            continue
        st.pending_attack_bonuses.remove_at(i)
        var amount := int(bonus.get("amount", 0))
        st.emit("attack_bonus_claimed", {
            "attacker": attacker, "amount": amount,
            "message": "%s takes the waiting bonus and deals %d more damage." % [ad.name, amount]})
        return amount
    return 0


static func _resolve_reaction(st: GameState, slot: ActionSlot, r: Dictionary) -> void:
    if bool(r.get("resolved", false)):
        return
    r["resolved"] = true
    if String(r.get("attacker", "")) != "":
        _resolve_reaction_attack(st, r)
        return
    var iid := String(r.get("iid", ""))
    var cd := st.def_of(iid)
    if cd == null:
        return
    var controller := int(r.get("controller", 0))
    var kind := ""
    if cd.target_spec is Dictionary:
        kind = String((cd.target_spec as Dictionary).get("kind", ""))
    st.emit("resolving_reaction", {
        "iid": iid, "window": r.get("window", "before"),
        "message": "Reaction resolves (%s the Action): %s (P%d)." % [
            String(r.get("window", "before")), cd.name, controller + 1]})
    var ctx := EffectRunner.make_ctx(iid, controller, st.current_step,
        r.get("targets", []), int(r.get("x_paid", 0)), {
            "target_kind": kind,
            "target_filter": cd.target_spec if cd.target_spec is Dictionary else {},
            "current_attacker": slot.attacker_iid,
            "current_target": String(slot.targets[0]) if not slot.targets.is_empty() else "",
        })
    EffectRunner.run_with_triggers(st, cd.effects, ctx)
    if not cd.is_persistent():
        Mechanics.exhaust_resolved(st, iid)
    # A Reaction can still trigger "whenever a card resolves" effects even
    # though it never joins the Affinity chain.
    st.trigger_events.append({
        "kind": "card_resolved", "iid": iid, "controller": controller,
        "affinities": cd.affinities.duplicate(), "types": cd.types.duplicate(),
        "slot": st.current_step, "reaction": true})
    EffectRunner.process_trigger_queue(st, 1)


# ------------------------------------------------------------------ round end ---

static func _do_round_end(st: GameState) -> void:
    st.emit("phase", {"phase": "round_end", "message": "Round %d — Round End." % st.round_number})
    st.trigger_events.append({"kind": "round_end"})
    EffectRunner.process_trigger_queue(st, 1)
    if Mechanics.settle_failures(st):
        return

    # Expire round-limited effects and reset round tracking. A bonus left for
    # the next attack lapses with them: it was for this round's Sequence.
    if not st.pending_attack_bonuses.is_empty():
        st.emit("attack_bonus_lapsed", {
            "count": st.pending_attack_bonuses.size(),
            "message": "%d waiting attack bonus(es) lapse unclaimed at Round End."
                % st.pending_attack_bonuses.size()})
        st.pending_attack_bonuses.clear()
    for iid in st.instances.keys():
        var ci: CardInstance = st.instances[iid]
        ci.expire("round")
        ci.expire("step")
    for p in st.players:
        var ps: PlayerState = p
        ps.expire("round")
        ps.passed_actions = false
        ps.committed_characters = []

    st.round_history.append({
        "round": st.round_number,
        "slots": st.sequence.map(func(s): return (s as ActionSlot).to_dict()),
    })
    st.sequence = []
    st.sequence_members = []
    st.current_step = -1
    st.reaction_window = null

    # Refresh current Energy to the current maximum.
    for i in 2:
        st.player(i).energy_current = st.energy_max(i)
        st.emit("energy_refreshed", {
            "player": i, "energy": st.player(i).energy_current,
            "message": "P%d Energy refreshes to %d." % [i + 1, st.player(i).energy_current]})

    st.round_number += 1
    # The first player alternates each later round (provisional).
    st.first_player = st.opponent_of(st.first_player)
    st.action_priority = st.first_player
    st.phase = "draw"


# ------------------------------------------------------------ legal commands ---

## Every legal command for a player right now. The AI picks from exactly this
## list, and the UI enables exactly these controls.
static func legal_commands(st: GameState, player: int) -> Array:
    var out: Array = []
    if st.result != null:
        return out
    if st.pending is Dictionary:
        var p: Dictionary = st.pending
        if int(p.get("player", -1)) != player:
            return out
        match String(p.get("kind", "")):
            "reaction_window":
                for cmd in legal_reactions(st, player):
                    out.append(cmd)
                out.append({"cmd": "pass_reaction", "player": player})
            "choose_cards":
                out.append({"cmd": "choose_cards", "player": player,
                    "pool": _choice_pool(st, p), "count": int(p.get("count", 0)),
                    "optional": bool(p.get("optional", false))})
            "choose_deploy":
                out.append({"cmd": "choose_deploy", "player": player,
                    "pool": _deployable_from_hand(st, player), "optional": bool(p.get("optional", false))})
            "choose_card_type":
                out.append({"cmd": "choose_card_type", "player": player,
                    "pool": EffectSchema.CARD_TYPES.duplicate(),
                    "source": String(p.get("source", ""))})
        return out
    if st.phase != "action":
        return out
    if st.action_priority != player or st.player(player).passed_actions:
        return out

    for iid in st.player(player).hand:
        var cd := st.def_of(String(iid))
        if cd == null or not cd.allows_action_timing():
            continue
        out.append_array(_card_commands(st, player, String(iid), cd, "commit_card"))

    for iid in _attack_candidates(st, player):
        var acd := st.def_of(String(iid))
        var cost := acd.attack_cost
        if st.player(player).energy_current < cost:
            continue
        for t in Targeting.legal_attack_targets(st, player):
            out.append({"cmd": "commit_attack", "player": player,
                "attacker_iid": String(iid), "target_iid": String(t), "cost": cost})

    out.append({"cmd": "pass_actions", "player": player})
    return out


static func legal_reactions(st: GameState, player: int) -> Array:
    var out: Array = []
    if not (st.pending is Dictionary) or String((st.pending as Dictionary).get("kind", "")) != "reaction_window":
        return out
    for iid in st.player(player).hand:
        var cd := st.def_of(String(iid))
        if cd == null or not cd.allows_reaction_timing():
            continue
        out.append_array(_card_commands(st, player, String(iid), cd, "play_reaction"))
    for attacker in reaction_attackers(st, player):
        var acd := st.def_of(String(attacker))
        if acd == null or st.player(player).energy_current < acd.attack_cost:
            continue
        for t in Targeting.legal_attack_targets(st, player):
            out.append({"cmd": "commit_attack_reaction", "player": player,
                "attacker_iid": String(attacker), "target_iid": String(t)})
    return out


## Companions a card in play is letting into the Action Sequence out of turn.
##
## Nothing may do this by itself: a character enters the Sequence in the Action
## Phase. A card that grants it says which of its controller's Companions may,
## and the granting card's own conditions have to hold at the moment of asking.
static func reaction_attackers(st: GameState, player: int) -> Array:
    var grants: Array = []
    for src_iid in st.grant_sources():
        var src := st.inst(String(src_iid))
        var cd := st.def_of(String(src_iid))
        if src == null or cd == null:
            continue
        for e in cd.effects:
            if not (e is Dictionary) or String(e.get("op", "")) != "grant_reaction_attack":
                continue
            var grantee := src.controller if String(e.get("who", "self")) == "self" \
                else st.opponent_of(src.controller)
            if grantee != player:
                continue
            if e.has("cond") and not st.grant_condition(String(src_iid), e["cond"]):
                continue
            grants.append({"affinity": String(e.get("affinity", "")), "source": String(src_iid)})
    if grants.is_empty():
        return []
    var out: Array = []
    for iid in _attack_candidates(st, player):
        var ci := st.inst(String(iid))
        if ci == null or ci.zone != "companions":
            continue
        var cd2 := st.def_of(String(iid))
        if cd2 == null:
            continue
        for g in grants:
            # "other Companions": the character wearing the card that grants
            # this is not let in by its own Equipment.
            var host := st.inst(String((g as Dictionary)["source"]))
            if host != null and host.attached_to == String(iid):
                continue
            var want := String((g as Dictionary)["affinity"])
            if want != "" and not cd2.affinities.has(want):
                continue
            out.append(String(iid))
            break
    return out


## Enumerate the concrete commitments for one card: every legal target and,
## for an X cost, every affordable amount.
static func _card_commands(st: GameState, player: int, iid: String, cd: CardDef, cmd_name: String) -> Array:
    var out: Array = []
    var energy := st.player(player).energy_current
    var costs: Array = []
    match cd.cost_kind():
        "none":
            costs = [0]
        "fixed":
            if energy >= cd.fixed_cost():
                costs = [cd.fixed_cost()]
        "x":
            var x := cd.x_min()
            while x <= energy:
                costs.append(x)
                x += 1
    if costs.is_empty():
        return out
    var target_kind := ""
    if cd.target_spec is Dictionary:
        target_kind = String((cd.target_spec as Dictionary).get("kind", ""))
    var target_options: Array = [[]]
    if target_kind != "":
        var legal := Targeting.legal_targets(st, target_kind, player, cd.target_spec)
        var optional := bool((cd.target_spec as Dictionary).get("optional", false))
        target_options = []
        for t in legal:
            target_options.append([String(t)])
        if optional:
            target_options.append([])
        if target_options.is_empty():
            return out  # a required target with no legal choice cannot be committed
    for c in costs:
        for opts in target_options:
            var cmd := {"cmd": cmd_name, "player": player, "card_iid": iid,
                "targets": (opts as Array).duplicate(), "cost": int(c)}
            if cd.cost_kind() == "x":
                cmd["x"] = int(c)
            out.append(cmd)
    return out


## Characters eligible to commit an attack: one Sequence appearance each per
## round, and a Companion deployed this round cannot attack this round.
static func _attack_candidates(st: GameState, player: int) -> Array:
    var out: Array = []
    var p := st.player(player)
    if not p.committed_characters.has(p.hero_iid):
        out.append(p.hero_iid)
    for iid in p.companions:
        var ci := st.inst(String(iid))
        if ci == null:
            continue
        if p.committed_characters.has(String(iid)):
            continue
        if ci.deployed_round == st.round_number:
            continue
        out.append(String(iid))
    return out


static func _choice_pool(st: GameState, p: Dictionary) -> Array:
    var owner := int(p.get("owner", p.get("player", 0)))
    var from := String(p.get("from", "hand"))
    if from == "hand":
        return st.player(owner).hand.duplicate()
    if from == "exhaust":
        # Most recently Exhausted cards appear first for convenience.
        var arr := st.player(owner).exhaust.duplicate()
        arr.reverse()
        return arr
    if from == "decks":
        # A search: one or more of the player's own decks, narrowed to the
        # kind of card the searching effect named. The Hit Deck is face down,
        # so a search reveals only what the searcher is entitled to see.
        var want := String(p.get("tag", ""))
        var found: Array = []
        for zone in p.get("zones", []):
            for iid in st.player(owner).pile(String(zone)):
                var cd := st.def_of(String(iid))
                if cd != null and (want == "" or cd.tags.has(want)):
                    found.append(String(iid))
        return found
    return []


static func _deployable_from_hand(st: GameState, player: int) -> Array:
    var out: Array = []
    for iid in st.player(player).hand:
        var cd := st.def_of(String(iid))
        if cd != null and cd.has_type("companion"):
            out.append(String(iid))
    return out


# ------------------------------------------------------------------- commands ---

## Validate and apply one command. Nothing is paid or moved when a command is
## rejected. Returns {"ok": bool, "error": String}.
static func submit(st: GameState, cmd: Dictionary) -> Dictionary:
    var name := String(cmd.get("cmd", ""))
    var player := int(cmd.get("player", -1))
    if st.result != null:
        return _err("The match has already ended.")
    if player < 0 or player > 1:
        return _err("Unknown player.")

    match name:
        "concede":
            Mechanics.concede(st, player)
            return {"ok": true, "error": ""}
        "pass_actions":
            return _do_pass_actions(st, player)
        "commit_card":
            return _do_commit_card(st, player, cmd)
        "commit_attack":
            return _do_commit_attack(st, player, cmd)
        "commit_attack_reaction":
            return _do_commit_attack_reaction(st, player, cmd)
        "play_reaction":
            return _do_play_reaction(st, player, cmd)
        "pass_reaction":
            return _do_pass_reaction(st, player)
        "choose_cards":
            return _do_choose_cards(st, player, cmd)
        "choose_deploy":
            return _do_choose_deploy(st, player, cmd)
        "choose_card_type":
            return _do_choose_card_type(st, player, cmd)
    return _err("Unknown command '%s'." % name)


static func _err(msg: String) -> Dictionary:
    return {"ok": false, "error": msg}


static func _require_action_turn(st: GameState, player: int) -> String:
    if st.pending != null:
        return "A choice is pending; that must be answered first."
    if st.phase != "action":
        return "Actions can only be committed during the Action Phase."
    if st.player(player).passed_actions:
        return "You passed this round, so you cannot commit further Actions."
    if st.action_priority != player:
        return "It is not your turn to commit an Action."
    return ""


static func _do_pass_actions(st: GameState, player: int) -> Dictionary:
    var why := _require_action_turn(st, player)
    if why != "":
        return _err(why)
    st.player(player).passed_actions = true
    st.emit("passed", {
        "player": player,
        "message": "P%d passes for the round. Reactions are still available during resolution." % (player + 1)})
    if not st.player(st.opponent_of(player)).passed_actions:
        st.action_priority = st.opponent_of(player)
    advance(st)
    return {"ok": true, "error": ""}


static func _do_commit_card(st: GameState, player: int, cmd: Dictionary) -> Dictionary:
    var why := _require_action_turn(st, player)
    if why != "":
        return _err(why)
    var iid := String(cmd.get("card_iid", ""))
    var check := _validate_card_commit(st, player, iid, cmd, false)
    if check != "":
        return _err(check)
    var cd := st.def_of(iid)
    var pay := _cost_to_pay(cd, cmd)
    if not Mechanics.pay_energy(st, player, pay):
        return _err("Not enough Energy.")

    var slot := ActionSlot.new(Ids.next_in(st.counters, "s"), player)
    slot.kind = "card"
    slot.card_iid = iid
    slot.targets = (cmd.get("targets", []) as Array).duplicate()
    slot.x_paid = int(cmd.get("x", 0)) if cd.cost_kind() == "x" else 0
    slot.energy_paid = pay
    slot.affinities = cd.affinities.duplicate()
    st.move_to_sequence(iid)
    st.sequence.append(slot)
    st.emit("committed", {
        "slot": slot.slot_id, "player": player, "iid": iid, "paid": pay, "x": slot.x_paid,
        "message": "P%d commits %s to the Action Sequence (position %d)%s." % [
            player + 1, cd.name, st.sequence.size(),
            " with X = %d" % slot.x_paid if cd.cost_kind() == "x" else ""]})
    _after_commit(st, player)
    return {"ok": true, "error": ""}


static func _cost_to_pay(cd: CardDef, cmd: Dictionary) -> int:
    match cd.cost_kind():
        "fixed": return cd.fixed_cost()
        "x": return int(cmd.get("x", cd.x_min()))
    return 0


static func _validate_card_commit(st: GameState, player: int, iid: String, cmd: Dictionary, as_reaction: bool) -> String:
    var ci := st.inst(iid)
    if ci == null:
        return "That card is not in the match."
    if ci.zone != "hand" or ci.owner != player:
        return "That card is not in your hand."
    var cd := st.def_of(iid)
    if cd == null:
        return "That card has no definition."
    if as_reaction and not cd.allows_reaction_timing():
        return "%s cannot be played as a Reaction." % cd.name
    if not as_reaction and not cd.allows_action_timing():
        return "%s can only be played as a Reaction." % cd.name
    var pay := _cost_to_pay(cd, cmd)
    if cd.cost_kind() == "x" and pay < cd.x_min():
        return "X must be at least %d." % cd.x_min()
    if st.player(player).energy_current < pay:
        return "Not enough Energy: %s costs %d and you have %d." % [cd.name, pay, st.player(player).energy_current]
    if cd.target_spec is Dictionary:
        var spec: Dictionary = cd.target_spec
        var kind := String(spec.get("kind", ""))
        var want := int(spec.get("count", 1))
        var optional := bool(spec.get("optional", false))
        var targets: Array = cmd.get("targets", [])
        var legal := Targeting.legal_targets(st, kind, player, spec)
        if targets.size() < want:
            if not optional:
                if legal.is_empty():
                    return "%s needs a target and there is none available." % cd.name
                return "%s needs %d target(s)." % [cd.name, want]
        for t in targets:
            if not legal.has(String(t)):
                return Targeting.explain_invalid(st, kind, player, String(t), spec)
    return ""


static func _after_commit(st: GameState, player: int) -> void:
    # Players alternate committing one Action at a time.
    if not st.player(st.opponent_of(player)).passed_actions:
        st.action_priority = st.opponent_of(player)
    advance(st)


static func _do_commit_attack(st: GameState, player: int, cmd: Dictionary) -> Dictionary:
    var why := _require_action_turn(st, player)
    if why != "":
        return _err(why)
    var attacker := String(cmd.get("attacker_iid", ""))
    var target := String(cmd.get("target_iid", ""))
    if not _attack_candidates(st, player).has(attacker):
        var aci := st.inst(attacker)
        if aci == null:
            return _err("That character is not in the match.")
        if st.player(player).committed_characters.has(attacker):
            return _err("%s already appeared in the Action Sequence this round." % _label(st, attacker))
        if aci.deployed_round == st.round_number:
            return _err("%s was deployed this round and cannot attack this round." % _label(st, attacker))
        return _err("%s cannot attack right now." % _label(st, attacker))
    if not Targeting.legal_attack_targets(st, player).has(target):
        return _err("Attacks may only target the opposing Hero or an opposing Companion.")
    var acd := st.def_of(attacker)
    if not Mechanics.pay_energy(st, player, acd.attack_cost):
        return _err("Not enough Energy: attacking with %s costs %d." % [acd.name, acd.attack_cost])

    var slot := ActionSlot.new(Ids.next_in(st.counters, "s"), player)
    slot.kind = "attack"
    slot.attacker_iid = attacker
    slot.targets = [target]
    slot.energy_paid = acd.attack_cost
    # An attack uses its character's Affinities captured on commitment.
    slot.affinities = st.affinities_of_character(attacker)
    st.sequence.append(slot)
    # The limit is one Sequence appearance per character per round; an Energy
    # refund never clears this.
    st.player(player).committed_characters.append(attacker)
    if not st.sequence_members.has(attacker):
        st.sequence_members.append(attacker)
    st.emit("committed_attack", {
        "slot": slot.slot_id, "player": player, "attacker": attacker, "target": target,
        "paid": acd.attack_cost,
        "message": "P%d commits an attack: %s → %s (position %d, %d Energy)." % [
            player + 1, acd.name, _label(st, target), st.sequence.size(), acd.attack_cost]})
    _after_commit(st, player)
    return {"ok": true, "error": ""}


## A Companion entering the Action Sequence during a Reaction window, because
## a card in play lets it. It attaches to the step being reacted to rather than
## taking a step of its own, and it spends its one appearance for the round.
static func _do_commit_attack_reaction(st: GameState, player: int, cmd: Dictionary) -> Dictionary:
    if not (st.pending is Dictionary) or String((st.pending as Dictionary).get("kind", "")) != "reaction_window":
        return _err("There is no open Reaction window.")
    if int((st.pending as Dictionary).get("player", -1)) != player:
        return _err("It is not your Reaction opportunity.")
    var attacker := String(cmd.get("attacker_iid", ""))
    if not reaction_attackers(st, player).has(attacker):
        return _err("Nothing in play is letting %s into the Action Sequence right now."
            % _label(st, attacker))
    var target := String(cmd.get("target_iid", ""))
    if not Targeting.legal_attack_targets(st, player).has(target):
        return _err("Attacks may only target the opposing Hero or an opposing Companion.")
    var acd := st.def_of(attacker)
    if not Mechanics.pay_energy(st, player, acd.attack_cost):
        return _err("Not enough Energy: attacking with %s costs %d." % [acd.name, acd.attack_cost])

    var slot: ActionSlot = st.sequence[st.current_step]
    slot.reactions.append({
        "attacker": attacker, "controller": player, "window": "before",
        "targets": [target], "x_paid": 0, "energy_paid": acd.attack_cost, "resolved": false,
    })
    st.player(player).committed_characters.append(attacker)
    if not st.sequence_members.has(attacker):
        st.sequence_members.append(attacker)
    st.emit("reaction_committed", {
        "iid": attacker, "player": player, "window": "before",
        "message": "P%d sends %s into the Action Sequence as a Reaction: → %s." % [
            player + 1, acd.name, _label(st, target)]})
    if st.reaction_window != null:
        (st.reaction_window as Dictionary)["passes"] = 0
        (st.reaction_window as Dictionary)["player"] = st.opponent_of(player)
    st.pending = null
    advance(st)
    return {"ok": true, "error": ""}


static func _do_play_reaction(st: GameState, player: int, cmd: Dictionary) -> Dictionary:
    if not (st.pending is Dictionary) or String((st.pending as Dictionary).get("kind", "")) != "reaction_window":
        return _err("There is no open Reaction window.")
    if int((st.pending as Dictionary).get("player", -1)) != player:
        return _err("It is not your Reaction opportunity.")
    var iid := String(cmd.get("card_iid", ""))
    var check := _validate_card_commit(st, player, iid, cmd, true)
    if check != "":
        return _err(check)
    var cd := st.def_of(iid)
    var pay := _cost_to_pay(cd, cmd)
    if not Mechanics.pay_energy(st, player, pay):
        return _err("Not enough Energy.")
    var slot: ActionSlot = st.sequence[st.current_step]
    st.move_to_sequence(iid)
    slot.reactions.append({
        "iid": iid, "controller": player, "window": cd.reaction_window(),
        "targets": (cmd.get("targets", []) as Array).duplicate(),
        "x_paid": int(cmd.get("x", 0)) if cd.cost_kind() == "x" else 0,
        "energy_paid": pay, "resolved": false,
    })
    st.emit("reaction_committed", {
        "iid": iid, "player": player, "window": cd.reaction_window(),
        "message": "P%d commits the Reaction %s (%s the Action)." % [player + 1, cd.name, cd.reaction_window()]})
    # Committing a Reaction resets the consecutive-pass count.
    if st.reaction_window != null:
        (st.reaction_window as Dictionary)["passes"] = 0
        (st.reaction_window as Dictionary)["player"] = st.opponent_of(player)
    st.pending = null
    advance(st)
    return {"ok": true, "error": ""}


static func _do_pass_reaction(st: GameState, player: int) -> Dictionary:
    if not (st.pending is Dictionary) or String((st.pending as Dictionary).get("kind", "")) != "reaction_window":
        return _err("There is no open Reaction window.")
    if int((st.pending as Dictionary).get("player", -1)) != player:
        return _err("It is not your Reaction opportunity.")
    st.pending = null
    _register_reaction_pass(st, player, false)
    advance(st)
    return {"ok": true, "error": ""}


static func _do_choose_cards(st: GameState, player: int, cmd: Dictionary) -> Dictionary:
    if not (st.pending is Dictionary) or String((st.pending as Dictionary).get("kind", "")) != "choose_cards":
        return _err("No card choice is pending.")
    var p: Dictionary = st.pending
    if int(p.get("player", -1)) != player:
        return _err("That choice belongs to the other player.")
    var iids: Array = cmd.get("iids", [])
    var pool := _choice_pool(st, p)
    var want := int(p.get("count", 0))
    var optional := bool(p.get("optional", false))
    if iids.size() > want:
        return _err("Choose at most %d card(s)." % want)
    if not optional and iids.size() < min(want, pool.size()):
        return _err("You must choose %d card(s)." % min(want, pool.size()))
    for iid in iids:
        if not pool.has(String(iid)):
            return _err("One of the chosen cards is not available.")
    _apply_card_choice(st, p, iids)
    st.pending = null
    advance(st)
    return {"ok": true, "error": ""}


static func _apply_card_choice(st: GameState, p: Dictionary, iids: Array) -> void:
    var owner := int(p.get("owner", p.get("player", 0)))
    match String(p.get("purpose", "")):
        "equip":
            var host := String(p.get("host", ""))
            if st.inst(host) == null:
                return
            for iid in iids:
                Mechanics.attach_card(st, String(iid), host)
            return
        "recover":
            for iid in iids:
                var cd := st.def_of(String(iid))
                st.move_to_pile(String(iid), "hand")
                st.emit("recovered", {
                    "player": owner, "iid": iid,
                    "message": "P%d returns %s from Exhaust to hand." % [
                        owner + 1, cd.name if cd != null else String(iid)]})
        _:
            Mechanics.exhaust_from_hand(st, owner, iids)


## Name a Card Type. The answer is remembered on the card that asked, for the
## rest of the round, and triggers that read it consult it from there.
static func _do_choose_card_type(st: GameState, player: int, cmd: Dictionary) -> Dictionary:
    if not (st.pending is Dictionary) \
            or String((st.pending as Dictionary).get("kind", "")) != "choose_card_type":
        return _err("No Card Type choice is pending.")
    var p: Dictionary = st.pending
    if int(p.get("player", -1)) != player:
        return _err("That choice belongs to the other player.")
    var chosen := String(cmd.get("card_type", ""))
    if not EffectSchema.CARD_TYPES.has(chosen):
        return _err("'%s' is not a Card Type." % chosen)
    var ci := st.inst(String(p.get("source", "")))
    if ci == null:
        st.pending = null
        advance(st)
        return {"ok": true, "error": ""}
    ci.chosen_type = chosen
    var sd := st.def_of(ci.iid)
    st.emit("card_type_chosen", {
        "player": player, "iid": ci.iid, "card_type": chosen,
        "message": "P%d names %s for %s." % [
            player + 1, chosen.capitalize(), sd.name if sd != null else ci.iid]})
    st.pending = null
    advance(st)
    return {"ok": true, "error": ""}


static func _do_choose_deploy(st: GameState, player: int, cmd: Dictionary) -> Dictionary:
    if not (st.pending is Dictionary) or String((st.pending as Dictionary).get("kind", "")) != "choose_deploy":
        return _err("No deployment choice is pending.")
    var p: Dictionary = st.pending
    if int(p.get("player", -1)) != player:
        return _err("That choice belongs to the other player.")
    var iid := String(cmd.get("card_iid", ""))
    if iid == "":
        if not bool(p.get("optional", false)):
            return _err("You must put a Companion into play.")
        st.pending = null
        advance(st)
        return {"ok": true, "error": ""}
    if not _deployable_from_hand(st, player).has(iid):
        return _err("That card is not a Companion in your hand.")
    Mechanics.deploy_companion(st, iid, player)
    EffectRunner.process_trigger_queue(st, 1)
    st.pending = null
    advance(st)
    return {"ok": true, "error": ""}


# --------------------------------------------------------------- description ---

static func _label(st: GameState, iid: String) -> String:
    var cd := st.def_of(iid)
    return cd.name if cd != null else iid


static func describe_slot(st: GameState, slot: ActionSlot) -> String:
    if slot.kind == "attack":
        return "P%d attack — %s → %s" % [
            slot.controller + 1, _label(st, slot.attacker_iid),
            _label(st, String(slot.targets[0])) if not slot.targets.is_empty() else "no target"]
    var extra := ""
    if slot.x_paid > 0:
        extra = " (X = %d)" % slot.x_paid
    if not slot.targets.is_empty():
        extra += " → %s" % _label(st, String(slot.targets[0]))
    return "P%d plays %s%s" % [slot.controller + 1, _label(st, slot.card_iid), extra]
