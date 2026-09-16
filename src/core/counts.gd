class_name Counts
extends RefCounted

## Every quantity a card can read off the match as it stands.
##
## A card that says "for each" needs a number the engine works out at the
## moment it is read, and three places read them: the effect interpreter, the
## aura evaluator on GameState, and the rules-text generator (which describes
## them rather than counting them). This holds the counting so all three agree,
## and so an aura can scale the same way a one-shot effect does.
##
## The vocabulary itself is declared in EffectSchema, which is what validation
## checks a card against.


## A dynamic amount, or a plain number.
##
##   ctx: {"controller": int, "slot_index": int, "x_paid": int, "self_iid": String}
static func amount(state: GameState, spec, ctx: Dictionary) -> int:
    if spec == null:
        return 0
    if spec is int or spec is float:
        return int(spec)
    if not (spec is Dictionary):
        return 0
    var controller: int = int(ctx.get("controller", 0))
    var base := 0
    match String(spec.get("from", "")):
        "x":
            base = int(ctx.get("x_paid", 0))
        "chain_count":
            base = AffinityChain.count(state, int(ctx.get("slot_index", 0)),
                String(spec.get("affinity", "any")), String(spec.get("scope", "either")),
                controller)
        "count":
            base = _count(state, spec, ctx, controller)
    if spec.has("multiplier"):
        base = int(floor(float(base) * float(spec["multiplier"])))
    if spec.has("plus"):
        base += int(spec["plus"])
    return max(0, base)


static func _count(state: GameState, spec: Dictionary, ctx: Dictionary, controller: int) -> int:
    var opp := state.opponent_of(controller)
    match String(spec.get("of", "")):
        "own_companions": return _in(state, spec, state.player(controller).companions)
        "opponent_companions": return _in(state, spec, state.player(opp).companions)
        "own_hand": return _in(state, spec, state.player(controller).hand)
        "opponent_hand": return _in(state, spec, state.player(opp).hand)
        "own_exhaust": return _in(state, spec, state.player(controller).exhaust)
        "opponent_exhaust": return _in(state, spec, state.player(opp).exhaust)
        "own_wound": return _in(state, spec, state.player(controller).wound)
        "opponent_wound": return _in(state, spec, state.player(opp).wound)
        "resolved_before": return _resolved_before(state, spec, ctx, controller)
        "attackers_in_sequence": return _in_sequence(state, spec, controller, true)
        "characters_in_sequence": return _in_sequence(state, spec, controller, false)
        "copies_in_play": return _copies_in_play(state, ctx, controller)
    return 0


## How many of these cards match the spec's filters. A spec with no filters
## counts the pile, which is what the plain counts have always meant.
static func _in(state: GameState, spec: Dictionary, pile: Array) -> int:
    var types: Array = spec.get("types", [])
    var affinity := String(spec.get("affinity", ""))
    if types.is_empty() and affinity == "":
        return pile.size()
    var n := 0
    for iid in pile:
        var cd := state.def_of(String(iid))
        if cd == null:
            continue
        if affinity != "" and not cd.affinities.has(affinity):
            continue
        if not types.is_empty() and not _any_type(cd, types):
            continue
        n += 1
    return n


static func _any_type(cd: CardDef, types: Array) -> bool:
    for t in types:
        if cd.has_type(String(t)):
            return true
    return false


## Slots of the Action Sequence that resolved before the one being read.
##
## The Sequence resolves in order, so every slot earlier than this one has
## already happened and no later one has: it is the round's own record, and it
## needs no separate bookkeeping to stay right.
static func _resolved_before(state: GameState, spec: Dictionary, ctx: Dictionary,
        evaluator: int) -> int:
    var up_to: int = int(ctx.get("slot_index", 0))
    var types: Array = spec.get("types", [])
    var affinity := String(spec.get("affinity", ""))
    var scope := String(spec.get("scope", "either"))
    var n := 0
    for i in mini(up_to, state.sequence.size()):
        var slot: ActionSlot = state.sequence[i]
        if not _scope_ok(scope, slot.controller, evaluator):
            continue
        if slot.card_iid == "":
            continue
        var cd := state.def_of(slot.card_iid)
        if cd == null:
            continue
        if affinity != "" and not cd.affinities.has(affinity):
            continue
        if not types.is_empty() and not _any_type(cd, types):
            continue
        n += 1
    return n


## Characters standing in the Action Sequence, either every one of them or
## only those committed to an attack.
static func _in_sequence(state: GameState, spec: Dictionary, evaluator: int,
        attacking_only: bool) -> int:
    var scope := String(spec.get("scope", "either"))
    var seen := {}
    for slot in state.sequence:
        var s: ActionSlot = slot
        if not _scope_ok(scope, s.controller, evaluator):
            continue
        var who := s.attacker_iid
        if who == "":
            if attacking_only:
                continue
            # A committed card is not a character standing in the Sequence
            # unless it is the character itself being played.
            var cd := state.def_of(s.card_iid)
            if cd == null or not cd.is_character():
                continue
            who = s.card_iid
        if who != "":
            seen[who] = true
    return seen.size()


## How many copies of the reading card its controller has in play, itself
## included. Named cards that stack read this.
static func _copies_in_play(state: GameState, ctx: Dictionary, controller: int) -> int:
    var self_iid := String(ctx.get("self_iid", ""))
    if self_iid == "":
        return 0
    var mine := state.def_of(self_iid)
    if mine == null:
        return 0
    var n := 0
    for ciid in state.player(controller).companions:
        var cd := state.def_of(String(ciid))
        if cd != null and cd.id == mine.id:
            n += 1
    return n


static func _scope_ok(scope: String, owner: int, evaluator: int) -> bool:
    match scope:
        "controller": return owner == evaluator
        "opponent": return owner != evaluator
    return true
