extends RefCounted

## The card creator's pricing model and the definitions it builds.
##
## Two things matter here and are pinned hard. First, a created card is priced:
## every choice raises the total, and the printed Energy cost is what the total
## comes to, so a card cannot be made cheaper than what is on it. Second, a
## created card is a real card: it passes the same validator as the shipped
## catalog, its rules text is generated from its own effect data, and the
## engine performs it in a real match.

const F := preload("res://tests/fixtures.gd")

var _rules: RulesProfile


func suite_name() -> String:
    return "forge"


func run(t: TestHarness) -> void:
    _rules = F.rules()
    _every_feature_builds_a_real_card(t)
    _every_choice_raises_the_price(t)
    _points_become_energy(t)
    _rarity_follows_the_total(t)
    _a_design_is_checked_before_it_is_built(t)
    _a_card_can_be_opened_again(t)
    _the_catalog_takes_a_created_card(t)
    _a_created_card_belongs_to_the_save(t)
    _the_engine_plays_a_created_card(t)


## The whole feature table, on every card type it offers itself for. A feature
## that builds a definition the validator rejects would be a card the creator
## offers and then refuses to save, so this is checked exhaustively rather than
## by sampling.
func _every_feature_builds_a_real_card(t: TestHarness) -> void:
    t.begin("every feature builds a card that validates")
    var checked := 0
    for card_type in CardForge.TYPES:
        var available := CardForge.features_for(String(card_type))
        t.ok(not available.is_empty(), "a %s card has features to choose from" % card_type)
        for fid in available:
            var design := _design_for(String(card_type), String(fid))
            var raw := CardForge.build(design, "CUSTOM_TEST_001")
            var def := CardDef.from_dict(raw)
            t.empty(def.validate(), "%s on a %s validates" % [fid, card_type])
            t.ok(def.text.strip_edges() != "",
                "%s on a %s says what it does" % [fid, card_type])
            t.eq(def.text, TextGen.render(def),
                "%s on a %s prints exactly its generated text" % [fid, card_type])
            checked += 1
    t.ge(float(checked), 20.0, "the feature table covers a useful range of cards")


## The heart of the idea: nothing is free. Every switch and every extra point
## costs points, and points are what the Energy cost is made of.
func _every_choice_raises_the_price(t: TestHarness) -> void:
    t.begin("every choice on a card raises what it costs")

    var skill := CardForge.blank_design("skill", "passion")
    skill["name"] = "Priced Skill"
    var empty_points := int(CardForge.price(skill)["points"])
    t.eq(empty_points, 0, "a Skill with nothing on it is worth nothing")

    skill["features"] = [{"id": "damage", "amount": 1}]
    var one := int(CardForge.price(skill)["points"])
    skill["features"] = [{"id": "damage", "amount": 2}]
    var two := int(CardForge.price(skill)["points"])
    t.gt(float(one), float(empty_points), "adding a feature costs points")
    t.eq(two - one, int(CardForge.FEATURES["damage"]["price"]),
        "and each further point of it costs the feature's price again")

    skill["features"] = [{"id": "damage", "amount": 2}, {"id": "draw", "amount": 1}]
    var both := int(CardForge.price(skill)["points"])
    t.eq(both - two, int(CardForge.FEATURES["draw"]["price"]),
        "a second feature costs its own price on top")

    skill["features"] = [{"id": "damage", "amount": 2}]
    skill["affinities"] = ["passion", "will"]
    t.eq(int(CardForge.price(skill)["points"]) - two, CardForge.SECOND_AFFINITY_PRICE,
        "a second Affinity costs points, because the card counts for both chains")
    skill["affinities"] = ["passion"]

    skill["reaction"] = true
    t.eq(int(CardForge.price(skill)["points"]) - two, CardForge.REACTION_PRICE,
        "being playable on your opponent's turn costs points")
    skill["reaction"] = false

    # A body on the board is priced by its numbers.
    var comp := CardForge.blank_design("companion", "passion")
    comp["name"] = "Priced Companion"
    var bare := int(CardForge.price(comp)["points"])
    t.eq(bare, int(CardForge.TYPE_BASE["companion"]),
        "a Companion is worth something before anything is put on it")
    comp["attack"] = 2
    var with_attack := int(CardForge.price(comp)["points"])
    t.eq(with_attack - bare, 2 * int(CardForge.STAT_PRICE["attack"]),
        "Attack is paid for by the point")
    comp["defense"] = 3
    t.eq(int(CardForge.price(comp)["points"]) - with_attack,
        3 * int(CardForge.STAT_PRICE["defense"]), "and so is Defense")

    # An attack that costs nothing to declare is worth paying for; a dearer one
    # is the one thing on a card that gives points back.
    comp["attack_cost"] = 0
    var free_attack := int(CardForge.price(comp)["points"])
    comp["attack_cost"] = 2
    var dear_attack := int(CardForge.price(comp)["points"])
    t.gt(float(free_attack), float(dear_attack),
        "a free attack costs more than an expensive one")

    # The ledger is what the player reads, so it has to name every line.
    comp["attack_cost"] = 1
    comp["features"] = [{"id": "aura_attack", "amount": 1}]
    var priced := CardForge.price(comp)
    var total := 0
    for line in priced["lines"]:
        total += int((line as Dictionary)["points"])
    t.eq(total, int(priced["points"]), "the ledger adds up to the total it reports")
    t.ge(float((priced["lines"] as Array).size()), 4.0,
        "and itemises the type, the statistics and the feature")


