class_name EconomyConfig
extends RefCounted

## Provisional economy settings loaded from data/economy.json.

const DEFAULT_PATH := "res://data/economy.json"

var data: Dictionary = {}


static func load_from(path: String = DEFAULT_PATH) -> EconomyConfig:
    var e := EconomyConfig.new()
    var text := ""
    if FileAccess.file_exists(path):
        text = FileAccess.get_file_as_string(path)
    var parsed = JSON.parse_string(text) if text.strip_edges() != "" else null
    e.data = parsed if parsed is Dictionary else {}
    e._defaults()
    return e


func _defaults() -> void:
    var d := {
        "starting_gold": 300, "victory_gold": 50, "loss_gold": 0, "draw_gold": 0,
        "concede_gold": 0, "booster_price": 100, "cards_per_booster": 5,
        "booster_slots": [
            {"slot": 1, "pool": "common"}, {"slot": 2, "pool": "common"},
            {"slot": 3, "pool": "common"}, {"slot": 4, "pool": "uncommon"},
            {"slot": 5, "pool": "premium"}],
        "premium_odds": {"rare": 0.85, "legendary": 0.15},
        "duplicate_gold": {"common": 5, "uncommon": 10, "rare": 20, "legendary": 50},
        "collection_cap_ordinary": 3, "collection_cap_restricted": 1,
        "sandbox_awards_gold": false,
    }
    for k in d:
        if not data.has(k):
            data[k] = d[k]


func get_int(key: String, fallback: int = 0) -> int:
    return int(data.get(key, fallback))


var starting_gold: int:
    get: return get_int("starting_gold", 300)

var victory_gold: int:
    get: return get_int("victory_gold", 50)

var booster_price: int:
    get: return get_int("booster_price", 100)

var cards_per_booster: int:
    get: return get_int("cards_per_booster", 5)

var booster_slots: Array:
    get: return data.get("booster_slots", [])

var premium_odds: Dictionary:
    get: return data.get("premium_odds", {})

var duplicate_gold: Dictionary:
    get: return data.get("duplicate_gold", {})


## Gold awarded for a finished match outcome, from the player's point of view.
func reward_for(outcome: String) -> int:
    match outcome:
        "win": return victory_gold
        "loss": return get_int("loss_gold", 0)
        "draw": return get_int("draw_gold", 0)
        "concede": return get_int("concede_gold", 0)
    return 0


func dust_for(rarity: String) -> int:
    return int(duplicate_gold.get(rarity, 0))


## Human-readable slot odds for the shop screen.
func slot_descriptions() -> Array:
    var out: Array = []
    for s in booster_slots:
        var pool := String((s as Dictionary).get("pool", ""))
        if pool == "premium":
            var bits: Array = []
            var keys: Array = premium_odds.keys()
            keys.sort()
            for k in keys:
                bits.append("%d%% %s" % [int(round(float(premium_odds[k]) * 100.0)), String(k).capitalize()])
            out.append("Slot %d — premium: %s" % [int((s as Dictionary).get("slot", 0)), ", ".join(bits)])
        else:
            out.append("Slot %d — %s" % [int((s as Dictionary).get("slot", 0)), pool.capitalize()])
    return out
