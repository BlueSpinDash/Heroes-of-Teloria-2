extends RefCounted

## Opponent AI acceptance checks.
##
## The expensive checks run bounded simulations rather than full matches: the
## point is that every Affinity drives the real engine legally, not that each
## one plays to the last card.

static var _cat: Catalog = null

const SWEEP_ROUNDS := 4


func suite_name() -> String:
    return "ai"


func _catalog() -> Catalog:
    if _cat == null:
        _cat = Catalog.load_bundled()
    return _cat


func run(t: TestHarness) -> void:
    test_observation_hides_hidden_information(t)
    test_sanitized_clone_destroys_hidden_information(t)
    test_profiles_differ(t)
    test_decisions_are_always_legal(t)
    test_every_opponent_plays_legally(t)
    test_ai_completes_a_match(t)
    test_reproducible(t)
    test_round_limit_is_a_simulation_limit(t)


func _match(deck_a: Dictionary, deck_b: Dictionary, seed_value: int) -> GameState:
    return GameEngine.start_match(_catalog(), RulesProfile.load_from(), [deck_a, deck_b],
        seed_value, Ids.unique("aitest"), ["P1", "P2"], [true, true],
        [String(deck_a.get("affinity", "")), String(deck_b.get("affinity", ""))])


func test_observation_hides_hidden_information(t: TestHarness) -> void:
    t.begin("the observation never contains hidden information")
    var ai := DeckLibrary.ai_decks()
    var st := _match(ai[0], ai[1], 31337)
    var obs := Observation.build(st, 0)
    var blob := JSON.stringify(obs)

    # The opponent's hand contents must not appear anywhere in the observation.
    var leaked: Array = []
    for iid in st.player(1).hand:
        if blob.contains('"%s"' % String(iid)):
            leaked.append(String(iid))
        var cd := st.def_of(String(iid))
        if cd != null and blob.contains(cd.id):
            # A definition id can legitimately appear via a public zone, so only
            # flag it when that definition is nowhere public.
            if not _is_public_anywhere(st, cd.id):
                leaked.append(cd.id)
    t.empty(leaked, "no card from the opponent's hand is visible to the AI")
    t.eq(int(obs["opponent_hand_count"]), st.player(1).hand.size(), "only the opponent's hand COUNT is visible")

    # Own hand is visible; Hit order is not, for either player.
    t.eq((obs["my_hand"] as Array).size(), st.player(0).hand.size(), "the AI sees its own hand")
    t.ok(not obs.has("my_hit"), "the AI is not handed its own Hit Deck order")
    t.ok(not obs.has("opponent_hit"), "the AI is not handed the opponent's Hit Deck order")
    var hit_leak: Array = []
    for i in 2:
        for iid in st.player(i).hit:
            if blob.contains('"%s"' % String(iid)):
                hit_leak.append(String(iid))
    t.empty(hit_leak, "no Hit Deck card instance appears in the observation")

    # Deck counts and public zones are allowed.
    t.eq(int((obs["opponent_deck_counts"] as Dictionary)["hit"]), st.player(1).hit.size(),
        "deck counts are public")
    t.ok(obs.has("opponent_exhaust"), "Exhaust is a public zone the AI may inspect")
    t.ok(not obs.has("rng"), "the hidden RNG state is not part of the observation")
    t.eq(String(obs["opponent_deck_theme"]), String(ai[1].get("affinity", "")),
        "the authored opponent's deck theme is public knowledge")


func _is_public_anywhere(st: GameState, def_id: String) -> bool:
    for i in 2:
        var p := st.player(i)
        for zone in [p.exhaust, p.wound, p.companions]:
            for iid in zone:
                var cd := st.def_of(String(iid))
                if cd != null and cd.id == def_id:
                    return true
        var hd := st.def_of(p.hero_iid)
        if hd != null and hd.id == def_id:
            return true
    # The AI's own hand is legitimately visible to it.
    for iid in st.player(0).hand:
        var cd2 := st.def_of(String(iid))
        if cd2 != null and cd2.id == def_id:
            return true
    return false


