extends RefCounted

## Collection, gold, pack and persistence acceptance checks.

static var _cat: Catalog = null


func suite_name() -> String:
    return "progression"


func _catalog() -> Catalog:
    if _cat == null:
        _cat = Catalog.load_bundled()
    return _cat


func run(t: TestHarness) -> void:
    test_reward_is_idempotent(t)
    test_pack_purchase(t)
    test_pack_reveal_resume(t)
    test_unaffordable_purchase(t)
    test_duplicate_conversion(t)
    test_save_round_trip(t)
    test_save_rejects_bad_import(t)
    test_wounds_do_not_touch_collection(t)


func _profile() -> PlayerProfile:
    return PlayerProfile.create_new(_catalog(), EconomyConfig.load_from())


func test_reward_is_idempotent(t: TestHarness) -> void:
    t.begin("a victory pays exactly once")
    var economy := EconomyConfig.load_from()
    var p := _profile()
    var start := p.gold

    var first := p.award_match("match_a", "win", economy, "Passion Opponent")
    t.eq(int(first["gold"]), economy.victory_gold, "the win paid the configured reward")
    t.ok(not bool(first["already_paid"]), "it was a fresh payment")
    t.eq(p.gold, start + economy.victory_gold, "gold increased once")

    # Reopening the results screen, or a reload, replays the same award call.
    var again := p.award_match("match_a", "win", economy, "Passion Opponent")
    t.ok(bool(again["already_paid"]), "the second call reports the reward was already paid")
    t.eq(p.gold, start + economy.victory_gold, "gold did not increase a second time")
    t.eq(p.record_count(), 1, "only one match record exists")

    # A rematch is a new match id and pays again.
    p.award_match("match_b", "win", economy, "Passion Opponent")
    t.eq(p.gold, start + economy.victory_gold * 2, "a rematch is a separate match and pays again")

    # Losses, draws and concessions pay nothing.
    var before := p.gold
    p.award_match("match_c", "loss", economy)
    p.award_match("match_d", "draw", economy)
    p.award_match("match_e", "concede", economy)
    t.eq(p.gold, before, "a loss, a draw and a concession pay no gold")
    t.eq(p.record_count(), 5, "every completed match is recorded")

    # A sandbox match awards nothing regardless of outcome.
    var sandbox_before := p.gold
    p.award_match("match_sandbox", "win", economy, "Sandbox", true)
    t.eq(p.gold, sandbox_before, "a sandbox match awards no gold")


func test_pack_purchase(t: TestHarness) -> void:
    t.begin("opening a booster")
    var cat := _catalog()
    var economy := EconomyConfig.load_from()
    var p := _profile()
    var gold_before := p.gold
    var owned_before := 0
    for k in p.owned().keys():
        owned_before += int(p.owned()[k])

    var res := p.open_pack(cat, economy)
    t.ok(bool(res["ok"]), "the purchase succeeded: %s" % str(res["error"]))
    var opening: Dictionary = res["opening"]
    var cards: Array = opening["cards"]
    t.eq(cards.size(), economy.cards_per_booster, "the booster contained five cards")

    var expected_pools := ["common", "common", "common", "uncommon", "premium"]
    for i in cards.size():
        var c: Dictionary = cards[i]
        t.eq(String(c["pool"]), expected_pools[i], "slot %d drew from the %s pool" % [i + 1, expected_pools[i]])
        var def := cat.get_def(String(c["def_id"]))
        t.ne(def, null, "slot %d produced a real card" % (i + 1))
        if def != null:
            if String(c["pool"]) == "premium":
                t.ok(def.rarity == "rare" or def.rarity == "legendary",
                    "the premium slot produced a Rare or Legendary, not %s" % def.rarity)
            else:
                t.eq(def.rarity, String(c["pool"]), "slot %d matched its pool's rarity" % (i + 1))

    var spent := gold_before - p.gold + int(opening["duplicate_gold"])
    t.eq(spent, economy.booster_price, "exactly the booster price was deducted (duplicates refunded separately)")

    var owned_after := 0
    for k in p.owned().keys():
        owned_after += int(p.owned()[k])
    var added := 0
    for c in cards:
        added += int((c as Dictionary)["added"])
    t.eq(owned_after - owned_before, added, "the collection grew by exactly the cards that fit under their caps")
    t.eq(p.pack_openings().size(), 1, "the opening was recorded with its contents")


