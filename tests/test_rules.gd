extends RefCounted

## Rules-engine acceptance checks from the blueprint's "Rules checks" list.

const F := preload("res://tests/fixtures.gd")


func suite_name() -> String:
    return "rules"


func run(t: TestHarness) -> void:
    test_deck_legality(t)
    test_draw_to_five(t)
    test_exact_exhaustion(t)
    test_hero_damage_order(t)
    test_companion_damage(t)
    test_energy_rules(t)
    test_deploy_then_attack(t)
    test_attack_once_per_round(t)
    test_invalid_target(t)
    test_pass_then_react(t)
    test_reaction_window_profile(t)
    test_simultaneous_defeat(t)
    test_persistent_destinations(t)
    test_parfait_refund(t)
    test_sorbet_named_type(t)
    test_chain_rules(t)
    test_x_is_locked(t)
    test_instance_integrity(t)


# ------------------------------------------------------------------ helpers ---

func _fresh(hero0: String = "FIX_HERO_A", hero1: String = "FIX_HERO_B", seed_value: int = 7) -> GameState:
    return F.fresh(hero0, hero1, seed_value)


## Both players pass, the Sequence resolves, and the round completes.
## Resolution always happens after the Action Phase, so control returns in the
## next round's Action Phase.
func _finish_round(st: GameState) -> void:
    F.pass_round(st)


# --------------------------------------------------------------------- tests ---

func test_deck_legality(t: TestHarness) -> void:
    t.begin("deck legality")
    var cat := F.catalog()
    var rules := F.rules()

    var good := F.sink_deck("FIX_HERO_A")
    var r := DeckValidator.validate(cat, rules, good)
    t.ok(r["ok"], "a Hero plus exactly 45 cards with mixed Affinities is legal: %s" % str(r["errors"]))
    t.eq(r["count"], 45, "the Hit Deck holds 45 cards")

    var four := F.sink_deck("FIX_HERO_A")
    (four["cards"] as Dictionary)["FIX_BURN"] = 4
    (four["cards"] as Dictionary)["FIX_DRAW"] = 2
    var r2 := DeckValidator.validate(cat, rules, four)
    t.ok(not r2["ok"], "a fourth copy of the same card name is rejected")

    var short_deck := {"hero": "FIX_HERO_A", "cards": {"FIX_BURN": 3}}
    t.ok(not DeckValidator.validate(cat, rules, short_deck)["ok"], "a 3-card deck is rejected")

    var no_hero := F.sink_deck("")
    t.ok(not DeckValidator.validate(cat, rules, no_hero)["ok"], "a deck with no Hero is rejected")

    var hero_inside := F.sink_deck("FIX_HERO_A")
    (hero_inside["cards"] as Dictionary)["FIX_HERO_B"] = 1
    t.ok(not DeckValidator.validate(cat, rules, hero_inside)["ok"], "a Hero inside the deck is rejected")

    # Ownership is checked per deck and saving never consumes cards.
    var owned: Dictionary = {"FIX_HERO_A": 1}
    for id in F.SINK:
        owned[id] = 3
    owned["FIX_BURN"] = 2
    var r3 := DeckValidator.validate(cat, rules, F.sink_deck("FIX_HERO_A"), owned)
    t.ok(not r3["ok"], "using 3 copies while owning 2 is reported")
    owned["FIX_BURN"] = 3
    t.ok(DeckValidator.validate(cat, rules, F.sink_deck("FIX_HERO_A"), owned)["ok"],
        "owning enough copies passes the ownership check")

    # The same owned copies may back several saved decks.
    var need := DeckValidator.union_requirements([
        F.sink_deck("FIX_HERO_A"), F.sink_deck("FIX_HERO_B")])
    t.eq(int(need["FIX_BURN"]), 3, "two decks each using 3 copies need 3 copies in total, not 6")


func test_draw_to_five(t: TestHarness) -> void:
    t.begin("draw phase")
    var st := F.match_of(F.sink_deck("FIX_HERO_A"), F.sink_deck("FIX_HERO_B"), 11)
    t.eq(st.player(0).hand.size(), 5, "P1 drew to five in round one")
    t.eq(st.player(1).hand.size(), 5, "P2 drew to five in round one")

    # A player already holding six draws nothing and does not discard to five.
    F.to_hand(st, 0, "FIX_BURN")
    t.eq(st.player(0).hand.size(), 6, "P1 now holds six cards")
    F.pass_round(st)
    t.eq(st.player(0).hand.size(), 6, "holding six, P1 draws nothing and keeps all six")
    t.eq(st.player(1).hand.size(), 5, "P2 refills to five")

    # Exhaust is only recycled when a draw actually requires it.
    var st2 := _fresh()
    var p := st2.player(0)
    var kept: Array = p.hit.duplicate()
    for iid in kept:
        st2.move_to_pile(String(iid), "exhaust")
    t.eq(p.hit.size(), 0, "Hit Deck emptied for the test")
    var before_exhaust := p.exhaust.size()
    t.ge(before_exhaust, 5.0, "Exhaust Deck holds cards")
    F.pass_round(st2)
    t.ok(p.hit.size() > 0, "the Draw Phase recycled Exhaust into a new Hit Deck when it had to")
    t.ok(p.wound.is_empty(), "recycling does not touch the Wound Deck")


