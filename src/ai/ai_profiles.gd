class_name AiProfiles
extends RefCounted

## Loads the per-Affinity strategic weights. Each Affinity opponent evaluates
## the same features with different weights, so their play differs in kind and
## not only in portrait colour.

const PATH := "res://data/ai_profiles.json"

static var _cache: Dictionary = {}


static func _all() -> Dictionary:
    if _cache.is_empty():
        var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH)) \
            if FileAccess.file_exists(PATH) else null
        _cache = parsed if parsed is Dictionary else {}
    return _cache


static func weights_for(affinity: String) -> Dictionary:
    var all := _all()
    var base: Dictionary = (all.get("default", {}) as Dictionary).duplicate()
    var specific = all.get(affinity, null)
    if specific is Dictionary:
        base.merge(specific, true)
    if base.is_empty():
        base = {
            "pressure": 1.0, "preservation": 0.45, "board_attack": 0.55,
            "board_defense": 0.4, "companion_count": 0.6, "hand_value": 0.35,
            "energy_value": 0.18, "max_energy_value": 0.45, "hero_size": 0.3,
            "reaction_reserve": 0, "reaction_reserve_weight": 0.5,
            "protect_own": 0.5, "aggression": 1.0, "search_candidates": 40,
        }
    return base


static func affinities() -> Array:
    var out: Array = []
    for k in _all().keys():
        if String(k) != "default" and (_all()[k] is Dictionary):
            out.append(String(k))
    out.sort()
    return out
