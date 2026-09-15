class_name AffinityChain
extends RefCounted

## The replaceable Affinity-chain evaluator.
##
## Provisional interpretation (see PROVISIONAL_RULES.md):
##   * only normal committed Action slots supply membership, attacks included;
##   * an attack uses its character's Affinities as captured on commitment;
##   * Reactions attach to a slot but never join or break the chain;
##   * differing Affinities do not break a contiguous Affinity-bearing run;
##   * a slot with no Affinity breaks the run and cannot start one;
##   * evaluation at slot K reads the contiguous run ending at K inclusive and
##     never looks at later slots;
##   * slot records survive their cards leaving the physical Sequence.
##
## Nothing here awards anything by itself: individual cards state their own
## thresholds and rewards.


## The contiguous Affinity-bearing run of slots ending at `up_to_index`
## inclusive, oldest first. Empty when that slot carries no Affinity.
static func run_ending_at(state: GameState, up_to_index: int) -> Array:
    var out: Array = []
    if up_to_index < 0 or up_to_index >= state.sequence.size():
        return out
    var i := up_to_index
    while i >= 0:
        var slot: ActionSlot = state.sequence[i]
        if not slot.has_affinity():
            break
        out.push_front(slot)
        i -= 1
    return out


## Count slots in the run matching an Affinity filter and a scope, relative to
## the player evaluating the effect.
##   affinity: an Affinity name, or "any"
##   scope:    "either" | "controller" | "opponent"
static func count(state: GameState, up_to_index: int, affinity: String, scope: String, evaluator: int) -> int:
    var n := 0
    for slot in run_ending_at(state, up_to_index):
        var s: ActionSlot = slot
        if scope == "controller" and s.controller != evaluator:
            continue
        if scope == "opponent" and s.controller == evaluator:
            continue
        if affinity == "any" or s.affinities.has(affinity):
            n += 1
    return n


## Human-readable summary for the battle screen's chain inspector.
static func describe(state: GameState, up_to_index: int) -> String:
    var run := run_ending_at(state, up_to_index)
    if run.is_empty():
        return "No chain (this Action carries no Affinity)."
    var bits: Array = []
    for slot in run:
        var s: ActionSlot = slot
        var labels: Array = []
        for a in s.affinities:
            labels.append(String(a).capitalize())
        bits.append("P%d %s" % [s.controller + 1, "/".join(labels)])
    return "Chain of %d: %s" % [run.size(), " → ".join(bits)]
