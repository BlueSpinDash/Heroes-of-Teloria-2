# Effect schema guide

How to replace a proxy card, and what the engine can be told to do without
writing any code.

The single source of truth is `src/core/effect_schema.gd`. Three consumers share
it: catalog validation, the effect interpreter (`src/core/effects.gd`) and the
rules-text generator (`src/core/text_gen.gd`). If this document and that file
ever disagree, the file is right.

## The one rule that makes the editor trustworthy

**Card text is generated from the effect data. It is never typed by hand.**

Validation compares a definition's stored `text` against what `TextGen` produces
from its effects and rejects any mismatch. The in-app editor regenerates the
text on every preview and every save. So a card cannot advertise behaviour the
interpreter will not perform: if you want the card to say something different,
you change what it does.

## Anatomy of a definition

```json
{
  "id": "PAS_SKILL_01",
  "revision": 1,
  "placeholder": true,
  "name": "Passion Proxy Skill 01",
  "types": ["skill"],
  "tags": ["magic", "ranged"],
  "affinities": ["passion"],
  "rarity": "common",
  "unique": false,
  "character_id": "",
  "cost": {"kind": "fixed", "amount": 1},
  "timing": ["action"],
  "target": null,
  "effects": [{"op": "damage_hero", "who": "opponent", "amount": 2}],
  "triggers": [],
  "text": "Deal 2 damage to the opposing Hero.",
  "flavor": "…",
  "art": {"style": "abstract_sigil", "seed": 285, "hue": 350, "saturation": 0.45},
  "patterns": ["hero_burn"],
  "ai_hints": {"role": "aggro", "priority": 0.47, "patterns": ["hero_burn"]}
}
```

* `id` is immutable. Owned copies and saved decks reference it, so renaming a
  card or rebalancing it never breaks either.
* `revision` increments on every edit. A match snapshot pins the revisions it
  started with, so editing a card mid-match cannot change that match.
* `character_id` is the named-character identity, separate from `unique`. Two
  definitions sharing a `character_id` can never both appear in one deck, which
  is what stops a future alternate version from evading the restriction.
* `patterns` are behaviour tags used for catalog coverage checks and by the AI's
  candidate ranking. They do not affect rules.

Type-specific fields: `hero_max_energy` on Heroes; `attack`, `defense` and
`attack_cost` on characters; `energy_contribution` on Companions; printed
`attack` and `defense` modifiers on Equipment; a `persistent` block on anything
that stays in play; `reaction_window` (`"before"` or `"after"`) on Reactions.

## Replacing a proxy

Everything here is a data change. No code, no rebuild.

1. **Rename it, reflavour it, change its art.** Edit `name`, `flavor` and `art`.
   Art is generated from `seed`, `hue` and `saturation`; swapping in real
   illustration later changes nothing about mechanics or identity.
2. **Rebalance it.** Edit `cost`, `attack`, `defense`, `attack_cost`,
   `energy_contribution`, `hero_max_energy`.
3. **Reclassify it.** Edit `rarity`, `affinities`, `tags`, `unique`.
4. **Change what it does.** Edit `effects` and `triggers` using the vocabulary
   below.

Do it in the app (Card editor) or in `data/catalog/*.json` directly. Editing in
the app stores an override in your save and leaves the shipped file untouched,
so "Restore bundled version" always works. Editing the JSON changes the shipped
card for everyone.

After editing the JSON by hand, regenerate the text and revalidate:

```sh
GODOT=/path/to/godot tools/build_catalog.sh
```

Or just open the card in the in-app editor and press Save, which regenerates the
text for that one card.

## Costs

| `cost` | Meaning |
| --- | --- |
| `{"kind": "none"}` | No play cost. Heroes must use this. |
| `{"kind": "fixed", "amount": N}` | Costs N Energy, paid on commitment. |
| `{"kind": "x", "min": N}` | The player chooses X at commitment, at least N. |

An X card must use `{"from": "x"}` in at least one amount, and a card that uses
X must have an X cost. The chosen X is stored on the committed Action and later
Energy changes never rewrite it. Such cards display the established wording
automatically: *"X is equal to the amount of Energy spent to play this card."*

## Amounts

An amount is a plain integer or a dynamic object:

| Amount | Meaning |
| --- | --- |
| `7` | Exactly seven. |
| `{"from": "x"}` | The Energy actually spent on this card's X cost. |
| `{"from": "chain_count", "affinity": "passion", "scope": "either"}` | Matching Actions in the current Affinity chain. `affinity` may be `"any"`; `scope` is `controller`, `opponent` or `either`. |
| `{"from": "count", "of": "own_companions"}` | A board or pile count. `of` is one of `own_companions`, `opponent_companions`, `own_hand`, `opponent_hand`, `own_exhaust`, `opponent_exhaust`. |

