#!/usr/bin/env python3
"""Generate the 300 proxy card definitions for Heroes of Teloria.

Every definition here is placeholder test content: names, art, numbers and
rarities are deliberately replaceable and establish no Teloria lore or final
balance. The generator exists so the catalog can be regenerated after a schema
change; the JSON files it writes under data/catalog are the authoritative,
hand-editable source that the game loads.

Rules text is deliberately NOT written here. It is generated from the effect
data by src/core/text_gen.gd via tools/fill_text.gd, so there is exactly one
implementation of card text and a definition can never advertise behaviour the
interpreter will not run.

Usage (or just run tools/build_catalog.sh, which does all three passes):
    python3 tools/generate_catalog.py
    godot --headless --path . --script tools/dump_card_text.gd
    python3 tools/generate_catalog.py
"""

import glob
import json
import os

OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "data", "catalog")
TEXT_FILE = os.path.join(os.path.dirname(__file__), "..", "build", "card_text.json")

# Rules text rendered by the engine (see tools/dump_card_text.gd). Missing
# entries simply leave the text empty for the next pass to fill.
try:
    with open(TEXT_FILE) as _fh:
        CARD_TEXT = json.load(_fh)
except (IOError, ValueError):
    CARD_TEXT = {}


def _load_existing():
    """The catalog as it stands on disk, so regeneration never destroys
    hand-authored work.

    A definition marked "authored": true is a real card rather than a proxy and
    is carried across untouched. For every other definition, a real art file is
    still preserved, because art is supplied separately from mechanics.
    """
    existing = {}
    for path in sorted(glob.glob(os.path.join(OUT_DIR, "*.json"))):
        try:
            with open(path) as fh:
                for card in json.load(fh):
                    existing[card["id"]] = card
        except (IOError, ValueError, KeyError, TypeError):
            continue
    return existing


EXISTING = _load_existing()

AFFINITIES = [
    # (key, code, display, hue, ai role)
    ("devotion",  "DEV", "Devotion",  45,  "support"),
    ("passion",   "PAS", "Passion",   350, "aggro"),
    ("will",      "WIL", "Will",      25,  "midrange"),
    ("vigilance", "VIG", "Vigilance", 215, "control"),
    ("purpose",   "PUR", "Purpose",   200, "combo"),
    ("harmony",   "HAR", "Harmony",   160, "synergy"),
    ("silence",   "SIL", "Silence",   280, "disruption"),
]


# --------------------------------------------------------------------- helpers

def amount_x():
    return {"from": "x"}


def amount_chain(affinity="any", scope="either"):
    return {"from": "chain_count", "affinity": affinity, "scope": scope}


def amount_count(of):
    return {"from": "count", "of": of}


# ------------------------------------------------------------- skill builders
# Each builder returns the mechanical part of a card. Costs and numbers are set
# per call so that every Affinity gets usable low-, middle- and higher-cost
# options rather than one mechanic repeated.

def sk(cost, effects, tags=("martial",), patterns=(), target=None,
       timing=("action",), window=None, x_min=None):
    body = {
        "types": ["skill"],
        "tags": list(tags),
        "cost": {"kind": "x", "min": x_min} if x_min is not None else {"kind": "fixed", "amount": cost},
        "timing": list(timing),
        "effects": effects,
        "patterns": list(patterns),
    }
    if target:
        body["target"] = target
    if window:
        body["reaction_window"] = window
    return body


def burn(cost, dmg, tags=("magic", "ranged")):
    return sk(cost, [{"op": "damage_hero", "who": "opponent", "amount": dmg}],
              tags, ["hero_burn"])


def burn_draw(cost, dmg):
    return sk(cost, [{"op": "damage_hero", "who": "opponent", "amount": dmg},
                     {"op": "draw", "who": "self", "amount": 1}],
              ("magic",), ["hero_burn", "draw"])


def draw_cards(cost, n, tags=("magic",)):
    return sk(cost, [{"op": "draw", "who": "self", "amount": n}], tags, ["draw"])


def energy_burst(cost, n):
    return sk(cost, [{"op": "energy_gain", "who": "self", "amount": n}],
              ("magic",), ["energy_refund"])


def max_energy_up(cost, n, duration="round"):
    return sk(cost, [{"op": "energy_max_mod", "who": "self", "amount": n, "duration": duration}],
              ("magic",), ["max_energy_boost"])


def buff(cost, atk, dfn, duration="round", kind="own_character"):
    e = {"op": "stat_mod", "target": "chosen", "duration": duration}
    if atk:
        e["attack"] = atk
    if dfn:
        e["defense"] = dfn
    pat = ["permanent_buff"] if duration == "permanent" else \
        (["temp_attack_buff"] if atk else ["temp_defense_buff"])
    return sk(cost, [e], ("martial", "melee"), pat, {"kind": kind, "count": 1})


def mass_buff(cost, atk, dfn):
    e = {"op": "stat_mod", "target": "all_own_companions", "duration": "round"}
    if atk:
        e["attack"] = atk
    if dfn:
        e["defense"] = dfn
    return sk(cost, [e], ("martial",), ["mass_buff"])


def debuff(cost, atk, dfn):
    e = {"op": "stat_mod", "target": "chosen", "duration": "round"}
    if atk:
        e["attack"] = atk
    if dfn:
        e["defense"] = dfn
    return sk(cost, [e], ("magic",), ["debuff"],
              {"kind": "opponent_character", "count": 1})


def removal(cost):
    return sk(cost, [{"op": "destroy", "target": "chosen"}], ("magic",), ["removal"],
              {"kind": "opponent_companion", "count": 1})


def conditional_removal(cost, max_defense):
    return sk(cost, [{"op": "conditional",
                      "cond": {"kind": "target_defense_at_most", "max": max_defense},
                      "then": [{"op": "destroy", "target": "chosen"}]}],
              ("magic",), ["removal", "conditional_bonus"],
              {"kind": "opponent_companion", "count": 1})


def strike(cost, dmg, ignores=False):
    return sk(cost, [{"op": "direct_damage", "target": "chosen", "amount": dmg,
                      "ignores_defense": ignores}],
              ("martial", "melee"), ["direct_damage"],
              {"kind": "opponent_companion", "count": 1})


def bounce(cost):
    return sk(cost, [{"op": "bounce", "target": "chosen"}], ("magic",), ["bounce"],
              {"kind": "opponent_companion", "count": 1})


def destroy_equipment(cost):
    return sk(cost, [{"op": "destroy", "target": "chosen"}], ("magic",),
              ["attachment_removal"], {"kind": "opponent_equipment", "count": 1})


def destroy_taahma(cost):
    return sk(cost, [{"op": "destroy", "target": "chosen"}], ("magic",),
              ["attachment_removal"], {"kind": "opponent_taahma", "count": 1})


def destroy_location(cost):
    return sk(cost, [{"op": "destroy", "target": "chosen"}], ("magic",),
              ["location_removal"], {"kind": "location", "count": 1})


def drain(cost, n):
    return sk(cost, [{"op": "energy_drain", "who": "opponent", "amount": n}],
              ("magic",), ["energy_denial"])


