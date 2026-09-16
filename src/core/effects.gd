class_name EffectRunner
extends RefCounted

## Executes the structured card instructions defined in EffectSchema.
##
## Cards never carry code: an effect is validated data, and this file is the
## only place that turns it into state changes. A mechanic outside this
## vocabulary genuinely requires extending the engine — see
## docs/EFFECT_SCHEMA.md.
##
## Ordering guarantees:
##   * one primitive runs to completion, then its trigger queue is processed
##     before the next primitive starts;
##   * triggers run first-player-controller first, then the other player, and
##     within a controller in source entry order then printed effect order;
##   * the chosen order is written to the event log.


## Build the execution context for an effect list.
##   source_iid  — the card producing the effect
##   controller  — the player the effect belongs to ("self" / "opponent")
##   slot_index  — the Action Sequence slot being resolved, for chain reads
static func make_ctx(source_iid: String, controller: int, slot_index: int = -1,
        targets: Array = [], x_paid: int = 0, extra: Dictionary = {}) -> Dictionary:
    var ctx := {
        "source_iid": source_iid,
        "controller": controller,
        "slot_index": slot_index,
        "targets": targets.duplicate(),
        "x_paid": x_paid,
        "target_kind": "",
        "current_attacker": "",
        "current_target": "",
    }
    ctx.merge(extra, true)
    return ctx


## Top-level entry point: run each primitive then drain its trigger queue.
static func run_with_triggers(state: GameState, effects: Array, ctx: Dictionary) -> void:
    for e in effects:
        if state.result != null:
            return
        if e is Dictionary:
            exec_one(state, e, ctx)
        process_trigger_queue(state, 1)


## Run effects without draining (used for trigger bodies, whose own queue is
## drained by the caller at the right depth).
static func run(state: GameState, effects: Array, ctx: Dictionary) -> void:
    for e in effects:
        if state.result != null:
            return
        if e is Dictionary:
            exec_one(state, e, ctx)


# --------------------------------------------------------------- primitives ---

