#!/usr/bin/env python3
"""Build the seven starter decks and the seven Affinity AI decklists.

Both sets are ordinary catalog content: they reference definitions by id and
are validated by the real engine (tests/test_catalog.gd). Starters are built
from cards that can legally use three copies; the AI lists additionally
include one named Companion and one Unique Equipment at their legal limit of
one copy, so the deck rules get exercised by real content.

Usage:
    python3 tools/generate_decks.py
"""

import json
import glob
import os

ROOT = os.path.join(os.path.dirname(__file__), "..")
CATALOG = os.path.join(ROOT, "data", "catalog")
DECKS = os.path.join(ROOT, "data", "decks")

AFFINITY_CODES = {
    "devotion": "DEV", "passion": "PAS", "will": "WIL", "vigilance": "VIG",
    "purpose": "PUR", "harmony": "HAR", "silence": "SIL",
}

# The provisional Affinity playstyles, used for the opponent-selection blurbs.
PLANS = {
    "devotion": ("Companion support and protection",
                 "Builds a Companion line, then keeps it alive with protection "
                 "effects and Defense buffs while the Hero grinds you down."),
    "passion": ("Aggression and Energy refunds",
                "Spends Energy freely on burn and attacks, refunding it whenever "
                "Passion cards resolve so it can keep committing Actions."),
    "will": ("Character enhancement and sustained pressure",
             "Grows one or two characters with lasting stat increases and "
             "attacks every round to convert that size into Hero damage."),
    "vigilance": ("Efficient Reactions and defensive timing",
                  "Holds Energy back for Reactions, blunts your attacks as they "
                  "resolve, and wins slowly from a stable board."),
    "purpose": ("Equipment, Ta'ahma and prepared combinations",
                "Assembles attachments on its characters, then cashes in cards "
                "that pay off only when a host is already equipped."),
    "harmony": ("Relationships across Affinities and the Sequence",
                "Commits Affinity-bearing Actions back to back and plays cards "
                "whose payoffs scale with the length of the chain."),
    "silence": ("Disruption, Energy denial and removal",
                "Drains your Energy, shrinks your Companions and removes what it "
                "cannot outmuscle, winning once you cannot act."),
}

# Card slots, as offsets within each Affinity's block.
STARTER_SKILLS = [1, 2, 3, 4, 5, 6, 7, 8, 9]
STARTER_COMPANIONS = [1, 2, 3, 5]
STARTER_EQUIPMENT = [1]
STARTER_TAAHMA = [1]

AI_SKILLS = [1, 2, 5, 13, 14, 17]
AI_COMPANIONS = [2, 4, 6, 7]
AI_EQUIPMENT = [2]
AI_NAMED_COMPANION = 9      # a named character: one copy only
AI_UNIQUE_EQUIPMENT = 4     # marked Unique: one copy only
AI_NEUTRAL_TRIPLES = ["NEU_SKILL_01", "NEU_SKILL_02", "NEU_COMP_02"]
AI_NEUTRAL_SINGLE = "NEU_COMP_01"


def load_catalog():
    cards = {}
    for path in sorted(glob.glob(os.path.join(CATALOG, "*.json"))):
        for c in json.load(open(path)):
            cards[c["id"]] = c
    if not cards:
        raise SystemExit("no catalog found; run tools/generate_catalog.py first")
    return cards


def cid(code, kind, index):
    return "%s_%s_%02d" % (code, kind, index)


def build_starter(affinity, code, cards):
    deck = {}
    for i in STARTER_SKILLS:
        deck[cid(code, "SKILL", i)] = 3
    for i in STARTER_COMPANIONS:
        deck[cid(code, "COMP", i)] = 3
    for i in STARTER_EQUIPMENT:
        deck[cid(code, "EQUIP", i)] = 3
    for i in STARTER_TAAHMA:
        deck[cid(code, "TAAHMA", i)] = 3
    plan, blurb = PLANS[affinity]
    return {
        "deck_id": "starter_%s" % affinity,
        "name": "%s Starter" % affinity.capitalize(),
        "affinity": affinity,
        "hero": cid(code, "HERO", 1),
        "plan": plan,
        "description": ("A granted starter deck built only from cards that allow "
                        "three copies. %s") % blurb,
        "starter": True,
        "cards": deck,
    }


