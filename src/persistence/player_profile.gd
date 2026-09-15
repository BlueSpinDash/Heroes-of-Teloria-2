class_name PlayerProfile
extends RefCounted

## The player's persistent data: gold, owned copies by card id, saved decks,
## card-editor overrides, match reward records, pack openings and any active
## match snapshot.
##
## Rewards are idempotent by match id and pack openings are recorded with their
## contents, so reloading a results screen or refreshing mid-reveal can never
## pay or grant twice.

var raw: Dictionary = {}


func _init(d: Dictionary = {}) -> void:
    raw = d.duplicate(true)
    _defaults()


func _defaults() -> void:
    var defaults := {
        "schema": SaveStore.SCHEMA_VERSION,
        "profile_id": "",
        "created_at": "",
        "gold": 0,
        "owned": {},
        "decks": [],
        "catalog_overrides": {},
        "rewarded_matches": {},
        "match_records": [],
        "pack_openings": [],
        "pending_reveal": null,
        "active_match": null,
        "settings": {},
        "sandbox": false,
        "opening_counter": 0,
        "pack_seed": 0,
    }
    for k in defaults:
        if not raw.has(k):
            raw[k] = defaults[k]


## A brand-new profile: starting gold, the seven starter decks, and the union
## of cards needed to actually play all of them.
static func create_new(catalog: Catalog, economy: EconomyConfig) -> PlayerProfile:
    var p := PlayerProfile.new()
    p.raw["profile_id"] = Ids.unique("profile")
    p.raw["created_at"] = Time.get_datetime_string_from_system(true)
    p.raw["gold"] = economy.starting_gold
    var rng := RandomNumberGenerator.new()
    rng.randomize()
    p.raw["pack_seed"] = rng.randi() & 0x7FFFFFFF

    var grant := DeckLibrary.starter_grant()
    var owned: Dictionary = {}
    for def_id in grant.keys():
        owned[String(def_id)] = min(int(grant[def_id]), catalog.collection_cap(String(def_id)))
    p.raw["owned"] = owned

    var decks: Array = []
    for s in DeckLibrary.starters():
        var src: Dictionary = s
        decks.append({
            "deck_id": String(src.get("deck_id", Ids.unique("deck"))),
            "name": String(src.get("name", "Starter")),
            "hero": String(src.get("hero", "")),
            "cards": (src.get("cards", {}) as Dictionary).duplicate(),
            "starter": true,
            "affinity": String(src.get("affinity", "")),
        })
    p.raw["decks"] = decks
    return p


func to_dict() -> Dictionary:
    return raw.duplicate(true)


# ---------------------------------------------------------------------- gold ---

var gold: int:
    get: return int(raw.get("gold", 0))
    set(value): raw["gold"] = max(0, value)


func can_afford(amount: int) -> bool:
    return gold >= amount


# ---------------------------------------------------------------- collection ---

func owned() -> Dictionary:
    return raw.get("owned", {})


func owned_count(def_id: String) -> int:
    return int(owned().get(def_id, 0))


func distinct_owned() -> int:
    var n := 0
    for k in owned().keys():
        if int(owned()[k]) > 0:
            n += 1
    return n


## Add copies, converting anything past the collection cap into gold.
## Returns {"added": int, "gold": int}.
func add_cards(catalog: Catalog, economy: EconomyConfig, def_id: String, count: int = 1) -> Dictionary:
    var def := catalog.get_def(def_id)
    if def == null or count <= 0:
        return {"added": 0, "gold": 0}
    var cap := catalog.collection_cap(def_id)
    var have := owned_count(def_id)
    var room: int = max(0, cap - have)
    var added: int = min(room, count)
    var excess := count - added
    if added > 0:
        (raw["owned"] as Dictionary)[def_id] = have + added
    var dust := excess * economy.dust_for(def.rarity)
    if dust > 0:
        raw["gold"] = gold + dust
    return {"added": added, "gold": dust}


# --------------------------------------------------------------------- decks ---

func decks() -> Array:
    return raw.get("decks", [])


func deck_by_id(deck_id: String) -> Dictionary:
    for d in decks():
        if String((d as Dictionary).get("deck_id", "")) == deck_id:
            return d
    return {}


func save_deck(deck: Dictionary) -> String:
    var deck_id := String(deck.get("deck_id", ""))
    if deck_id == "":
        deck_id = Ids.unique("deck")
        deck["deck_id"] = deck_id
    var list: Array = raw["decks"]
    for i in list.size():
        if String((list[i] as Dictionary).get("deck_id", "")) == deck_id:
            list[i] = deck.duplicate(true)
            return deck_id
    list.append(deck.duplicate(true))
    return deck_id


func delete_deck(deck_id: String) -> bool:
    var list: Array = raw["decks"]
    for i in list.size():
        if String((list[i] as Dictionary).get("deck_id", "")) == deck_id:
            list.remove_at(i)
            return true
    return false


func duplicate_deck(deck_id: String) -> String:
    var src := deck_by_id(deck_id)
    if src.is_empty():
        return ""
    var copy := src.duplicate(true)
    copy["deck_id"] = Ids.unique("deck")
    copy["name"] = "%s (copy)" % String(src.get("name", "Deck"))
    copy["starter"] = false
    (raw["decks"] as Array).append(copy)
    return String(copy["deck_id"])