func test_exact_exhaustion(t: TestHarness) -> void:
    t.begin("exact exhaustion is not itself a loss")
    var st := _fresh()
    var p := st.player(0)
    # Leave exactly five cards across Hit plus Exhaust, so the next Draw Phase
    # is satisfied exactly and both piles end empty.
    var all_cards: Array = p.hit.duplicate()
    for i in all_cards.size():
        if i < 3:
            st.move_to_pile(String(all_cards[i]), "hit")
        elif i < 5:
            st.move_to_pile(String(all_cards[i]), "exhaust")
        else:
            st.move_to_pile(String(all_cards[i]), "wound")
    t.eq(p.hit.size() + p.exhaust.size(), 5, "exactly five cards remain across Hit plus Exhaust")

    F.pass_round(st)
    t.eq(p.hit.size() + p.exhaust.size(), 0, "the required draw consumed both piles exactly")
    t.eq(st.result, null, "emptying both piles exactly does not end the match")
    t.eq(p.hand.size(), 5, "the five drawn cards are in hand, where they cannot satisfy a later draw")

    # The next unsatisfied requirement is what loses.
    var held: Array = p.hand.duplicate()
    for iid in held:
        st.move_to_pile(String(iid), "wound")
    F.pass_round(st)
    t.ne(st.result, null, "the next Draw Phase cannot be satisfied and ends the match")
    if st.result != null:
        t.eq(int((st.result as Dictionary).get("winner", -2)), 1, "P2 wins after P1 fails a required draw")


func test_hero_damage_order(t: TestHarness) -> void:
    t.begin("Hero damage takes Exhaust first, then Hit, without reshuffling")
    var st := _fresh()
    var p := st.player(1)
    var cards: Array = p.hit.duplicate()
    for i in cards.size():
        if i < 2:
            st.move_to_pile(String(cards[i]), "exhaust")
    var exhaust_before := p.exhaust.size()
    var hit_before := p.hit.size()
    t.eq(exhaust_before, 2, "P2 has two cards in Exhaust")

    Mechanics.hero_damage(st, 1, 3, "test")
    t.eq(p.exhaust.size(), 0, "both Exhaust cards were Wounded first")
    t.eq(p.hit.size(), hit_before - 1, "the remaining damage came from Hit")
    t.eq(p.wound.size(), 3, "three cards are in the Wound Deck")
    t.eq(st.result, null, "the Hero survives because Hit plus Exhaust supplied the damage")

    # There is no separate Hero health total: damage only removes cards.
    t.eq(st.current_defense(p.hero_iid), 2, "the Hero's Defense is unchanged by damage")

    # Failing to supply the full amount loses.
    var st2 := _fresh()
    var q := st2.player(1)
    var leftover: Array = q.hit.duplicate()
    for i in leftover.size():
        if i >= 2:
            st2.move_to_pile(String(leftover[i]), "wound")
    t.eq(q.hit.size() + q.exhaust.size(), 2, "only two cards remain to absorb damage")
    Mechanics.hero_damage(st2, 1, 5, "test")
    Mechanics.settle_failures(st2)
    t.ne(st2.result, null, "damage beyond Hit plus Exhaust loses the match")


func test_companion_damage(t: TestHarness) -> void:
    t.begin("Companion damage")
    var st := _fresh()
    # Deploy a tough Companion (1/5) for P2 and attack it with a 3/1 Hero.
    var tough := F.to_hand(st, 1, "FIX_COMP_TOUGH")
    Mechanics.deploy_companion(st, tough, 1)
    st.inst(tough).deployed_round = 0
    t.eq(st.current_defense(tough), 5, "the Companion has Defense 5")

    var ra := GameEngine.submit(st, {"cmd": "commit_attack", "player": 0,
        "attacker_iid": st.player(0).hero_iid, "target_iid": tough})
    t.ok(ra["ok"], "the attack into Defense 5 was committed: %s" % str(ra["error"]))
    _finish_round(st)
    t.eq(st.inst(tough).zone, "companions", "zero damage does not destroy the Companion")
    t.ok(st.player(1).wound.is_empty(), "nothing went to the Wound Deck")

    # Positive damage destroys it and sends it to its owner's Wound Deck.
    var st2 := _fresh()
    var comp := F.to_hand(st2, 1, "FIX_COMP")
    Mechanics.deploy_companion(st2, comp, 1)
    st2.inst(comp).deployed_round = 0
    var rb := GameEngine.submit(st2, {"cmd": "commit_attack", "player": 0,
        "attacker_iid": st2.player(0).hero_iid, "target_iid": comp})
    t.ok(rb["ok"], "the attack was committed: %s" % str(rb["error"]))
    _finish_round(st2)
    t.eq(st2.inst(comp).zone, "wound", "positive damage sends the Companion to Wound")
    t.eq(st2.inst(comp).owner, 1, "it goes to its own owner's Wound Deck")


