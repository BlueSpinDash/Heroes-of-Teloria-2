class_name DeckLibrary
extends RefCounted

## The authored decks shipped with the game: seven starter decks granted at
## first launch and seven Affinity AI decklists. AI decks are catalog content
## and never depend on what the human owns.

const STARTERS_PATH := "res://data/decks/starters.json"
const AI_PATH := "res://data/decks/ai_decks.json"


static func _load_list(path: String) -> Array:
    if not FileAccess.file_exists(path):
        push_warning("Deck file missing: %s" % path)
        return []
    var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
    if not (parsed is Array):
        push_warning("Deck file is not a JSON array: %s" % path)
        return []
    return parsed


static func starters() -> Array:
    return _load_list(STARTERS_PATH)


static func ai_decks() -> Array:
    return _load_list(AI_PATH)


static func ai_deck_for(affinity: String) -> Dictionary:
    for d in ai_decks():
        if String((d as Dictionary).get("affinity", "")) == affinity:
            return d
    return {}


## The copies the starter grant needs: the highest requirement per definition
## across all seven decks, not the sum across them.
static func starter_grant() -> Dictionary:
    return DeckValidator.union_requirements(starters())