# ------------------------------------------------------------------- rewards ---

## Record a finished match and pay its reward exactly once. Returns
## {"gold": int, "already_paid": bool}.
func award_match(match_id: String, outcome: String, economy: EconomyConfig,
        opponent: String = "", sandbox: bool = false) -> Dictionary:
    var rewarded: Dictionary = raw["rewarded_matches"]
    if rewarded.has(match_id):
        return {"gold": int(rewarded[match_id]), "already_paid": true}
    var amount := 0 if sandbox else economy.reward_for(outcome)
    rewarded[match_id] = amount
    if amount > 0:
        raw["gold"] = gold + amount
    (raw["match_records"] as Array).append({
        "match_id": match_id, "outcome": outcome, "gold": amount,
        "opponent": opponent, "sandbox": sandbox,
        "at": Time.get_datetime_string_from_system(true),
    })
    return {"gold": amount, "already_paid": false}


func match_records() -> Array:
    return raw.get("match_records", [])


func record_count() -> int:
    return match_records().size()


func wins() -> int:
    var n := 0
    for r in match_records():
        if String((r as Dictionary).get("outcome", "")) == "win":
            n += 1
    return n


# --------------------------------------------------------------------- packs ---

## Roll one booster, spend its price and grant its contents in one step.
## The caller must commit the profile to disk before revealing anything.
## Returns {"ok": bool, "error": String, "opening": Dictionary}.
func open_pack(catalog: Catalog, economy: EconomyConfig) -> Dictionary:
    if raw.get("pending_reveal", null) is Dictionary:
        # A previous purchase has not been acknowledged yet; resume it rather
        # than rolling or charging again.
        return {"ok": true, "error": "", "opening": raw["pending_reveal"], "resumed": true}
    if not can_afford(economy.booster_price):
        return {"ok": false, "error": "You need %d gold; you have %d." % [
            economy.booster_price, gold], "opening": {}}

    var index := int(raw.get("opening_counter", 0)) + 1
    var rng := HotRng.new(int(raw.get("pack_seed", 0)) ^ (index * 2654435761))
    var results: Array = []
    for slot in economy.booster_slots:
        var pool_name := String((slot as Dictionary).get("pool", "common"))
        var rarity := pool_name
        if pool_name == "premium":
            var roll := rng.randf_in("premium")
            var legendary_chance := float(economy.premium_odds.get("legendary", 0.15))
            rarity = "legendary" if roll < legendary_chance else "rare"
        var pool := catalog.pool_by_rarity(rarity)
        if pool.is_empty():
            continue
        # Slot draws are independent and uniform, so duplicates are possible.
        var pick := String(pool[rng.randi_range_in("slot%d" % int((slot as Dictionary).get("slot", 0)), 0, pool.size() - 1)])
        results.append({"slot": int((slot as Dictionary).get("slot", 0)), "pool": pool_name,
            "rarity": rarity, "def_id": pick})

    # One durable transaction: spend, then grant, then record.
    raw["gold"] = gold - economy.booster_price
    raw["opening_counter"] = index
    var granted: Array = []
    var dust_total := 0
    for r in results:
        var res := add_cards(catalog, economy, String((r as Dictionary).get("def_id", "")), 1)
        var entry: Dictionary = (r as Dictionary).duplicate()
        entry["added"] = int(res["added"])
        entry["gold"] = int(res["gold"])
        dust_total += int(res["gold"])
        granted.append(entry)

    var opening := {
        "opening_id": "open_%d_%s" % [index, String(raw.get("profile_id", ""))],
        "index": index,
        "price": economy.booster_price,
        "cards": granted,
        "duplicate_gold": dust_total,
        "at": Time.get_datetime_string_from_system(true),
    }
    (raw["pack_openings"] as Array).append(opening)
    raw["pending_reveal"] = opening
    return {"ok": true, "error": "", "opening": opening, "resumed": false}


func pending_reveal():
    return raw.get("pending_reveal", null)


func acknowledge_reveal() -> void:
    raw["pending_reveal"] = null


func pack_openings() -> Array:
    return raw.get("pack_openings", [])


# --------------------------------------------------------- catalog overrides ---

func overrides() -> Dictionary:
    return raw.get("catalog_overrides", {})


func set_override(def_id: String, def_raw: Dictionary) -> void:
    (raw["catalog_overrides"] as Dictionary)[def_id] = def_raw.duplicate(true)


func clear_override(def_id: String) -> bool:
    var o: Dictionary = raw["catalog_overrides"]
    if o.has(def_id):
        o.erase(def_id)
        return true
    return false


# ---------------------------------------------------------------- active match ---

func active_match():
    return raw.get("active_match", null)


func set_active_match(snapshot) -> void:
    raw["active_match"] = snapshot


func clear_active_match() -> void:
    raw["active_match"] = null


# ------------------------------------------------------------------- settings ---

func setting(key: String, fallback = null):
    return (raw.get("settings", {}) as Dictionary).get(key, fallback)


func set_setting(key: String, value) -> void:
    (raw["settings"] as Dictionary)[key] = value
