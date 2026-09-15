extends RefCounted

## Catalog and deck-content acceptance checks.

static var _cat: Catalog = null


func suite_name() -> String:
    return "catalog"


func _catalog() -> Catalog:
    if _cat == null:
        _cat = Catalog.load_bundled()
    return _cat


func run(t: TestHarness) -> void:
    test_totals(t)
    test_all_validate(t)
    test_rarity_and_acquisition(t)
    test_behaviour_patterns(t)
    test_identity_modelling(t)
    test_decks_legal(t)
    test_starter_grant_plays(t)
    test_ai_deck_themes(t)
    test_art_assets(t)
    test_authored_flag(t)
    test_edit_preserves_references(t)
    test_edit_reports_illegality(t)
    test_active_match_freezes_definitions(t)


func test_totals(t: TestHarness) -> void:
    t.begin("catalog totals")
    var cat := _catalog()
    t.empty(cat.load_errors, "the catalog files loaded cleanly")
    t.eq(cat.size(), 300, "exactly 300 definitions exist")

    var by_type := {"hero": 0, "companion": 0, "skill": 0, "equipment": 0, "location": 0, "taahma": 0}
    var by_affinity: Dictionary = {}
    var neutral := 0
    var reaction_skills := 0
    var reaction_by_affinity: Dictionary = {}
    for def in cat.all_defs():
        for ty in def.types:
            by_type[String(ty)] = int(by_type.get(String(ty), 0)) + 1
        if def.affinities.is_empty():
            neutral += 1
        for a in def.affinities:
            by_affinity[String(a)] = int(by_affinity.get(String(a), 0)) + 1
        if def.has_tag("reaction"):
            reaction_skills += 1
            var key := "neutral" if def.affinities.is_empty() else String(def.affinities[0])
            reaction_by_affinity[key] = int(reaction_by_affinity.get(key, 0)) + 1
            t.ok(def.has_type("skill"), "%s is tagged Reaction and is a Skill" % def.id)

    t.eq(by_type["hero"], 14, "14 Hero definitions")
    t.eq(by_type["skill"], 150, "150 Skill definitions")
    t.eq(by_type["companion"], 76, "76 Companion definitions")
    t.eq(by_type["equipment"], 30, "30 Equipment definitions")
    t.eq(by_type["taahma"], 15, "15 Ta'ahma definitions")
    t.eq(by_type["location"], 15, "15 Location definitions")
    t.eq(by_type["hero"] + by_type["skill"] + by_type["companion"] + by_type["equipment"]
        + by_type["taahma"] + by_type["location"], 300, "type counts add up to 300")

    t.eq(neutral, 20, "20 definitions have no Affinity")
    for a in EffectSchema.AFFINITIES:
        t.eq(int(by_affinity.get(a, 0)), 40, "%s has 40 definitions" % a)
    t.eq(by_affinity.size(), 7, "exactly the seven established Affinities appear")

    t.eq(reaction_skills, 40, "40 Reaction-tagged Skills")
    for a in EffectSchema.AFFINITIES:
        t.eq(int(reaction_by_affinity.get(a, 0)), 5, "%s has 5 Reaction Skills" % a)
    t.eq(int(reaction_by_affinity.get("neutral", 0)), 5, "5 neutral Reaction Skills")

    var martial := 0
    var magic := 0
    var melee := 0
    var ranged := 0
    for def in cat.all_defs():
        if def.has_tag("martial"):
            martial += 1
        if def.has_tag("magic"):
            magic += 1
        if def.has_tag("melee"):
            melee += 1
        if def.has_tag("ranged"):
            ranged += 1
    t.ge(martial, 20.0, "the catalog contains Martial Skills")
    t.ge(magic, 20.0, "the catalog contains Magic Skills")
    t.ge(melee, 5.0, "Melee tags are used")
    t.ge(ranged, 5.0, "Ranged tags are used")

    t.eq(cat.heroes().size(), 14, "14 Hero choices")
    t.eq(cat.deck_eligible().size(), 286, "286 definitions are eligible for a 45-card deck")


