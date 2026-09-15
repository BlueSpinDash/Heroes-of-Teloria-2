class_name RulesProfile
extends RefCounted

## Established rule constants plus the explicitly provisional prototype
## defaults, loaded from data/rules_profile.json.
##
## A match snapshot stores the profile id and version it started with so a
## later edit to the profile cannot change an in-progress match.

const DEFAULT_PATH := "res://data/rules_profile.json"

var profile_id: String = "prototype-v1"
var profile_version: int = 1
var established: Dictionary = {}
var provisional: Dictionary = {}


static func load_from(path: String = DEFAULT_PATH) -> RulesProfile:
    var p := RulesProfile.new()
    var text := ""
    if FileAccess.file_exists(path):
        text = FileAccess.get_file_as_string(path)
    if text.strip_edges() == "":
        push_warning("Rules profile missing at %s; using built-in defaults." % path)
        p._apply_defaults()
        return p
    var parsed = JSON.parse_string(text)
    if not (parsed is Dictionary):
        push_warning("Rules profile at %s is not a JSON object; using built-in defaults." % path)
        p._apply_defaults()
        return p
    p.profile_id = String(parsed.get("profile_id", "prototype-v1"))
    p.profile_version = int(parsed.get("profile_version", 1))
    p.established = parsed.get("established", {})
    p.provisional = parsed.get("provisional", {})
    p._apply_defaults()
    return p


func _apply_defaults() -> void:
    var est_defaults := {
        "hit_deck_size": 45, "draw_to": 5, "max_hand_size": 7,
        "copy_limit_by_name": 3, "named_character_limit": 1, "unique_limit": 1,
        "heroes_per_deck": 1, "sideboard_size": 0,
    }
    for k in est_defaults:
        if not established.has(k):
            established[k] = est_defaults[k]
    var prov_defaults := {
        "first_priority": "seeded_random_then_alternate",
        "opening_mulligan": false,
        "hand_overflow": "full_draw_then_choose_exhaust",
        "companion_board_cap": 0,
        "reaction_first_opportunity": "opponent_of_step_controller",
        "reaction_consecutive_passes_to_close": 2,
        "reaction_allow_reentry_after_single_pass": true,
        "reaction_nesting": false,
        "simultaneous_defeat_result": "draw",
        "taahma_replacement_destination": "exhaust",
        "orphan_attachment_destination": "exhaust",
        "companion_energy_on_entry": "max_only",
        "simulation_round_limit": 200,
        "ai_think_budget_ms": 45,
    }
    for k in prov_defaults:
        if not provisional.has(k):
            provisional[k] = prov_defaults[k]


func est(key: String, fallback = 0):
    return established.get(key, fallback)


func prov(key: String, fallback = null):
    return provisional.get(key, fallback)


var hit_deck_size: int:
    get: return int(est("hit_deck_size", 45))

var draw_to: int:
    get: return int(est("draw_to", 5))

var max_hand_size: int:
    get: return int(est("max_hand_size", 7))

var copy_limit_by_name: int:
    get: return int(est("copy_limit_by_name", 3))

var reaction_passes_to_close: int:
    get: return int(prov("reaction_consecutive_passes_to_close", 2))

var simulation_round_limit: int:
    get: return int(prov("simulation_round_limit", 200))


func stamp() -> Dictionary:
    return {"profile_id": profile_id, "profile_version": profile_version}
