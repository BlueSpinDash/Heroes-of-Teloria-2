class_name Observation
extends RefCounted

## What the AI is allowed to know.
##
## The policy never receives the human's hand contents, either player's Hit
## order, cards sampled from a Hit Deck, or the match's hidden RNG state. It
## does receive its own hand, every public zone, visible resources, deck counts
## and the public event history — and it may reason from a known deck theme,
## which is public information about an authored opponent.
##
## `sanitized_clone` is the forward model the policy searches with. Hidden
## information is destroyed there rather than merely ignored, so a bug in the
## policy cannot start exploiting it.

const UNKNOWN := "?"


## The AI's permitted view of the match, as plain data.
static func build(state: GameState, me: int) -> Dictionary:
    var opp := state.opponent_of(me)
    var mine := state.player(me)
    var theirs := state.player(opp)

    var my_hand: Array = []
    for iid in mine.hand:
        var cd := state.def_of(String(iid))
        my_hand.append({
            "iid": String(iid), "def_id": cd.id if cd != null else UNKNOWN,
            "name": cd.name if cd != null else UNKNOWN,
        })

    return {
        "me": me,
        "round": state.round_number,
        "phase": state.phase,
        "first_player": state.first_player,
        "action_priority": state.action_priority,
        "my_hand": my_hand,
        # Only the COUNT of the opponent's hand is visible, never its contents.
        "opponent_hand_count": theirs.hand.size(),
        "my_deck_counts": {"hit": mine.hit.size(), "exhaust": mine.exhaust.size(),
            "wound": mine.wound.size()},
        "opponent_deck_counts": {"hit": theirs.hit.size(), "exhaust": theirs.exhaust.size(),
            "wound": theirs.wound.size()},
        "my_energy": {"current": mine.energy_current, "max": state.energy_max(me)},
        "opponent_energy": {"current": theirs.energy_current, "max": state.energy_max(opp)},
        "my_hero": _character(state, mine.hero_iid),
        "opponent_hero": _character(state, theirs.hero_iid),
        "my_companions": _characters(state, mine.companions),
        "opponent_companions": _characters(state, theirs.companions),
        "location": _public_card(state, state.location_iid),
        # Exhaust and Wound are public zones and may be inspected.
        "my_exhaust": _public_cards(state, mine.exhaust),
        "opponent_exhaust": _public_cards(state, theirs.exhaust),
        "sequence": _sequence(state),
        "current_step": state.current_step,
        "my_passed": mine.passed_actions,
        "opponent_passed": theirs.passed_actions,
        "my_committed_characters": mine.committed_characters.duplicate(),
        "opponent_committed_characters": theirs.committed_characters.duplicate(),
        "opponent_deck_theme": theirs.affinity_profile,
        "public_events": _public_events(state),
        "pending": state.pending.duplicate(true) if state.pending is Dictionary else null,
    }


static func _character(state: GameState, iid: String) -> Dictionary:
    var cd := state.def_of(iid)
    if cd == null:
        return {}
    var ci := state.inst(iid)
    return {
        "iid": iid, "def_id": cd.id, "name": cd.name,
        "attack": state.current_attack(iid), "defense": state.current_defense(iid),
        "affinities": cd.affinities.duplicate(),
        "equipment": _public_card(state, ci.equipment_iid),
        "taahma": _public_card(state, ci.taahma_iid),
        "shield": ci.shield_total(),
        "deployed_round": ci.deployed_round,
        "energy_contribution": cd.energy_contribution,
    }


static func _characters(state: GameState, iids: Array) -> Array:
    var out: Array = []
    for iid in iids:
        out.append(_character(state, String(iid)))
    return out


static func _public_card(state: GameState, iid: String) -> Dictionary:
    if iid == "":
        return {}
    var cd := state.def_of(iid)
    if cd == null:
        return {}
    return {"iid": iid, "def_id": cd.id, "name": cd.name, "types": cd.types.duplicate(),
        "affinities": cd.affinities.duplicate()}


static func _public_cards(state: GameState, iids: Array) -> Array:
    var out: Array = []
    for iid in iids:
        out.append(_public_card(state, String(iid)))
    return out


static func _sequence(state: GameState) -> Array:
    var out: Array = []
    for s in state.sequence:
        var slot: ActionSlot = s
        out.append({
            "slot_id": slot.slot_id, "controller": slot.controller, "kind": slot.kind,
            "card": _public_card(state, slot.card_iid),
            "attacker": _public_card(state, slot.attacker_iid),
            "targets": slot.targets.duplicate(),
            "affinities": slot.affinities.duplicate(),
            "x_paid": slot.x_paid, "resolved": slot.resolved,
            "reactions": slot.reactions.size(),
        })
    return out


## Public event history. Nothing here names a card that is still hidden.
static func _public_events(state: GameState, limit: int = 60) -> Array:
    var out: Array = []
    var src: Array = state.events
    if src.size() > limit:
        src = src.slice(src.size() - limit, src.size())
    for e in src:
        out.append({"kind": String((e as Dictionary).get("kind", "")),
            "round": int((e as Dictionary).get("round", 0))})
    return out


## A forward model with hidden information destroyed.
##
##  * both Hit Decks are reshuffled with the AI's own stream, so no policy can
##    read a draw order it is not entitled to know;
##  * the opponent's hand is replaced with plausible cards drawn from its known
##    deck theme, keeping only the visible card count;
##  * the match RNG is replaced with a stream seeded from the AI's search seed.
static func sanitized_clone(state: GameState, me: int, search_seed: int) -> GameState:
    var clone := state.clone_for_search()
    clone.rng = HotRng.new(search_seed)
    var opp := clone.opponent_of(me)

    for i in 2:
        var p := clone.player(i)
        p.hit = clone.rng.shuffled("sanitize_hit_%d" % i, p.hit)

    # Replace the opponent's hand with cards it plausibly holds. The candidates
    # come from its Hit and Exhaust piles, which is the public deck theme, not
    # the actual cards in hand.
    var theirs := clone.player(opp)
    var hand_size := theirs.hand.size()
    if hand_size > 0:
        var pool: Array = theirs.hit.duplicate()
        pool.append_array(theirs.exhaust)
        pool = clone.rng.shuffled("sanitize_hand", pool)
        var replacements: Array = []
        for iid in theirs.hand:
            var placeholder := String(iid)
            if not pool.is_empty():
                var donor := String(pool.pop_back())
                var donor_def := clone.inst(donor)
                var target := clone.inst(placeholder)
                if donor_def != null and target != null:
                    # Keep the instance identity, swap in a plausible definition.
                    target.def_id = donor_def.def_id
                    target.def_rev = donor_def.def_rev
            replacements.append(placeholder)
        theirs.hand = replacements
    return clone
