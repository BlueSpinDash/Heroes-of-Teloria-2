class_name PlayerState
extends RefCounted

## Per-player match state. Piles hold instance ids in order; Hit order is
## private information and never reaches the AI observation.

var index: int = 0
var display_name: String = "Player"
var hero_iid: String = ""
var deck_id: String = ""
var hand: Array = []
var hit: Array = []
var exhaust: Array = []
var wound: Array = []
var companions: Array = []
## One shared current-Energy pool per player.
var energy_current: int = 0
## Temporary maximum-Energy modifiers: {"amount": int, "expires": String}
var energy_max_mods: Array = []
## Passing normal Actions is permanent for the round; it does not stop Reactions.
var passed_actions: bool = false
## Characters that have appeared in the Action Sequence this round. An Energy
## refund never clears an entry here.
var committed_characters: Array = []
var is_ai: bool = false
var affinity_profile: String = ""


func _init(player_index: int = 0) -> void:
    index = player_index


func energy_max_mod_total() -> int:
    var total := 0
    for m in energy_max_mods:
        total += int(m.get("amount", 0))
    return total


func expire(duration: String) -> void:
    var kept: Array = []
    for m in energy_max_mods:
        if String(m.get("expires", "round")) != duration:
            kept.append(m)
    energy_max_mods = kept


func pile(name: String) -> Array:
    match name:
        "hand": return hand
        "hit": return hit
        "exhaust": return exhaust
        "wound": return wound
        "companions": return companions
    return []


func to_dict() -> Dictionary:
    return {
        "index": index, "display_name": display_name, "hero_iid": hero_iid, "deck_id": deck_id,
        "hand": hand.duplicate(), "hit": hit.duplicate(), "exhaust": exhaust.duplicate(),
        "wound": wound.duplicate(), "companions": companions.duplicate(),
        "energy_current": energy_current, "energy_max_mods": energy_max_mods.duplicate(true),
        "passed_actions": passed_actions, "committed_characters": committed_characters.duplicate(),
        "is_ai": is_ai, "affinity_profile": affinity_profile,
    }


static func from_dict(d: Dictionary) -> PlayerState:
    var p := PlayerState.new(int(d.get("index", 0)))
    p.display_name = String(d.get("display_name", "Player"))
    p.hero_iid = String(d.get("hero_iid", ""))
    p.deck_id = String(d.get("deck_id", ""))
    p.hand = d.get("hand", []).duplicate()
    p.hit = d.get("hit", []).duplicate()
    p.exhaust = d.get("exhaust", []).duplicate()
    p.wound = d.get("wound", []).duplicate()
    p.companions = d.get("companions", []).duplicate()
    p.energy_current = int(d.get("energy_current", 0))
    p.energy_max_mods = d.get("energy_max_mods", []).duplicate(true)
    p.passed_actions = bool(d.get("passed_actions", false))
    p.committed_characters = d.get("committed_characters", []).duplicate()
    p.is_ai = bool(d.get("is_ai", false))
    p.affinity_profile = String(d.get("affinity_profile", ""))
    return p
