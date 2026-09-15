class_name GameState
extends RefCounted

## The single authoritative match state.
##
## The UI renders this and submits commands; it never keeps its own copy of
## the rules. A match is fully serialisable, including its RNG streams and the
## frozen card definitions it started with, so it can be resumed exactly.

const PHASES := ["draw", "action", "resolve", "round_end", "ended"]

var match_id: String = ""
var rules_stamp: Dictionary = {}
var catalog: Catalog = null          # frozen for the duration of the match
var rules: RulesProfile = null
var rng: HotRng = null

var round_number: int = 0
var phase: String = "draw"
## Player index that acts first this round; also breaks trigger-order ties.
var first_player: int = 0
## Whose turn it is to commit an Action during the Action Phase.
var action_priority: int = 0

var players: Array = []              # Array[PlayerState], exactly 2
var instances: Dictionary = {}       # iid -> CardInstance
var counters: Dictionary = {}        # id-minting counters

## The shared Action Sequence for the current round, left to right.
var sequence: Array = []             # Array[ActionSlot]
var current_step: int = -1
## Resolved-slot records kept for chain inspection after cards leave the
## physical Sequence. One entry per round.
var round_history: Array = []

## The single shared Location field.
var location_iid: String = ""

## Characters actually inside the Action Sequence right now, as opposed to the
## historical slot records. A character joins on attack commitment and leaves
## after its own resolution triggers have finished.
var sequence_members: Array = []

## Player choices raised by a resolving card. They are presented at the end of
## the current step rather than interrupting mid-effect (provisional ruling).
var deferred_choices: Array = []

## A required choice blocking progress, or null.
var pending = null
## Live Reaction window: {"slot": int, "player": int, "passes": int} or null.
var reaction_window = null
## Terminal result: {"winner": int|-1, "reason": String} or null while playing.
var result = null
## Requirement failures recorded since the last boundary, player index ->
## reason. Gathered so simultaneous failures produce a draw rather than a
## race, then settled by Mechanics.settle_failures().
var pending_failures = {}

## Transient queue of trigger events raised by the primitive currently
## executing. Drained by the effect runner before the next primitive, so it is
## always empty at a save boundary.
var trigger_events: Array = []

var events: Array = []               # Array[Dictionary]
var event_seq: int = 0
## Set true while replaying a snapshot so events are not duplicated.
var silent: bool = false


## Guard against a card pair that retriggers each other forever. Reported as
## an engine guard in the log, never converted into a new defeat rule.
var trigger_depth_limit: int = 24


func _init() -> void:
    players = []


# ------------------------------------------------------------------ lookups ---

func player(i: int) -> PlayerState:
    return players[i]


func opponent_of(i: int) -> int:
    return 1 - i


func inst(iid: String) -> CardInstance:
    return instances.get(iid, null)


func def_of(iid: String) -> CardDef:
    var ci := inst(iid)
    if ci == null:
        return null
    return catalog.get_def(ci.def_id)


func hero_of(i: int) -> CardInstance:
    return inst(player(i).hero_iid)


func hero_def(i: int) -> CardDef:
    return def_of(player(i).hero_iid)


func location_def() -> CardDef:
    if location_iid == "":
        return null
    return def_of(location_iid)


func is_over() -> bool:
    return result != null


# ------------------------------------------------------- derived quantities ---

## Maximum Energy = the Hero's printed maximum, plus each in-play Companion's
## printed contribution, plus any active maximum-Energy modifiers (including
## auras from permanents). Never derived from any universal formula.
func energy_max(i: int) -> int:
    var p := player(i)
    var total := 0
    var hd := hero_def(i)
    if hd != null:
        total += hd.hero_max_energy
    for ciid in p.companions:
        var cd := def_of(ciid)
        if cd != null:
            total += cd.energy_contribution
    total += p.energy_max_mod_total()
    total += _aura_energy_max(i)
    return max(0, total)


func _aura_energy_max(i: int) -> int:
    var total := 0
    for iid in _permanent_sources():
        var ci := inst(iid)
        var cd := def_of(iid)
        if cd == null:
            continue
        for e in cd.effects:
            if not (e is Dictionary) or String(e.get("op", "")) != "aura_energy_max":
                continue
            var who := String(e.get("who", "self"))
            var target_player := ci.controller if who == "self" else opponent_of(ci.controller)
            if target_player == i:
                total += int(e.get("amount", 0))
    return total


## Every card currently in play that can host an aura: Companions, the active
## Location, and attachments.
func _permanent_sources() -> Array:
    var out: Array = []
    for p in players:
        out.append(p.hero_iid)
        for ciid in p.companions:
            out.append(ciid)
    if location_iid != "":
        out.append(location_iid)
    for iid in instances.keys():
        var ci: CardInstance = instances[iid]
        if ci.zone == "attached":
            out.append(iid)
    return out