static func exec_one(state: GameState, e: Dictionary, ctx: Dictionary) -> void:
    var op := String(e.get("op", ""))
    var controller: int = int(ctx["controller"])
    var opp := state.opponent_of(controller)

    match op:
        "aura_stat_mod", "aura_energy_max":
            return  # continuous; read directly by GameState while in play

        "damage_hero":
            var who := _who(state, e, ctx)
            Mechanics.hero_damage(state, who, _amount(state, e.get("amount"), ctx), _source_label(state, ctx))

        "direct_damage":
            var amt := _amount(state, e.get("amount"), ctx)
            var ig := bool(e.get("ignores_defense", false))
            for t in _resolve_targets(state, e.get("target"), ctx):
                Mechanics.damage_character(state, String(t), amt, ig, _source_label(state, ctx))

        "destroy":
            for t in _resolve_targets(state, e.get("target"), ctx):
                Mechanics.destroy(state, String(t), _source_label(state, ctx))

        "bounce":
            for t in _resolve_targets(state, e.get("target"), ctx):
                Mechanics.bounce(state, String(t))

        "draw":
            # A card-instructed draw is a required draw: failing it loses.
            var who2 := _who(state, e, ctx)
            var n := _amount(state, e.get("amount"), ctx)
            if n > 0 and not Mechanics.required_draw(state, who2, n):
                Mechanics.mark_failure(state, who2, "A required draw could not be completed from Hit plus Exhaust.")

        "energy_gain":
            Mechanics.gain_energy(state, _who(state, e, ctx), _amount(state, e.get("amount"), ctx), _source_label(state, ctx))

        "energy_drain":
            Mechanics.drain_energy(state, _who(state, e, ctx), _amount(state, e.get("amount"), ctx))

        "energy_max_mod":
            var raw: Variant = e.get("amount", 0)
            var signed := int(raw) if (raw is int or raw is float) else _amount(state, raw, ctx)
            Mechanics.add_energy_max_mod(state, _who(state, e, ctx), signed, String(e.get("duration", "round")))

        "stat_mod":
            var duration := String(e.get("duration", "round"))
            for t in _resolve_targets(state, e.get("target"), ctx):
                var ci := state.inst(String(t))
                if ci == null:
                    continue
                var m := {"expires": duration}
                if e.has("attack"):
                    m["attack"] = int(e["attack"])
                if e.has("defense"):
                    m["defense"] = int(e["defense"])
                ci.mods.append(m)
                var cd := state.def_of(String(t))
                state.emit("stat_modified", {
                    "iid": t, "mod": m,
                    "message": "%s is now %d/%d%s." % [
                        cd.name if cd != null else String(t),
                        state.current_attack(String(t)), state.current_defense(String(t)),
                        "" if duration == "permanent" else " (%s)" % duration]})

        "choose_card_type":
            var who := int(ctx["controller"])
            if String(e.get("chooser", "controller")) == "opponent":
                who = state.opponent_of(who)
            var src_iid := String(ctx.get("source_iid", ""))
            if state.inst(src_iid) != null:
                _defer_choice(state, {
                    "kind": "choose_card_type", "player": who, "source": src_iid})

        "next_attack_bonus":
            # Left for the next attack that qualifies to claim. Nothing is
            # applied here: which character it will be is not known yet.
            var bonus := {
                "amount": _amount(state, e.get("amount", 0), ctx),
                "scope": String(e.get("scope", "controller")),
                "affinity": String(e.get("affinity", "")),
                "controller": int(ctx["controller"]),
                "source": _source_label(state, ctx),
            }
            state.pending_attack_bonuses.append(bonus)
            state.emit("attack_bonus_pending", {
                "amount": bonus["amount"], "affinity": bonus["affinity"],
                "message": "%s: the next %sattack to resolve deals %d more damage." % [
                    String(bonus["source"]) if String(bonus["source"]) != "" else "A card",
                    "%s " % String(bonus["affinity"]).capitalize() if String(bonus["affinity"]) != "" else "",
                    int(bonus["amount"])]})

        "prevent_damage":
            var amt2 := _amount(state, e.get("amount"), ctx)
            for t in _resolve_targets(state, e.get("target"), ctx):
                var ci2 := state.inst(String(t))
                if ci2 == null:
                    continue
                ci2.shields.append({"amount": amt2, "expires": String(e.get("duration", "round"))})
                var cd2 := state.def_of(String(t))
                state.emit("shield_added", {
                    "iid": t, "amount": amt2,
                    "message": "The next %d damage to %s is prevented." % [amt2, cd2.name if cd2 != null else String(t)]})

        "mill":
            Mechanics.mill(state, _who(state, e, ctx), _amount(state, e.get("amount"), ctx))

        "random_exhaust_from_hand":
            var who3 := _who(state, e, ctx)
            var p := state.player(who3)
            var n3: int = min(_amount(state, e.get("amount"), ctx), p.hand.size())
            var picked := state.rng.take_random("discard_p%d" % who3, p.hand, n3)
            for iid in picked:
                var ci3 := state.inst(String(iid))
                if ci3 == null:
                    continue
                ci3.zone = "exhaust"
                state.player(ci3.owner).exhaust.append(iid)
            if n3 > 0:
                state.emit("hand_exhausted_random", {
                    "player": who3, "count": n3,
                    "message": "P%d Exhausts %d card%s at random from hand." % [who3 + 1, n3, "" if n3 == 1 else "s"]})

        "exhaust_from_hand":
            var who4 := _who(state, e, ctx)
            var chooser := controller if String(e.get("chooser", "controller")) == "controller" else opp
            _defer_choice(state, {
                "kind": "choose_cards", "purpose": "exhaust", "from": "hand",
                "owner": who4, "player": chooser,
                "count": _amount(state, e.get("amount"), ctx), "optional": false})

        "recover_from_exhaust":
            var who5 := _who(state, e, ctx)
            _defer_choice(state, {
                "kind": "choose_cards", "purpose": "recover", "from": "exhaust",
                "owner": who5, "player": who5,
                "count": _amount(state, e.get("amount"), ctx), "optional": true})

        "deploy_from_hand":
            var who6 := _who(state, e, ctx)
            _defer_choice(state, {
                "kind": "choose_deploy", "player": who6, "owner": who6, "optional": who6 == controller})

        "conditional":
            if check_condition(state, e.get("cond", {}), ctx):
                run(state, e.get("then", []), ctx)
            elif e.has("otherwise"):
                run(state, e["otherwise"], ctx)

        "chain_reward":
            var req: Dictionary = {"kind": "chain_at_least"}
            req.merge(e.get("require", {}))
            if check_condition(state, req, ctx):
                state.emit("chain_reward", {
                    "player": controller,
                    "message": "Chain requirement met: %s" % AffinityChain.describe(state, int(ctx["slot_index"]))})
                run(state, e.get("then", []), ctx)
            else:
                state.emit("chain_reward_missed", {
                    "player": controller,
                    "message": "Chain requirement not met; that part of the card does nothing."})

        "repeat":
            var times := _amount(state, e.get("amount"), ctx)
            for _i in min(times, 32):
                run(state, e.get("effects", []), ctx)