func _points_become_energy(t: TestHarness) -> void:
    t.begin("points become the printed Energy cost")
    t.eq(CardForge.cost_for_points(0), 0, "nothing costs nothing")
    t.eq(CardForge.cost_for_points(1), 1, "part of a point is still paid for")
    t.eq(CardForge.cost_for_points(CardForge.POINTS_PER_ENERGY), 1,
        "%d points is one Energy" % CardForge.POINTS_PER_ENERGY)
    t.eq(CardForge.cost_for_points(CardForge.POINTS_PER_ENERGY + 1), 2,
        "and one point past it is two")
    t.eq(CardForge.cost_for_points(10000), CardForge.MAX_COST,
        "however much is piled on, the cost stops at the maximum")

    # The built card prints exactly the cost it was priced at.
    var design := CardForge.blank_design("skill", "passion")
    design["name"] = "Costed Skill"
    design["features"] = [{"id": "burn_hero", "amount": 3}]
    var priced := CardForge.price(design)
    var def := CardDef.from_dict(CardForge.build(design, "CUSTOM_TEST_002"))
    t.eq(def.cost_kind(), "fixed", "a created card has a fixed cost")
    t.eq(def.fixed_cost(), int(priced["cost"]),
        "and prints the cost its choices came to")


func _rarity_follows_the_total(t: TestHarness) -> void:
    t.begin("rarity follows what was put into the card")
    t.eq(CardForge.rarity_for_points(0), "common", "a plain card is Common")
    t.eq(CardForge.rarity_for_points(100), "legendary", "a card with everything is Legendary")
    var last := -1
    var order := {"common": 0, "uncommon": 1, "rare": 2, "legendary": 3}
    for points in range(0, 80, 4):
        var step := int(order[CardForge.rarity_for_points(points)])
        t.ge(float(step), float(last), "rarity never falls as the total rises")
        last = step

    var design := CardForge.blank_design("companion", "will")
    design["name"] = "Rare By Construction"
    design["attack"] = 5
    design["defense"] = 5
    design["features"] = [{"id": "aura_attack", "amount": 2}]
    var priced := CardForge.price(design)
    var def := CardDef.from_dict(CardForge.build(design, "CUSTOM_TEST_003"))
    t.eq(def.rarity, String(priced["rarity"]), "the card is marked with the rarity it earned")
    t.ok(def.custom, "and marked as a card the player made")
    t.ok(def.authored, "which is not a proxy")


