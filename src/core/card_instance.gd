class_name CardInstance
extends RefCounted

## One physical card in a match.
##
## Instance ids are match-scoped and distinct from the definition id: three
## copies of one Skill share a def_id and have three separate iids. Every
## instance is in exactly one zone at all times; an attachment's zone is
## "attached" and its host is named by `attached_to`.

const ZONES := ["hero", "hand", "hit", "exhaust", "wound", "companions", "location", "attached", "sequence"]

var iid: String = ""
var def_id: String = ""
var def_rev: int = 1
## Ownership never changes: a card returning to a pile goes to its owner's pile.
var owner: int = 0
## Controller is modelled separately from owner even though the first catalog
## contains no control-stealing cards.
var controller: int = 0
var zone: String = "hit"
var attached_to: String = ""
var equipment_iid: String = ""
var taahma_iid: String = ""
## Round the Companion's deployment resolved, or -1. A Companion deployed this
## round cannot attack this round.
var deployed_round: int = -1
## Temporary stat modifiers: {"attack": int, "defense": int, "expires": String}
var mods: Array = []
## Damage prevention: {"amount": int, "expires": String}
var shields: Array = []
## Order in which this card entered play. Breaks ties when several sources
## would trigger at the same moment.
var entry_seq: int = 0


func _init(instance_id: String = "", definition_id: String = "", definition_rev: int = 1, owner_index: int = 0) -> void:
    iid = instance_id
    def_id = definition_id
    def_rev = definition_rev
    owner = owner_index
    controller = owner_index


func mod_attack() -> int:
    var total := 0
    for m in mods:
        total += int(m.get("attack", 0))
    return total


func mod_defense() -> int:
    var total := 0
    for m in mods:
        total += int(m.get("defense", 0))
    return total


func shield_total() -> int:
    var total := 0
    for s in shields:
        total += int(s.get("amount", 0))
    return total


func expire(duration: String) -> void:
    var kept: Array = []
    for m in mods:
        if String(m.get("expires", "round")) != duration:
            kept.append(m)
    mods = kept
    var kept_shields: Array = []
    for s in shields:
        if String(s.get("expires", "round")) != duration:
            kept_shields.append(s)
    shields = kept_shields


func to_dict() -> Dictionary:
    return {
        "iid": iid, "def_id": def_id, "def_rev": def_rev,
        "owner": owner, "controller": controller, "zone": zone,
        "attached_to": attached_to, "equipment_iid": equipment_iid, "taahma_iid": taahma_iid,
        "deployed_round": deployed_round, "entry_seq": entry_seq,
        "mods": mods.duplicate(true), "shields": shields.duplicate(true),
    }


static func from_dict(d: Dictionary) -> CardInstance:
    var ci := CardInstance.new(String(d.get("iid", "")), String(d.get("def_id", "")), int(d.get("def_rev", 1)), int(d.get("owner", 0)))
    ci.controller = int(d.get("controller", ci.owner))
    ci.zone = String(d.get("zone", "hit"))
    ci.attached_to = String(d.get("attached_to", ""))
    ci.equipment_iid = String(d.get("equipment_iid", ""))
    ci.taahma_iid = String(d.get("taahma_iid", ""))
    ci.deployed_round = int(d.get("deployed_round", -1))
    ci.entry_seq = int(d.get("entry_seq", 0))
    ci.mods = d.get("mods", []).duplicate(true)
    ci.shields = d.get("shields", []).duplicate(true)
    return ci