func test_energy_rules(t: TestHarness) -> void:
    t.begin("Energy")
    var st := _fresh()
    t.eq(st.energy_max(0), 4, "the Hero's printed maximum is the starting maximum")
    t.eq(st.player(0).energy_current, 4, "current Energy starts at the maximum")

    # Cost is paid on commitment, not on resolution.
    var burn := F.to_hand(st, 0, "FIX_BURN")
    var res := GameEngine.submit(st, {"cmd": "commit_card", "player": 0, "card_iid": burn, "targets": []})
    t.ok(res["ok"], "committing a 1-cost Skill succeeds: %s" % str(res["error"]))
    t.eq(st.player(0).energy_current, 3, "Energy was spent at commitment")

    # A Companion raises the maximum only; it grants no current Energy.
    var st2 := _fresh()
    var comp := F.to_hand(st2, 0, "FIX_COMP")
    var before_current := st2.player(0).energy_current
    Mechanics.deploy_companion(st2, comp, 0)
    t.eq(st2.energy_max(0), 6, "the Companion's printed Energy raised the maximum to 6")
    t.eq(st2.player(0).energy_current, before_current, "entering play granted no current Energy")

    # A refund caps at the current maximum.
    Mechanics.gain_energy(st2, 0, 10, "test")
    t.eq(st2.player(0).energy_current, 6, "a refund cannot exceed the maximum")

    # Losing the Companion drops the maximum and clamps current Energy at once.
    Mechanics.destroy(st2, comp, "test")
    t.eq(st2.energy_max(0), 4, "the maximum fell when the Companion left play")
    t.eq(st2.player(0).energy_current, 4, "current Energy was clamped immediately")

    # Round End refreshes current Energy to the current maximum.
    var st3 := _fresh()
    Mechanics.pay_energy(st3, 0, 3)
    t.eq(st3.player(0).energy_current, 1, "Energy was spent")
    F.pass_round(st3)
    t.eq(st3.player(0).energy_current, st3.energy_max(0), "Round End refreshed Energy to the maximum")


func test_deploy_then_attack(t: TestHarness) -> void:
    t.begin("a Companion deployed this round cannot attack this round")
    var st := _fresh()
    var comp := F.to_hand(st, 0, "FIX_COMP")
    var res := GameEngine.submit(st, {"cmd": "commit_card", "player": 0, "card_iid": comp, "targets": []})
    t.ok(res["ok"], "the Companion was committed: %s" % str(res["error"]))
    t.eq(st.inst(comp).zone, "sequence", "the card sits in the Action Sequence until its step resolves")
    t.ok(not st.player(0).companions.has(comp), "it is not in play yet, so it grants no Energy maximum")
    t.eq(st.energy_max(0), 4, "a pending Companion contributes nothing to the maximum")

    _finish_round(st)
    t.eq(st.inst(comp).zone, "companions", "the Companion entered play when its deployment step resolved")
    t.eq(st.inst(comp).deployed_round, 1, "it is recorded as deployed in round 1")
    t.eq(st.energy_max(0), 6, "now in play, it raises the maximum Energy")
    t.eq(st.round_number, 2, "deployment resolves after the Action Phase, so it could not have attacked in round 1")
    t.ok(GameEngine._attack_candidates(st, 0).has(comp), "in the following round it may attack")

    # The guard itself: a Companion whose deployment round is the current round
    # is never an attack candidate, whatever put it into play.
    st.inst(comp).deployed_round = st.round_number
    t.ok(not GameEngine._attack_candidates(st, 0).has(comp),
        "a Companion deployed in the current round is excluded from attacking")
    st.action_priority = 0
    var blocked := GameEngine.submit(st, {"cmd": "commit_attack", "player": 0,
        "attacker_iid": comp, "target_iid": st.player(1).hero_iid})
    t.ok(not blocked["ok"], "committing its attack is refused")
    t.ok(String(blocked["error"]).contains("deployed this round"), "the refusal explains why: %s" % str(blocked["error"]))


func test_attack_once_per_round(t: TestHarness) -> void:
    t.begin("one Sequence appearance per character, refunds do not reset it")
    var st := _fresh()
    var hero := st.player(0).hero_iid
    var r1 := GameEngine.submit(st, {"cmd": "commit_attack", "player": 0,
        "attacker_iid": hero, "target_iid": st.player(1).hero_iid})
    t.ok(r1["ok"], "the first attack is legal: %s" % str(r1["error"]))
    t.eq(st.player(0).energy_current, 3, "the attack cost one Energy")

    # Refund the Energy and try again: the allowance is still spent.
    Mechanics.gain_energy(st, 0, 1, "test refund")
    t.eq(st.player(0).energy_current, 4, "Energy was refunded to the maximum")
    st.action_priority = 0
    var r2 := GameEngine.submit(st, {"cmd": "commit_attack", "player": 0,
        "attacker_iid": hero, "target_iid": st.player(1).hero_iid})
    t.ok(not r2["ok"], "the same character cannot appear in the Sequence twice in a round")
    t.ok(String(r2["error"]).contains("already appeared"), "the refusal explains why: %s" % str(r2["error"]))