func test_pack_reveal_resume(t: TestHarness) -> void:
    t.begin("a reload mid-reveal resumes the same result")
    var cat := _catalog()
    var economy := EconomyConfig.load_from()
    var p := _profile()
    var first := p.open_pack(cat, economy)
    var gold_after_purchase := p.gold
    var opening_id := String((first["opening"] as Dictionary)["opening_id"])

    # Simulate a refresh: persist, reload, and ask to open again.
    var store := SaveStore.new()
    var err := store.commit(p.to_dict())
    t.eq(err, "", "the purchase was committed durably before any reveal")
    var reloaded := PlayerProfile.new(store.load_raw())
    t.eq(reloaded.gold, gold_after_purchase, "the reload shows the gold already spent, spent once")
    t.ok(reloaded.pending_reveal() is Dictionary, "the un-acknowledged reveal is still pending")

    var second := reloaded.open_pack(cat, economy)
    t.ok(bool(second.get("resumed", false)), "opening again resumes the pending reveal instead of rerolling")
    t.eq(String((second["opening"] as Dictionary)["opening_id"]), opening_id, "it is the same opening")
    t.eq(reloaded.gold, gold_after_purchase, "no second charge was made")
    t.eq(reloaded.pack_openings().size(), 1, "no second opening was recorded")

    reloaded.acknowledge_reveal()
    t.eq(reloaded.pending_reveal(), null, "acknowledging clears the pending reveal")
    var third := reloaded.open_pack(cat, economy)
    t.ok(not bool(third.get("resumed", false)), "the next purchase is a genuinely new opening")
    t.eq(reloaded.gold, gold_after_purchase - economy.booster_price + int((third["opening"] as Dictionary)["duplicate_gold"]),
        "the new purchase charged the price once")


func test_unaffordable_purchase(t: TestHarness) -> void:
    t.begin("an unaffordable purchase changes nothing")
    var cat := _catalog()
    var economy := EconomyConfig.load_from()
    var p := _profile()
    p.gold = economy.booster_price - 1
    var before := p.to_dict()

    var res := p.open_pack(cat, economy)
    t.ok(not bool(res["ok"]), "the purchase was refused")
    t.ok(String(res["error"]).contains("gold"), "the refusal explains the shortfall: %s" % str(res["error"]))
    t.eq(p.gold, economy.booster_price - 1, "gold is unchanged")
    t.eq(p.pack_openings().size(), 0, "no opening was recorded")
    t.eq(p.pending_reveal(), null, "no reveal is pending")
    t.eq(JSON.stringify(p.to_dict()), JSON.stringify(before), "the whole save is byte-for-byte unchanged")


func test_duplicate_conversion(t: TestHarness) -> void:
    t.begin("copies past the cap convert to gold")
    var cat := _catalog()
    var economy := EconomyConfig.load_from()
    var p := _profile()

    # An ordinary Common caps at three copies.
    var ordinary := "SIL_SKILL_03"
    var def := cat.get_def(ordinary)
    t.ne(def, null, "the test card exists")
    p.raw["owned"][ordinary] = 0
    var r1 := p.add_cards(cat, economy, ordinary, 3)
    t.eq(int(r1["added"]), 3, "three copies fit")
    t.eq(int(r1["gold"]), 0, "nothing converted yet")
    var gold_before := p.gold
    var r2 := p.add_cards(cat, economy, ordinary, 2)
    t.eq(int(r2["added"]), 0, "no further copies fit")
    t.eq(int(r2["gold"]), economy.dust_for(def.rarity) * 2, "both extras converted at the configured rate")
    t.eq(p.gold, gold_before + economy.dust_for(def.rarity) * 2, "the gold was credited")
    t.eq(p.owned_count(ordinary), 3, "the collection stayed at the cap")

    # Heroes, named characters and Unique cards cap at one.
    var hero_id := "PAS_HERO_01"
    p.raw["owned"][hero_id] = 0
    var h1 := p.add_cards(cat, economy, hero_id, 1)
    t.eq(int(h1["added"]), 1, "the first Hero copy is granted")
    var h2 := p.add_cards(cat, economy, hero_id, 1)
    t.eq(int(h2["added"]), 0, "a second Hero copy does not fit")
    t.eq(int(h2["gold"]), economy.dust_for("legendary"), "it converted at the Legendary rate")


