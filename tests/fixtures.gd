class_name TestFixtures
extends RefCounted

## Development-only card definitions used by the rules tests.
##
## These are fixtures, not collectible content: they are built in code, never
## written to data/catalog, and never counted toward the 300 definitions.


static func def(overrides: Dictionary) -> Dictionary:
    var base := {
        "id": "FIX_X", "revision": 1, "placeholder": true, "name": "Fixture",
        "types": ["skill"], "tags": [], "affinities": [], "rarity": "common",
        "unique": false, "character_id": "", "cost": {"kind": "fixed", "amount": 0},
        "timing": ["action"], "effects": [], "triggers": [], "patterns": ["fixture"],
    }
    base.merge(overrides, true)
    base["text"] = TextGen.render(CardDef.from_dict(base))
    return base


static func all_defs() -> Array:
    return [
        # --- Heroes -------------------------------------------------------
        def({"id": "FIX_HERO_A", "name": "Fixture Hero A", "types": ["hero"],
            "affinities": ["will"], "rarity": "legendary", "unique": true,
            "character_id": "fix_hero_a", "cost": {"kind": "none"},
            "hero_max_energy": 4, "attack": 3, "defense": 1, "attack_cost": 1,
            "patterns": ["fixture_hero"]}),
        def({"id": "FIX_HERO_B", "name": "Fixture Hero B", "types": ["hero"],
            "affinities": ["silence"], "rarity": "legendary", "unique": true,
            "character_id": "fix_hero_b", "cost": {"kind": "none"},
            "hero_max_energy": 4, "attack": 2, "defense": 2, "attack_cost": 1,
            "patterns": ["fixture_hero"]}),
        # The confirmed Parfait timing example: one Energy for a Passion
        # attack, refunded whenever a Passion card resolves while she is in
        # the Action Sequence — including her own attack.
        def({"id": "FIX_HERO_PARFAIT", "name": "Fixture Hero Parfait", "types": ["hero"],
            "affinities": ["passion"], "rarity": "legendary", "unique": true,
            "character_id": "fix_parfait", "cost": {"kind": "none"},
            "hero_max_energy": 4, "attack": 3, "defense": 1, "attack_cost": 1,
            "triggers": [{"on": {"kind": "affinity_card_resolved", "affinity": "passion", "scope": "either"},
                "effects": [{"op": "energy_gain", "who": "self", "amount": 1}]}],
            "patterns": ["fixture_hero", "energy_refund"]}),

        # --- Companions ---------------------------------------------------
        def({"id": "FIX_COMP", "name": "Fixture Companion", "types": ["companion"],
            "affinities": ["will"], "cost": {"kind": "fixed", "amount": 2},
            "energy_contribution": 2, "attack": 2, "defense": 2, "attack_cost": 1,
            "persistent": {"kind": "companion"}, "patterns": ["deploy"]}),
        def({"id": "FIX_COMP_TOUGH", "name": "Fixture Tough Companion", "types": ["companion"],
            "affinities": ["devotion"], "cost": {"kind": "fixed", "amount": 3},
            "energy_contribution": 3, "attack": 1, "defense": 5, "attack_cost": 1,
            "persistent": {"kind": "companion"}, "patterns": ["deploy", "high_defense"]}),
        def({"id": "FIX_COMP_ETB", "name": "Fixture Herald", "types": ["companion"],
            "affinities": ["passion"], "cost": {"kind": "fixed", "amount": 1},
            "energy_contribution": 1, "attack": 1, "defense": 1, "attack_cost": 1,
            "persistent": {"kind": "companion"},
            "triggers": [{"on": {"kind": "self_deployed"},
                "effects": [{"op": "damage_hero", "who": "opponent", "amount": 1}]}],
            "patterns": ["deploy", "etb_burn"]}),

        # --- Skills -------------------------------------------------------
        def({"id": "FIX_DRAW", "name": "Fixture Draw", "types": ["skill"], "tags": ["magic"],
            "affinities": ["harmony"], "cost": {"kind": "fixed", "amount": 1},
            "effects": [{"op": "draw", "who": "self", "amount": 1}], "patterns": ["draw"]}),
        def({"id": "FIX_BURN", "name": "Fixture Burn", "types": ["skill"], "tags": ["magic", "ranged"],
            "affinities": ["passion"], "cost": {"kind": "fixed", "amount": 1},
            "effects": [{"op": "damage_hero", "who": "opponent", "amount": 2}], "patterns": ["hero_burn"]}),
        def({"id": "FIX_NEUTRAL", "name": "Fixture Neutral Skill", "types": ["skill"], "tags": ["martial"],
            "affinities": [], "cost": {"kind": "fixed", "amount": 0},
            "effects": [{"op": "draw", "who": "self", "amount": 1}], "patterns": ["draw"]}),
        def({"id": "FIX_XBURN", "name": "Fixture X Burn", "types": ["skill"], "tags": ["magic"],
            "affinities": ["passion"], "cost": {"kind": "x", "min": 1},
            "effects": [{"op": "damage_hero", "who": "opponent", "amount": {"from": "x"}}],
            "patterns": ["x_cost", "hero_burn"]}),
        def({"id": "FIX_CHAIN", "name": "Fixture Chain Payoff", "types": ["skill"], "tags": ["magic"],
            "affinities": ["passion"], "cost": {"kind": "fixed", "amount": 1},
            "effects": [{"op": "chain_reward",
                "require": {"min": 2, "affinity": "passion", "scope": "either"},
                "then": [{"op": "draw", "who": "self", "amount": 1}]}],
            "patterns": ["chain_payoff"]}),
        def({"id": "FIX_REMOVE", "name": "Fixture Removal", "types": ["skill"], "tags": ["magic"],
            "affinities": ["silence"], "cost": {"kind": "fixed", "amount": 2},
            "target": {"kind": "opponent_companion", "count": 1},
            "effects": [{"op": "destroy", "target": "chosen"}], "patterns": ["removal"]}),
        def({"id": "FIX_BUFF", "name": "Fixture Buff", "types": ["skill"], "tags": ["martial"],
            "affinities": ["will"], "cost": {"kind": "fixed", "amount": 1},
            "target": {"kind": "own_character", "count": 1},
            "effects": [{"op": "stat_mod", "target": "chosen", "attack": 2, "duration": "round"}],
            "patterns": ["stat_buff"]}),
        def({"id": "FIX_REACT_SHIELD", "name": "Fixture Guard", "types": ["skill"],
            "tags": ["martial", "reaction"], "affinities": ["vigilance"],
            "cost": {"kind": "fixed", "amount": 1}, "timing": ["reaction"], "reaction_window": "before",
            "effects": [{"op": "prevent_damage", "target": "current_target", "amount": 3, "duration": "round"}],
            "patterns": ["defensive_reaction"]}),
        def({"id": "FIX_REACT_WEAKEN", "name": "Fixture Weaken", "types": ["skill"],
            "tags": ["magic", "reaction"], "affinities": ["silence"],
            "cost": {"kind": "fixed", "amount": 1}, "timing": ["reaction"], "reaction_window": "before",
            "effects": [{"op": "stat_mod", "target": "current_attacker", "attack": -2, "duration": "round"}],
            "patterns": ["debuff_reaction"]}),
        def({"id": "FIX_FILLER", "name": "Fixture Filler", "types": ["skill"], "tags": ["martial"],
            "affinities": [], "cost": {"kind": "fixed", "amount": 0},
            "effects": [{"op": "energy_gain", "who": "self", "amount": 1}], "patterns": ["energy"]}),

        # --- Persistent non-characters ------------------------------------
        def({"id": "FIX_EQUIP", "name": "Fixture Blade", "types": ["equipment"],
            "affinities": ["purpose"], "cost": {"kind": "fixed", "amount": 2},
            "attack": 2, "defense": 0, "persistent": {"kind": "attachment", "slot": "equipment"},
            "target": {"kind": "own_character_host", "count": 1},
            "effects": [{"op": "aura_stat_mod", "scope": "host", "attack": 2}],
            "patterns": ["equipment_buff"]}),
        def({"id": "FIX_TAAHMA", "name": "Fixture Ward", "types": ["taahma"],
            "affinities": ["purpose"], "cost": {"kind": "fixed", "amount": 2},
            "persistent": {"kind": "attachment", "slot": "taahma"},
            "target": {"kind": "own_character_host", "count": 1},
            "effects": [{"op": "aura_stat_mod", "scope": "host", "defense": 2}],
            "patterns": ["taahma_buff"]}),
        def({"id": "FIX_LOCATION", "name": "Fixture Field", "types": ["location"],
            "affinities": ["harmony"], "cost": {"kind": "fixed", "amount": 2},
            "persistent": {"kind": "location"},
            "effects": [{"op": "aura_stat_mod", "scope": "all_companions", "attack": 1}],
            "patterns": ["location_aura"]}),
    ]