# ---------------------------------------------------------------- conditions ---

static func check_condition(state: GameState, cond: Dictionary, ctx: Dictionary) -> bool:
    var controller: int = int(ctx["controller"])
    var opp := state.opponent_of(controller)
    var kind := String(cond.get("kind", ""))
    match kind:
        "chain_at_least":
            var n := AffinityChain.count(state, int(ctx["slot_index"]),
                String(cond.get("affinity", "any")), String(cond.get("scope", "either")), controller)
            return n >= int(cond.get("min", 1))
        "controls_companions":
            var who := controller if String(cond.get("who", "self")) == "self" else opp
            return state.player(who).companions.size() >= int(cond.get("min", 1))
        "energy_at_least":
            var who2 := controller if String(cond.get("who", "self")) == "self" else opp
            return state.player(who2).energy_current >= int(cond.get("min", 1))
        "hand_size_at_least":
            var who3 := controller if String(cond.get("who", "self")) == "self" else opp
            return state.player(who3).hand.size() >= int(cond.get("min", 1))
        "exhaust_at_least":
            var who4 := controller if String(cond.get("who", "self")) == "self" else opp
            return state.player(who4).exhaust.size() >= int(cond.get("min", 1))
        "hit_at_most":
            var who5 := controller if String(cond.get("who", "self")) == "self" else opp
            return state.player(who5).hit.size() <= int(cond.get("max", 0))
        "location_active":
            return state.location_iid != ""
        "has_attachment":
            var of := String(cond.get("of", "equipment"))
            for t in _resolve_targets(state, cond.get("target"), ctx):
                var ci := state.inst(String(t))
                if ci == null:
                    continue
                if of == "equipment" and ci.equipment_iid != "":
                    return true
                if of == "taahma" and ci.taahma_iid != "":
                    return true
            return false
        "target_defense_at_most":
            for t in _resolve_targets(state, "chosen", ctx):
                if state.current_defense(String(t)) <= int(cond.get("max", 0)):
                    return true
            return false
        "target_attack_at_least":
            for t in _resolve_targets(state, "chosen", ctx):
                if state.current_attack(String(t)) >= int(cond.get("min", 0)):
                    return true
            return false
    return false


# ------------------------------------------------------------------- amounts ---

static func _amount(state: GameState, spec, ctx: Dictionary) -> int:
    if spec == null:
        return 0
    if spec is int or spec is float:
        return int(spec)
    if not (spec is Dictionary):
        return 0
    var controller: int = int(ctx["controller"])
    var opp := state.opponent_of(controller)
    var base := 0
    match String(spec.get("from", "")):
        "x":
            base = int(ctx.get("x_paid", 0))
        "chain_count":
            base = AffinityChain.count(state, int(ctx["slot_index"]),
                String(spec.get("affinity", "any")), String(spec.get("scope", "either")), controller)
        "count":
            match String(spec.get("of", "")):
                "own_companions": base = state.player(controller).companions.size()
                "opponent_companions": base = state.player(opp).companions.size()
                "own_hand": base = state.player(controller).hand.size()
                "opponent_hand": base = state.player(opp).hand.size()
                "own_exhaust": base = state.player(controller).exhaust.size()
                "opponent_exhaust": base = state.player(opp).exhaust.size()
    if spec.has("multiplier"):
        base = int(floor(float(base) * float(spec["multiplier"])))
    return max(0, base)


static func _who(state: GameState, e: Dictionary, ctx: Dictionary) -> int:
    var controller: int = int(ctx["controller"])
    return controller if String(e.get("who", "self")) == "self" else state.opponent_of(controller)


static func _source_label(state: GameState, ctx: Dictionary) -> String:
    var cd := state.def_of(String(ctx.get("source_iid", "")))
    return cd.name if cd != null else ""


# -------------------------------------------------------------------- targets ---

