class_name MatchRunner
extends RefCounted

## Headless match driver.
##
## Plays a match through the real engine with the real AI policy on one or both
## sides. Used by the simulation tests and by the developer tools; the battle
## screen drives the same engine through the same commands.
##
## A round limit here is a SIMULATION safety limit. Hitting it is reported as
## such and never converted into a gameplay defeat.


## Run a match to completion (or to the simulation limit).
## `controllers` is one entry per player: "ai" or "pass" (a do-nothing driver
## used to exercise specific rules paths).
static func simulate(catalog: Catalog, rules: RulesProfile, decks: Array, seed_value: int,
        profiles: Array = ["", ""], controllers: Array = ["ai", "ai"],
        round_limit: int = 0) -> Dictionary:
    var limit := round_limit if round_limit > 0 else rules.simulation_round_limit
    var st := GameEngine.start_match(catalog, rules, decks, seed_value,
        Ids.unique("sim"), ["P1", "P2"], [true, true], profiles)
    return drive(st, controllers, limit)


## Drive an existing match state with automatic controllers.
static func drive(st: GameState, controllers: Array = ["ai", "ai"], round_limit: int = 200) -> Dictionary:
    var illegal: Array = []
    var decisions := 0
    var guard := 0
    var stalled := false
    var hit_round_limit := false

    while st.result == null:
        guard += 1
        if guard > 20000:
            stalled = true
            break
        if st.round_number > round_limit:
            hit_round_limit = true
            break

        var actor := _actor(st)
        if actor < 0:
            GameEngine.advance(st)
            if st.result == null and _actor(st) < 0 and st.pending == null and st.phase == "ended":
                break
            continue

        var cmd: Dictionary = {}
        if String(controllers[actor]) == "ai":
            cmd = AiPolicy.decide(st, actor)
        else:
            cmd = _passive_command(st, actor)
        if cmd.is_empty():
            stalled = true
            break
        var res := GameEngine.submit(st, cmd)
        decisions += 1
        if not bool(res.get("ok", false)):
            illegal.append("%s -> %s" % [JSON.stringify(cmd), String(res.get("error", ""))])
            # Never let a rejected command hang the match: fall back to a pass.
            var fallback := _passive_command(st, actor)
            if fallback.is_empty() or not bool(GameEngine.submit(st, fallback).get("ok", false)):
                stalled = true
                break

    var guards: Array = []
    for e in st.events:
        var kind := String((e as Dictionary).get("kind", ""))
        if kind == "trigger_guard" or kind == "engine_guard":
            guards.append(String((e as Dictionary).get("message", "")))

    return {
        "state": st,
        "result": st.result,
        "rounds": st.round_number,
        "decisions": decisions,
        "illegal_commands": illegal,
        "stalled": stalled,
        "hit_round_limit": hit_round_limit,
        "engine_guards": guards,
        "events": st.events.size(),
    }


## Whose decision the match is waiting on, or -1 if it can advance itself.
static func _actor(st: GameState) -> int:
    if st.result != null:
        return -1
    if st.pending is Dictionary:
        return int((st.pending as Dictionary).get("player", -1))
    if st.phase == "action":
        if st.player(st.action_priority).passed_actions:
            return -1
        return st.action_priority
    return -1


static func _passive_command(st: GameState, player: int) -> Dictionary:
    if st.pending is Dictionary:
        var p: Dictionary = st.pending
        match String(p.get("kind", "")):
            "reaction_window":
                return {"cmd": "pass_reaction", "player": player}
            "choose_cards":
                var pool := GameEngine._choice_pool(st, p)
                var n: int = min(int(p.get("count", 0)), pool.size())
                return {"cmd": "choose_cards", "player": player, "iids": pool.slice(0, n)}
            "choose_deploy":
                return {"cmd": "choose_deploy", "player": player, "card_iid": ""}
        return {}
    if st.phase == "action":
        return {"cmd": "pass_actions", "player": player}
    return {}


## A compact, reproducible transcript for the developer view and for
## regression comparison between runs with the same seed.
static func transcript(st: GameState) -> Array:
    var out: Array = []
    for e in st.events:
        var d: Dictionary = e
        var msg := String(d.get("message", ""))
        if msg != "":
            out.append("%04d R%d %s | %s" % [int(d.get("n", 0)), int(d.get("round", 0)),
                String(d.get("phase", "")), msg])
    return out