func current_attack(iid: String) -> int:
    var ci := inst(iid)
    var cd := def_of(iid)
    if ci == null or cd == null:
        return 0
    return max(0, cd.attack + ci.mod_attack() + _aura_stat_for(iid, "attack"))


func current_defense(iid: String) -> int:
    var ci := inst(iid)
    var cd := def_of(iid)
    if ci == null or cd == null:
        return 0
    return max(0, cd.defense + ci.mod_defense() + _aura_stat_for(iid, "defense"))


func _aura_stat_for(iid: String, field: String) -> int:
    var target := inst(iid)
    if target == null:
        return 0
    var total := 0
    for src_iid in _permanent_sources():
        var src := inst(src_iid)
        var sd := def_of(src_iid)
        if src == null or sd == null:
            continue
        for e in sd.effects:
            if not (e is Dictionary) or String(e.get("op", "")) != "aura_stat_mod":
                continue
            if not e.has(field):
                continue
            if _aura_applies(src, String(e.get("scope", "")), target):
                total += int(e[field])
    return total


func _aura_applies(src: CardInstance, scope: String, target: CardInstance) -> bool:
    var sc := src.controller
    match scope:
        "host":
            return src.attached_to == target.iid
        "own_companions":
            return target.zone == "companions" and target.controller == sc
        "opponent_companions":
            return target.zone == "companions" and target.controller == opponent_of(sc)
        "all_companions":
            return target.zone == "companions"
        "own_hero":
            return target.zone == "hero" and target.controller == sc
        "opponent_hero":
            return target.zone == "hero" and target.controller == opponent_of(sc)
        "own_characters":
            return (target.zone == "hero" or target.zone == "companions") and target.controller == sc
        "opponent_characters":
            return (target.zone == "hero" or target.zone == "companions") and target.controller == opponent_of(sc)
    return false


func affinities_of_character(iid: String) -> Array:
    var cd := def_of(iid)
    if cd == null:
        return []
    return cd.affinities.duplicate()


# ------------------------------------------------------- zone bookkeeping ---

const PILE_ZONES := ["hand", "hit", "exhaust", "wound", "companions"]


func _remove_from_current_zone(ci: CardInstance) -> void:
    if PILE_ZONES.has(ci.zone):
        var arr: Array = player(ci.owner if ci.zone != "companions" else ci.controller).pile(ci.zone)
        var idx := arr.find(ci.iid)
        if idx >= 0:
            arr.remove_at(idx)
        else:
            # Companions are tracked under their controller; check both.
            for p in players:
                var a: Array = p.pile(ci.zone)
                var j := a.find(ci.iid)
                if j >= 0:
                    a.remove_at(j)
                    break
    elif ci.zone == "location":
        if location_iid == ci.iid:
            location_iid = ""
    elif ci.zone == "attached":
        var host := inst(ci.attached_to)
        if host != null:
            if host.equipment_iid == ci.iid:
                host.equipment_iid = ""
            if host.taahma_iid == ci.iid:
                host.taahma_iid = ""
        ci.attached_to = ""


## Move an instance to a pile owned by `to_player` (defaults to its owner).
## Cards returning to a pile always go to their owner's pile.
func move_to_pile(iid: String, zone: String, to_top: bool = false) -> void:
    var ci := inst(iid)
    if ci == null:
        return
    _remove_from_current_zone(ci)
    ci.zone = zone
    ci.attached_to = ""
    if zone != "companions":
        ci.controller = ci.owner
    var arr: Array = player(ci.owner).pile(zone)
    if to_top:
        arr.insert(0, iid)
    else:
        arr.append(iid)


func move_to_companions(iid: String, controller: int) -> void:
    var ci := inst(iid)
    if ci == null:
        return
    _remove_from_current_zone(ci)
    ci.zone = "companions"
    ci.controller = controller
    player(controller).companions.append(iid)


func move_to_sequence(iid: String) -> void:
    var ci := inst(iid)
    if ci == null:
        return
    _remove_from_current_zone(ci)
    ci.zone = "sequence"


func attach(iid: String, host_iid: String, slot: String) -> void:
    var ci := inst(iid)
    var host := inst(host_iid)
    if ci == null or host == null:
        return
    _remove_from_current_zone(ci)
    ci.zone = "attached"
    ci.attached_to = host_iid
    ci.controller = host.controller
    if slot == "equipment":
        host.equipment_iid = iid
    else:
        host.taahma_iid = iid


func place_location(iid: String) -> void:
    var ci := inst(iid)
    if ci == null:
        return
    _remove_from_current_zone(ci)
    ci.zone = "location"
    location_iid = iid


func attachments_of(host_iid: String) -> Array:
    var host := inst(host_iid)
    if host == null:
        return []
    var out: Array = []
    if host.equipment_iid != "":
        out.append(host.equipment_iid)
    if host.taahma_iid != "":
        out.append(host.taahma_iid)
    return out


# -------------------------------------------------------------------- events ---