func test_invalid_target(t: TestHarness) -> void:
    t.begin("an invalid target finishes the Action with no retarget and no refund")
    var st := _fresh()
    var comp := F.to_hand(st, 1, "FIX_COMP")
    Mechanics.deploy_companion(st, comp, 1)
    st.inst(comp).deployed_round = 0

    var r := GameEngine.submit(st, {"cmd": "commit_attack", "player": 0,
        "attacker_iid": st.player(0).hero_iid, "target_iid": comp})
    t.ok(r["ok"], "the attack was committed against the Companion: %s" % str(r["error"]))
    var slot0: ActionSlot = st.sequence[0]
    var energy_after_commit := st.player(0).energy_current

    # Remove the target before resolution.
    Mechanics.destroy(st, comp, "test removal")
    t.eq(st.inst(comp).zone, "wound", "the declared target left play before resolution")

    _finish_round(st)

    t.ok(st.player(0).energy_current >= energy_after_commit,
        "Energy was not refunded by the failed target (it only refreshed at Round End)")
    var refunded := false
    for e in st.events:
        if String(e.get("kind", "")) == "energy_gained" and int(e.get("player", -1)) == 0:
            refunded = true
    t.ok(not refunded, "no Energy refund was issued for the invalid target")
    t.eq(st.player(1).wound.size(), 1, "the attack did not hit the Hero instead")
    var saw_message := false
    for e in st.events:
        if String(e.get("kind", "")) == "attack_no_target":
            saw_message = true
    t.ok(saw_message, "the log records that the attack affected no target but still resolved")
    t.ok(slot0.resolved, "the step finished normally")
    t.ok(st.player(0).committed_characters.is_empty() or st.round_number > 1,
        "the character's action allowance was not restored within the round")


func test_pass_then_react(t: TestHarness) -> void:
    t.begin("passing Actions still permits Reactions")
    var st := _fresh()
    var guard_card := F.to_hand(st, 1, "FIX_REACT_SHIELD")
    var r := GameEngine.submit(st, {"cmd": "commit_attack", "player": 0,
        "attacker_iid": st.player(0).hero_iid, "target_iid": st.player(1).hero_iid})
    t.ok(r["ok"], "P1 commits an attack")
    GameEngine.submit(st, {"cmd": "pass_actions", "player": 1})
    var blocked := GameEngine.submit(st, {"cmd": "commit_card", "player": 1, "card_iid": guard_card, "targets": []})
    t.ok(not blocked["ok"], "after passing, P2 cannot commit a normal Action")
    GameEngine.submit(st, {"cmd": "pass_actions", "player": 0})

    t.ok(st.pending is Dictionary, "resolution opened a pending choice")
    if st.pending is Dictionary:
        var p: Dictionary = st.pending
        t.eq(String(p.get("kind", "")), "reaction_window", "a Reaction window is open")
        t.eq(int(p.get("player", -1)), 1, "the opponent of the step's controller acts first")
        var legal := GameEngine.legal_reactions(st, 1)
        t.ok(legal.size() > 0, "P2 may still play a Reaction despite having passed Actions")
        var played := GameEngine.submit(st, {"cmd": "play_reaction", "player": 1,
            "card_iid": guard_card, "targets": []})
        t.ok(played["ok"], "the Reaction was committed: %s" % str(played["error"]))
        var paid := false
        for e in st.events:
            if String(e.get("kind", "")) == "energy_spent" and int(e.get("player", -1)) == 1 \
                    and int(e.get("amount", 0)) == 1:
                paid = true
        t.ok(paid, "the Reaction's cost was paid on commitment")

    var guard2 := 0
    while st.result == null and st.round_number == 1 and guard2 < 200:
        guard2 += 1
        if st.pending != null:
            F._auto_answer(st)
        else:
            GameEngine.advance(st)
    # The Guard prevented three damage, so the Hero lost no cards.
    t.eq(st.player(1).wound.size(), 0, "the defensive Reaction prevented the attack's damage")


