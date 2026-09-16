class_name AiThinker
extends RefCounted

## Bounded, incremental AI thinking.
##
## The caller drives the search with step(budget_ms) — once per frame from the
## battle screen, or in a tight loop headlessly — so the interface stays
## responsive and a decision always arrives. If the budget runs out the best
## candidate found so far is used; if nothing was evaluated at all, the policy
## falls back to a legal pass.

var state: GameState
var player: int
var weights: Dictionary
var pool: Array = []
var index: int = 0
var best: Dictionary = {}
var best_score: float = -INF
var evaluated: int = 0
var search_seed: int = 0
var _choice_answer: Dictionary = {}


func _init(match_state: GameState, player_index: int, w: Dictionary = {}) -> void:
    state = match_state
    player = player_index
    weights = w
    if weights.is_empty():
        weights = AiProfiles.weights_for(state.player(player_index).affinity_profile)
    search_seed = int(state.rng.root_seed()) ^ (state.event_seq * 2246822519) ^ (player_index * 668265263)

    # A pending card/deployment choice is answered heuristically, not searched.
    if state.pending is Dictionary and String((state.pending as Dictionary).get("kind", "")) != "reaction_window":
        _choice_answer = AiPolicy.answer_choice(state, player, weights)
        return

    var limit := int(weights.get("search_candidates", 16))
    var wide := AiPolicy.candidates(state, player, limit)
    # Rank cheaply, then spend the rollout budget on the strongest candidates.
    # A legal pass is always kept so the search can decide to do nothing.
    var rollouts := int(weights.get("rollout_candidates", 6))
    if wide.size() > rollouts:
        var scored: Array = []
        var passes: Array = []
        for c in wide:
            var n := String((c as Dictionary).get("cmd", ""))
            if n == "pass_actions" or n == "pass_reaction":
                passes.append(c)
            else:
                scored.append({"cmd": c, "s": AiPolicy.static_score(state, player, c, weights)})
        scored.sort_custom(func(a, b): return float(a["s"]) > float(b["s"]))
        pool = []
        for i in min(rollouts, scored.size()):
            pool.append((scored[i] as Dictionary)["cmd"])
        pool.append_array(passes)
    else:
        pool = wide


func done() -> bool:
    if not _choice_answer.is_empty():
        return true
    return index >= pool.size()


## Evaluate candidates until the budget is spent or the pool is exhausted.
func step(budget_ms: int) -> void:
    if done():
        return
    var deadline: int = Time.get_ticks_msec() + maxi(1, budget_ms)
    while index < pool.size():
        var cmd: Dictionary = pool[index]
        index += 1
        var s := _evaluate(cmd)
        evaluated += 1
        if s > best_score:
            best_score = s
            best = cmd
        if Time.get_ticks_msec() >= deadline:
            return


func _evaluate(cmd: Dictionary) -> float:
    var clone := Observation.sanitized_clone(state, player, search_seed + index)
    var res := GameEngine.submit(clone, _strip(cmd))
    if not bool(res.get("ok", false)):
        return -INF
    _close_reaction_windows(clone)
    _play_out_round(clone)
    var s := AiPolicy.score(clone, player, weights)

    # Holding Energy back for Reactions is a deliberate choice, so charge for
    # dropping below the profile's reserve while Reaction cards are in hand.
    var reserve := int(weights.get("reaction_reserve", 0))
    if reserve > 0 and String(cmd.get("cmd", "")) != "pass_actions" and _holds_reaction(state, player):
        var left := state.player(player).energy_current - int(cmd.get("cost", 0))
        if left < reserve:
            s -= float(reserve - left) * float(weights.get("reaction_reserve_weight", 0.5)) * 6.0
    return s


## Commands carry display fields the engine does not expect; send only the
## fields that make up the actual command.
static func _strip(cmd: Dictionary) -> Dictionary:
    var out: Dictionary = {}
    for k in ["cmd", "player", "card_iid", "attacker_iid", "target_iid", "targets", "x", "iids"]:
        if cmd.has(k):
            out[k] = cmd[k]
    return out


static func _holds_reaction(state: GameState, player: int) -> bool:
    for iid in state.player(player).hand:
        var cd := state.def_of(String(iid))
        if cd != null and cd.allows_reaction_timing():
            return true
    return false


## Inside a rollout both sides pass every Reaction window, so the windows are
## closed up front rather than walked step by step. This is a search
## approximation, not a rules change: the real match always offers every legal
## Reaction opportunity.
static func _close_reaction_windows(clone: GameState) -> void:
    for s in clone.sequence:
        (s as ActionSlot).window_done = true
    clone.reaction_window = null
    if clone.pending is Dictionary \
            and String((clone.pending as Dictionary).get("kind", "")) == "reaction_window":
        clone.pending = null


## Let the round finish inside the rollout so a candidate is judged on the
## position it actually produces, chain payoffs and refunds included.
func _play_out_round(clone: GameState) -> void:
    var start_round := clone.round_number
    var guard := 0
    while clone.result == null and clone.round_number == start_round and guard < 400:
        guard += 1
        _close_reaction_windows(clone)
        if clone.pending is Dictionary:
            var p: Dictionary = clone.pending
            var who := int(p.get("player", 0))
            match String(p.get("kind", "")):
                "reaction_window":
                    GameEngine.submit(clone, {"cmd": "pass_reaction", "player": who})
                "choose_cards":
                    var pool2 := GameEngine._choice_pool(clone, p)
                    var n: int = min(int(p.get("count", 0)), pool2.size())
                    GameEngine.submit(clone, {"cmd": "choose_cards", "player": who,
                        "iids": pool2.slice(0, n)})
                "choose_deploy":
                    GameEngine.submit(clone, {"cmd": "choose_deploy", "player": who, "card_iid": ""})
                "choose_card_type":
                    GameEngine.submit(clone, {"cmd": "choose_card_type", "player": who,
                        "card_type": AiPolicy._best_card_type(clone, who)})
                _:
                    clone.pending = null
                    GameEngine.advance(clone)
            continue
        if clone.phase == "action":
            GameEngine.submit(clone, {"cmd": "pass_actions", "player": clone.action_priority})
            continue
        GameEngine.advance(clone)


## The chosen command. Always legal: the fallback is a legal pass.
func result() -> Dictionary:
    if not _choice_answer.is_empty():
        return _choice_answer
    if not best.is_empty() and best_score > -INF:
        return AiThinker._strip(best)
    var legal := GameEngine.legal_commands(state, player)
    for c in legal:
        var name := String((c as Dictionary).get("cmd", ""))
        if name == "pass_actions" or name == "pass_reaction":
            return AiThinker._strip(c)
    if not legal.is_empty():
        return AiThinker._strip(legal[0])
    return {}