Add `"multiplier": 0.5` to scale a dynamic amount. Negative amounts are only
allowed on `energy_max_mod` and `aura_energy_max`.

## Targets

A card that needs the player to choose declares one `target` block:

```json
"target": {"kind": "opponent_companion", "count": 1, "optional": false}
```

Kinds: `opponent_companion`, `own_companion`, `any_companion`,
`opponent_character`, `own_character`, `any_character`, `own_equipment`,
`opponent_equipment`, `any_equipment`, `own_taahma`, `opponent_taahma`,
`any_taahma`, `location`, `own_character_host`.

An attachment played from hand must target `own_character_host`.

Inside effects, a `target` field is a symbolic reference, not a kind:

| Reference | Resolves to |
| --- | --- |
| `chosen` | What the player picked, revalidated at resolution |
| `self` | This card |
| `host` | An attachment's host character |
| `self_hero` / `opponent_hero` | The controller's Hero / the other Hero |
| `all_own_companions` / `all_opponent_companions` / `all_companions` | Every matching Companion |
| `current_attacker` / `current_target` | The attack this Reaction is responding to |

A reference may be narrowed by Affinity by writing it as an object instead of
a name:

```json
{"op": "stat_mod", "duration": "round", "attack": 1, "defense": 1,
 "target": {"ref": "all_own_companions", "affinity": "vigilance"}}
```

That reads "each Vigilance Companion you control". Narrowing a reference that
resolves to a single card is allowed and simply makes the effect do nothing
when that card does not carry the Affinity.

Targets are chosen on commitment and revalidated on resolution. An invalid
choice makes the referencing component do nothing: there is no retarget, no
Energy refund, and no restored action allowance.

## Effect operations

Twenty operations. Anything else fails validation.

**Damage and removal**

| Op | Fields | Effect |
| --- | --- | --- |
| `damage_hero` | `who`, `amount` | Wounds that many random cards, Exhaust first then Hit. |
| `direct_damage` | `target`, `amount`, `ignores_defense` | Damage to a character. `ignores_defense` must be stated explicitly. |
| `destroy` | `target` | To the owner's Wound Deck. |
| `bounce` | `target` | A Companion returns to its owner's hand. |

**Cards and piles**

| Op | Fields | Effect |
| --- | --- | --- |
| `draw` | `who`, `amount` | A required draw: failing it loses the match. |
| `mill` | `who`, `amount` | Up to that many cards from the top of Hit to Exhaust. |
| `recover_from_exhaust` | `who`, `amount` | Up to that many cards from Exhaust to hand, chosen by that player. |
| `exhaust_from_hand` | `who`, `amount`, `chooser` | A chosen discard. |
| `random_exhaust_from_hand` | `who`, `amount` | A random discard. |
| `deploy_from_hand` | `who` | Put a Companion from hand into play. |
| `choose_card_type` | `chooser` | That player names one of the six Card Types. The card remembers it for the round, and `chosen_type_card_resolved` reads it. |

**Energy**

| Op | Fields | Effect |
| --- | --- | --- |
| `energy_gain` | `who`, `amount` | Restores spent Energy, capped at the current maximum. |
| `energy_drain` | `who`, `amount` | Removes current Energy. |
| `energy_max_mod` | `who`, `amount`, `duration` | Changes the maximum. May be negative. |

**Modifiers**

| Op | Fields | Effect |
| --- | --- | --- |
| `stat_mod` | `target`, `duration`, `attack` and/or `defense` | A temporary or permanent stat change. |
| `prevent_damage` | `target`, `amount`, `duration` | Prevents the next N damage to that card. |

**Continuous, only on a card that stays in play**

| Op | Fields | Effect |
| --- | --- | --- |
| `aura_stat_mod` | `scope`, `attack` and/or `defense` | A continuous stat aura while the source is in play. |
| `aura_energy_max` | `who`, `amount` | A continuous maximum-Energy change. |

Aura scopes: `own_companions`, `opponent_companions`, `all_companions`,
`own_hero`, `opponent_hero`, `own_characters`, `opponent_characters`, `host`.

**Control flow**

| Op | Fields | Effect |
| --- | --- | --- |
| `conditional` | `cond`, `then`, optional `otherwise` | Branch on a condition. |
| `chain_reward` | `require`, `then` | Branch on an Affinity-chain requirement. |
| `repeat` | `amount`, `effects` | Repeat, capped at 32 iterations. |