def max_energy_down(cost, n):
    return sk(cost, [{"op": "energy_max_mod", "who": "opponent", "amount": -n,
                      "duration": "round"}],
              ("magic",), ["max_energy_reduction"])


def mill(cost, n):
    return sk(cost, [{"op": "mill", "who": "opponent", "amount": n}], ("magic",), ["mill"])


def recover(cost, n):
    return sk(cost, [{"op": "recover_from_exhaust", "who": "self", "amount": n}],
              ("magic",), ["recovery"])


def discard_random(cost, n):
    return sk(cost, [{"op": "random_exhaust_from_hand", "who": "opponent", "amount": n}],
              ("magic",), ["discard_random"])


def discard_choice(cost, n):
    return sk(cost, [{"op": "exhaust_from_hand", "who": "opponent", "amount": n,
                      "chooser": "opponent"}],
              ("magic",), ["discard_choice"])


def protect(cost, amount, kind="own_character"):
    return sk(cost, [{"op": "prevent_damage", "target": "chosen", "amount": amount,
                      "duration": "round"}],
              ("martial",), ["protection"], {"kind": kind, "count": 1})


def protect_hero(cost, amount):
    return sk(cost, [{"op": "prevent_damage", "target": "self_hero", "amount": amount,
                      "duration": "round"}],
              ("martial",), ["protection"])


def chain_draw(cost, minimum, affinity):
    return sk(cost, [{"op": "chain_reward",
                      "require": {"min": minimum, "affinity": affinity, "scope": "either"},
                      "then": [{"op": "draw", "who": "self", "amount": 1}]}],
              ("magic",), ["chain_payoff", "draw"])


def chain_burn(cost, minimum, affinity, dmg):
    return sk(cost, [{"op": "chain_reward",
                      "require": {"min": minimum, "affinity": affinity, "scope": "either"},
                      "then": [{"op": "damage_hero", "who": "opponent", "amount": dmg}]}],
              ("magic",), ["chain_payoff", "hero_burn"])


def chain_scale_burn(cost, affinity):
    return sk(cost, [{"op": "damage_hero", "who": "opponent",
                      "amount": amount_chain(affinity, "either")}],
              ("magic", "ranged"), ["chain_scaling", "hero_burn"])


def chain_scale_energy(cost, affinity):
    return sk(cost, [{"op": "energy_gain", "who": "self",
                      "amount": amount_chain(affinity, "controller")}],
              ("magic",), ["chain_scaling", "energy_refund"])


def x_burn(x_min=1):
    return sk(0, [{"op": "damage_hero", "who": "opponent", "amount": amount_x()}],
              ("magic", "ranged"), ["x_cost", "hero_burn"], x_min=x_min)


def x_buff():
    return sk(0, [{"op": "repeat", "amount": amount_x(),
                   "effects": [{"op": "stat_mod", "target": "chosen", "attack": 1,
                                "duration": "round"}]}],
              ("martial", "melee"), ["x_cost", "temp_attack_buff"],
              {"kind": "own_character", "count": 1}, x_min=1)


def x_draw():
    return sk(0, [{"op": "draw", "who": "self", "amount": amount_x()}],
              ("magic",), ["x_cost", "draw"], x_min=1)


def count_burn(cost, of):
    return sk(cost, [{"op": "damage_hero", "who": "opponent", "amount": amount_count(of)}],
              ("magic", "ranged"), ["count_scaling", "hero_burn"])


def count_energy(cost, of):
    return sk(cost, [{"op": "energy_gain", "who": "self", "amount": amount_count(of)}],
              ("magic",), ["count_scaling", "energy_refund"])


def conditional_burn(cost, dmg, cond, patterns):
    return sk(cost, [{"op": "conditional", "cond": cond,
                      "then": [{"op": "damage_hero", "who": "opponent", "amount": dmg}],
                      "otherwise": [{"op": "draw", "who": "self", "amount": 1}]}],
              ("magic",), list(patterns) + ["conditional_bonus"])


def optional_deploy(cost):
    return sk(cost, [{"op": "deploy_from_hand", "who": "self"}],
              ("martial",), ["optional_deploy"])


# ------------------------------------------------------------ reaction skills

def rx(cost, effects, tags, patterns, target=None, window="before"):
    return sk(cost, effects, tuple(list(tags) + ["reaction"]), patterns,
              target, timing=("reaction",), window=window)


def rx_shield(cost, amount):
    return rx(cost, [{"op": "prevent_damage", "target": "current_target",
                      "amount": amount, "duration": "round"}],
              ("martial",), ["defensive_reaction", "protection"])


def rx_guard_hero(cost, amount):
    return rx(cost, [{"op": "prevent_damage", "target": "self_hero",
                      "amount": amount, "duration": "round"}],
              ("martial",), ["defensive_reaction", "protection"])


def rx_weaken(cost, atk):
    return rx(cost, [{"op": "stat_mod", "target": "current_attacker",
                      "attack": -atk, "duration": "round"}],
              ("magic",), ["debuff_reaction"])


def rx_brace(cost, dfn):
    return rx(cost, [{"op": "stat_mod", "target": "current_target",
                      "defense": dfn, "duration": "round"}],
              ("martial",), ["defensive_reaction", "temp_defense_buff"])


def rx_energy(cost, n):
    return rx(cost, [{"op": "energy_gain", "who": "self", "amount": n}],
              ("magic",), ["energy_reaction", "energy_refund"])


def rx_draw(cost, n):
    return rx(cost, [{"op": "draw", "who": "self", "amount": n}],
              ("magic",), ["draw_reaction", "draw"])


def rx_burn(cost, dmg):
    return rx(cost, [{"op": "damage_hero", "who": "opponent", "amount": dmg}],
              ("magic", "ranged"), ["reaction_burn", "hero_burn"], window="after")


def rx_drain(cost, n):
    return rx(cost, [{"op": "energy_drain", "who": "opponent", "amount": n}],
              ("magic",), ["energy_denial", "reaction_denial"])


def rx_punish(cost, dmg):
    return rx(cost, [{"op": "direct_damage", "target": "current_attacker", "amount": dmg,
                      "ignores_defense": True}],
              ("martial", "melee"), ["reaction_punish", "direct_damage"], window="after")


def rx_boost_own(cost, atk):
    return rx(cost, [{"op": "stat_mod", "target": "current_attacker", "attack": atk,
                      "duration": "round"}],
              ("martial",), ["reaction_boost", "temp_attack_buff"])


def rx_chain_energy(cost, affinity):
    return rx(cost, [{"op": "chain_reward",
                      "require": {"min": 2, "affinity": affinity, "scope": "either"},
                      "then": [{"op": "energy_gain", "who": "self", "amount": 2}]}],
              ("magic",), ["chain_payoff", "energy_reaction"])


def rx_save(cost):
    return rx(cost, [{"op": "bounce", "target": "current_target"}],
              ("magic",), ["defensive_reaction", "bounce"])


# --------------------------------------------------------- companion builders