func test_save_round_trip(t: TestHarness) -> void:
    t.begin("save export and import preserve everything")
    var cat := Catalog.load_bundled()
    var economy := EconomyConfig.load_from()
    var p := _profile()
    p.award_match("m1", "win", economy)
    p.open_pack(cat, economy)
    p.acknowledge_reveal()

    # A card-editor override and a custom deck.
    var edited := cat.get_def("HAR_SKILL_02").duplicate_def()
    edited.data["name"] = "Custom Renamed Skill"
    t.empty(cat.put_override(edited), "the override validates")
    p.set_override("HAR_SKILL_02", cat.overrides["HAR_SKILL_02"])
    var custom := (p.decks()[0] as Dictionary).duplicate(true)
    custom["deck_id"] = "custom_deck"
    custom["name"] = "My Deck"
    custom["starter"] = false
    p.save_deck(custom)

    var store := SaveStore.new()
    var path := "user://export_test.json"
    t.eq(store.export_to(path, p.to_dict()), "", "the save exported")

    var read := store.read_import(path)
    t.ok(bool(read["ok"]), "the export re-imports: %s" % str(read["error"]))
    var restored := PlayerProfile.new(read["data"])
    t.eq(restored.gold, p.gold, "gold survived the round trip")
    t.eq(restored.decks().size(), p.decks().size(), "all decks survived")
    t.ne(restored.deck_by_id("custom_deck"), {}, "the custom deck survived")
    t.eq(restored.owned_count("PAS_SKILL_01"), p.owned_count("PAS_SKILL_01"), "owned counts survived")
    t.eq(restored.record_count(), p.record_count(), "match records survived")
    t.ok(restored.overrides().has("HAR_SKILL_02"), "the card-editor override survived")
    t.eq(String((restored.overrides()["HAR_SKILL_02"] as Dictionary).get("name", "")),
        "Custom Renamed Skill", "the override's contents survived")

    # A committed save reloads identically.
    t.eq(store.commit(p.to_dict()), "", "the save committed")
    var loaded := PlayerProfile.new(store.load_raw())
    t.eq(loaded.gold, p.gold, "the committed save reloads with the same gold")
    t.eq(loaded.decks().size(), p.decks().size(), "the committed save reloads with the same decks")
    t.eq(store.last_load_problem, "", "no load problem was reported")

    # Committing twice keeps a recoverable previous save.
    p.gold = p.gold + 7
    t.eq(store.commit(p.to_dict()), "", "the second commit succeeded")
    t.ok(FileAccess.file_exists(SaveStore.BACKUP_PATH), "the previous save was kept as a backup")


func test_save_rejects_bad_import(t: TestHarness) -> void:
    t.begin("a bad import is refused without replacing anything")
    var store := SaveStore.new()
    var path := "user://bad_import.json"
    var f := FileAccess.open(path, FileAccess.WRITE)
    f.store_string("{ not json at all")
    f.close()
    var r := store.read_import(path)
    t.ok(not bool(r["ok"]), "malformed JSON is refused")

    var f2 := FileAccess.open(path, FileAccess.WRITE)
    f2.store_string(JSON.stringify({"schema": SaveStore.SCHEMA_VERSION + 5, "gold": 1,
        "owned": {}, "decks": []}))
    f2.close()
    var r2 := store.read_import(path)
    t.ok(not bool(r2["ok"]), "a newer save format is refused rather than half-read")
    t.ok(String(r2["error"]).contains("format"), "the refusal explains the version: %s" % str(r2["error"]))

    var f3 := FileAccess.open(path, FileAccess.WRITE)
    f3.store_string(JSON.stringify({"schema": 1, "gold": 5}))
    f3.close()
    var r3 := store.read_import(path)
    t.ok(not bool(r3["ok"]), "a save missing its collection is refused")


func test_wounds_do_not_touch_collection(t: TestHarness) -> void:
    t.begin("a match's wounds are temporary match state")
    var cat := _catalog()
    var economy := EconomyConfig.load_from()
    var rules := RulesProfile.load_from()
    var p := _profile()
    var deck: Dictionary = p.decks()[0]
    var sample_id := String((deck["cards"] as Dictionary).keys()[0])
    var owned_before := p.owned_count(sample_id)

    var st := GameEngine.start_match(cat, rules, [deck, DeckLibrary.ai_decks()[0]], 777,
        "wound_test", ["You", "Opponent"], [false, true], ["", "devotion"])
    Mechanics.hero_damage(st, 0, 8, "test")
    t.ge(float(st.player(0).wound.size()), 8.0, "cards moved to the Wound Deck during the match")

    p.award_match("wound_test", "loss", economy)
    t.eq(p.owned_count(sample_id), owned_before, "the collection is untouched by in-match wounds")
    var r := DeckValidator.validate(cat, rules, deck, p.owned())
    t.ok(r["ok"], "the deck is still legal and fully owned after the match: %s" % str(r["errors"]))
