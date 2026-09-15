class_name ActionSlot
extends RefCounted

## One committed Action in the shared Action Sequence, plus the Reactions
## collected for its step.
##
## An attack is stored as a reference to its attacker, not by moving the
## character card: the attacker stays targetable and keeps contributing its
## persistent bonuses while its attack is pending.

var slot_id: String = ""
var controller: int = 0
var kind: String = "card"  # "card" | "attack"
var card_iid: String = ""
var attacker_iid: String = ""
## Chosen targets, captured on commitment and revalidated on resolution.
var targets: Array = []
## Energy actually spent for an X cost. Later refunds never rewrite this.
var x_paid: int = 0
var energy_paid: int = 0
## Affinities captured at commitment time. For an attack these come from the
## attacking character; they are what the chain evaluator reads.
var affinities: Array = []
var resolved: bool = false
## True once this step's Reaction window has closed.
var window_done: bool = false
## Reactions attached to this step: each is a Dictionary with
## {"iid", "controller", "window", "targets", "x_paid", "energy_paid", "resolved"}
var reactions: Array = []


func _init(id: String = "", controller_index: int = 0) -> void:
    slot_id = id
    controller = controller_index


func has_affinity() -> bool:
    return not affinities.is_empty()


func reactions_for(window: String) -> Array:
    var out: Array = []
    for r in reactions:
        if String(r.get("window", "before")) == window:
            out.append(r)
    return out


func clone() -> ActionSlot:
    var s := ActionSlot.new(slot_id, controller)
    s.kind = kind
    s.card_iid = card_iid
    s.attacker_iid = attacker_iid
    s.targets = targets.duplicate()
    s.x_paid = x_paid
    s.energy_paid = energy_paid
    s.affinities = affinities.duplicate()
    s.resolved = resolved
    s.window_done = window_done
    s.reactions = reactions.duplicate(true)
    return s


func to_dict() -> Dictionary:
    return {
        "slot_id": slot_id, "controller": controller, "kind": kind,
        "card_iid": card_iid, "attacker_iid": attacker_iid,
        "targets": targets.duplicate(), "x_paid": x_paid, "energy_paid": energy_paid,
        "affinities": affinities.duplicate(), "resolved": resolved, "window_done": window_done,
        "reactions": reactions.duplicate(true),
    }


static func from_dict(d: Dictionary) -> ActionSlot:
    var s := ActionSlot.new(String(d.get("slot_id", "")), int(d.get("controller", 0)))
    s.kind = String(d.get("kind", "card"))
    s.card_iid = String(d.get("card_iid", ""))
    s.attacker_iid = String(d.get("attacker_iid", ""))
    s.targets = d.get("targets", []).duplicate()
    s.x_paid = int(d.get("x_paid", 0))
    s.energy_paid = int(d.get("energy_paid", 0))
    s.affinities = d.get("affinities", []).duplicate()
    s.resolved = bool(d.get("resolved", false))
    s.window_done = bool(d.get("window_done", false))
    s.reactions = d.get("reactions", []).duplicate(true)
    return s