def comp(cost, atk, dfn, attack_cost, effects=None, triggers=None, patterns=(),
         named=False):
    body = {
        "types": ["companion"],
        "tags": [],
        "cost": {"kind": "fixed", "amount": cost},
        "timing": ["action"],
        "energy_contribution": cost,
        "attack": atk,
        "defense": dfn,
        "attack_cost": attack_cost,
        "persistent": {"kind": "companion"},
        "effects": effects or [],
        "triggers": triggers or [],
        "patterns": list(patterns) or ["deploy"],
    }
    if named:
        body["named"] = True
    return body


def comp_body(cost, atk, dfn, attack_cost):
    return comp(cost, atk, dfn, attack_cost, patterns=["deploy", "body"])


def comp_etb(cost, atk, dfn, attack_cost, effects, patterns):
    return comp(cost, atk, dfn, attack_cost,
                triggers=[{"on": {"kind": "self_deployed"}, "effects": effects}],
                patterns=["deploy", "etb_effect"] + list(patterns))


def comp_death(cost, atk, dfn, attack_cost, effects, patterns):
    return comp(cost, atk, dfn, attack_cost,
                triggers=[{"on": {"kind": "self_leaves_play"}, "effects": effects}],
                patterns=["deploy", "death_trigger"] + list(patterns))


def comp_on_attack(cost, atk, dfn, attack_cost, effects, patterns):
    return comp(cost, atk, dfn, attack_cost,
                triggers=[{"on": {"kind": "self_attack_resolved"}, "effects": effects}],
                patterns=["deploy", "attack_trigger"] + list(patterns))


def comp_refund(cost, atk, dfn, attack_cost, affinity, amount=1, named=False):
    return comp(cost, atk, dfn, attack_cost,
                triggers=[{"on": {"kind": "affinity_card_resolved", "affinity": affinity,
                                  "scope": "either"},
                           "effects": [{"op": "energy_gain", "who": "self", "amount": amount}]}],
                patterns=["deploy", "energy_refund", "affinity_engine"], named=named)


def comp_aura(cost, atk, dfn, attack_cost, scope, a, d, named=False):
    e = {"op": "aura_stat_mod", "scope": scope}
    if a:
        e["attack"] = a
    if d:
        e["defense"] = d
    return comp(cost, atk, dfn, attack_cost, effects=[e],
                patterns=["deploy", "aura_buff"], named=named)


def comp_watch_deploy(cost, atk, dfn, attack_cost, effects, named=False):
    return comp(cost, atk, dfn, attack_cost,
                triggers=[{"on": {"kind": "own_companion_deployed"}, "effects": effects}],
                patterns=["deploy", "companion_deploy_trigger"], named=named)


def comp_round_end(cost, atk, dfn, attack_cost, effects, patterns, named=False):
    return comp(cost, atk, dfn, attack_cost,
                triggers=[{"on": {"kind": "round_end"}, "effects": effects}],
                patterns=["deploy", "round_end_trigger"] + list(patterns), named=named)


def comp_watch_hero_damage(cost, atk, dfn, attack_cost, effects, named=False):
    return comp(cost, atk, dfn, attack_cost,
                triggers=[{"on": {"kind": "own_hero_damaged"}, "effects": effects}],
                patterns=["deploy", "hero_damage_trigger"], named=named)


def comp_watch_enemy_attack(cost, atk, dfn, attack_cost, effects, named=False):
    return comp(cost, atk, dfn, attack_cost,
                triggers=[{"on": {"kind": "attack_resolved", "scope": "opponent"},
                           "effects": effects}],
                patterns=["deploy", "attack_watch_trigger"], named=named)


# -------------------------------------------- equipment / ta'ahma / locations

def equip(cost, a, d, unique=False, triggers=None, extra_effects=None, patterns=()):
    e = {"op": "aura_stat_mod", "scope": "host"}
    if a:
        e["attack"] = a
    if d:
        e["defense"] = d
    body = {
        "types": ["equipment"],
        "tags": [],
        "cost": {"kind": "fixed", "amount": cost},
        "timing": ["action"],
        "attack": a,
        "defense": d,
        "persistent": {"kind": "attachment", "slot": "equipment"},
        "target": {"kind": "own_character_host", "count": 1},
        "effects": [e] + list(extra_effects or []),
        "triggers": triggers or [],
        "patterns": ["equipment_buff"] + list(patterns),
        "unique": unique,
    }
    return body


def taahma(cost, effects, triggers=None, patterns=(), unique=False):
    return {
        "types": ["taahma"],
        "tags": [],
        "cost": {"kind": "fixed", "amount": cost},
        "timing": ["action"],
        "persistent": {"kind": "attachment", "slot": "taahma"},
        "target": {"kind": "own_character_host", "count": 1},
        "effects": effects,
        "triggers": triggers or [],
        "patterns": ["taahma_buff"] + list(patterns),
        "unique": unique,
    }


def location(cost, effects, triggers=None, patterns=(), unique=False):
    return {
        "types": ["location"],
        "tags": [],
        "cost": {"kind": "fixed", "amount": cost},
        "timing": ["action"],
        "persistent": {"kind": "location"},
        "effects": effects,
        "triggers": triggers or [],
        "patterns": ["location_aura"] + list(patterns),
        "unique": unique,
    }


def hero(max_energy, atk, dfn, attack_cost, triggers=None, effects=None, patterns=()):
    return {
        "types": ["hero"],
        "tags": [],
        "cost": {"kind": "none"},
        "hero_max_energy": max_energy,
        "attack": atk,
        "defense": dfn,
        "attack_cost": attack_cost,
        "effects": effects or [],
        "triggers": triggers or [],
        "patterns": ["hero"] + list(patterns),
    }


# =============================================================================
# Per-Affinity content.
#
# Each Affinity contributes 2 Heroes, 20 Skills (exactly 5 Reaction-tagged),
# 10 Companions (the last two are named characters), 4 Equipment (the last is
# Unique), 2 Ta'ahma and 2 Locations, for 40 definitions.
#
# Rarity is assigned by position so the totals come out at exactly
# 150 Common / 90 Uncommon / 45 Rare / 15 Legendary across the catalog.
# =============================================================================

SKILL_RARITY = ["common"] * 12 + ["uncommon"] * 6 + ["rare"] * 2
COMPANION_RARITY = ["common"] * 5 + ["uncommon"] * 3 + ["rare"] * 2
EQUIPMENT_RARITY = ["common", "common", "uncommon", "rare"]
TAAHMA_RARITY = ["common", "uncommon"]
LOCATION_RARITY = ["uncommon", "rare"]

NEUTRAL_SKILL_RARITY = ["common"] * 6 + ["uncommon"] * 3 + ["rare"]
NEUTRAL_COMPANION_RARITY = ["common"] * 3 + ["uncommon"] * 2 + ["legendary"]
NEUTRAL_EQUIPMENT_RARITY = ["common", "uncommon"]
NEUTRAL_TAAHMA_RARITY = ["rare"]
NEUTRAL_LOCATION_RARITY = ["rare"]