func _a_design_is_checked_before_it_is_built(t: TestHarness) -> void:
    t.begin("a design the creator cannot honour is refused with a reason")

    var blank := CardForge.blank_design("skill", "passion")
    t.ok(_mentions(CardForge.design_errors(blank), "name"), "a card needs a name")

    var empty_skill := CardForge.blank_design("skill", "passion")
    empty_skill["name"] = "Empty Skill"
    t.ok(_mentions(CardForge.design_errors(empty_skill), "feature"),
        "a Skill with no features is refused: it would be a blank card")

    var wrong_type := CardForge.blank_design("companion", "passion")
    wrong_type["name"] = "Confused Companion"
    wrong_type["features"] = [{"id": "damage", "amount": 1}]
    t.ok(_mentions(CardForge.design_errors(wrong_type), "cannot go on"),
        "a feature is refused on a card type it was not written for")

    var two_targets := CardForge.blank_design("skill", "passion")
    two_targets["name"] = "Two Questions"
    two_targets["features"] = [{"id": "damage", "amount": 1}, {"id": "buff", "amount": 1}]
    t.ok(_mentions(CardForge.design_errors(two_targets), "asks for one"),
        "two features that ask for different targets are refused: a card asks once")

    var reaction_body := CardForge.blank_design("companion", "passion")
    reaction_body["name"] = "Reacting Body"
    reaction_body["reaction"] = true
    reaction_body["features"] = [{"id": "aura_attack", "amount": 1}]
    t.ok(_mentions(CardForge.design_errors(reaction_body), "Reaction"),
        "only a Skill can be played as a Reaction")

    var unknown := CardForge.blank_design("skill", "passion")
    unknown["name"] = "Made Up"
    unknown["features"] = [{"id": "summon_dragon", "amount": 1}]
    t.ok(_mentions(CardForge.design_errors(unknown), "not a feature"),
        "a feature the creator does not know is refused rather than invented")

    var three := CardForge.blank_design("skill", "passion")
    three["name"] = "Three Ways"
    three["affinities"] = ["passion", "will", "harmony"]
    three["features"] = [{"id": "draw", "amount": 1}]
    t.ok(_mentions(CardForge.design_errors(three), "two Affinities"),
        "a card carries at most two Affinities")

    # A name another card already has is a catalog error, so the creator will
    # not let it be made in the first place.
    var taken := CardForge.blank_design("skill", "passion")
    taken["name"] = "Burning Rush"
    taken["features"] = [{"id": "draw", "amount": 1}]
    var catalog := Catalog.load_bundled()
    t.ok(_mentions(CardForge.design_errors(taken, catalog), "already carries that name"),
        "a name a shipped card already carries is refused")
    taken["name"] = "A Name Nothing Else Has"
    t.empty(CardForge.design_errors(taken, catalog), "and a free name is accepted")


## A creator you only get one try at is not much of a creator: a card carries
## the design it was made from, so it can be opened and changed.
func _a_card_can_be_opened_again(t: TestHarness) -> void:
    t.begin("a created card can be opened again exactly as it was made")
    var design := CardForge.blank_design("companion", "harmony")
    design["name"] = "Reopened Guard"
    design["flavor"] = "Stands where it was put."
    design["attack"] = 2
    design["defense"] = 4
    design["attack_cost"] = 0
    design["energy_contribution"] = 1
    design["features"] = [{"id": "aura_defense", "amount": 3},
        {"id": "on_deploy_draw", "amount": 2}]

    var raw := CardForge.build(design, "CUSTOM_COMP_001")
    var stored := CardForge.design_in(raw)
    t.ok(not stored.is_empty(), "the card carries its own design")
    t.eq(String(stored["name"]), "Reopened Guard", "with the name it was given")
    t.eq(int(stored["defense"]), 4, "and the numbers it was given")
    t.eq(int(stored["attack_cost"]), 0, "including the cost of its attack")
    t.eq((stored["features"] as Array).size(), 2, "and both of its features")
    for f in stored["features"]:
        var feature: Dictionary = f
        if String(feature["id"]) == "aura_defense":
            t.eq(int(feature["amount"]), 3, "each with the amount that was chosen")

    # Rebuilding from the stored design gives the same card back.
    var again := CardForge.build(stored, "CUSTOM_COMP_001")
    t.eq(int((again["cost"] as Dictionary)["amount"]),
        int((raw["cost"] as Dictionary)["amount"]), "rebuilding it costs the same")
    t.eq(String(again["text"]), String(raw["text"]), "and says the same thing")
    t.eq(String(again["rarity"]), String(raw["rarity"]), "at the same rarity")

    t.ok(CardForge.design_in({"id": "PAS_SKILL_01"}).is_empty(),
        "a card that was not made here carries no design")