func test_sanitized_clone_destroys_hidden_information(t: TestHarness) -> void:
    t.begin("the search model destroys hidden information rather than ignoring it")
    var ai := DeckLibrary.ai_decks()
    var st := _match(ai[2], ai[3], 909)
    var clone := Observation.sanitized_clone(st, 0, 12345)

    t.eq(clone.player(1).hand.size(), st.player(1).hand.size(),
        "the opponent's hand keeps only its visible size")
    var identical := 0
    for i in st.player(1).hand.size():
        var real := st.inst(String(st.player(1).hand[i]))
        var fake := clone.inst(String(clone.player(1).hand[i]))
        if real != null and fake != null and real.def_id == fake.def_id:
            identical += 1
    t.ok(identical < st.player(1).hand.size(),
        "the opponent's hand contents were replaced, not copied (%d of %d still match by chance)" % [
            identical, st.player(1).hand.size()])

    var same_order := true
    for i in min(st.player(1).hit.size(), clone.player(1).hit.size()):
        if String(st.player(1).hit[i]) != String(clone.player(1).hit[i]):
            same_order = false
            break
    t.ok(not same_order, "the opponent's Hit order was reshuffled away")
    var own_same_order := true
    for i in min(st.player(0).hit.size(), clone.player(0).hit.size()):
        if String(st.player(0).hit[i]) != String(clone.player(0).hit[i]):
            own_same_order = false
            break
    t.ok(not own_same_order, "the AI's own Hit order was reshuffled too; nobody knows their own draw order")
    t.ne(clone.rng.root_seed(), st.rng.root_seed(), "the match's hidden RNG state is not reused for search")

    # The player's own hand is untouched: that is information it is entitled to.
    for i in st.player(0).hand.size():
        var mine := st.inst(String(st.player(0).hand[i]))
        var mine_clone := clone.inst(String(clone.player(0).hand[i]))
        t.eq(mine_clone.def_id, mine.def_id, "the AI's own hand is preserved in the search model")


func test_profiles_differ(t: TestHarness) -> void:
    t.begin("each Affinity profile carries distinct strategic weights")
    var seen: Dictionary = {}
    for a in EffectSchema.AFFINITIES:
        var w := AiProfiles.weights_for(a)
        t.ok(not w.is_empty(), "%s has a profile" % a)
        var key := JSON.stringify(w)
        t.ok(not seen.has(key), "%s's weights differ from %s's" % [a, String(seen.get(key, ""))])
        seen[key] = a
    var passion := AiProfiles.weights_for("passion")
    var vigilance := AiProfiles.weights_for("vigilance")
    t.ok(float(passion["pressure"]) > float(vigilance["pressure"]),
        "Passion weighs pressure more heavily than Vigilance")
    t.ok(float(vigilance["preservation"]) > float(passion["preservation"]),
        "Vigilance weighs preserving its own deck more heavily than Passion")
    t.ok(int(vigilance["reaction_reserve"]) > int(passion["reaction_reserve"]),
        "Vigilance holds Energy back for Reactions and Passion does not")


func test_decisions_are_always_legal(t: TestHarness) -> void:
    t.begin("every decision is drawn from the engine's own legal-command list")
    var ai := DeckLibrary.ai_decks()
    var st := _match(ai[1], ai[5], 777)
    var checked := 0
    var guard := 0
    while st.result == null and st.round_number <= 3 and guard < 400:
        guard += 1
        var actor := MatchRunner._actor(st)
        if actor < 0:
            GameEngine.advance(st)
            continue
        var legal := GameEngine.legal_commands(st, actor)
        var cmd := AiPolicy.decide(st, actor)
        t.ok(not cmd.is_empty(), "the policy produced a command")
        var found := false
        for c in legal:
            if String((c as Dictionary).get("cmd", "")) != String(cmd.get("cmd", "")):
                continue
            var same := true
            for k in ["card_iid", "attacker_iid", "target_iid", "x"]:
                if cmd.has(k) and String(cmd[k]) != String((c as Dictionary).get(k, "")):
                    same = false
            if same:
                found = true
                break
        if not found:
            t.ok(false, "the chosen command %s is in the legal list" % JSON.stringify(cmd))
        checked += 1
        var res := GameEngine.submit(st, cmd)
        if not bool(res["ok"]):
            t.ok(false, "the engine accepted the AI's command: %s" % String(res["error"]))
            break
    t.ge(float(checked), 10.0, "a meaningful number of decisions were checked (%d)" % checked)


func test_every_opponent_plays_legally(t: TestHarness) -> void:
    t.begin("all seven Affinity opponents drive the real engine")
    var cat := _catalog()
    var rules := RulesProfile.load_from()
    var ai := DeckLibrary.ai_decks()
    for i in ai.size():
        var a: Dictionary = ai[i]
        var b: Dictionary = ai[(i + 1) % ai.size()]
        var r := MatchRunner.simulate(cat, rules, [a, b], 1000 + i * 17,
            [String(a.get("affinity", "")), String(b.get("affinity", ""))],
            ["ai", "ai"], SWEEP_ROUNDS)
        var label := String(a.get("affinity", "?"))
        t.empty(r["illegal_commands"], "%s never submits an illegal command" % label)
        t.ok(not bool(r["stalled"]), "%s never stalls the match" % label)
        t.empty(r["engine_guards"], "%s triggers no engine guard or trigger loop" % label)
        t.ge(float(r["decisions"]), 5.0, "%s actually made decisions (%d)" % [label, int(r["decisions"])])