CONTENT = {
    # ---------------------------------------------------------------- Devotion
    # Companion support and explicit protection effects.
    "devotion": {
        "heroes": [
            hero(4, 2, 3, 1,
                 triggers=[{"on": {"kind": "own_companion_deployed"},
                            "effects": [{"op": "energy_gain", "who": "self", "amount": 1}]}],
                 patterns=["companion_deploy_trigger", "energy_refund"]),
            hero(5, 2, 2, 1,
                 triggers=[{"on": {"kind": "own_hero_damaged"},
                            "effects": [{"op": "draw", "who": "self", "amount": 1}]}],
                 patterns=["hero_damage_trigger", "draw"]),
        ],
        "skills": [
            protect(1, 2), protect_hero(1, 2), buff(1, 0, 2), buff(1, 1, 1),
            mass_buff(2, 0, 1), draw_cards(1, 1), energy_burst(1, 2),
            rx_shield(1, 2), rx_brace(1, 2), rx_guard_hero(1, 3),
            rx_save(2), buff(2, 0, 3),
            mass_buff(3, 1, 2), protect(2, 4), recover(2, 2), optional_deploy(2),
            rx_chain_energy(2, "devotion"),
            conditional_burn(2, 3, {"kind": "controls_companions", "who": "self", "min": 2},
                             ["hero_burn"]),
            buff(3, 2, 3, "permanent"), max_energy_up(3, 2, "permanent"),
        ],
        "companions": [
            comp_body(1, 1, 2, 1),
            comp_body(2, 1, 3, 1),
            comp_aura(2, 1, 1, 1, "own_companions", 0, 1),
            comp_etb(2, 1, 2, 1,
                     [{"op": "prevent_damage", "target": "self_hero", "amount": 2,
                       "duration": "round"}], ["protection"]),
            comp_body(3, 2, 3, 2),
            comp_aura(3, 1, 3, 1, "own_hero", 0, 2),
            comp_watch_deploy(3, 1, 2, 1,
                              [{"op": "stat_mod", "target": "all_own_companions",
                                "defense": 1, "duration": "round"}]),
            comp_watch_hero_damage(3, 2, 2, 1, [{"op": "draw", "who": "self", "amount": 1}]),
            comp_aura(4, 2, 4, 2, "own_companions", 1, 1),
            comp_round_end(4, 2, 3, 1, [{"op": "energy_gain", "who": "self", "amount": 2}],
                           ["energy_refund"]),
        ],
        "equipment": [
            equip(1, 0, 2), equip(2, 1, 1), equip(2, 0, 3),
            equip(3, 1, 3, unique=True,
                  extra_effects=[{"op": "aura_energy_max", "who": "self", "amount": 1}],
                  patterns=["energy_ramp"]),
        ],
        "taahma": [
            taahma(1, [{"op": "aura_stat_mod", "scope": "host", "defense": 2}]),
            taahma(2, [{"op": "aura_stat_mod", "scope": "host", "defense": 1}],
                   triggers=[{"on": {"kind": "own_hero_damaged"},
                              "effects": [{"op": "energy_gain", "who": "self", "amount": 1}]}],
                   patterns=["hero_damage_trigger"]),
        ],
        "locations": [
            location(2, [{"op": "aura_stat_mod", "scope": "own_companions", "defense": 1}]),
            location(3, [{"op": "aura_stat_mod", "scope": "all_companions", "defense": 1}],
                     triggers=[{"on": {"kind": "round_end"},
                                "effects": [{"op": "energy_gain", "who": "self", "amount": 1}]}],
                     patterns=["round_end_trigger"], unique=True),
        ],
    },

    # ----------------------------------------------------------------- Passion
    # Aggression, Energy refunds and spending decisions.
    "passion": {
        "heroes": [
            hero(4, 3, 1, 1,
                 triggers=[{"on": {"kind": "affinity_card_resolved", "affinity": "passion",
                                   "scope": "either"},
                            "effects": [{"op": "energy_gain", "who": "self", "amount": 1}]}],
                 patterns=["affinity_engine", "energy_refund"]),
            hero(5, 3, 2, 2,
                 triggers=[{"on": {"kind": "self_attack_resolved"},
                            "effects": [{"op": "damage_hero", "who": "opponent", "amount": 1}]}],
                 patterns=["attack_trigger", "hero_burn"]),
        ],
        "skills": [
            burn(1, 2), burn(2, 3), burn_draw(2, 2), energy_burst(1, 2),
            strike(1, 2), buff(1, 2, 0), x_burn(1), chain_burn(1, 2, "passion", 2),
            rx_burn(1, 2), rx_energy(1, 2), rx_boost_own(1, 2), rx_punish(2, 2),
            burn(3, 5), chain_scale_burn(2, "passion"), x_draw(), discard_random(2, 1),
            count_burn(2, "own_companions"), rx_chain_energy(2, "passion"),
            conditional_burn(3, 6, {"kind": "energy_at_least", "who": "self", "min": 4},
                             ["hero_burn"]),
            max_energy_up(3, 3, "permanent"),
        ],
        "companions": [
            comp_body(1, 2, 1, 1),
            comp_etb(1, 1, 1, 1, [{"op": "damage_hero", "who": "opponent", "amount": 1}],
                     ["hero_burn"]),
            comp_body(2, 3, 1, 1),
            comp_on_attack(2, 2, 1, 1, [{"op": "energy_gain", "who": "self", "amount": 1}],
                           ["energy_refund"]),
            comp_death(2, 1, 2, 1, [{"op": "damage_hero", "who": "opponent", "amount": 2}],
                       ["hero_burn"]),
            comp_refund(3, 3, 2, 1, "passion", 1),
            comp_on_attack(3, 3, 2, 1, [{"op": "damage_hero", "who": "opponent", "amount": 1}],
                           ["hero_burn"]),
            comp_body(3, 4, 2, 2),
            comp_refund(4, 4, 2, 1, "passion", 1),
            comp_on_attack(4, 3, 3, 1, [{"op": "damage_hero", "who": "opponent", "amount": 2}],
                           ["hero_burn"]),
        ],
        "equipment": [
            equip(1, 2, 0), equip(2, 3, 0), equip(2, 2, 1),
            equip(3, 3, 1, unique=True,
                  triggers=[{"on": {"kind": "attack_resolved", "scope": "controller"},
                             "effects": [{"op": "damage_hero", "who": "opponent", "amount": 1}]}],
                  patterns=["attack_watch_trigger", "hero_burn"]),
        ],
        "taahma": [
            taahma(1, [{"op": "aura_stat_mod", "scope": "host", "attack": 1}]),
            taahma(2, [{"op": "aura_stat_mod", "scope": "host", "attack": 2}],
                   triggers=[{"on": {"kind": "affinity_card_resolved", "affinity": "passion",
                                     "scope": "controller"},
                              "effects": [{"op": "energy_gain", "who": "self", "amount": 1}]}],
                   patterns=["affinity_engine", "energy_refund"]),
        ],
        "locations": [
            location(2, [{"op": "aura_stat_mod", "scope": "all_companions", "attack": 1}]),
            location(3, [{"op": "aura_stat_mod", "scope": "own_companions", "attack": 2}],
                     triggers=[{"on": {"kind": "round_end"},
                                "effects": [{"op": "damage_hero", "who": "opponent", "amount": 1}]}],
                     patterns=["round_end_trigger", "hero_burn"], unique=True),
        ],
    },

    # -------------------------------------------------------------------- Will
    # Character enhancement and sustained attack pressure.
    "will": {
        "heroes": [
            hero(4, 3, 2, 1,
                 triggers=[{"on": {"kind": "self_attack_resolved"},
                            "effects": [{"op": "stat_mod", "target": "self", "attack": 1,
                                         "duration": "permanent"}]}],
                 patterns=["attack_trigger", "permanent_buff"]),
            hero(5, 2, 3, 1,
                 triggers=[{"on": {"kind": "own_companion_deployed"},
                            "effects": [{"op": "stat_mod", "target": "all_own_companions",
                                         "attack": 1, "duration": "round"}]}],
                 patterns=["companion_deploy_trigger", "mass_buff"]),
        ],
        "skills": [
            buff(1, 2, 0), buff(1, 1, 1), buff(2, 3, 0), strike(1, 2),
            mass_buff(2, 1, 0), draw_cards(1, 1), energy_burst(1, 2), x_buff(),
            rx_boost_own(1, 2), rx_brace(1, 2), rx_shield(1, 2), rx_punish(2, 2),
            buff(3, 3, 2), mass_buff(3, 2, 1), strike(3, 4), buff(2, 0, 2),
            conditional_burn(2, 3, {"kind": "controls_companions", "who": "self", "min": 2},
                             ["hero_burn"]),
            rx_draw(2, 1),
            buff(3, 3, 3, "permanent"), max_energy_up(3, 2, "permanent"),
        ],
        "companions": [
            comp_body(1, 2, 1, 1),
            comp_body(2, 2, 2, 1),
            comp_on_attack(2, 2, 2, 1,
                           [{"op": "stat_mod", "target": "self", "attack": 1,
                             "duration": "permanent"}], ["permanent_buff"]),
            comp_etb(2, 1, 2, 1,
                     [{"op": "stat_mod", "target": "self_hero", "attack": 1,
                       "duration": "round"}], ["temp_attack_buff"]),
            comp_body(3, 3, 2, 1),
            comp_aura(3, 2, 2, 1, "own_companions", 1, 0),
            comp_on_attack(3, 3, 3, 2, [{"op": "draw", "who": "self", "amount": 1}], ["draw"]),
            comp_watch_deploy(3, 2, 3, 1,
                              [{"op": "stat_mod", "target": "all_own_companions", "attack": 1,
                                "duration": "round"}]),
            comp_aura(4, 3, 3, 2, "own_characters", 1, 0),
            comp_on_attack(4, 4, 3, 1,
                           [{"op": "stat_mod", "target": "self", "attack": 1, "defense": 1,
                             "duration": "permanent"}], ["permanent_buff"]),
        ],
        "equipment": [
            equip(1, 1, 1), equip(2, 2, 1), equip(2, 3, 0),
            equip(3, 2, 2, unique=True,
                  triggers=[{"on": {"kind": "attack_resolved", "scope": "controller"},
                             "effects": [{"op": "energy_gain", "who": "self", "amount": 1}]}],
                  patterns=["attack_watch_trigger", "energy_refund"]),
        ],
        "taahma": [
            taahma(1, [{"op": "aura_stat_mod", "scope": "host", "attack": 1, "defense": 1}]),
            taahma(2, [{"op": "aura_stat_mod", "scope": "host", "attack": 2, "defense": 1}]),
        ],
        "locations": [
            location(2, [{"op": "aura_stat_mod", "scope": "own_characters", "attack": 1}]),
            location(3, [{"op": "aura_stat_mod", "scope": "own_companions", "attack": 1,
                          "defense": 1}], unique=True),
        ],
    },

    # --------------------------------------------------------------- Vigilance
    # Efficient Reactions and deliberate defensive timing.
    "vigilance": {
        "heroes": [
            hero(4, 2, 3, 1,
                 triggers=[{"on": {"kind": "attack_resolved", "scope": "opponent"},
                            "effects": [{"op": "energy_gain", "who": "self", "amount": 1}]}],
                 patterns=["attack_watch_trigger", "energy_refund"]),
            hero(5, 1, 4, 1,
                 triggers=[{"on": {"kind": "own_hero_damaged"},
                            "effects": [{"op": "energy_gain", "who": "self", "amount": 2}]}],
                 patterns=["hero_damage_trigger", "energy_refund"]),
        ],
        "skills": [
            protect(1, 2), buff(1, 0, 3), draw_cards(1, 1), protect_hero(1, 3),
            mill(1, 2), conditional_removal(2, 2), bounce(2),
            rx_guard_hero(1, 3), rx_shield(1, 3), rx_brace(1, 3), rx_weaken(1, 2),
            rx_draw(1, 1),
            protect(2, 5), recover(2, 2), draw_cards(3, 2), destroy_equipment(2),
            max_energy_down(2, 2), bounce(3),
            removal(3), protect_hero(3, 6),
        ],
        "companions": [
            comp_body(1, 1, 2, 1),
            comp_body(2, 2, 2, 1),
            comp_aura(2, 1, 2, 1, "own_companions", 0, 1),
            comp_watch_enemy_attack(2, 1, 3, 1,
                                    [{"op": "energy_gain", "who": "self", "amount": 1}]),
            comp_body(3, 1, 4, 1),
            comp_etb(3, 2, 2, 1,
                     [{"op": "prevent_damage", "target": "self_hero", "amount": 3,
                       "duration": "round"}], ["protection"]),
            comp_watch_hero_damage(3, 2, 3, 1, [{"op": "draw", "who": "self", "amount": 1}]),
            comp_round_end(3, 1, 3, 1, [{"op": "draw", "who": "self", "amount": 1}], ["draw"]),
            comp_aura(4, 2, 4, 1, "own_hero", 0, 2),
            comp_watch_enemy_attack(4, 2, 4, 1,
                                    [{"op": "damage_hero", "who": "opponent", "amount": 1}]),
        ],
        "equipment": [
            equip(1, 0, 2), equip(2, 1, 2), equip(2, 0, 4),
            equip(3, 1, 4, unique=True,
                  triggers=[{"on": {"kind": "attack_resolved", "scope": "opponent"},
                             "effects": [{"op": "energy_gain", "who": "self", "amount": 1}]}],
                  patterns=["attack_watch_trigger", "energy_refund"]),
        ],
        "taahma": [
            taahma(1, [{"op": "aura_stat_mod", "scope": "host", "defense": 2}]),
            taahma(2, [{"op": "aura_stat_mod", "scope": "host", "defense": 3}]),
        ],
        "locations": [
            location(2, [{"op": "aura_stat_mod", "scope": "all_companions", "defense": 1}]),
            location(3, [{"op": "aura_stat_mod", "scope": "own_characters", "defense": 1}],
                     triggers=[{"on": {"kind": "round_end"},
                                "effects": [{"op": "draw", "who": "self", "amount": 1}]}],
                     patterns=["round_end_trigger", "draw"], unique=True),
        ],
    },

    # ----------------------------------------------------------------- Purpose
    # Equipment, Ta'ahma and prepared combinations.
    "purpose": {
        "heroes": [
            hero(4, 2, 2, 1,
                 triggers=[{"on": {"kind": "affinity_card_resolved", "affinity": "purpose",
                                   "scope": "controller"},
                            "effects": [{"op": "energy_gain", "who": "self", "amount": 1}]}],
                 patterns=["affinity_engine", "energy_refund"]),
            hero(5, 2, 3, 1,
                 effects=[{"op": "aura_stat_mod", "scope": "own_characters", "defense": 1}],
                 patterns=["aura_buff"]),
        ],
        "skills": [
            buff(1, 1, 1), draw_cards(1, 1), energy_burst(1, 2),
            conditional_burn(2, 3, {"kind": "has_attachment", "target": "self_hero",
                                    "of": "equipment"}, ["hero_burn"]),
            destroy_equipment(2), destroy_taahma(2), protect(1, 2),
            rx_brace(1, 2), rx_energy(1, 2), rx_draw(1, 1), rx_shield(1, 2),
            rx_chain_energy(2, "purpose"),
            recover(2, 2), draw_cards(3, 2), max_energy_up(2, 2), buff(2, 2, 2),
            x_buff(),
            conditional_burn(3, 5, {"kind": "has_attachment", "target": "self_hero",
                                    "of": "taahma"}, ["hero_burn"]),
            buff(3, 2, 2, "permanent"), max_energy_up(4, 3, "permanent"),
        ],
        "companions": [
            comp_body(1, 1, 1, 1),
            comp_body(2, 2, 2, 1),
            comp_etb(2, 1, 2, 1, [{"op": "draw", "who": "self", "amount": 1}], ["draw"]),
            comp_aura(2, 1, 2, 1, "own_hero", 1, 0),
            comp_body(3, 2, 3, 1),
            comp_round_end(3, 2, 2, 1, [{"op": "energy_gain", "who": "self", "amount": 1}],
                           ["energy_refund"]),
            comp_etb(3, 2, 2, 1,
                     [{"op": "stat_mod", "target": "self_hero", "defense": 1,
                       "duration": "permanent"}], ["permanent_buff"]),
            comp_refund(3, 2, 3, 1, "purpose", 1),
            comp_aura(4, 2, 3, 1, "own_characters", 1, 1),
            comp_refund(4, 3, 3, 2, "purpose", 1),
        ],
        "equipment": [
            equip(1, 1, 1), equip(2, 2, 2), equip(2, 1, 3),
            equip(4, 3, 3, unique=True,
                  extra_effects=[{"op": "aura_energy_max", "who": "self", "amount": 2}],
                  patterns=["energy_ramp"]),
        ],
        "taahma": [
            taahma(1, [{"op": "aura_stat_mod", "scope": "host", "attack": 1, "defense": 1}]),
            taahma(3, [{"op": "aura_stat_mod", "scope": "host", "attack": 2, "defense": 2}],
                   patterns=["energy_ramp"]),
        ],
        "locations": [
            location(2, [{"op": "aura_stat_mod", "scope": "own_characters", "attack": 1}],
                     triggers=[{"on": {"kind": "round_end"},
                                "effects": [{"op": "energy_gain", "who": "self", "amount": 1}]}],
                     patterns=["round_end_trigger", "energy_refund"]),
            location(3, [{"op": "aura_energy_max", "who": "self", "amount": 2}],
                     patterns=["energy_ramp"], unique=True),
        ],
    },

    # ----------------------------------------------------------------- Harmony
    # Cards rewarding relationships across Affinities and the Sequence.
    "harmony": {
        "heroes": [
            hero(4, 2, 2, 1,
                 triggers=[{"on": {"kind": "affinity_card_resolved", "affinity": "harmony",
                                   "scope": "either"},
                            "effects": [{"op": "energy_gain", "who": "self", "amount": 1}]}],
                 patterns=["affinity_engine", "energy_refund"]),
            hero(5, 2, 3, 1,
                 effects=[{"op": "aura_energy_max", "who": "self", "amount": 1}],
                 patterns=["energy_ramp"]),
        ],
        "skills": [
            chain_draw(1, 2, "any"), chain_burn(1, 2, "any", 2), draw_cards(1, 1),
            energy_burst(1, 2), buff(1, 1, 1), chain_scale_burn(2, "any"),
            chain_scale_energy(2, "any"),
            rx_chain_energy(1, "harmony"), rx_draw(1, 1), rx_energy(1, 2),
            rx_brace(1, 2), rx_shield(1, 2),
            chain_draw(2, 3, "any"), chain_burn(2, 3, "any", 4),
            count_energy(2, "own_companions"), draw_cards(3, 2), mass_buff(3, 1, 1),
            chain_scale_burn(3, "harmony"),
            chain_burn(3, 4, "any", 6), max_energy_up(3, 2, "permanent"),
        ],
        "companions": [
            comp_body(1, 1, 2, 1),
            comp_etb(1, 1, 1, 1, [{"op": "energy_gain", "who": "self", "amount": 1}],
                     ["energy_refund"]),
            comp_body(2, 2, 2, 1),
            comp_refund(2, 1, 2, 1, "harmony", 1),
            comp_body(3, 2, 3, 1),
            comp_refund(3, 2, 3, 1, "harmony", 1),
            comp_round_end(3, 2, 2, 1, [{"op": "draw", "who": "self", "amount": 1}], ["draw"]),
            comp_watch_deploy(3, 2, 2, 1, [{"op": "energy_gain", "who": "self", "amount": 1}]),
            comp_aura(4, 3, 3, 2, "all_companions", 1, 0),
            comp_refund(4, 3, 3, 1, "harmony", 2),
        ],
        "equipment": [
            equip(1, 1, 1), equip(2, 2, 1), equip(2, 1, 2),
            equip(3, 2, 2, unique=True,
                  extra_effects=[{"op": "aura_energy_max", "who": "self", "amount": 1}],
                  patterns=["energy_ramp"]),
        ],
        "taahma": [
            taahma(1, [{"op": "aura_stat_mod", "scope": "host", "attack": 1}]),
            taahma(2, [{"op": "aura_stat_mod", "scope": "host", "defense": 1}],
                   triggers=[{"on": {"kind": "affinity_card_resolved", "affinity": "harmony",
                                     "scope": "either"},
                              "effects": [{"op": "energy_gain", "who": "self", "amount": 1}]}],
                   patterns=["affinity_engine", "energy_refund"]),
        ],
        "locations": [
            location(2, [{"op": "aura_stat_mod", "scope": "all_companions", "attack": 1,
                          "defense": 1}]),
            location(3, [{"op": "aura_stat_mod", "scope": "own_companions", "attack": 1}],
                     triggers=[{"on": {"kind": "round_end"},
                                "effects": [{"op": "draw", "who": "self", "amount": 1}]}],
                     patterns=["round_end_trigger", "draw"], unique=True),
        ],
    },

    # ----------------------------------------------------------------- Silence
    # Disruption through modifiers, Energy denial and removal.
    "silence": {
        "heroes": [
            hero(4, 2, 2, 1,
                 triggers=[{"on": {"kind": "opponent_hero_damaged"},
                            "effects": [{"op": "energy_drain", "who": "opponent", "amount": 1}]}],
                 patterns=["hero_damage_trigger", "energy_denial"]),
            hero(5, 2, 3, 1,
                 effects=[{"op": "aura_stat_mod", "scope": "opponent_companions", "attack": -1}],
                 patterns=["aura_buff", "debuff"]),
        ],
        "skills": [
            drain(1, 2), debuff(1, 2, 0), mill(1, 2), discard_random(1, 1),
            max_energy_down(1, 1), conditional_removal(2, 2), destroy_location(2),
            rx_weaken(1, 2), rx_drain(1, 2), rx_shield(1, 2), rx_draw(1, 1), rx_save(2),
            removal(3), drain(2, 3), discard_choice(2, 1), debuff(2, 3, 2),
            max_energy_down(2, 2), bounce(2),
            removal(2), discard_random(3, 2),
        ],
        "companions": [
            comp_body(1, 1, 1, 1),
            comp_etb(1, 1, 1, 1, [{"op": "energy_drain", "who": "opponent", "amount": 1}],
                     ["energy_denial"]),
            comp_body(2, 2, 2, 1),
            comp_etb(2, 1, 2, 1, [{"op": "mill", "who": "opponent", "amount": 2}], ["mill"]),
            comp_aura(2, 1, 2, 1, "opponent_companions", -1, 0),
            comp_on_attack(3, 2, 2, 1,
                           [{"op": "energy_drain", "who": "opponent", "amount": 1}],
                           ["energy_denial"]),
            comp_etb(3, 2, 2, 1,
                     [{"op": "random_exhaust_from_hand", "who": "opponent", "amount": 1}],
                     ["discard_random"]),
            comp_death(3, 2, 3, 1,
                       [{"op": "energy_drain", "who": "opponent", "amount": 2}],
                       ["energy_denial"]),
            comp_aura(4, 3, 3, 1, "opponent_characters", -1, 0),
            comp_round_end(4, 2, 4, 1,
                           [{"op": "mill", "who": "opponent", "amount": 2}], ["mill"]),
        ],
        "equipment": [
            equip(1, 1, 1), equip(2, 2, 1), equip(2, 1, 2),
            equip(3, 2, 2, unique=True,
                  triggers=[{"on": {"kind": "attack_resolved", "scope": "controller"},
                             "effects": [{"op": "energy_drain", "who": "opponent", "amount": 1}]}],
                  patterns=["attack_watch_trigger", "energy_denial"]),
        ],
        "taahma": [
            taahma(1, [{"op": "aura_stat_mod", "scope": "host", "attack": 1}]),
            taahma(2, [{"op": "aura_stat_mod", "scope": "host", "attack": 1, "defense": 1}],
                   triggers=[{"on": {"kind": "attack_resolved", "scope": "controller"},
                              "effects": [{"op": "mill", "who": "opponent", "amount": 1}]}],
                   patterns=["attack_watch_trigger", "mill"]),
        ],
        "locations": [
            location(2, [{"op": "aura_stat_mod", "scope": "opponent_companions", "attack": -1}]),
            location(3, [{"op": "aura_energy_max", "who": "opponent", "amount": -1}],
                     patterns=["max_energy_reduction"], unique=True),
        ],
    },
}