func test_all_validate(t: TestHarness) -> void:
    t.begin("every definition validates")
    var errs := _catalog().validate_all()
    t.empty(errs, "all 300 definitions pass schema, effect and text validation")

    # Every referenced op, condition and trigger is one the interpreter runs.
    var unknown: Array = []
    for def in _catalog().all_defs():
        for e in def.all_effect_ops():
            var op := String((e as Dictionary).get("op", ""))
            if not EffectSchema.is_authorable_op(op):
                unknown.append("%s uses unimplemented op '%s'" % [def.id, op])
        for trig in def.triggers:
            var on: Dictionary = (trig as Dictionary).get("on", {})
            if not EffectSchema.TRIGGERS.has(String(on.get("kind", ""))):
                unknown.append("%s uses unimplemented trigger '%s'" % [def.id, String(on.get("kind", ""))])
    t.empty(unknown, "no definition claims an effect the engine cannot execute")

    # Proxies must say so. A card that has been authored for real is exempt,
    # which is how the catalog can be replaced one card at a time.
    var mislabelled: Array = []
    for def in _catalog().all_defs():
        if not def.authored and not def.placeholder:
            mislabelled.append("%s is neither placeholder nor authored" % def.id)
        if def.authored and def.placeholder:
            mislabelled.append("%s is marked both authored and placeholder" % def.id)
    t.empty(mislabelled, "every definition is labelled either proxy or finished")


func test_rarity_and_acquisition(t: TestHarness) -> void:
    t.begin("rarity pools and acquisition")
    var cat := _catalog()
    var counts := cat.rarity_counts()
    t.eq(int(counts.get("common", 0)), 150, "150 Common")
    t.eq(int(counts.get("uncommon", 0)), 90, "90 Uncommon")
    t.eq(int(counts.get("rare", 0)), 45, "45 Rare")
    t.eq(int(counts.get("legendary", 0)), 15, "15 Legendary")

    var economy := EconomyConfig.load_from()
    var pools: Array = ["common", "uncommon", "rare", "legendary"]
    for r in pools:
        t.ok(not cat.pool_by_rarity(String(r)).is_empty(), "the %s pack pool is not empty" % r)

    # Every definition sits in a pool a booster can draw from.
    var reachable: Dictionary = {}
    for r in pools:
        for cid in cat.pool_by_rarity(String(r)):
            reachable[cid] = true
    var orphans: Array = []
    for def in cat.all_defs():
        if not reachable.has(def.id):
            orphans.append(def.id)
    t.empty(orphans, "every card has an acquisition path through a booster slot")

    # Premium odds cover the whole slot.
    var total := 0.0
    for k in economy.premium_odds.keys():
        total += float(economy.premium_odds[k])
    t.ok(abs(total - 1.0) < 0.001, "the premium slot's odds sum to 1")


func test_behaviour_patterns(t: TestHarness) -> void:
    t.begin("behaviour coverage")
    var patterns: Dictionary = {}
    for def in _catalog().all_defs():
        for p in def.patterns:
            patterns[String(p)] = int(patterns.get(String(p), 0)) + 1
    t.ge(float(patterns.size()), 24.0, "at least 24 distinct behaviour patterns across the catalog")

    # No single mechanic is simply copied across the whole catalog.
    var biggest := 0
    var biggest_name := ""
    for k in patterns.keys():
        if int(patterns[k]) > biggest:
            biggest = int(patterns[k])
            biggest_name = String(k)
    t.le(float(biggest) / 300.0, 0.45, "no one pattern dominates the catalog (%s appears %d times)" % [
        biggest_name, biggest])

    # Each Affinity offers low, middle and higher-cost options.
    for a in EffectSchema.AFFINITIES:
        var costs: Dictionary = {"low": 0, "mid": 0, "high": 0}
        for def in _catalog().all_defs():
            if not def.has_affinity(a) or def.has_type("hero"):
                continue
            var c: int = def.fixed_cost() if def.cost_kind() == "fixed" else def.x_min()
            if c <= 1:
                costs["low"] += 1
            elif c == 2:
                costs["mid"] += 1
            else:
                costs["high"] += 1
        t.ok(costs["low"] > 0 and costs["mid"] > 0 and costs["high"] > 0,
            "%s has low, middle and higher-cost options (%s)" % [a, str(costs)])