`who` is `self` or `opponent`, relative to the card's controller. `duration` is
`step`, `round` or `permanent`.

## Conditions

`chain_at_least`, `controls_companions`, `energy_at_least`,
`hand_size_at_least`, `exhaust_at_least`, `hit_at_most`, `location_active`,
`has_attachment`, `target_defense_at_most`, `target_attack_at_least`.

```json
{"op": "conditional",
 "cond": {"kind": "controls_companions", "who": "self", "min": 2},
 "then": [{"op": "damage_hero", "who": "opponent", "amount": 3}],
 "otherwise": [{"op": "draw", "who": "self", "amount": 1}]}
```

## Triggers

```json
"triggers": [
  {"on": {"kind": "affinity_card_resolved", "affinity": "passion", "scope": "either"},
   "effects": [{"op": "energy_gain", "who": "self", "amount": 1}]}
]
```

Kinds: `affinity_card_resolved`, `chosen_type_card_resolved`, `self_deployed`,
`own_companion_deployed`, `self_attack_resolved`, `attack_resolved`,
`round_end`, `own_hero_damaged`, `opponent_hero_damaged`, `self_leaves_play`.

`affinity_card_resolved` on a **character** only fires while that character is
actually in the Action Sequence. That is the Parfait pattern: she pays one
Energy for her Passion attack and gets it back when her own attack resolves,
before she leaves the Sequence. `tests/test_rules.gd` keeps that behaviour
pinned as a fixture.

`chosen_type_card_resolved` fires when a card of the type this card named
resolves. It does **not** require its source to still be in the Sequence,
because it is worded for the rest of the round rather than for while the card
is committed. It reads as "after" on its own: a type is only named when the
card resolves, so nothing that resolved earlier can match it, and the name is
forgotten at Round End with everything else that lasts a round. That is the
Sorbet pattern — she names a Card Type when her attack resolves, and every
Vigilance Companion her controller has grows each time a card of that type
resolves afterwards — and it is pinned as a fixture too.

Avoid `stat_mod` or `prevent_damage` with `"duration": "round"` inside a
`round_end` trigger: round-duration effects expire moments later in the same
phase. Use `draw`, `energy_gain`, `damage_hero` or a permanent duration instead.

## Worked example: a new proxy

A two-Energy Vigilance Reaction that blunts an incoming attack and draws a card
if you are already ahead on board.

```json
{
  "id": "VIG_SKILL_21",
  "revision": 1,
  "placeholder": true,
  "name": "Vigilance Proxy Skill 21",
  "types": ["skill"],
  "tags": ["martial", "reaction"],
  "affinities": ["vigilance"],
  "rarity": "uncommon",
  "unique": false,
  "character_id": "",
  "cost": {"kind": "fixed", "amount": 2},
  "timing": ["reaction"],
  "reaction_window": "before",
  "effects": [
    {"op": "stat_mod", "target": "current_attacker", "attack": -3, "duration": "round"},
    {"op": "conditional",
     "cond": {"kind": "controls_companions", "who": "self", "min": 2},
     "then": [{"op": "draw", "who": "self", "amount": 1}]}
  ],
  "triggers": [],
  "text": "",
  "flavor": "Placeholder flavour.",
  "art": {"style": "abstract_sigil", "seed": 4711, "hue": 215, "saturation": 0.45},
  "patterns": ["debuff_reaction", "draw", "conditional_bonus"],
  "ai_hints": {"role": "control", "priority": 0.6}
}
```

Leave `text` empty and let the build fill it in. It will read:

> Reaction (before the Action): The attacking character gets -3 Attack for the
> round. If you control at least 2 Companions, you draw 1 card.

## What needs the engine extended

Honestly: anything the vocabulary above cannot express. For example a card that
cancels an Action outright, reorders the Action Sequence, copies another card,
searches a Hit Deck for a named card, or steals control of a Companion. None of
those are in the first catalog, and the first three need further timing
decisions before they could be added safely.

Adding one means three coordinated changes:

1. Add the op, condition or trigger to `src/core/effect_schema.gd`.
2. Implement it in `src/core/effects.gd` (or `src/core/mechanics.gd` for a new
   rules primitive).
3. Add a text template in `src/core/text_gen.gd`, so the card can describe
   itself truthfully.

Then add a test in `tests/test_rules.gd` that pins the behaviour, and the
catalog validator will start accepting cards that use it.