func _the_catalog_takes_a_created_card(t: TestHarness) -> void:
    t.begin("a created card joins the catalog as an ordinary card")
    var catalog := Catalog.load_bundled()
    var before := catalog.size()

    var design := CardForge.blank_design("skill", "passion")
    design["name"] = "Test Forged Strike"
    design["features"] = [{"id": "damage", "amount": 2}]
    var def_id := CardForge.next_id("skill", catalog.customs)
    t.eq(def_id, "CUSTOM_SKILL_001", "the first created Skill gets a readable id")
    var errs := catalog.put_custom(CardDef.from_dict(CardForge.build(design, def_id)))
    t.empty(errs, "it was accepted")
    t.eq(catalog.size(), before + 1, "the catalog grew by one card")
    t.ok(catalog.is_custom(def_id), "and knows the card was made rather than shipped")
    t.ne(catalog.get_def(def_id), null, "the card can be looked up like any other")
    var eligible := false
    for d in catalog.deck_eligible():
        if (d as CardDef).id == def_id:
            eligible = true
    t.ok(eligible, "a created card may go in a deck")
    t.eq(catalog.collection_cap(def_id), 3, "and caps at three copies like any common card")
    t.empty(catalog.validate_all(), "the whole catalog still validates with it in")

    # The same name twice is refused, because two cards sharing a name is a
    # catalog error rather than a matter of taste.
    var twin := CardForge.blank_design("skill", "passion")
    twin["name"] = "Test Forged Strike"
    twin["features"] = [{"id": "draw", "amount": 1}]
    var second_id := CardForge.next_id("skill", catalog.customs)
    t.eq(second_id, "CUSTOM_SKILL_002", "the next created Skill gets the next id")
    t.ok(not catalog.put_custom(CardDef.from_dict(CardForge.build(twin, second_id))).is_empty(),
        "a second card with the same name is refused")

    # Nothing that fails the real validator can be stored, however it was made.
    var broken := CardDef.from_dict({"id": "CUSTOM_SKILL_009", "name": "Broken",
        "types": ["skill"], "rarity": "common", "revision": 1,
        "cost": {"kind": "fixed", "amount": 1}, "timing": ["action"],
        "patterns": ["custom"], "effects": [], "triggers": [], "text": ""})
    t.ok(not catalog.put_custom(broken).is_empty(),
        "a definition that does not validate is never stored")

    t.ok(catalog.remove_custom(def_id), "a created card can be deleted")
    t.eq(catalog.size(), before, "which takes it back out of the catalog")
    t.eq(catalog.get_def(def_id), null, "and it can no longer be looked up")
    t.ok(not catalog.ids().has(def_id), "nor left behind in the load order")
    # Rebuilding after a deletion must not reach for a definition that is no
    # longer there.
    catalog.rebuild()
    t.eq(catalog.size(), before, "and the catalog rebuilds cleanly without it")


