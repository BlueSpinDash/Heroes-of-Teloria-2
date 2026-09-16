class_name AiPolicy
extends RefCounted

## The local opponent's decision policy.
##
## It only ever returns a command drawn from GameEngine.legal_commands(), so the
## AI is bound by exactly the same legality, timing, targeting and destruction
## rules as the human. Search runs on Observation.sanitized_clone(), where the
## human's hand contents and both Hit orders have been destroyed, so the policy
## cannot read hidden information even by accident.
##
## The baseline is a heuristic evaluation with a bounded one-ply search: commit
## a candidate, let the round play out, and score the resulting position with
## the Affinity's weights.

const TERMINAL_SCORE := 10000.0

## Coarse value of a card's advertised behaviour, used only to rank candidates
## before the expensive rollout. The rollout, not this table, decides.
const PATTERN_BONUS := {
    "removal": 1.5, "hero_burn": 1.2, "direct_damage": 1.0, "deploy": 1.0,
    "draw": 0.9, "chain_payoff": 0.8, "chain_scaling": 0.8, "equipment_buff": 0.7,
    "taahma_buff": 0.6, "energy_refund": 0.6, "protection": 0.6, "mass_buff": 0.7,
    "permanent_buff": 0.7, "aura_buff": 0.8, "energy_denial": 0.5, "debuff": 0.5,
    "location_aura": 0.6, "recovery": 0.5, "mill": 0.4, "discard_random": 0.4,
    "discard_choice": 0.4, "x_cost": 0.5, "bounce": 0.6, "max_energy_boost": 0.6,
    "etb_effect": 0.5, "attack_trigger": 0.4, "body": 0.3,
}


static func decide(state: GameState, player: int, weights: Dictionary = {}) -> Dictionary:
    var thinker := AiThinker.new(state, player, weights)
    while not thinker.done():
        thinker.step(1000)
    return thinker.result()


## Every legal command, pruned to a bounded candidate set.
static func candidates(state: GameState, player: int, limit: int) -> Array:
    var legal := GameEngine.legal_commands(state, player)
    if legal.size() <= 1:
        return legal
    var passes: Array = []
    var plays: Array = []
    for c in legal:
        var name := String((c as Dictionary).get("cmd", ""))
        if name == "pass_actions" or name == "pass_reaction":
            passes.append(c)
        else:
            plays.append(c)

    plays = _prune_x_variants(plays)
    if plays.size() > limit:
        plays.sort_custom(func(a, b): return int(a.get("cost", 0)) < int(b.get("cost", 0)))
        plays = plays.slice(0, limit)
    var out: Array = plays
    out.append_array(passes)
    return out


## For an X cost, keep only the smallest, a middle and the largest amount:
## every intermediate value plays out almost identically.
static func _prune_x_variants(plays: Array) -> Array:
    var grouped: Dictionary = {}
    var others: Array = []
    for c in plays:
        var cmd: Dictionary = c
        if not cmd.has("x"):
            others.append(cmd)
            continue
        var key := "%s|%s" % [String(cmd.get("card_iid", "")), str(cmd.get("targets", []))]
        if not grouped.has(key):
            grouped[key] = []
        (grouped[key] as Array).append(cmd)
    for key in grouped.keys():
        var list: Array = grouped[key]
        list.sort_custom(func(a, b): return int(a["x"]) < int(b["x"]))
        var picks: Array = [list[0]]
        if list.size() > 2:
            picks.append(list[list.size() / 2])
        if list.size() > 1:
            picks.append(list[list.size() - 1])
        others.append_array(picks)
    return others


## A cheap ranking used to choose which candidates deserve a full rollout.
## It never decides the move on its own.
static func static_score(state: GameState, me: int, cmd: Dictionary, w: Dictionary) -> float:
    var name := String(cmd.get("cmd", ""))
    if name == "pass_actions" or name == "pass_reaction":
        return -1.0
    if name == "commit_attack":
        var attacker := String(cmd.get("attacker_iid", ""))
        var target := String(cmd.get("target_iid", ""))
        var dmg: int = max(0, state.current_attack(attacker) - state.current_defense(target))
        var tci := state.inst(target)
        if tci == null:
            return -1.0
        if tci.zone == "hero":
            return float(dmg) * _w(w, "pressure", 1.0) * 2.0
        if dmg > 0:
            return (float(state.current_attack(target) + state.current_defense(target))
                * _w(w, "board_attack", 0.55) * 1.6)
        return 0.05
    var cd := state.def_of(String(cmd.get("card_iid", "")))
    if cd == null:
        return -1.0
    var s := 1.0 + float(cd.ai_hints.get("priority", 0.5))
    for p in cd.patterns:
        s += float(PATTERN_BONUS.get(String(p), 0.2))
    if cd.has_type("companion"):
        s += float(cd.attack + cd.defense) * 0.15
    s -= float(int(cmd.get("cost", 0))) * 0.15
    return s


