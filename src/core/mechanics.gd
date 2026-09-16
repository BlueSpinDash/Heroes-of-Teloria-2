class_name Mechanics
extends RefCounted

## Low-level rules primitives: draws, Hero damage, destruction destinations,
## Energy bookkeeping and loss checks.
##
## These functions only raise trigger events onto state.trigger_events; they
## never execute card effects themselves. The effect runner drains that queue,
## which keeps this module free of dependencies on the interpreter.


# ------------------------------------------------------------------- energy ---

static func clamp_energy(state: GameState, pi: int) -> void:
    var p := state.player(pi)
    var cap := state.energy_max(pi)
    if p.energy_current > cap:
        var before := p.energy_current
        p.energy_current = cap
        state.emit("energy_clamped", {
            "player": pi, "from": before, "to": cap,
            "message": "P%d Energy clamped from %d to %d (maximum fell)." % [pi + 1, before, cap]})


static func pay_energy(state: GameState, pi: int, amount: int) -> bool:
    if amount < 0:
        return false
    var p := state.player(pi)
    if p.energy_current < amount:
        return false
    p.energy_current -= amount
    if amount > 0:
        state.emit("energy_spent", {
            "player": pi, "amount": amount, "left": p.energy_current,
            "message": "P%d spends %d Energy (%d left)." % [pi + 1, amount, p.energy_current]})
    return true


## Gains, generation and refunds all restore spent Energy up to the current
## maximum. They never raise the maximum by themselves.
static func gain_energy(state: GameState, pi: int, amount: int, reason: String = "") -> int:
    if amount <= 0:
        return 0
    var p := state.player(pi)
    var cap := state.energy_max(pi)
    var before := p.energy_current
    p.energy_current = min(cap, p.energy_current + amount)
    var gained := p.energy_current - before
    state.emit("energy_gained", {
        "player": pi, "requested": amount, "gained": gained, "now": p.energy_current, "reason": reason,
        "message": "P%d gains %d Energy%s (%d/%d)." % [
            pi + 1, gained, (" from %s" % reason) if reason != "" else "", p.energy_current, cap]})
    return gained


static func drain_energy(state: GameState, pi: int, amount: int) -> int:
    if amount <= 0:
        return 0
    var p := state.player(pi)
    var lost: int = min(p.energy_current, amount)
    p.energy_current -= lost
    state.emit("energy_drained", {
        "player": pi, "amount": lost, "now": p.energy_current,
        "message": "P%d loses %d Energy (%d left)." % [pi + 1, lost, p.energy_current]})
    return lost


static func add_energy_max_mod(state: GameState, pi: int, amount: int, duration: String) -> void:
    if amount == 0:
        return
    state.player(pi).energy_max_mods.append({"amount": amount, "expires": duration})
    state.emit("energy_max_changed", {
        "player": pi, "amount": amount, "duration": duration, "now": state.energy_max(pi),
        "message": "P%d maximum Energy %s%d (now %d)." % [pi + 1, "+" if amount > 0 else "", amount, state.energy_max(pi)]})
    clamp_energy(state, pi)


# ------------------------------------------------------------------- drawing ---

## Draw one card. Returns false when Hit plus Exhaust cannot supply it, which
## is the moment a required draw fails.
static func draw_one(state: GameState, pi: int) -> bool:
    var p := state.player(pi)
    if p.hit.is_empty():
        if p.exhaust.is_empty():
            return false
        _recycle_exhaust(state, pi)
    if p.hit.is_empty():
        return false
    var iid := String(p.hit[0])
    state.move_to_pile(iid, "hand")
    return true


static func _recycle_exhaust(state: GameState, pi: int) -> void:
    var p := state.player(pi)
    var moved := p.exhaust.duplicate()
    for iid in moved:
        var ci := state.inst(String(iid))
        if ci != null:
            ci.zone = "hit"
    p.hit = state.rng.shuffled("shuffle_p%d" % pi, moved)
    p.exhaust = []
    state.emit("exhaust_recycled", {
        "player": pi, "count": p.hit.size(),
        "message": "P%d Hit Deck was empty; %d Exhaust cards were shuffled into a new Hit Deck." % [pi + 1, p.hit.size()]})


## A required draw of `count` cards. Returns true when fully satisfied.
## Wound never joins the ordinary reshuffle and cards in hand or in play can
## never satisfy this requirement.
static func required_draw(state: GameState, pi: int, count: int) -> bool:
    var drawn := 0
    for _i in count:
        if not draw_one(state, pi):
            state.emit("draw_failed", {
                "player": pi, "requested": count, "drawn": drawn,
                "message": "P%d could not complete a required draw (%d of %d)." % [pi + 1, drawn, count]})
            return false
        drawn += 1
    if drawn > 0:
        state.emit("drew", {
            "player": pi, "count": drawn,
            "message": "P%d draws %d card%s." % [pi + 1, drawn, "" if drawn == 1 else "s"]})
    return true