func test_identity_modelling(t: TestHarness) -> void:
    t.begin("named-character and Unique modelling")
    var cat := _catalog()
    var named := 0
    var unique := 0
    var unique_not_character := 0
    var characters: Dictionary = {}
    for def in cat.all_defs():
        if def.is_named_character():
            named += 1
            t.ok(def.unique, "%s is a named character and is Unique" % def.id)
            t.ok(not characters.has(def.character_id),
                "character id '%s' is not shared by two definitions yet" % def.character_id)
            characters[def.character_id] = def.id
        if def.unique:
            unique += 1
            if not def.is_named_character():
                unique_not_character += 1
        if def.has_type("hero"):
            t.ok(def.is_named_character(), "%s is a named Hero" % def.id)
            t.eq(cat.collection_cap(def.id), 1, "%s caps at one owned copy" % def.id)
    t.ge(float(named), 25.0, "the catalog distinguishes named characters from ordinary units")
    t.ge(float(unique_not_character), 1.0, "Unique is modelled separately from named-character identity")

    var ordinary := cat.get_def("PAS_SKILL_01")
    t.ne(ordinary, null, "an ordinary Skill exists")
    if ordinary != null:
        t.eq(cat.collection_cap(ordinary.id), 3, "an ordinary definition caps at three owned copies")


func test_decks_legal(t: TestHarness) -> void:
    t.begin("starter and AI decks are legal")
    var cat := _catalog()
    var rules := RulesProfile.load_from()
    var starters := DeckLibrary.starters()
    var ai := DeckLibrary.ai_decks()
    t.eq(starters.size(), 7, "seven starter decks are shipped")
    t.eq(ai.size(), 7, "seven AI decks are shipped")

    var affinities_seen: Dictionary = {}
    for deck in starters + ai:
        var d: Dictionary = deck
        var r := DeckValidator.validate(cat, rules, d)
        t.ok(r["ok"], "%s is legal: %s" % [String(d.get("deck_id", "?")), str(r["errors"])])
        t.eq(int(r["count"]), 45, "%s holds exactly 45 cards" % String(d.get("deck_id", "?")))
        affinities_seen[String(d.get("affinity", ""))] = true
        var blurb := String(d.get("description", ""))
        t.ok(blurb.length() > 20, "%s describes its plan" % String(d.get("deck_id", "?")))
    for a in EffectSchema.AFFINITIES:
        t.ok(affinities_seen.has(a), "an opponent exists for %s" % a)


func test_starter_grant_plays(t: TestHarness) -> void:
    t.begin("a new profile can actually play all seven starters")
    var cat := _catalog()
    var rules := RulesProfile.load_from()
    var economy := EconomyConfig.load_from()
    var profile := PlayerProfile.create_new(cat, economy)
    t.eq(profile.gold, economy.starting_gold, "the profile starts with the configured gold")
    t.eq(profile.decks().size(), 7, "all seven starter decks are saved")

    for deck in profile.decks():
        var d: Dictionary = deck
        var r := DeckValidator.validate(cat, rules, d, profile.owned())
        t.ok(r["ok"], "%s is legal and fully owned: %s" % [String(d.get("name", "?")), str(r["errors"])])

    # The grant takes the highest requirement per definition, not the sum.
    var grant := DeckLibrary.starter_grant()
    var over_cap: Array = []
    for def_id in grant.keys():
        if int(grant[def_id]) > cat.collection_cap(String(def_id)):
            over_cap.append(String(def_id))
    t.empty(over_cap, "no granted definition exceeds its collection cap")
    t.eq(profile.owned_count("PAS_SKILL_01"), 3, "a shared starter card was granted at three copies, not six")


func test_ai_deck_themes(t: TestHarness) -> void:
    t.begin("AI decks carry their advertised Affinity")
    var cat := _catalog()
    for deck in DeckLibrary.ai_decks():
        var d: Dictionary = deck
        var affinity := String(d.get("affinity", ""))
        var on_theme := 0
        for def_id in (d.get("cards", {}) as Dictionary).keys():
            var def := cat.get_def(String(def_id))
            if def != null and def.has_affinity(affinity):
                on_theme += int((d["cards"] as Dictionary)[def_id])
        t.ge(float(on_theme), 30.0, "%s uses at least 30 on-Affinity cards (%d)" % [affinity, on_theme])