# Neutral: the absence of Affinity, not an eighth Affinity.
NEUTRAL = {
    "skills": [
        draw_cards(1, 1), energy_burst(1, 2), buff(1, 1, 1),
        rx_brace(1, 2), rx_shield(1, 2), rx_energy(1, 2),
        strike(2, 3), draw_cards(3, 2), rx_draw(2, 1),
        rx_punish(2, 3),
    ],
    "companions": [
        comp_body(1, 1, 1, 1),
        comp_body(2, 2, 2, 1),
        comp_etb(2, 1, 2, 1, [{"op": "draw", "who": "self", "amount": 1}], ["draw"]),
        comp_body(3, 3, 2, 1),
        comp_round_end(3, 2, 2, 1, [{"op": "energy_gain", "who": "self", "amount": 1}],
                       ["energy_refund"]),
        comp_aura(5, 3, 4, 2, "all_companions", 1, 1),
    ],
    "equipment": [
        equip(1, 1, 0), equip(2, 1, 2),
    ],
    "taahma": [
        taahma(2, [{"op": "aura_stat_mod", "scope": "host", "defense": 1}],
               triggers=[{"on": {"kind": "round_end"},
                          "effects": [{"op": "draw", "who": "self", "amount": 1}]}],
               patterns=["round_end_trigger", "draw"]),
    ],
    "locations": [
        location(2, [{"op": "aura_stat_mod", "scope": "all_companions", "attack": 1}]),
    ],
}