## Best-effort draw used by card effects that are not a required draw.
static func draw_up_to(state: GameState, pi: int, count: int) -> int:
    var drawn := 0
    for _i in count:
        if not draw_one(state, pi):
            break
        drawn += 1
    if drawn > 0:
        state.emit("drew", {
            "player": pi, "count": drawn,
            "message": "P%d draws %d card%s." % [pi + 1, drawn, "" if drawn == 1 else "s"]})
    return drawn


# -------------------------------------------------------------- Hero damage ---

## Apply N positive damage to a player's Hero.
##
## Damage removes cards: up to N random cards from Exhaust first, then the
## remainder at random from Hit, with no reshuffle during the operation. If
## Hit plus Exhaust cannot supply the full amount, that player loses.
static func hero_damage(state: GameState, pi: int, amount: int, source_label: String = "") -> int:
    if amount <= 0:
        return 0
    var hero := state.hero_of(pi)
    var incoming := amount
    if hero != null and hero.shield_total() > 0:
        incoming = _consume_shields(state, hero, incoming)
        if incoming <= 0:
            state.emit("damage_prevented", {
                "player": pi, "amount": amount,
                "message": "All %d damage to P%d's Hero was prevented." % [amount, pi + 1]})
            return 0
    var p := state.player(pi)
    var from_exhaust: int = min(incoming, p.exhaust.size())
    var taken_exhaust := state.rng.take_random("hero_damage_p%d" % pi, p.exhaust, from_exhaust)
    for iid in taken_exhaust:
        var ci := state.inst(String(iid))
        if ci != null:
            ci.zone = "wound"
        p.wound.append(iid)
    var remaining := incoming - from_exhaust
    var from_hit: int = min(remaining, p.hit.size())
    var taken_hit := state.rng.take_random("hero_damage_p%d" % pi, p.hit, from_hit)
    for iid in taken_hit:
        var ci2 := state.inst(String(iid))
        if ci2 != null:
            ci2.zone = "wound"
        p.wound.append(iid)

    var supplied := from_exhaust + from_hit
    state.emit("hero_damaged", {
        "player": pi, "amount": incoming, "from_exhaust": from_exhaust, "from_hit": from_hit,
        "source": source_label,
        "message": "P%d's Hero takes %d damage%s: %d card%s Wounded from Exhaust, %d from Hit." % [
            pi + 1, incoming, (" from %s" % source_label) if source_label != "" else "",
            from_exhaust, "" if from_exhaust == 1 else "s", from_hit]})

    state.trigger_events.append({"kind": "hero_damaged", "player": pi, "amount": incoming})

    if supplied < incoming:
        state.emit("damage_unsatisfied", {
            "player": pi, "required": incoming, "supplied": supplied,
            "message": "P%d's Hit and Exhaust Decks could not supply %d damage (%d available)." % [
                pi + 1, incoming, supplied]})
        mark_failure(state, pi, "Hero damage could not be fully absorbed by Hit plus Exhaust.")
    return supplied


static func _consume_shields(state: GameState, target: CardInstance, incoming: int) -> int:
    var left := incoming
    var kept: Array = []
    for s in target.shields:
        var amount := int(s.get("amount", 0))
        if left <= 0:
            kept.append(s)
            continue
        var used: int = min(left, amount)
        left -= used
        if amount - used > 0:
            var partial: Dictionary = (s as Dictionary).duplicate()
            partial["amount"] = amount - used
            kept.append(partial)
    target.shields = kept
    if left < incoming:
        state.emit("damage_prevented", {
            "target": target.iid, "prevented": incoming - left,
            "message": "%d damage was prevented." % (incoming - left)})
    return left


## Direct damage to a character. Companions are destroyed by any positive
## damage; damage never accumulates as hit points.
static func damage_character(state: GameState, target_iid: String, amount: int, ignores_defense: bool, source_label: String = "") -> void:
    var ci := state.inst(target_iid)
    if ci == null:
        return
    var cd := state.def_of(target_iid)
    var label := cd.name if cd != null else target_iid
    var dealt := amount
    if not ignores_defense:
        dealt = max(0, amount - state.current_defense(target_iid))
    if ci.shield_total() > 0:
        dealt = _consume_shields(state, ci, dealt)
    if ci.zone == "hero":
        hero_damage(state, ci.controller, dealt, source_label)
        return
    if dealt <= 0:
        state.emit("no_damage", {
            "target": target_iid,
            "message": "%s takes no damage and is not destroyed." % label})
        return
    state.emit("companion_damaged", {
        "target": target_iid, "amount": dealt,
        "message": "%s takes %d damage." % [label, dealt]})
    destroy(state, target_iid, "damage")