func test_art_assets(t: TestHarness) -> void:
    t.begin("supplied art files")
    ArtLibrary.clear_cache()

    # A bare filename resolves into the art folder; a full path is left alone.
    t.eq(ArtLibrary.resolve_path("hero.png"), "res://assets/art/hero.png",
        "a bare filename is looked for in assets/art")
    t.eq(ArtLibrary.resolve_path("user://elsewhere/hero.png"), "user://elsewhere/hero.png",
        "a full path is used exactly as written")
    t.eq(ArtLibrary.resolve_path(""), "", "an empty path resolves to nothing")
    t.ok(not ArtLibrary.has_image({}), "a card with no art entry has no image")
    t.ok(not ArtLibrary.has_image({"image": "   "}), "whitespace is not an art path")

    # A real image file loads and is reported as loaded.
    var img := Image.create(64, 36, false, Image.FORMAT_RGB8)
    img.fill(Color(0.8, 0.2, 0.3))
    var path := "user://test_card_art.png"
    t.eq(img.save_png(path), OK, "a test image was written")
    var art := {"image": path, "fit": "cover"}
    var tex := ArtLibrary.texture_for(art)
    t.ne(tex, null, "the image loaded as a texture")
    if tex != null:
        t.eq(tex.get_width(), 64, "at its real width")
        t.eq(tex.get_height(), 36, "and its real height")
    t.ok(ArtLibrary.describe(art).contains("Art loaded"), "the editor reports it as loaded")

    # The portrait uses it instead of the generated sigil.
    var portrait := CardArt.new()
    portrait.setup(art)
    t.ne(portrait.texture, null, "the card portrait picked up the supplied image")
    t.eq(portrait.fit, "cover", "and its fit setting")
    portrait.free()

    # A missing file falls back rather than failing.
    ArtLibrary.clear_cache()
    var absent := {"image": "user://definitely_not_here.png"}
    t.eq(ArtLibrary.texture_for(absent), null, "a missing art file loads nothing")
    t.ok(ArtLibrary.describe(absent).contains("not found"),
        "the editor says the file was not found: %s" % ArtLibrary.describe(absent))
    var fallback := CardArt.new()
    fallback.setup(absent)
    t.eq(fallback.texture, null, "the portrait falls back to its generated sigil")
    t.ok(fallback.sigil_points >= 4, "and the sigil is still configured")
    fallback.free()

    # A definition carrying an art file still validates, and a bad art block
    # does not.
    var base := _catalog().get_def("PAS_SKILL_01").duplicate_def()
    base.data["art"] = {"image": "emberfall.png", "fit": "contain", "hue": 350, "seed": 1}
    t.empty(base.validate(), "a definition naming an art file validates even before the file exists")

    var bad_fit := _catalog().get_def("PAS_SKILL_01").duplicate_def()
    bad_fit.data["art"] = {"image": "x.png", "fit": "stretch"}
    t.ok(not bad_fit.validate().is_empty(), "an unknown art fit is rejected")

    var bad_image := _catalog().get_def("PAS_SKILL_01").duplicate_def()
    bad_image.data["art"] = {"image": 12}
    t.ok(not bad_image.validate().is_empty(), "a non-text art path is rejected")

    # Nothing in the shipped catalog points at art that cannot be read.
    t.empty(ArtLibrary.missing_for(_catalog()),
        "no shipped definition references an art file that is missing")
    ArtLibrary.clear_cache()


func test_authored_flag(t: TestHarness) -> void:
    t.begin("finished cards are set aside from the proxy generator")
    var def := _catalog().get_def("WIL_SKILL_01").duplicate_def()
    t.ok(not def.authored, "a shipped proxy is not marked finished")
    t.ok(def.placeholder, "and is marked placeholder")

    def.data["authored"] = true
    t.ok(not def.validate().is_empty(), "marking it finished while still placeholder is rejected")
    def.data["placeholder"] = false
    def.data["text"] = TextGen.render(def)
    t.empty(def.validate(), "a finished card that is no longer placeholder validates")
    t.ok(def.authored, "and reports itself as finished")

    def.data["authored"] = "yes"
    t.ok(not def.validate().is_empty(), "a non-boolean finished flag is rejected")