## Resolve a target reference to currently valid instance ids.
##
## "chosen" targets are revalidated here, at resolution time. An invalid
## choice makes the referencing component do nothing; it never retargets,
## refunds Energy or restores an action allowance.
static func _resolve_targets(state: GameState, ref, ctx: Dictionary) -> Array:
    # A target may be narrowed: {"ref": ..., "affinity": ...} keeps only the
    # cards carrying that Affinity.
    if ref is Dictionary:
        var spec: Dictionary = ref
        var picked := _resolve_targets(state, spec.get("ref", "chosen"), ctx)
        var want := String(spec.get("affinity", ""))
        if want == "":
            return picked
        var kept: Array = []
        for t in picked:
            var td := state.def_of(String(t))
            if td != null and td.affinities.has(want):
                kept.append(String(t))
        return kept
    var r := String(ref) if ref != null else "chosen"
    var controller: int = int(ctx["controller"])
    var opp := state.opponent_of(controller)
    match r:
        "chosen":
            var kind := String(ctx.get("target_kind", ""))
            var out: Array = []
            for t in ctx.get("targets", []):
                if kind == "" or Targeting.is_valid(state, kind, controller, String(t)):
                    out.append(String(t))
                else:
                    state.emit("target_invalid", {
                        "iid": t,
                        "message": "Declared target is no longer valid: %s That part of the card does nothing." % \
                            Targeting.explain_invalid(state, kind, controller, String(t))})
            return out
        "self":
            return [String(ctx.get("source_iid", ""))]
        "host":
            var ci := state.inst(String(ctx.get("source_iid", "")))
            return [ci.attached_to] if ci != null and ci.attached_to != "" else []
        "self_hero":
            return [state.player(controller).hero_iid]
        "opponent_hero":
            return [state.player(opp).hero_iid]
        "all_own_companions":
            return state.player(controller).companions.duplicate()
        "all_opponent_companions":
            return state.player(opp).companions.duplicate()
        "all_companions":
            return state.player(controller).companions + state.player(opp).companions
        "current_attacker":
            var a := String(ctx.get("current_attacker", ""))
            return [a] if a != "" and state.inst(a) != null else []
        "current_target":
            var t2 := String(ctx.get("current_target", ""))
            if t2 == "" or state.inst(t2) == null:
                return []
            var tci := state.inst(t2)
            if not ["hero", "companions"].has(tci.zone):
                return []
            return [t2]
    return []


static func _defer_choice(state: GameState, choice: Dictionary) -> void:
    if int(choice.get("count", 1)) <= 0 and String(choice.get("kind", "")) == "choose_cards":
        return
    state.deferred_choices.append(choice)


# ------------------------------------------------------------------ triggers ---

## Process every trigger event raised by the primitive that just finished.
static func process_trigger_queue(state: GameState, depth: int) -> void:
    if state.trigger_events.is_empty():
        return
    if depth > state.trigger_depth_limit:
        state.emit("trigger_guard", {
            "depth": depth,
            "message": "Engine guard: trigger chain exceeded %d levels and was stopped. This is an engine limit, not a game rule." % state.trigger_depth_limit})
        state.trigger_events.clear()
        return
    var batch: Array = state.trigger_events.duplicate(true)
    state.trigger_events.clear()
    for ev in batch:
        var matches := _collect_matching(state, ev)
        if matches.is_empty():
            continue
        var order: Array = []
        for m in matches:
            var cd: CardDef = m["def"]
            order.append(cd.name)
        state.emit("triggers_ordered", {
            "event": ev.get("kind", ""), "order": order,
            "message": "Triggers on %s resolve in order: %s." % [String(ev.get("kind", "")), ", ".join(order)]})
        for m in matches:
            if state.result != null:
                return
            var src_iid := String(m["iid"])
            var src_ci := state.inst(src_iid)
            if src_ci == null:
                continue
            var t_ctx := make_ctx(src_iid, src_ci.controller, _slot_index_for(state),
                [], 0, {"current_attacker": String(ev.get("attacker", "")), "current_target": String(ev.get("target", ""))})
            var cd2: CardDef = m["def"]
            state.emit("trigger_fired", {
                "iid": src_iid, "event": ev.get("kind", ""),
                "message": "%s triggers on %s." % [cd2.name, String(ev.get("kind", "")).replace("_", " ")]})
            run(state, m["effects"], t_ctx)
            process_trigger_queue(state, depth + 1)


static func _slot_index_for(state: GameState) -> int:
    return state.current_step