# =============================================================================
# Assembly
# =============================================================================

TYPE_WORD = {
    "HERO": "Hero", "SKILL": "Skill", "COMP": "Companion",
    "EQUIP": "Equipment", "TAAHMA": "Ta'ahma", "LOC": "Location",
}


def stable_seed(text):
    """A small, stable pseudo-random number derived from a card id."""
    h = 2166136261
    for ch in text:
        h = ((h ^ ord(ch)) * 16777619) & 0xFFFFFFFF
    return h % 100000


def finish(body, *, code, key, display, hue, role, kind, index, rarity,
           named=False, unique=None):
    cid = "%s_%s_%02d" % (code, kind, index)

    # A card that has been authored for real is not regenerated. This is what
    # lets proxies be replaced one at a time without the next regeneration
    # undoing the work.
    prior = EXISTING.get(cid)
    if prior is not None and prior.get("authored"):
        return prior

    name = "%s Proxy %s %02d" % (display, TYPE_WORD[kind], index)
    is_neutral = key == "neutral"

    d = {
        "id": cid,
        "revision": 1,
        "placeholder": True,
        "name": name,
        "types": list(body["types"]),
        "tags": list(body.get("tags", [])),
        "affinities": [] if is_neutral else [key],
        "rarity": rarity,
        "unique": bool(body.get("unique", False)) if unique is None else bool(unique),
        "character_id": "",
        "cost": body["cost"],
    }
    if named:
        suffix = "hero" if kind == "HERO" else "char"
        d["character_id"] = "%s_%s_%02d" % (key, suffix, index)

    if kind != "HERO":
        d["timing"] = list(body.get("timing", ["action"]))
        if "reaction" in d["timing"]:
            d["reaction_window"] = body.get("reaction_window", "before")
    else:
        d["hero_max_energy"] = body["hero_max_energy"]

    for field in ("energy_contribution", "attack", "defense", "attack_cost"):
        if body.get(field, 0):
            d[field] = body[field]

    if "persistent" in body:
        d["persistent"] = body["persistent"]
    if "target" in body:
        d["target"] = body["target"]

    d["effects"] = body.get("effects", [])
    d["triggers"] = body.get("triggers", [])
    # Rules text is generated from the effects above by src/core/text_gen.gd;
    # nothing here ever writes card text by hand.
    d["text"] = CARD_TEXT.get(cid, "")
    d["flavor"] = ("Placeholder flavour for %s. Names, art and flavour are "
                   "replaceable and never change mechanics." % name)
    d["art"] = {
        "style": "abstract_sigil",
        "seed": stable_seed(cid),
        "hue": hue,
        "saturation": 0.0 if is_neutral else 0.45,
    }
    # Real art survives regeneration even on a card that is still a proxy.
    if prior is not None and isinstance(prior.get("art"), dict):
        for field in ("image", "fit"):
            if prior["art"].get(field):
                d["art"][field] = prior["art"][field]
    d["patterns"] = sorted(set(body.get("patterns", []) or ["misc"]))
    d["ai_hints"] = {
        "role": role,
        "priority": round(min(1.0, 0.35 + 0.12 * _body_cost(body)), 2),
        "patterns": d["patterns"],
    }
    return d


