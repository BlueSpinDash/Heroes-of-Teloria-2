class_name DeckValidator
extends RefCounted

## Deck legality and ownership.
##
## A legal deck is exactly one named Hero outside a Hit Deck of exactly 45
## cards. Ordinary copy limits apply by card NAME, not by database id, so two
## definitions that share a name cannot stack to six copies. Named-character
## identity is tracked separately so a future alternate version of a character
## cannot evade the one-per-deck restriction.
##
## There is no sideboard, and no Hero, faction or Affinity restriction on the
## rest of the deck. Rarity affects pack acquisition only.


## deck: {"deck_id", "name", "hero": def_id, "cards": {def_id: qty}}
## owned: {def_id: count}, or null to skip the ownership check.
static func validate(catalog: Catalog, rules: RulesProfile, deck: Dictionary, owned = null) -> Dictionary:
    var errors: Array = []
    var warnings: Array = []

    var hero_id := String(deck.get("hero", ""))
    var hero_def: CardDef = catalog.get_def(hero_id) if hero_id != "" else null
    if hero_id == "":
        errors.append("Choose a Hero. Every deck needs exactly one.")
    elif hero_def == null:
        errors.append("Hero '%s' is not in the catalog." % hero_id)
    elif not hero_def.has_type("hero"):
        errors.append("'%s' is not a Hero card." % hero_def.name)

    var cards: Dictionary = deck.get("cards", {})
    var total := 0
    var by_name: Dictionary = {}
    var by_character: Dictionary = {}

    var ids: Array = cards.keys()
    ids.sort()
    for def_id in ids:
        var qty := int(cards[def_id])
        var def := catalog.get_def(String(def_id))
        if qty <= 0:
            continue
        if def == null:
            errors.append("Card '%s' is not in the catalog." % String(def_id))
            continue
        if def.has_type("hero"):
            errors.append("%s is a Hero and belongs outside the deck." % def.name)
            continue
        total += qty

        by_name[def.name] = int(by_name.get(def.name, 0)) + qty
        if def.is_named_character():
            by_character[def.character_id] = int(by_character.get(def.character_id, 0)) + qty

        if def.unique and qty > int(rules.est("unique_limit", 1)):
            errors.append("%s is Unique: at most %d copy." % [def.name, int(rules.est("unique_limit", 1))])

        if owned is Dictionary:
            var have := int((owned as Dictionary).get(String(def_id), 0))
            if qty > have:
                errors.append("You own %d copy of %s but the deck uses %d." % [have, def.name, qty])

    for nm in by_name.keys():
        if int(by_name[nm]) > rules.copy_limit_by_name:
            errors.append("%s appears %d times; the limit is %d copies of a card with the same name." % [
                String(nm), int(by_name[nm]), rules.copy_limit_by_name])

    var named_limit := int(rules.est("named_character_limit", 1))
    for ch in by_character.keys():
        if int(by_character[ch]) > named_limit:
            errors.append("The named character '%s' appears %d times; a deck may contain only %d." % [
                String(ch), int(by_character[ch]), named_limit])

    # Provisional: a deck card that is the same named character as the Hero
    # would put two copies of that character into the match.
    if hero_def != null and hero_def.is_named_character() and by_character.has(hero_def.character_id):
        errors.append("%s is already your Hero; the same named character cannot also be in the deck." % hero_def.name)

    if total != rules.hit_deck_size:
        errors.append("The Hit Deck must contain exactly %d cards; this deck has %d." % [rules.hit_deck_size, total])

    if owned is Dictionary and hero_id != "":
        if int((owned as Dictionary).get(hero_id, 0)) < 1:
            errors.append("You do not own the Hero %s." % (hero_def.name if hero_def != null else hero_id))

    if deck.has("sideboard") and (deck["sideboard"] is Array) and not (deck["sideboard"] as Array).is_empty():
        errors.append("There is no sideboard in Heroes of Teloria.")

    return {"ok": errors.is_empty(), "errors": errors, "warnings": warnings, "count": total}


## Deck composition summary for the builder: counts by type, Affinity and
## Energy cost, used for the Energy curve display.
static func stats(catalog: Catalog, deck: Dictionary) -> Dictionary:
    var by_type: Dictionary = {}
    var by_affinity: Dictionary = {}
    var curve: Dictionary = {}
    var reaction_count := 0
    var total := 0
    var cards: Dictionary = deck.get("cards", {})
    for def_id in cards.keys():
        var qty := int(cards[def_id])
        var def := catalog.get_def(String(def_id))
        if def == null or qty <= 0:
            continue
        total += qty
        for t in def.types:
            by_type[String(t)] = int(by_type.get(String(t), 0)) + qty
        if def.affinities.is_empty():
            by_affinity["neutral"] = int(by_affinity.get("neutral", 0)) + qty
        for a in def.affinities:
            by_affinity[String(a)] = int(by_affinity.get(String(a), 0)) + qty
        if def.has_tag("reaction"):
            reaction_count += qty
        var key := "X" if def.cost_kind() == "x" else str(def.fixed_cost())
        curve[key] = int(curve.get(key, 0)) + qty
    return {
        "total": total, "by_type": by_type, "by_affinity": by_affinity,
        "curve": curve, "reactions": reaction_count,
    }


## How many copies of each definition a set of decks needs, taking the highest
## requirement per definition rather than the sum across decks.
static func union_requirements(decks: Array) -> Dictionary:
    var need: Dictionary = {}
    for deck in decks:
        var d: Dictionary = deck
        var hero := String(d.get("hero", ""))
        if hero != "":
            need[hero] = max(int(need.get(hero, 0)), 1)
        for def_id in (d.get("cards", {}) as Dictionary).keys():
            var qty := int((d["cards"] as Dictionary)[def_id])
            need[String(def_id)] = max(int(need.get(String(def_id), 0)), qty)
    return need