func test_reaction_window_profile(t: TestHarness) -> void:
    t.begin("Reaction window: priority, passes, re-entry, ordering, no nesting")
    var st := _fresh()
    var shield := F.to_hand(st, 1, "FIX_REACT_SHIELD")
    var weaken := F.to_hand(st, 1, "FIX_REACT_WEAKEN")
    var shield2 := F.to_hand(st, 0, "FIX_REACT_SHIELD")
    # Give both players enough Energy for several Reactions.
    st.player(0).energy_current = 4
    st.player(1).energy_current = 4

    var rc := GameEngine.submit(st, {"cmd": "commit_attack", "player": 0,
        "attacker_iid": st.player(0).hero_iid, "target_iid": st.player(1).hero_iid})
    t.ok(rc["ok"], "P1 commits an attack: %s" % str(rc["error"]))
    var slot0: ActionSlot = st.sequence[0]
    GameEngine.submit(st, {"cmd": "pass_actions", "player": 1})
    GameEngine.submit(st, {"cmd": "pass_actions", "player": 0})

    if not (st.pending is Dictionary):
        t.ok(false, "a Reaction window should be open before the first step")
        return
    var p: Dictionary = st.pending
    t.eq(int(p.get("player", -1)), 1, "first opportunity goes to the opponent of the step's controller")

    # P2 passes once, P1 passes once -> two consecutive passes close the window.
    GameEngine.submit(st, {"cmd": "pass_reaction", "player": 1})
    t.ok(st.pending is Dictionary, "a second opportunity exists after one pass")
    if st.pending is Dictionary:
        t.eq(int((st.pending as Dictionary).get("player", -1)), 0, "opportunities alternate")
        # P1 commits a Reaction, which resets the pass count and lets P2 re-enter.
        var r := GameEngine.submit(st, {"cmd": "play_reaction", "player": 0,
            "card_iid": shield2, "targets": []})
        t.ok(r["ok"], "P1 commits a Reaction: %s" % str(r["error"]))
    t.ok(st.pending is Dictionary, "the window is still open after a Reaction was added")
    if st.pending is Dictionary:
        t.eq(int((st.pending as Dictionary).get("player", -1)), 1, "P2 may re-enter after having passed once")
        var r2 := GameEngine.submit(st, {"cmd": "play_reaction", "player": 1,
            "card_iid": weaken, "targets": []})
        t.ok(r2["ok"], "P2 adds a Reaction after re-entering: %s" % str(r2["error"]))
        # No nested window: the Reaction just committed does not open a new one.
        t.eq(int((st.pending as Dictionary).get("slot", -1)), 0, "still the same step's window; no nesting")

    GameEngine.submit(st, {"cmd": "pass_reaction", "player": 0})
    GameEngine.submit(st, {"cmd": "pass_reaction", "player": 1})
    t.eq(slot0.reactions.size(), 2, "both Reactions are attached to the step")
    t.ok(slot0.window_done, "two consecutive passes closed the window")
    F.pass_round(st)
    # Weaken reduced the 3-Attack Hero to 1, and the Hero's Defense is 2,
    # so the attack dealt no damage at all.
    t.eq(st.player(1).wound.size(), 0, "the before-Action Reactions applied before the attack resolved")
    var order: Array = []
    for e in st.events:
        if String(e.get("kind", "")) == "resolving_reaction":
            order.append(String(e.get("iid", "")))
    t.eq(order, [shield2, weaken], "before-Action Reactions resolved in commitment order")


func test_simultaneous_defeat(t: TestHarness) -> void:
    t.begin("simultaneous defeat at the Draw Phase is a draw")
    var st := _fresh()
    for i in 2:
        var p := st.player(i)
        var cards: Array = p.hit.duplicate()
        for iid in cards:
            st.move_to_pile(String(iid), "wound")
        var hand: Array = p.hand.duplicate()
        for iid in hand:
            st.move_to_pile(String(iid), "wound")
    t.eq(st.player(0).hit.size() + st.player(0).exhaust.size(), 0, "P1 has no cards to draw")
    t.eq(st.player(1).hit.size() + st.player(1).exhaust.size(), 0, "P2 has no cards to draw")

    F.pass_round(st)
    t.ne(st.result, null, "the match ended")
    if st.result != null:
        t.eq(int((st.result as Dictionary).get("winner", -2)), -1, "both failing at the same boundary is a draw")