# --------------------------------------------------------------- destruction ---

## Explicit destruction. Companions, Equipment, Ta'ahma and Locations all go
## to their owner's Wound Deck when destroyed.
static func destroy(state: GameState, iid: String, reason: String = "") -> void:
    var ci := state.inst(iid)
    if ci == null:
        return
    var cd := state.def_of(iid)
    var label := cd.name if cd != null else iid
    if ci.zone == "hero":
        # A Hero is never destroyed; there is no Hero health total.
        return
    if not ["companions", "attached", "location"].has(ci.zone):
        return
    _release_attachments(state, iid, "exhaust")
    state.trigger_events.append({"kind": "leaves_play", "iid": iid, "controller": ci.controller})
    # Destruction is also the way a card in play enters its owner's Wound
    # Deck, which is a different thing from leaving play: replacement and a
    # bounce send a card to Exhaust and to hand instead.
    state.trigger_events.append({"kind": "wounded", "iid": iid, "controller": ci.controller})
    var was_companion := ci.zone == "companions"
    var controller := ci.controller
    state.move_to_pile(iid, "wound")
    state.emit("destroyed", {
        "iid": iid, "reason": reason, "owner": ci.owner,
        "message": "%s is destroyed and goes to P%d's Wound Deck." % [label, ci.owner + 1]})
    if was_companion:
        # A Companion leaving play removes its maximum-Energy contribution
        # immediately, and current Energy is clamped at once.
        clamp_energy(state, controller)


## Replacement (a new Equipment, Ta'ahma or Location taking the old one's
## place) sends the previous card to its owner's Exhaust Deck, not Wound.
static func replace_out(state: GameState, iid: String) -> void:
    var ci := state.inst(iid)
    if ci == null:
        return
    var cd := state.def_of(iid)
    var label := cd.name if cd != null else iid
    _release_attachments(state, iid, "exhaust")
    state.trigger_events.append({"kind": "leaves_play", "iid": iid, "controller": ci.controller})
    var owner := ci.owner
    state.move_to_pile(iid, "exhaust")
    state.emit("replaced", {
        "iid": iid,
        "message": "%s is replaced and goes to P%d's Exhaust Deck." % [label, owner + 1]})


## Return a Companion to its owner's hand.
static func bounce(state: GameState, iid: String) -> void:
    var ci := state.inst(iid)
    if ci == null or ci.zone != "companions":
        return
    var cd := state.def_of(iid)
    var label := cd.name if cd != null else iid
    var controller := ci.controller
    _release_attachments(state, iid, "exhaust")
    state.trigger_events.append({"kind": "leaves_play", "iid": iid, "controller": controller})
    ci.deployed_round = -1
    ci.mods = []
    ci.shields = []
    state.move_to_pile(iid, "hand")
    state.emit("bounced", {
        "iid": iid,
        "message": "%s returns to P%d's hand." % [label, ci.owner + 1]})
    clamp_energy(state, controller)


## Provisional: when a host leaves play its attachments go to their owners'
## Exhaust Decks unless card text explicitly destroys or redirects them.
static func _release_attachments(state: GameState, host_iid: String, destination: String) -> void:
    for a_iid in state.attachments_of(host_iid):
        var ad := state.def_of(String(a_iid))
        var alabel := ad.name if ad != null else String(a_iid)
        var a_ci := state.inst(String(a_iid))
        state.trigger_events.append({"kind": "leaves_play", "iid": String(a_iid), "controller": a_ci.controller})
        state.move_to_pile(String(a_iid), destination)
        state.emit("attachment_released", {
            "iid": a_iid, "host": host_iid, "destination": destination,
            "message": "%s loses its host and goes to P%d's %s Deck." % [
                alabel, a_ci.owner + 1, destination.capitalize()]})


## A non-persistent card that finished resolving goes to its owner's Exhaust.
static func exhaust_resolved(state: GameState, iid: String) -> void:
    var ci := state.inst(iid)
    if ci == null:
        return
    var cd := state.def_of(iid)
    var label := cd.name if cd != null else iid
    state.move_to_pile(iid, "exhaust")
    state.emit("to_exhaust", {
        "iid": iid,
        "message": "%s goes to P%d's Exhaust Deck." % [label, ci.owner + 1]})