func test_ai_completes_a_match(t: TestHarness) -> void:
    t.begin("an AI match reaches a real result")
    var ai := DeckLibrary.ai_decks()
    var r := MatchRunner.simulate(_catalog(), RulesProfile.load_from(), [ai[1], ai[3]], 24680,
        [String(ai[1].get("affinity", "")), String(ai[3].get("affinity", ""))])
    t.ok(not bool(r["hit_round_limit"]), "the match finished inside the simulation limit")
    t.ok(not bool(r["stalled"]), "the match never stalled")
    t.empty(r["illegal_commands"], "no illegal command was submitted")
    t.ne(r["result"], null, "the match produced a terminal result")
    if r["result"] != null:
        var res: Dictionary = r["result"]
        t.ok([0, 1, -1].has(int(res.get("winner", -99))), "the result names a winner or a draw")
        t.ok(String(res.get("reason", "")).length() > 0, "the result explains itself: %s" % str(res.get("reason", "")))
    t.ge(float(r["rounds"]), 2.0, "the match lasted more than one round")

    # Both players really played: the Sequence saw commitments from each side.
    var st: GameState = r["state"]
    var by_player := [0, 0]
    for round_rec in st.round_history:
        for slot in (round_rec as Dictionary).get("slots", []):
            by_player[int((slot as Dictionary).get("controller", 0))] += 1
    t.ge(float(by_player[0]), 3.0, "P1 committed Actions")
    t.ge(float(by_player[1]), 3.0, "P2 committed Actions")


func test_reproducible(t: TestHarness) -> void:
    t.begin("the same seed reproduces the same match")
    var cat := _catalog()
    var rules := RulesProfile.load_from()
    var ai := DeckLibrary.ai_decks()
    var a: Dictionary = ai[0]
    var b: Dictionary = ai[4]
    var first := MatchRunner.simulate(cat, rules, [a, b], 55555,
        [String(a.get("affinity", "")), String(b.get("affinity", ""))], ["ai", "ai"], SWEEP_ROUNDS)
    var second := MatchRunner.simulate(cat, rules, [a, b], 55555,
        [String(a.get("affinity", "")), String(b.get("affinity", ""))], ["ai", "ai"], SWEEP_ROUNDS)

    t.eq(int(second["decisions"]), int(first["decisions"]), "the same number of decisions was made")
    t.eq(int(second["events"]), int(first["events"]), "the same number of events was logged")
    var log_a := MatchRunner.transcript(first["state"])
    var log_b := MatchRunner.transcript(second["state"])
    t.eq(log_b.size(), log_a.size(), "the transcripts are the same length")
    var first_difference := -1
    for i in min(log_a.size(), log_b.size()):
        if log_a[i] != log_b[i]:
            first_difference = i
            break
    t.eq(first_difference, -1, "the transcripts are identical line for line")

    # A different seed produces a different game.
    var other := MatchRunner.simulate(cat, rules, [a, b], 98765,
        [String(a.get("affinity", "")), String(b.get("affinity", ""))], ["ai", "ai"], SWEEP_ROUNDS)
    var log_c := MatchRunner.transcript(other["state"])
    t.ok(log_c != log_a, "a different seed produces a different transcript")


func test_round_limit_is_a_simulation_limit(t: TestHarness) -> void:
    t.begin("a simulation limit is reported as such, never as a defeat")
    var ai := DeckLibrary.ai_decks()
    var r := MatchRunner.simulate(_catalog(), RulesProfile.load_from(), [ai[0], ai[2]], 4321,
        [String(ai[0].get("affinity", "")), String(ai[2].get("affinity", ""))], ["ai", "ai"], 2)
    t.ok(bool(r["hit_round_limit"]), "the run stopped at the simulation limit")
    t.eq(r["result"], null, "hitting the limit did not invent a winner or a loser")
    var st: GameState = r["state"]
    t.ne(st.phase, "ended", "the match state is still playable, not terminated by the limit")
    t.empty(r["illegal_commands"], "no illegal command was submitted before the limit")