func test_persistent_destinations(t: TestHarness) -> void:
    t.begin("persistent card destinations")
    var st := _fresh()
    var hero := st.player(0).hero_iid

    # Equipment replacement sends the old card to its owner's Exhaust.
    var eq1 := F.to_hand(st, 0, "FIX_EQUIP")
    var eq2 := F.to_hand(st, 0, "FIX_EQUIP")
    Mechanics.attach_card(st, eq1, hero)
    t.eq(st.current_attack(hero), 5, "the Equipment's aura raised the Hero's Attack to 5")
    Mechanics.attach_card(st, eq2, hero)
    t.eq(st.inst(eq1).zone, "exhaust", "the replaced Equipment went to Exhaust, not Wound")
    t.eq(st.inst(eq2).zone, "attached", "the new Equipment is attached")
    t.eq(st.current_attack(hero), 5, "only one Equipment applies at a time")

    # Explicit destruction sends it to Wound.
    Mechanics.destroy(st, eq2, "test")
    t.eq(st.inst(eq2).zone, "wound", "destroyed Equipment goes to Wound")
    t.eq(st.current_attack(hero), 3, "the aura stopped applying")

    # A character may hold one Equipment and one Ta'ahma at once.
    var eq3 := F.to_hand(st, 0, "FIX_EQUIP")
    var ta := F.to_hand(st, 0, "FIX_TAAHMA")
    Mechanics.attach_card(st, eq3, hero)
    Mechanics.attach_card(st, ta, hero)
    t.eq(st.inst(eq3).zone, "attached", "the Equipment is still attached")
    t.eq(st.inst(ta).zone, "attached", "the Ta'ahma attached alongside it")
    t.eq(st.current_attack(hero), 5, "the Equipment still grants +2 Attack")
    t.eq(st.current_defense(hero), 3, "the Ta'ahma grants +2 Defense")

    # Ta'ahma replacement matches Equipment: the previous card Exhausts.
    var ta2 := F.to_hand(st, 0, "FIX_TAAHMA")
    Mechanics.attach_card(st, ta2, hero)
    t.eq(st.inst(ta).zone, "exhaust", "the replaced Ta'ahma went to Exhaust")

    # Location replacement Exhausts the old one; destruction Wounds it.
    var loc1 := F.to_hand(st, 0, "FIX_LOCATION")
    var loc2 := F.to_hand(st, 1, "FIX_LOCATION")
    Mechanics.place_location(st, loc1)
    t.eq(st.location_iid, loc1, "the first Location is active")
    Mechanics.place_location(st, loc2)
    t.eq(st.inst(loc1).zone, "exhaust", "the replaced Location went to its owner's Exhaust")
    t.eq(st.inst(loc1).owner, 0, "it returned to its original owner's pile")
    Mechanics.destroy(st, loc2, "test")
    t.eq(st.inst(loc2).zone, "wound", "a destroyed Location goes to Wound")
    t.eq(st.location_iid, "", "no Location is active")

    # An attachment that loses its host goes to its owner's Exhaust.
    var st2 := _fresh()
    var comp := F.to_hand(st2, 0, "FIX_COMP")
    var eq4 := F.to_hand(st2, 0, "FIX_EQUIP")
    Mechanics.deploy_companion(st2, comp, 0)
    Mechanics.attach_card(st2, eq4, comp)
    t.eq(st2.current_attack(comp), 4, "the Companion gained +2 Attack from the Equipment")
    Mechanics.destroy(st2, comp, "test")
    t.eq(st2.inst(comp).zone, "wound", "the destroyed Companion went to Wound")
    t.eq(st2.inst(eq4).zone, "exhaust", "its orphaned attachment went to Exhaust")


func test_parfait_refund(t: TestHarness) -> void:
    t.begin("Parfait refunds her own Passion attack before leaving the Sequence")
    var st := F.fresh("FIX_HERO_PARFAIT", "FIX_HERO_B", 5)
    var parfait := st.player(0).hero_iid
    t.eq(st.player(0).energy_current, 4, "Parfait starts at her maximum Energy")

    var r := GameEngine.submit(st, {"cmd": "commit_attack", "player": 0,
        "attacker_iid": parfait, "target_iid": st.player(1).hero_iid})
    t.ok(r["ok"], "her Passion attack was committed: %s" % str(r["error"]))
    t.eq(st.player(0).energy_current, 3, "she paid one Energy on commitment")
    t.ok(st.sequence_members.has(parfait), "she is in the Action Sequence from commitment")

    GameEngine.submit(st, {"cmd": "pass_actions", "player": 1})
    GameEngine.submit(st, {"cmd": "pass_actions", "player": 0})
    var guard := 0
    while st.result == null and st.round_number == 1 and guard < 200:
        guard += 1
        if st.pending != null:
            F._auto_answer(st)
        else:
            GameEngine.advance(st)

    t.eq(st.player(0).energy_current, 4, "her own attack resolving refunded the Energy, capped at her maximum")
    t.ok(not st.sequence_members.has(parfait), "she left the Sequence after her resolution triggers finished")

    var refund_before_exit := false
    var seen_refund := false
    for e in st.events:
        var kind := String(e.get("kind", ""))
        if kind == "energy_gained" and int(e.get("player", -1)) == 0:
            seen_refund = true
        if kind == "left_sequence" and seen_refund:
            refund_before_exit = true
    t.ok(refund_before_exit, "the refund was logged before she left the Sequence")