static func exhaust_from_hand(state: GameState, pi: int, iids: Array) -> void:
    for iid in iids:
        var ci := state.inst(String(iid))
        if ci == null or ci.zone != "hand":
            continue
        var cd := state.def_of(String(iid))
        state.move_to_pile(String(iid), "exhaust")
        state.emit("hand_exhausted", {
            "player": pi, "iid": iid,
            "message": "P%d Exhausts %s from hand." % [pi + 1, cd.name if cd != null else String(iid)]})


static func mill(state: GameState, pi: int, count: int) -> int:
    var p := state.player(pi)
    var moved := 0
    for _i in count:
        if p.hit.is_empty():
            break
        state.move_to_pile(String(p.hit[0]), "exhaust")
        moved += 1
    if moved > 0:
        state.emit("milled", {
            "player": pi, "count": moved,
            "message": "P%d moves %d card%s from Hit to Exhaust." % [pi + 1, moved, "" if moved == 1 else "s"]})
    return moved


# ----------------------------------------------------------------- deployment ---

## Put a Companion into play. Its maximum-Energy contribution starts applying
## now; it is granted no current Energy on entry.
static func deploy_companion(state: GameState, iid: String, controller: int) -> void:
    var cd := state.def_of(iid)
    if cd == null:
        return
    state.move_to_companions(iid, controller)
    state.stamp_entry(iid)
    var ci := state.inst(iid)
    ci.deployed_round = state.round_number
    state.emit("deployed", {
        "iid": iid, "player": controller, "max": state.energy_max(controller),
        "message": "%s enters play for P%d (maximum Energy now %d)." % [
            cd.name, controller + 1, state.energy_max(controller)]})
    state.trigger_events.append({"kind": "companion_deployed", "iid": iid, "controller": controller})


static func attach_card(state: GameState, iid: String, host_iid: String) -> void:
    var cd := state.def_of(iid)
    if cd == null:
        return
    var slot := cd.attachment_slot()
    var host := state.inst(host_iid)
    if host == null:
        return
    var existing := host.equipment_iid if slot == "equipment" else host.taahma_iid
    if existing != "":
        replace_out(state, existing)
    state.attach(iid, host_iid, slot)
    state.stamp_entry(iid)
    var hd := state.def_of(host_iid)
    state.emit("attached", {
        "iid": iid, "host": host_iid,
        "message": "%s attaches to %s." % [cd.name, hd.name if hd != null else host_iid]})


static func place_location(state: GameState, iid: String) -> void:
    var cd := state.def_of(iid)
    if cd == null:
        return
    if state.location_iid != "" and state.location_iid != iid:
        replace_out(state, state.location_iid)
    state.place_location(iid)
    state.stamp_entry(iid)
    state.emit("location_placed", {
        "iid": iid,
        "message": "%s becomes the active Location." % cd.name})


# ------------------------------------------------------------- loss handling ---

## Record that a player has failed a requirement. The result is only decided
## at a resolution boundary so simultaneous failures can be compared fairly.
static func mark_failure(state: GameState, pi: int, reason: String) -> void:
    if state.pending_failures == null:
        state.pending_failures = {}
    if not state.pending_failures.has(pi):
        state.pending_failures[pi] = reason
        state.emit("failure_recorded", {
            "player": pi, "reason": reason,
            "message": "P%d cannot meet a requirement: %s" % [pi + 1, reason]})


## Resolve any recorded failures into a match result. Both players failing at
## the same boundary is a draw under the provisional profile.
static func settle_failures(state: GameState) -> bool:
    if state.result != null:
        return true
    if state.pending_failures == null or state.pending_failures.is_empty():
        return false
    var failed: Array = state.pending_failures.keys()
    failed.sort()
    if failed.size() >= 2:
        state.result = {"winner": -1, "reason": "Both players failed a requirement at the same boundary."}
        state.emit("match_ended", {
            "winner": -1,
            "message": "The match is a draw: both players failed a requirement simultaneously."})
    else:
        var loser := int(failed[0])
        var reason := String(state.pending_failures[loser])
        state.result = {"winner": state.opponent_of(loser), "reason": reason, "loser": loser}
        state.emit("match_ended", {
            "winner": state.opponent_of(loser), "loser": loser, "reason": reason,
            "message": "P%d loses: %s" % [loser + 1, reason]})
    state.pending_failures = {}
    state.phase = "ended"
    return true


static func concede(state: GameState, pi: int) -> void:
    if state.result != null:
        return
    state.result = {"winner": state.opponent_of(pi), "reason": "P%d conceded." % (pi + 1), "loser": pi, "conceded": true}
    state.phase = "ended"
    state.emit("match_ended", {
        "winner": state.opponent_of(pi), "loser": pi, "conceded": true,
        "message": "P%d concedes the match." % (pi + 1)})