func test_edit_preserves_references(t: TestHarness) -> void:
    t.begin("editing a definition preserves ownership and deck references")
    var cat := Catalog.load_bundled()
    var rules := RulesProfile.load_from()
    var economy := EconomyConfig.load_from()
    var profile := PlayerProfile.create_new(cat, economy)
    var deck: Dictionary = profile.decks()[0]
    var target_id := String((deck["cards"] as Dictionary).keys()[0])
    var owned_before := profile.owned_count(target_id)
    var rev_before := cat.get_def(target_id).revision

    var edited := cat.get_def(target_id).duplicate_def()
    edited.data["name"] = "Renamed Proxy Card"
    edited.data["flavor"] = "Replaced flavour."
    edited.data["art"] = {"style": "photo", "seed": 1, "hue": 12, "saturation": 0.2}
    edited.data["cost"] = {"kind": "fixed", "amount": 2}
    var errs := cat.put_override(edited)
    t.empty(errs, "the edited definition validates")
    t.eq(cat.get_def(target_id).name, "Renamed Proxy Card", "the new name is in effect")
    t.ge(float(cat.get_def(target_id).revision), float(rev_before + 1), "the revision incremented")
    t.eq(profile.owned_count(target_id), owned_before, "owned copies are untouched by the edit")
    t.ok((deck["cards"] as Dictionary).has(target_id), "the saved deck still references the same card id")
    var r := DeckValidator.validate(cat, rules, deck, profile.owned())
    t.ok(r["ok"], "the deck is still legal after a rename and cost change: %s" % str(r["errors"]))

    # Restoring drops the override and brings the bundled definition back.
    t.ok(cat.restore_bundled(target_id), "the override can be restored")
    t.eq(cat.get_def(target_id).revision, rev_before, "the bundled revision is back")
    t.ne(cat.get_def(target_id).name, "Renamed Proxy Card", "the bundled name is back")


func test_edit_reports_illegality(t: TestHarness) -> void:
    t.begin("an edit that makes a deck illegal is reported, never silently fixed")
    var cat := Catalog.load_bundled()
    var rules := RulesProfile.load_from()
    var economy := EconomyConfig.load_from()
    var profile := PlayerProfile.create_new(cat, economy)
    var deck: Dictionary = profile.decks()[0]
    var ids: Array = (deck["cards"] as Dictionary).keys()
    ids.sort()
    var a := String(ids[0])
    var b := String(ids[1])
    t.eq(int((deck["cards"] as Dictionary)[a]), 3, "the first card is at three copies")
    t.eq(int((deck["cards"] as Dictionary)[b]), 3, "the second card is at three copies")

    var edited := cat.get_def(a).duplicate_def()
    edited.data["name"] = cat.get_def(b).name  # now six cards share one name
    t.empty(cat.put_override(edited), "the edit itself is a valid definition")

    var r := DeckValidator.validate(cat, rules, deck, profile.owned())
    t.ok(not r["ok"], "the deck is now reported as illegal")
    var mentions_limit := false
    for e in r["errors"]:
        if String(e).contains("limit is 3"):
            mentions_limit = true
    t.ok(mentions_limit, "the error names the exact problem: %s" % str(r["errors"]))
    t.eq(profile.decks().size(), 7, "the deck was not deleted")
    t.ok((deck["cards"] as Dictionary).has(a), "its card list is intact")


func test_active_match_freezes_definitions(t: TestHarness) -> void:
    t.begin("an active match resumes with the definitions it started with")
    var cat := Catalog.load_bundled()
    var rules := RulesProfile.load_from()
    var starter: Dictionary = DeckLibrary.starters()[0]
    var ai_deck: Dictionary = DeckLibrary.ai_decks()[1]
    var st := GameEngine.start_match(cat, rules, [starter, ai_deck], 4242, "freeze_test",
        ["You", "Opponent"], [false, true], ["", String(ai_deck.get("affinity", ""))])
    var hero_id := String(starter.get("hero", ""))
    var original_name := cat.get_def(hero_id).name
    var snapshot := st.to_dict(true)

    # Edit the live catalog after the match started.
    var edited := cat.get_def(hero_id).duplicate_def()
    edited.data["name"] = "Edited Mid-Match Hero"
    t.empty(cat.put_override(edited), "the mid-match edit is valid")
    t.eq(cat.get_def(hero_id).name, "Edited Mid-Match Hero", "the live catalog changed")

    var resumed := GameState.from_dict(snapshot)
    t.eq(resumed.catalog.get_def(hero_id).name, original_name,
        "the resumed match still sees the definition it was started with")
    t.eq(resumed.match_id, "freeze_test", "the match identity survives the round trip")
    t.eq(resumed.round_number, st.round_number, "the round survives the round trip")
    t.eq(resumed.player(0).hand.size(), st.player(0).hand.size(), "hands survive the round trip")
    t.eq(int(resumed.rules_stamp.get("profile_version", -1)), rules.profile_version,
        "the rules profile version is pinned in the snapshot")
