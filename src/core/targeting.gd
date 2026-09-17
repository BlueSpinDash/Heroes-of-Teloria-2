class_name Targeting
extends RefCounted

## Legality of target choices. Targets are chosen on commitment and
## revalidated on resolution; an invalid target makes its component do
## nothing, with no retarget and no refund.


## Targets a card may choose.
##
## `filter` is the card's own target block, which may narrow the list further
## than its kind does: a Ta'ahma written for one named character attaches to
## that character and to nothing else.
static func legal_targets(state: GameState, kind: String, chooser: int,
        filter: Dictionary = {}) -> Array:
    return _narrow(state, _of_kind(state, kind, chooser), filter)


static func _narrow(state: GameState, iids: Array, filter: Dictionary) -> Array:
    var character_id := String(filter.get("character_id", ""))
    if character_id == "":
        return iids
    var out: Array = []
    for iid in iids:
        var cd := state.def_of(String(iid))
        if cd != null and cd.character_id == character_id:
            out.append(String(iid))
    return out


static func _of_kind(state: GameState, kind: String, chooser: int) -> Array:
    var opp := state.opponent_of(chooser)
    match kind:
        "own_companion":
            return state.player(chooser).companions.duplicate()
        "opponent_companion":
            return state.player(opp).companions.duplicate()
        "any_companion":
            return state.player(chooser).companions + state.player(opp).companions
        "own_character":
            return [state.player(chooser).hero_iid] + state.player(chooser).companions
        "opponent_character":
            return [state.player(opp).hero_iid] + state.player(opp).companions
        "any_character":
            return [state.player(chooser).hero_iid] + state.player(chooser).companions \
                + [state.player(opp).hero_iid] + state.player(opp).companions
        "own_character_host":
            return [state.player(chooser).hero_iid] + state.player(chooser).companions
        "own_equipment":
            return _attachments(state, "equipment", chooser)
        "opponent_equipment":
            return _attachments(state, "equipment", opp)
        "any_equipment":
            return _attachments(state, "equipment", -1)
        "own_taahma":
            return _attachments(state, "taahma", chooser)
        "opponent_taahma":
            return _attachments(state, "taahma", opp)
        "any_taahma":
            return _attachments(state, "taahma", -1)
        "location":
            return [state.location_iid] if state.location_iid != "" else []
    return []


static func _attachments(state: GameState, slot: String, controller: int) -> Array:
    var out: Array = []
    for i in 2:
        if controller >= 0 and i != controller:
            continue
        var p := state.player(i)
        var hosts: Array = [p.hero_iid]
        hosts.append_array(p.companions)
        for host_iid in hosts:
            var host := state.inst(String(host_iid))
            if host == null:
                continue
            var a := host.equipment_iid if slot == "equipment" else host.taahma_iid
            if a != "":
                out.append(a)
    out.sort()
    return out


static func is_valid(state: GameState, kind: String, chooser: int, iid: String,
        filter: Dictionary = {}) -> bool:
    return legal_targets(state, kind, chooser, filter).has(iid)


## Attacks may freely target the opposing Hero or any opposing Companion.
## Equipment, Locations and Ta'ahma are never default attack targets and
## there is no universal blocking or Hero protection.
static func legal_attack_targets(state: GameState, attacker_controller: int) -> Array:
    var opp := state.opponent_of(attacker_controller)
    var out: Array = [state.player(opp).hero_iid]
    out.append_array(state.player(opp).companions)
    return out


## A short reason a choice is illegal, for the "explain why" requirement.
static func explain_invalid(state: GameState, kind: String, chooser: int, iid: String,
        filter: Dictionary = {}) -> String:
    var named := String(filter.get("character_id", ""))
    if named != "":
        var named_def := state.def_of(iid)
        if named_def == null or named_def.character_id != named:
            return "This card attaches only to %s." % named.capitalize()
    var ci := state.inst(iid)
    if ci == null:
        return "That card is no longer in the match."
    var cd := state.def_of(iid)
    var label := cd.name if cd != null else iid
    if ci.zone == "wound":
        return "%s is already in a Wound Deck." % label
    if ci.zone == "exhaust":
        return "%s is in an Exhaust Deck, not in play." % label
    if kind.begins_with("own") and ci.controller != chooser:
        return "%s is not yours to target with this effect." % label
    if kind.begins_with("opponent") and ci.controller == chooser:
        return "%s is yours; this effect targets your opponent's cards." % label
    return "%s is not a legal target for this effect." % label