static func catalog() -> Catalog:
    return Catalog.from_defs(all_defs())


static func rules() -> RulesProfile:
    return RulesProfile.load_from()


## Fifteen distinct fixture definitions, three copies each: a legal 45-card
## Hit Deck that also puts one of everything within reach of the tests.
const SINK := [
    "FIX_COMP", "FIX_COMP_TOUGH", "FIX_COMP_ETB",
    "FIX_DRAW", "FIX_BURN", "FIX_NEUTRAL", "FIX_XBURN", "FIX_CHAIN",
    "FIX_REMOVE", "FIX_BUFF", "FIX_REACT_SHIELD", "FIX_REACT_WEAKEN",
    "FIX_EQUIP", "FIX_TAAHMA", "FIX_LOCATION",
]


static func sink_deck(hero: String) -> Dictionary:
    var cards: Dictionary = {}
    for id in SINK:
        cards[id] = 3
    return {"deck_id": "fixture_sink_" + hero.to_lower(), "hero": hero, "cards": cards}


## A 45-card deck made of `spec` (def_id -> qty) padded with filler.
static func deck(hero: String, spec: Dictionary = {}, filler: String = "FIX_FILLER", size: int = 45) -> Dictionary:
    var cards: Dictionary = spec.duplicate()
    var total := 0
    for k in cards.keys():
        total += int(cards[k])
    if total < size:
        cards[filler] = int(cards.get(filler, 0)) + (size - total)
    return {"deck_id": "fixture_" + hero.to_lower(), "hero": hero, "cards": cards}