## Sorbet names a Card Type when her attack resolves, and every Vigilance
## Companion her controller has grows each time a card of that type resolves
## after her. A card of another type must do nothing, or the choice is
## decoration rather than a decision.
func test_sorbet_named_type(t: TestHarness) -> void:
    t.begin("Sorbet's named Card Type decides what grows her Companions")
    F.auto_card_type = "skill"
    var st := F.fresh_decks(
        F.deck("FIX_HERO_SORBET", {"FIX_COMP_VIG": 3, "FIX_COMP": 3, "FIX_EQUIP": 3}),
        F.sink_deck("FIX_HERO_B"), 11)
    var sorbet := st.player(0).hero_iid
    st.player(0).energy_max_mods.append({"amount": 8, "expires": "permanent"})
    st.player(1).energy_max_mods.append({"amount": 8, "expires": "permanent"})
    st.player(0).energy_current = 12
    st.player(1).energy_current = 12

    # Already in play, so the round under test is only about what she names.
    var vig := F.to_hand(st, 0, "FIX_COMP_VIG")
    var will := F.to_hand(st, 0, "FIX_COMP")
    Mechanics.deploy_companion(st, vig, 0)
    Mechanics.deploy_companion(st, will, 0)
    st.inst(vig).deployed_round = 0
    st.inst(will).deployed_round = 0
    t.eq(st.current_attack(vig), 1, "the Vigilance Companion starts at its printed 1 Attack")
    t.eq(st.current_attack(will), 2, "and the Will Companion at its printed 2")

    # Sorbet first, then a Skill, then an Equipment. Only the Skill matches.
    st.action_priority = 0
    t.ok(bool(GameEngine.submit(st, {"cmd": "commit_attack", "player": 0,
        "attacker_iid": sorbet, "target_iid": st.player(1).hero_iid})["ok"]),
        "Sorbet's attack was committed first")
    var burn := F.to_hand(st, 1, "FIX_BURN")
    t.ok(bool(GameEngine.submit(st, {"cmd": "commit_card", "player": 1,
        "card_iid": burn, "targets": []})["ok"]), "a Skill was committed after her")
    var equip := F.to_hand(st, 0, "FIX_EQUIP")
    t.ok(bool(GameEngine.submit(st, {"cmd": "commit_card", "player": 0,
        "card_iid": equip, "targets": [sorbet]})["ok"]), "and an Equipment after that")

    # Three commitments alternate priority back to P2, so P2 passes first.
    GameEngine.submit(st, {"cmd": "pass_actions", "player": 1})
    GameEngine.submit(st, {"cmd": "pass_actions", "player": 0})
    # Drive the whole round. The buffs are for the round, so they are gone by
    # the time it ends: what they did is read from the event record, which is
    # the durable account of what happened.
    var guard := 0
    while st.result == null and st.round_number == 1 and guard < 300:
        guard += 1
        if st.pending != null:
            F._auto_answer(st)
        else:
            GameEngine.advance(st)

    var named := ""
    var left_sequence_at := -1
    var vig_buffs: Array = []
    var will_buffs: Array = []
    for i in st.events.size():
        var e: Dictionary = st.events[i]
        match String(e.get("kind", "")):
            "card_type_chosen":
                if String(e.get("iid", "")) == sorbet:
                    named = String(e.get("card_type", ""))
            "left_sequence":
                if String(e.get("iid", "")) == sorbet:
                    left_sequence_at = i
            "stat_modified":
                if String(e.get("iid", "")) == vig:
                    vig_buffs.append(i)
                elif String(e.get("iid", "")) == will:
                    will_buffs.append(i)
    t.eq(named, "skill", "she named a Card Type as her attack resolved")

    # One Skill resolved after her, so exactly one +1/+1 landed. The Equipment
    # resolved after her too and is of another type, so it added nothing.
    t.eq(vig_buffs.size(), 1, "the Vigilance Companion grew exactly once, for the Skill")
    t.empty(will_buffs, "the Will Companion never grew: the buff reads Vigilance")
    t.ge(float(left_sequence_at), 0.0, "she left the Sequence when her attack resolved")
    if not vig_buffs.is_empty():
        t.ok(int(vig_buffs[0]) > left_sequence_at,
            "and the buff landed after she had left it, because it is worded for the round")

    # The growth and the naming are both for this round only.
    t.eq(st.current_attack(vig), 1, "the growth expired at Round End")
    t.eq(st.current_defense(vig), 1, "in Defense as well")
    t.eq(st.inst(sorbet).chosen_type, "", "and the named type is forgotten with it")


func test_chain_rules(t: TestHarness) -> void:
    t.begin("Affinity chain history")
    var st := _fresh("FIX_HERO_PARFAIT", "FIX_HERO_B")
    F.clear_hands(st)
    st.player(0).energy_current = 8
    st.player(1).energy_current = 8
    st.player(0).energy_max_mods.append({"amount": 6, "expires": "permanent"})
    st.player(1).energy_max_mods.append({"amount": 6, "expires": "permanent"})

    var burn1 := F.to_hand(st, 0, "FIX_BURN")     # Passion
    var burn2 := F.to_hand(st, 1, "FIX_BURN")     # Passion
    var neutral := F.to_hand(st, 0, "FIX_NEUTRAL")  # no Affinity
    var chain := F.to_hand(st, 1, "FIX_CHAIN")    # Passion, pays off at 2+ Passion

    GameEngine.submit(st, {"cmd": "commit_card", "player": 0, "card_iid": burn1, "targets": []})
    GameEngine.submit(st, {"cmd": "commit_card", "player": 1, "card_iid": burn2, "targets": []})
    GameEngine.submit(st, {"cmd": "commit_card", "player": 0, "card_iid": neutral, "targets": []})
    GameEngine.submit(st, {"cmd": "commit_card", "player": 1, "card_iid": chain, "targets": []})

    t.eq(st.sequence.size(), 4, "four Actions are in the Sequence")
    t.eq(AffinityChain.count(st, 1, "passion", "either", 0), 2, "slots 0-1 form a 2-Passion run")
    t.eq(AffinityChain.count(st, 2, "passion", "either", 0), 0, "a card with no Affinity breaks the chain")
    t.eq(AffinityChain.count(st, 3, "passion", "either", 0), 1,
        "the run after the neutral card counts only the current slot")
    t.eq(AffinityChain.count(st, 1, "passion", "controller", 0), 1, "controller scope counts only your own slots")
    t.eq(AffinityChain.run_ending_at(st, 2).size(), 0, "a neutral Action cannot start a chain")

    # Never count later slots: evaluating at slot 0 sees only slot 0.
    t.eq(AffinityChain.count(st, 0, "passion", "either", 0), 1, "evaluating at slot 0 ignores later slots")

    GameEngine.submit(st, {"cmd": "pass_actions", "player": 0})
    GameEngine.submit(st, {"cmd": "pass_actions", "player": 1})
    var hand_before := st.player(1).hand.size()
    var guard := 0
    while st.result == null and st.round_number == 1 and guard < 300:
        guard += 1
        if st.pending != null:
            F._auto_answer(st)
        else:
            GameEngine.advance(st)

    var missed := false
    for e in st.events:
        if String(e.get("kind", "")) == "chain_reward_missed":
            missed = true
    t.ok(missed, "the chain payoff did not fire because the neutral card broke the run")

    # Slot history survives the cards leaving the physical Sequence.
    t.eq(st.round_history.size(), 1, "the resolved round's slots were archived for chain inspection")
    var archived: Array = (st.round_history[0] as Dictionary)["slots"]
    t.eq(archived.size(), 4, "all four slot records were retained")