## Score a position from `me`'s point of view using the Affinity's weights.
static func score(state: GameState, me: int, w: Dictionary) -> float:
    var opp := state.opponent_of(me)
    if state.result != null:
        var winner := int((state.result as Dictionary).get("winner", -1))
        if winner == me:
            return TERMINAL_SCORE
        if winner == opp:
            return -TERMINAL_SCORE
        return -TERMINAL_SCORE * 0.25  # a draw is better than losing, worse than winning

    var mine := state.player(me)
    var theirs := state.player(opp)
    var my_res := mine.hit.size() + mine.exhaust.size()
    var opp_res := theirs.hit.size() + theirs.exhaust.size()

    var my_atk := 0
    var my_def := 0
    for iid in mine.companions:
        my_atk += state.current_attack(String(iid))
        my_def += state.current_defense(String(iid))
    var opp_atk := 0
    var opp_def := 0
    for iid in theirs.companions:
        opp_atk += state.current_attack(String(iid))
        opp_def += state.current_defense(String(iid))

    var s := 0.0
    s += _w(w, "pressure", 1.0) * float(-opp_res)
    s += _w(w, "preservation", 0.45) * float(my_res)
    s += _w(w, "board_attack", 0.55) * float(my_atk - opp_atk)
    s += _w(w, "board_defense", 0.40) * float(my_def - opp_def)
    s += _w(w, "companion_count", 0.6) * float(mine.companions.size() - theirs.companions.size()) * 2.0
    s += _w(w, "hand_value", 0.35) * float(mine.hand.size())
    s += _w(w, "energy_value", 0.18) * float(mine.energy_current)
    s += _w(w, "max_energy_value", 0.45) * float(state.energy_max(me) - state.energy_max(opp))
    s += _w(w, "hero_size", 0.3) * float(
        state.current_attack(mine.hero_iid) + state.current_defense(mine.hero_iid))
    s += _w(w, "protect_own", 0.5) * float(state.inst(mine.hero_iid).shield_total())

    # Running low on cards to draw is how a player loses, so weight the danger
    # zone explicitly rather than trusting the linear term.
    if my_res <= 6:
        s -= float(7 - my_res) * 12.0
    if opp_res <= 6:
        s += float(7 - opp_res) * 8.0 * _w(w, "aggression", 1.0)
    return s


static func _w(w: Dictionary, key: String, fallback: float) -> float:
    return float(w.get(key, fallback))


## Answer a pending non-command choice. These are heuristics rather than a
## search, because a choice is always a small, local decision.
static func answer_choice(state: GameState, player: int, w: Dictionary) -> Dictionary:
    var p: Dictionary = state.pending
    match String(p.get("kind", "")):
        "choose_cards":
            var pool := GameEngine._choice_pool(state, p)
            var want: int = min(int(p.get("count", 0)), pool.size())
            var purpose := String(p.get("purpose", ""))
            var ranked := pool.duplicate()
            if purpose == "recover":
                # Bring back the cheapest cards, which are the most playable.
                ranked.sort_custom(func(a, b): return _cost_of(state, String(a)) < _cost_of(state, String(b)))
            else:
                # Exhaust the least playable cards first.
                ranked.sort_custom(func(a, b): return _cost_of(state, String(a)) > _cost_of(state, String(b)))
            return {"cmd": "choose_cards", "player": player, "iids": ranked.slice(0, want)}
        "choose_card_type":
            # Name the type that most of what is still to resolve carries, so
            # the choice is worth something rather than arbitrary.
            return {"cmd": "choose_card_type", "player": player,
                "card_type": _best_card_type(state, player)}
        "choose_deploy":
            var pool2 := GameEngine._deployable_from_hand(state, player)
            if pool2.is_empty():
                return {"cmd": "choose_deploy", "player": player, "card_iid": ""}
            pool2.sort_custom(func(a, b): return _body_value(state, String(a)) > _body_value(state, String(b)))
            return {"cmd": "choose_deploy", "player": player, "card_iid": String(pool2[0])}
    return {}


## The Card Type most represented among the Actions still to resolve this
## round, falling back to what is in hand, and to Skill when neither says
## anything. Naming a type nothing will carry is the one clearly bad answer.
static func _best_card_type(state: GameState, player: int) -> String:
    var counts: Dictionary = {}
    for i in range(state.current_step + 1, state.sequence.size()):
        var slot: ActionSlot = state.sequence[i]
        if slot.card_iid == "":
            continue
        var d := state.def_of(slot.card_iid)
        if d == null:
            continue
        for t in d.types:
            counts[String(t)] = int(counts.get(String(t), 0)) + 2
    for iid in state.player(player).hand:
        var hd := state.def_of(String(iid))
        if hd == null:
            continue
        for t in hd.types:
            counts[String(t)] = int(counts.get(String(t), 0)) + 1
    var best := "skill"
    var best_score := -1
    for t in EffectSchema.CARD_TYPES:
        var score := int(counts.get(String(t), 0))
        if score > best_score:
            best_score = score
            best = String(t)
    return best


static func _cost_of(state: GameState, iid: String) -> int:
    var cd := state.def_of(iid)
    if cd == null:
        return 0
    if cd.cost_kind() == "x":
        return cd.x_min() + 1
    return cd.fixed_cost()


static func _body_value(state: GameState, iid: String) -> int:
    var cd := state.def_of(iid)
    if cd == null:
        return 0
    return cd.attack + cd.defense + cd.energy_contribution