## Every in-play source whose printed trigger matches this event, in the
## provisional resolution order.
static func _collect_matching(state: GameState, ev: Dictionary) -> Array:
    var out: Array = []
    for iid in _trigger_sources(state):
        var ci := state.inst(String(iid))
        var cd := state.def_of(String(iid))
        if ci == null or cd == null:
            continue
        var effect_index := 0
        for trig in cd.triggers:
            if not (trig is Dictionary):
                continue
            if _trigger_matches(state, ci, trig.get("on", {}), ev):
                out.append({
                    "iid": String(iid), "def": cd, "effects": trig.get("effects", []),
                    "controller": ci.controller, "entry": ci.entry_seq, "order": effect_index,
                })
            effect_index += 1
    # First player's controller first, then entry order, then printed order.
    var fp := state.first_player
    out.sort_custom(func(a, b):
        var pa: int = 0 if int(a["controller"]) == fp else 1
        var pb: int = 0 if int(b["controller"]) == fp else 1
        if pa != pb:
            return pa < pb
        if int(a["entry"]) != int(b["entry"]):
            return int(a["entry"]) < int(b["entry"])
        return int(a["order"]) < int(b["order"]))
    return out


static func _trigger_sources(state: GameState) -> Array:
    var out: Array = []
    for p in state.players:
        var ps: PlayerState = p
        _add_source(state, out, ps.hero_iid)
        for ciid in ps.companions:
            _add_source(state, out, String(ciid))
    if state.location_iid != "":
        out.append(state.location_iid)
    return out


static func _add_source(state: GameState, out: Array, iid: String) -> void:
    if iid == "":
        return
    out.append(iid)
    var ci := state.inst(iid)
    if ci == null:
        return
    if ci.equipment_iid != "":
        out.append(ci.equipment_iid)
    if ci.taahma_iid != "":
        out.append(ci.taahma_iid)


static func _trigger_matches(state: GameState, src: CardInstance, on: Dictionary, ev: Dictionary) -> bool:
    var kind := String(on.get("kind", ""))
    var ev_kind := String(ev.get("kind", ""))
    match kind:
        "affinity_card_resolved":
            if ev_kind != "card_resolved":
                return false
            var aff := String(on.get("affinity", "any"))
            var list: Array = ev.get("affinities", [])
            if aff != "any" and not list.has(aff):
                return false
            if not _scope_ok(state, String(on.get("scope", "either")), src.controller, int(ev.get("controller", 0))):
                return false
            # A character only sees these while it is actually in the Sequence.
            var cd := state.def_of(src.iid)
            if cd != null and cd.is_character():
                return state.sequence_members.has(src.iid)
            return true
        "chosen_type_card_resolved":
            if ev_kind != "card_resolved":
                return false
            # Nothing has been named yet, so nothing matches. This is also what
            # makes the trigger read "after": a type is named when the card
            # resolves, so no earlier resolution can match it, and the name is
            # forgotten at Round End. Unlike the Affinity trigger, this one does
            # not need its source to still be in the Sequence — it is worded for
            # the rest of the round, not for while the card is committed.
            if src.chosen_type == "":
                return false
            var types: Array = ev.get("types", [])
            if not types.has(src.chosen_type):
                return false
            return _scope_ok(state, String(on.get("scope", "either")), src.controller,
                int(ev.get("controller", 0)))
        "self_deployed":
            return ev_kind == "companion_deployed" and String(ev.get("iid", "")) == src.iid
        "own_companion_deployed":
            return ev_kind == "companion_deployed" and int(ev.get("controller", -1)) == src.controller \
                and String(ev.get("iid", "")) != src.iid
        "self_attack_resolved":
            return ev_kind == "attack_resolved" and String(ev.get("attacker", "")) == src.iid
        "attack_resolved":
            if ev_kind != "attack_resolved":
                return false
            return _scope_ok(state, String(on.get("scope", "either")), src.controller, int(ev.get("controller", 0)))
        "round_end":
            return ev_kind == "round_end"
        "own_hero_damaged":
            return ev_kind == "hero_damaged" and int(ev.get("player", -1)) == src.controller
        "opponent_hero_damaged":
            return ev_kind == "hero_damaged" and int(ev.get("player", -1)) == state.opponent_of(src.controller)
        "self_leaves_play":
            return ev_kind == "leaves_play" and String(ev.get("iid", "")) == src.iid
    return false


static func _scope_ok(state: GameState, scope: String, source_controller: int, event_controller: int) -> bool:
    match scope:
        "either": return true
        "controller": return event_controller == source_controller
        "opponent": return event_controller != source_controller
    return true