## Assign the next entry-order number to a card arriving in play.
func stamp_entry(iid: String) -> void:
    var ci := inst(iid)
    if ci == null:
        return
    var n: int = int(counters.get("entry", 0)) + 1
    counters["entry"] = n
    ci.entry_seq = n


func emit(kind: String, data: Dictionary = {}) -> void:
    if silent:
        return
    event_seq += 1
    var e := {"n": event_seq, "round": round_number, "phase": phase, "kind": kind}
    e.merge(data)
    events.append(e)


func log_lines(limit: int = 0) -> Array:
    var out: Array = []
    var src: Array = events
    if limit > 0 and events.size() > limit:
        src = events.slice(events.size() - limit, events.size())
    for e in src:
        var msg := String(e.get("message", ""))
        if msg != "":
            out.append(msg)
    return out


# ------------------------------------------------------------- serialisation ---

func to_dict(include_catalog: bool = true) -> Dictionary:
    var insts: Dictionary = {}
    for iid in instances.keys():
        insts[iid] = (instances[iid] as CardInstance).to_dict()
    var seq: Array = []
    for s in sequence:
        seq.append((s as ActionSlot).to_dict())
    var pl: Array = []
    for p in players:
        pl.append((p as PlayerState).to_dict())
    var d := {
        "schema": 1,
        "match_id": match_id,
        "rules_stamp": rules_stamp.duplicate(),
        "round_number": round_number,
        "phase": phase,
        "first_player": first_player,
        "action_priority": action_priority,
        "players": pl,
        "instances": insts,
        "counters": counters.duplicate(),
        "sequence": seq,
        "current_step": current_step,
        "round_history": round_history.duplicate(true),
        "location_iid": location_iid,
        "sequence_members": sequence_members.duplicate(),
        "deferred_choices": deferred_choices.duplicate(true),
        "pending": pending.duplicate(true) if pending is Dictionary else null,
        "reaction_window": reaction_window.duplicate() if reaction_window is Dictionary else null,
        "pending_failures": pending_failures.duplicate() if pending_failures is Dictionary else {},
        "result": result.duplicate(true) if result is Dictionary else null,
        "events": events.duplicate(true),
        "event_seq": event_seq,
        "rng": rng.to_dict() if rng != null else {},
    }
    if include_catalog:
        # Freeze the exact definitions this match uses, by value.
        var used: Dictionary = {}
        for iid in instances.keys():
            used[(instances[iid] as CardInstance).def_id] = true
        d["frozen_catalog"] = catalog.freeze_subset(used.keys())
        d["rules_profile"] = {
            "profile_id": rules.profile_id, "profile_version": rules.profile_version,
            "established": rules.established.duplicate(true),
            "provisional": rules.provisional.duplicate(true),
        }
    return d


static func from_dict(d: Dictionary) -> GameState:
    var st := GameState.new()
    st.match_id = String(d.get("match_id", ""))
    st.rules_stamp = d.get("rules_stamp", {}).duplicate()
    st.round_number = int(d.get("round_number", 0))
    st.phase = String(d.get("phase", "draw"))
    st.first_player = int(d.get("first_player", 0))
    st.action_priority = int(d.get("action_priority", 0))
    st.counters = d.get("counters", {}).duplicate()
    st.current_step = int(d.get("current_step", -1))
    st.round_history = d.get("round_history", []).duplicate(true)
    st.location_iid = String(d.get("location_iid", ""))
    st.sequence_members = d.get("sequence_members", []).duplicate()
    st.deferred_choices = d.get("deferred_choices", []).duplicate(true)
    st.pending = d.get("pending", null)
    st.reaction_window = d.get("reaction_window", null)
    st.result = d.get("result", null)
    st.pending_failures = d.get("pending_failures", {}).duplicate()
    st.events = d.get("events", []).duplicate(true)
    st.event_seq = int(d.get("event_seq", 0))
    st.rng = HotRng.from_dict(d.get("rng", {}))

    st.players = []
    for pd in d.get("players", []):
        st.players.append(PlayerState.from_dict(pd))
    st.instances = {}
    var insts: Dictionary = d.get("instances", {})
    for iid in insts.keys():
        st.instances[String(iid)] = CardInstance.from_dict(insts[iid])
    st.sequence = []
    for sd in d.get("sequence", []):
        st.sequence.append(ActionSlot.from_dict(sd))

    # Rebuild the frozen catalog and rules profile so the resumed match uses
    # exactly the definitions it started with.
    st.catalog = Catalog.from_frozen(d.get("frozen_catalog", {}))
    var rp := RulesProfile.new()
    var raw_rules: Dictionary = d.get("rules_profile", {})
    rp.profile_id = String(raw_rules.get("profile_id", "prototype-v1"))
    rp.profile_version = int(raw_rules.get("profile_version", 1))
    rp.established = raw_rules.get("established", {}).duplicate(true)
    rp.provisional = raw_rules.get("provisional", {}).duplicate(true)
    rp._apply_defaults()
    st.rules = rp
    return st