func _a_created_card_belongs_to_the_save(t: TestHarness) -> void:
    t.begin("a created card is part of the save, with copies in the collection")
    var catalog := Catalog.load_bundled()
    var economy := EconomyConfig.load_from()
    var profile := PlayerProfile.create_new(catalog, economy, "passion", "Forge Test")

    var design := CardForge.blank_design("companion", "passion")
    design["name"] = "Test Forged Guard"
    design["attack"] = 1
    design["defense"] = 3
    design["features"] = [{"id": "on_deploy_draw", "amount": 1}]
    var def_id := CardForge.next_id("companion", catalog.customs)
    t.empty(catalog.put_custom(CardDef.from_dict(CardForge.build(design, def_id))),
        "the Companion was forged")
    profile.set_custom(def_id, catalog.customs[def_id])
    profile.grant_custom_copies(def_id, catalog.collection_cap(def_id))

    t.eq(profile.owned_count(def_id), 3, "its copies are in the collection")
    t.ok(profile.customs().has(def_id), "and the card itself is stored in the save")

    # Belonging to the save is the whole point: it has to survive one.
    var reloaded := PlayerProfile.new(profile.to_dict().duplicate(true))
    t.ok(reloaded.customs().has(def_id), "it survives a save and reload")
    var fresh_catalog := Catalog.load_bundled()
    fresh_catalog.set_customs(reloaded.customs())
    t.ne(fresh_catalog.get_def(def_id), null, "and comes back into the catalog on load")
    t.eq(fresh_catalog.get_def(def_id).name, "Test Forged Guard", "as the card it was")
    t.eq(reloaded.owned_count(def_id), 3, "with the copies still in the collection")

    # A deck may hold it, and nothing objects to the card itself.
    var deck := {"deck_id": "forge_deck", "hero": "PAS_HERO_01",
        "cards": {def_id: 3, "PAS_SKILL_02": 3}}
    var owned := reloaded.owned().duplicate()
    owned["PAS_HERO_01"] = 1
    owned["PAS_SKILL_02"] = 3
    var check := DeckValidator.validate(fresh_catalog, _rules, deck, owned)
    for e in check["errors"]:
        t.ok(not String(e).contains(def_id),
            "nothing objects to a created card being in a deck: %s" % String(e))

    # Deleting a card takes its copies with it: a collection of a card that no
    # longer exists would be a collection of nothing.
    t.ok(reloaded.clear_custom(def_id), "the card can be deleted from the save")
    t.eq(reloaded.owned_count(def_id), 0, "which also removes the copies it held")
    t.ok(not reloaded.customs().has(def_id), "and the card is gone from the save")


## The proof that a created card is a real card: the engine plays it and does
## exactly what its generated text says.
func _the_engine_plays_a_created_card(t: TestHarness) -> void:
    t.begin("the engine plays a created card")

    var design := CardForge.blank_design("skill", "passion")
    design["name"] = "Test Forged Bolt"
    design["features"] = [{"id": "burn_hero", "amount": 2}]
    var raw := CardForge.build(design, "CUSTOM_SKILL_001")
    var def := CardDef.from_dict(raw)
    t.empty(def.validate(), "the card validates")
    t.eq(def.text, "Deal 2 damage to the opposing Hero.",
        "and says what it will do in the game's own words")

    var defs := F.all_defs()
    defs.append(def)
    var catalog := Catalog.from_defs(defs)
    var deck0 := F.deck("FIX_HERO_A", {"CUSTOM_SKILL_001": 3})
    var deck1 := F.deck("FIX_HERO_B")
    var st := F.match_of(deck0, deck1, 11, catalog)
    F.setup_action_phase(st)
    F.clear_hands(st)
    st.first_player = 0
    st.action_priority = 0

    var iid := F.to_hand(st, 0, "CUSTOM_SKILL_001")
    if not t.ne(iid, "", "a copy is in hand"):
        return
    # Damage to a Hero is paid in cards: that many leave for the Wound Deck.
    var before := st.player(1).wound.size()
    var res := GameEngine.submit(st, {"cmd": "commit_card", "player": 0, "card_iid": iid})
    if not t.ok(bool(res["ok"]), "it commits: %s" % String(res.get("error", ""))):
        return
    F.pass_round(st)
    t.eq(st.player(1).wound.size(), before + 2,
        "and the opposing Hero took exactly the damage the card promised")


# ------------------------------------------------------------------- helpers ---

func _design_for(card_type: String, feature_id: String) -> Dictionary:
    var design := CardForge.blank_design(card_type, "passion")
    design["name"] = "Probe %s %s" % [card_type, feature_id]
    design["features"] = [{"id": feature_id, "amount": 2}]
    if card_type == "companion":
        design["attack"] = 2
        design["defense"] = 2
    return design


func _mentions(errs: Array, text: String) -> bool:
    for e in errs:
        if String(e).to_lower().contains(text.to_lower()):
            return true
    return false