func test_x_is_locked(t: TestHarness) -> void:
    t.begin("a chosen X stays the amount paid")
    var st := _fresh()
    st.player(0).energy_max_mods.append({"amount": 4, "expires": "permanent"})
    st.player(0).energy_current = 8
    var xburn := F.to_hand(st, 0, "FIX_XBURN")
    var r := GameEngine.submit(st, {"cmd": "commit_card", "player": 0, "card_iid": xburn, "targets": [], "x": 3})
    if not t.ok(r["ok"], "X = 3 was committed: %s" % str(r["error"])):
        return
    t.eq(st.player(0).energy_current, 5, "three Energy was spent")
    t.eq((st.sequence[0] as ActionSlot).x_paid, 3, "the committed Action recorded X = 3")

    # A later refund must not rewrite X.
    Mechanics.gain_energy(st, 0, 3, "test refund")
    t.eq((st.sequence[0] as ActionSlot).x_paid, 3, "X is still 3 after an Energy refund")

    var wound_before := st.player(1).wound.size()
    GameEngine.submit(st, {"cmd": "pass_actions", "player": 1})
    GameEngine.submit(st, {"cmd": "pass_actions", "player": 0})
    var guard := 0
    while st.result == null and st.round_number == 1 and guard < 200:
        guard += 1
        if st.pending != null:
            F._auto_answer(st)
        else:
            GameEngine.advance(st)
    t.eq(st.player(1).wound.size() - wound_before, 3, "the card dealt exactly the 3 damage it was paid for")


func test_instance_integrity(t: TestHarness) -> void:
    t.begin("every card instance is in exactly one zone")
    var st := F.match_of(F.sink_deck("FIX_HERO_A"), F.sink_deck("FIX_HERO_B"), 99)
    for _r in 6:
        if st.result != null:
            break
        F.pass_round(st)
    t.empty(_integrity_problems(st), "no duplicate or missing instances after several rounds")


func _integrity_problems(st: GameState) -> Array:
    var problems: Array = []
    var seen: Dictionary = {}
    for i in 2:
        var p := st.player(i)
        for zone in ["hand", "hit", "exhaust", "wound", "companions"]:
            for iid in p.pile(zone):
                if seen.has(iid):
                    problems.append("%s appears in %s and %s" % [iid, seen[iid], zone])
                seen[iid] = zone
        if p.hero_iid != "":
            if seen.has(p.hero_iid):
                problems.append("hero %s also in %s" % [p.hero_iid, seen[p.hero_iid]])
            seen[p.hero_iid] = "hero"
    if st.location_iid != "":
        if seen.has(st.location_iid):
            problems.append("location %s also in %s" % [st.location_iid, seen[st.location_iid]])
        seen[st.location_iid] = "location"
    for iid in st.instances.keys():
        var ci: CardInstance = st.instances[iid]
        if ci.zone == "attached":
            if seen.has(iid):
                problems.append("attachment %s also in %s" % [iid, seen[iid]])
            seen[iid] = "attached"
            if st.inst(ci.attached_to) == null:
                problems.append("attachment %s has no host" % iid)
        elif ci.zone == "sequence":
            if seen.has(iid):
                problems.append("sequence card %s also in %s" % [iid, seen[iid]])
            seen[iid] = "sequence"
    for iid in st.instances.keys():
        if not seen.has(iid):
            problems.append("%s (%s) is in no zone; recorded zone is '%s'" % [
                iid, (st.instances[iid] as CardInstance).def_id, (st.instances[iid] as CardInstance).zone])
    return problems