def _body_cost(body):
    cost = body.get("cost", {})
    if cost.get("kind") == "fixed":
        return cost.get("amount", 0)
    if cost.get("kind") == "x":
        return 2
    return 1


def build_affinity(key, code, display, hue, role):
    content = CONTENT[key]
    cards = []
    common = dict(code=code, key=key, display=display, hue=hue, role=role)

    for i, body in enumerate(content["heroes"], start=1):
        cards.append(finish(body, kind="HERO", index=i, rarity="legendary",
                            named=True, unique=True, **common))
    for i, body in enumerate(content["skills"], start=1):
        cards.append(finish(body, kind="SKILL", index=i,
                            rarity=SKILL_RARITY[i - 1], **common))
    for i, body in enumerate(content["companions"], start=1):
        named = i >= 9  # the last two Companions of each Affinity are named characters
        cards.append(finish(body, kind="COMP", index=i,
                            rarity=COMPANION_RARITY[i - 1],
                            named=named, unique=named, **common))
    for i, body in enumerate(content["equipment"], start=1):
        cards.append(finish(body, kind="EQUIP", index=i,
                            rarity=EQUIPMENT_RARITY[i - 1], **common))
    for i, body in enumerate(content["taahma"], start=1):
        cards.append(finish(body, kind="TAAHMA", index=i,
                            rarity=TAAHMA_RARITY[i - 1], **common))
    for i, body in enumerate(content["locations"], start=1):
        cards.append(finish(body, kind="LOC", index=i,
                            rarity=LOCATION_RARITY[i - 1], **common))
    return cards