static func match_of(deck0: Dictionary, deck1: Dictionary, seed_value: int = 1234) -> GameState:
    return GameEngine.start_match(catalog(), rules(), [deck0, deck1], seed_value,
        "fixture_match", ["P1", "P2"], [false, false], ["", ""])


## A match already in the Action Phase with empty hands and P1 on priority,
## so a test controls exactly what is playable and in what order.
static func fresh(hero0: String = "FIX_HERO_A", hero1: String = "FIX_HERO_B", seed_value: int = 7) -> GameState:
    var st := match_of(sink_deck(hero0), sink_deck(hero1), seed_value)
    setup_action_phase(st)
    clear_hands(st)
    st.first_player = 0
    st.action_priority = 0
    return st


## Move a card of `def_id` from a player's Hit Deck into their hand and return
## its instance id. Tests use this to set up an exact board.
static func to_hand(st: GameState, player: int, def_id: String) -> String:
    for iid in st.player(player).hit:
        var ci: CardInstance = st.instances[iid]
        if ci.def_id == def_id:
            st.move_to_pile(String(iid), "hand")
            return String(iid)
    return ""


static func find_in_hand(st: GameState, player: int, def_id: String) -> String:
    for iid in st.player(player).hand:
        if (st.instances[iid] as CardInstance).def_id == def_id:
            return String(iid)
    return ""


## Clear both hands so a test controls exactly what is playable.
static func clear_hands(st: GameState) -> void:
    for i in 2:
        var hand: Array = st.player(i).hand.duplicate()
        for iid in hand:
            st.move_to_pile(String(iid), "hit")


## Drive to the Action Phase of the current round with empty hands, then put
## the requested cards in hand.
static func setup_action_phase(st: GameState) -> void:
    while st.phase != "action" and st.result == null:
        if st.pending != null:
            _auto_answer(st)
        else:
            GameEngine.advance(st)


static func _auto_answer(st: GameState) -> void:
    var p: Dictionary = st.pending
    var player := int(p.get("player", 0))
    match String(p.get("kind", "")):
        "reaction_window":
            GameEngine.submit(st, {"cmd": "pass_reaction", "player": player})
        "choose_cards":
            var pool: Array = GameEngine._choice_pool(st, p)
            var n: int = min(int(p.get("count", 0)), pool.size())
            GameEngine.submit(st, {"cmd": "choose_cards", "player": player, "iids": pool.slice(0, n)})
        "choose_deploy":
            GameEngine.submit(st, {"cmd": "choose_deploy", "player": player, "card_iid": ""})
        _:
            st.pending = null
            GameEngine.advance(st)


## Play out the round with both players passing, answering any prompts.
static func pass_round(st: GameState) -> void:
    var guard := 0
    var target_round := st.round_number + 1
    while st.result == null and st.round_number < target_round and guard < 500:
        guard += 1
        if st.pending != null:
            _auto_answer(st)
            continue
        if st.phase == "action":
            var who := st.action_priority
            GameEngine.submit(st, {"cmd": "pass_actions", "player": who})
            continue
        GameEngine.advance(st)