def build_ai(affinity, code, cards):
    deck = {}
    for i in AI_SKILLS:
        deck[cid(code, "SKILL", i)] = 3
    for i in AI_COMPANIONS:
        deck[cid(code, "COMP", i)] = 3
    for i in AI_EQUIPMENT:
        deck[cid(code, "EQUIP", i)] = 3
    # A named character and a Unique card, each at its legal limit of one.
    deck[cid(code, "COMP", AI_NAMED_COMPANION)] = 1
    deck[cid(code, "EQUIP", AI_UNIQUE_EQUIPMENT)] = 1
    for nid in AI_NEUTRAL_TRIPLES:
        deck[nid] = 3
    deck[AI_NEUTRAL_SINGLE] = 1

    plan, blurb = PLANS[affinity]
    on_affinity = sum(q for k, q in deck.items() if cards[k]["affinities"] == [affinity])
    return {
        "deck_id": "ai_%s" % affinity,
        "name": "%s Opponent" % affinity.capitalize(),
        "affinity": affinity,
        "hero": cid(code, "HERO", 2),
        "plan": plan,
        "description": blurb,
        "on_affinity_cards": on_affinity,
        "cards": deck,
    }


def main():
    cards = load_catalog()
    os.makedirs(DECKS, exist_ok=True)

    starters = []
    ai_decks = []
    for affinity, code in sorted(AFFINITY_CODES.items()):
        starters.append(build_starter(affinity, code, cards))
        ai_decks.append(build_ai(affinity, code, cards))

    for deck in starters + ai_decks:
        total = sum(deck["cards"].values())
        assert total == 45, "%s has %d cards" % (deck["deck_id"], total)
        assert deck["hero"] in cards, "%s has an unknown Hero" % deck["deck_id"]
        for def_id, qty in deck["cards"].items():
            assert def_id in cards, "%s references unknown card %s" % (deck["deck_id"], def_id)
            card = cards[def_id]
            limit = 1 if (card["unique"] or card["character_id"]) else 3
            assert qty <= limit, "%s uses %d copies of %s (limit %d)" % (
                deck["deck_id"], qty, def_id, limit)
            assert "hero" not in card["types"], "%s puts a Hero in the deck" % deck["deck_id"]
        names = {}
        for def_id, qty in deck["cards"].items():
            names[cards[def_id]["name"]] = names.get(cards[def_id]["name"], 0) + qty
        for nm, q in names.items():
            assert q <= 3, "%s has %d copies named %s" % (deck["deck_id"], q, nm)

    for deck in ai_decks:
        assert deck["on_affinity_cards"] >= 30, "%s carries only %d on-Affinity cards" % (
            deck["deck_id"], deck["on_affinity_cards"])

    # Starters must be playable from the granted collection, which takes the
    # highest required count per definition rather than the sum across decks.
    union = {}
    for deck in starters:
        union[deck["hero"]] = max(union.get(deck["hero"], 0), 1)
        for def_id, qty in deck["cards"].items():
            union[def_id] = max(union.get(def_id, 0), qty)
    for def_id, qty in union.items():
        card = cards[def_id]
        cap = 1 if ("hero" in card["types"] or card["unique"] or card["character_id"]) else 3
        assert qty <= cap, "the starter grant would need %d of %s over its cap of %d" % (
            qty, def_id, cap)

    with open(os.path.join(DECKS, "starters.json"), "w") as fh:
        json.dump(starters, fh, indent=2)
        fh.write("\n")
    with open(os.path.join(DECKS, "ai_decks.json"), "w") as fh:
        json.dump(ai_decks, fh, indent=2)
        fh.write("\n")

    print("7 starter decks and 7 AI decks written, all 45 cards")
    print("starter grant covers %d definitions (%d cards)" % (len(union), sum(union.values())))
    for deck in ai_decks:
        print("  %-18s hero %-12s %2d on-Affinity cards" % (
            deck["deck_id"], deck["hero"], deck["on_affinity_cards"]))


if __name__ == "__main__":
    main()