def build_neutral():
    cards = []
    common = dict(code="NEU", key="neutral", display="Neutral", hue=210, role="flexible")
    for i, body in enumerate(NEUTRAL["skills"], start=1):
        cards.append(finish(body, kind="SKILL", index=i,
                            rarity=NEUTRAL_SKILL_RARITY[i - 1], **common))
    for i, body in enumerate(NEUTRAL["companions"], start=1):
        named = i == len(NEUTRAL["companions"])
        cards.append(finish(body, kind="COMP", index=i,
                            rarity=NEUTRAL_COMPANION_RARITY[i - 1],
                            named=named, unique=named, **common))
    for i, body in enumerate(NEUTRAL["equipment"], start=1):
        cards.append(finish(body, kind="EQUIP", index=i,
                            rarity=NEUTRAL_EQUIPMENT_RARITY[i - 1], **common))
    for i, body in enumerate(NEUTRAL["taahma"], start=1):
        cards.append(finish(body, kind="TAAHMA", index=i,
                            rarity=NEUTRAL_TAAHMA_RARITY[i - 1], **common))
    for i, body in enumerate(NEUTRAL["locations"], start=1):
        cards.append(finish(body, kind="LOC", index=i,
                            rarity=NEUTRAL_LOCATION_RARITY[i - 1], **common))
    return cards


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    files = {}
    for idx, (key, code, display, hue, role) in enumerate(AFFINITIES, start=1):
        files["%03d_%s.json" % (idx * 10, key)] = build_affinity(key, code, display, hue, role)
    files["080_neutral.json"] = build_neutral()

    everything = [c for cards in files.values() for c in cards]

    # --- self-checks: the blueprint's required catalog totals ---------------
    assert len(everything) == 300, "expected 300 definitions, got %d" % len(everything)

    authored = [c for c in everything if c.get("authored")]
    with_art = [c for c in everything if isinstance(c.get("art"), dict) and c["art"].get("image")]

    ids = [c["id"] for c in everything]
    assert len(set(ids)) == 300, "card ids are not unique"
    names = [c["name"] for c in everything]
    assert len(set(names)) == 300, "display names are not unique"

    def count_type(t):
        return sum(1 for c in everything if t in c["types"])

    expected_types = {"hero": 14, "skill": 150, "companion": 76,
                      "equipment": 30, "taahma": 15, "location": 15}
    for t, n in expected_types.items():
        got = count_type(t)
        assert got == n, "expected %d %s cards, got %d" % (n, t, got)

    reactions = [c for c in everything if "reaction" in c["tags"]]
    assert len(reactions) == 40, "expected 40 Reaction-tagged Skills, got %d" % len(reactions)
    for c in reactions:
        assert "skill" in c["types"], "%s is tagged Reaction but is not a Skill" % c["id"]
    for key, _code, _d, _h, _r in AFFINITIES:
        n = sum(1 for c in reactions if c["affinities"] == [key])
        assert n == 5, "%s has %d Reaction Skills, expected 5" % (key, n)
    n_neutral_rx = sum(1 for c in reactions if not c["affinities"])
    assert n_neutral_rx == 5, "expected 5 neutral Reaction Skills, got %d" % n_neutral_rx

    rarities = {"common": 0, "uncommon": 0, "rare": 0, "legendary": 0}
    for c in everything:
        rarities[c["rarity"]] += 1
    assert rarities == {"common": 150, "uncommon": 90, "rare": 45, "legendary": 15}, \
        "rarity distribution is %s" % rarities

    for key, _code, _d, _h, _r in AFFINITIES:
        n = sum(1 for c in everything if c["affinities"] == [key])
        assert n == 40, "%s has %d definitions, expected 40" % (key, n)
    assert sum(1 for c in everything if not c["affinities"]) == 20

    martial = sum(1 for c in everything if "martial" in c["tags"])
    magic = sum(1 for c in everything if "magic" in c["tags"])
    assert martial > 0 and magic > 0, "the catalog needs both Martial and Magic Skills"

    patterns = set()
    for c in everything:
        patterns.update(c["patterns"])
    assert len(patterns) >= 24, "only %d behaviour patterns: %s" % (len(patterns), sorted(patterns))

    for fname in sorted(files):
        path = os.path.join(OUT_DIR, fname)
        with open(path, "w") as fh:
            json.dump(files[fname], fh, indent=2)
            fh.write("\n")
        print("wrote %-22s %3d cards" % (fname, len(files[fname])))

    if authored:
        print("\npreserved %d authored definition(s): %s" % (
            len(authored), ", ".join(c["id"] for c in authored[:12])))
    if with_art:
        print("preserved art references on %d definition(s)" % len(with_art))
    print("\n%d definitions; types %s" % (len(everything), expected_types))
    print("rarities %s" % rarities)
    print("%d Reaction Skills; %d behaviour patterns" % (len(reactions), len(patterns)))
    print("patterns: %s" % ", ".join(sorted(patterns)))


if __name__ == "__main__":
    main()
