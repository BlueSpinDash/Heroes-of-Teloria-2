# Provisional rulings and settings

Everything in this file is a **temporary prototype decision**, not a claim about
the settled design of Heroes of Teloria. Each entry says what was chosen, why a
choice was needed, and where to change it.

Changing any of these means editing a data file and re-running the tests. None
of them requires touching engine code.

| Where | What it controls |
| --- | --- |
| `data/rules_profile.json` | Timing and structural defaults |
| `data/economy.json` | Gold, boosters and duplicate conversion |
| `data/ai_profiles.json` | Per-Affinity AI strategic weights |

A match records the rules profile id and version it started with, so editing
the profile never changes a game already in progress.

---

## 1. Timing and structure

These fill gaps the source rules do not specify.

| Topic | Default | Key |
| --- | --- | --- |
| First Action priority | A seeded random choice in round one, then the first player alternates each later round. | `first_priority` |
| Opening mulligan | None. | `opening_mulligan` |
| Hand overflow | The full required draw completes first, including loss checks, and only then does the affected player choose cards to Exhaust down to seven. A required draw is never truncated to dodge defeat. | `hand_overflow` |
| Unique variety cap | No cap on how many different Unique cards a deck may hold, beyond one copy of each. | `unique_variety_cap` |
| Companion capacity | No numeric board cap. The board scrolls horizontally instead. | `companion_board_cap` |
| Reaction first opportunity | The opponent of the current step's controller acts first. | `reaction_first_opportunity` |
| Reaction passes | Opportunities alternate. Two consecutive passes close the window. Committing a Reaction resets the pass count, and a player may re-enter after a single pass while the window is still open. | `reaction_consecutive_passes_to_close`, `reaction_allow_reentry_after_single_pass` |
| Reaction ordering | Reactions are collected for the step, then before-Action Reactions resolve in commitment order, then the Action, then after-Action Reactions in commitment order. | `reaction_ordering` |
| Nested Reactions | None. Committing a Reaction does not open a new window inside the collected group. | `reaction_nesting` |
| Simultaneous triggers | The current primitive effect finishes, then its trigger queue is processed before the next primitive. The first player's controller's triggers go first, then the other player's; within a controller, in the order the sources entered play, then printed effect order. The chosen order is written to the match log. | engine constant, logged as `triggers_ordered` |
| Simultaneous defeat | Both players are checked at a simultaneous boundary. If both fail, the match is a draw. The Draw Phase evaluates both required draws before awarding anything. | `simultaneous_defeat_result` |
| Ta'ahma replacement | Replaced like Equipment: the previous card goes to its owner's Exhaust Deck. Explicit destruction sends it to Wound. | `taahma_replacement_destination` |
| Attachments losing their host | When a host leaves play, its attachments go to their owners' Exhaust Decks unless card text explicitly destroys or redirects them. | `orphan_attachment_destination` |
| Companion Energy on entry | Entering play raises the controller's maximum Energy only. It grants no current Energy without an explicit gain or refund effect. | `companion_energy_on_entry` |
| Control changes | Owner and controller are modelled separately, but the first catalog contains no control-stealing cards. | `control_stealing_cards` |
| Simulation round limit | 200 rounds. This is a **simulation safety limit** for automated runs. Reaching it is reported as a simulation limit and is never converted into a gameplay defeat. | `simulation_round_limit` |
| AI thinking budget | 45 ms of search per frame while the opponent decides. | `ai_think_budget_ms` |

### Two additional rulings made during implementation

These were needed to build a working engine and are not in the blueprint's own
list, so they are called out separately.

* **Player choices raised by a resolving card are presented at the end of that
  Action's step**, rather than interrupting the card mid-effect. This affects
  discards, recovery from Exhaust and optional deployment. The engine remains a
  clean state machine, and the choice still happens inside the step that caused
  it, before the next step begins.
* **A deck card that is the same named character as its own Hero is rejected.**
  The Hero sits outside the deck, so the copy limit does not literally apply,
  but allowing it would put two copies of one named character into the match.

## 2. Affinity chains

The source does not fully specify matching requirements, Reaction membership or
historical evaluation. The evaluator in `src/core/chain.gd` implements:

* Normal committed Action slots supply chain membership, character attacks
  included. An attack uses its character's Affinities as captured on commitment.
* Reactions attach to a slot but never join or break the chain. They can still
  fire effects such as "whenever a Passion card resolves"; exclusion from the
  chain does not suppress those triggers.
* Differing Affinities do not break a contiguous Affinity-bearing run. A card
  with no Affinity breaks it and cannot start one.
* Evaluating at slot K reads the contiguous run ending at K inclusive, stopping
  at the nearest previous Action with no Affinity. Later slots are never counted.
* Slot records survive their cards leaving the physical Sequence, and a slot
  whose target disappeared still occupies its historical position.
* A chain awards nothing by itself. Each card states its own threshold, whose
  cards it counts, and which Affinity it filters.

No hard counter or cancel-Action effects and no Sequence-reordering cards appear
in the first catalog; those need further timing decisions. Silence disrupts
through modifiers, Energy effects and removal instead.

## 3. Economy

All values live in `data/economy.json`.

| Setting | Value |
| --- | --- |
| Starting gold | 300 |
| Completed AI-match victory | 50 gold |
| Loss, concession or draw | 0 gold |
| Standard booster price | 100 gold |
| Cards per booster | 5 |
| Booster slots | 3 Common, 1 Uncommon, 1 premium |
| Premium slot | 85% Rare, 15% Legendary |
| Excess Common duplicate | 5 gold |
| Excess Uncommon duplicate | 10 gold |
| Excess Rare duplicate | 20 gold |
| Excess Legendary duplicate | 50 gold |
| Collection cap, ordinary card | 3 copies |
| Collection cap, Hero, named character or Unique card | 1 copy |
| Sandbox matches award gold | No |

Guarantees the implementation keeps regardless of these numbers:

* A completed match pays **once**, keyed by match id. Reopening the results
  screen or reloading the game cannot pay again. A rematch is a new match id.
* A booster **spends gold and grants its contents in one durable transaction**
  that is committed before anything is revealed. Refreshing mid-reveal resumes
  the same result and cannot reroll, charge twice or grant twice.
* An **unaffordable purchase leaves the save byte-for-byte unchanged**.
* Slot draws are **independent and uniform** within their rarity pool, so the
  same card can appear twice in one booster.
* A match's Wounds are temporary match state. Ending a match never removes
  anything from the collection.

## 4. Content allocation

The 300 definitions are placeholder test content. The distribution is a
provisional acquisition and content plan, not a design statement.

| Group | Heroes | Skills | Companions | Equipment | Ta'ahma | Locations | Total |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Each of the seven Affinities | 2 | 20 | 10 | 4 | 2 | 2 | 40 |
| Seven Affinities combined | 14 | 140 | 70 | 28 | 14 | 14 | 280 |
| Neutral (no Affinity) | 0 | 10 | 6 | 2 | 1 | 1 | 20 |
| Full catalog | 14 | 150 | 76 | 30 | 15 | 15 | 300 |

* Rarity: 150 Common, 90 Uncommon, 45 Rare, 15 Legendary.
* Reaction-tagged Skills: five per Affinity plus five neutral, 40 in total.
* The 14 Heroes are all Legendary, named characters and Unique.
* The last two Companions of each Affinity, and the last neutral Companion, are
  named characters. Each Affinity's fourth Equipment is Unique without being a
  named character, so both restrictions are exercised by real content.
* 51 distinct behaviour patterns appear across the catalog, against a required
  minimum of 24.

## 5. Affinity playstyles

Directions for proxy content and AI deck design. Not automatic Affinity powers,
and not final lore. No Affinity bonus is baked into the engine: every thematic
behaviour comes from actual cards and AI weights.

| Affinity | Direction |
| --- | --- |
| Devotion | Companion support and explicit protection effects. |
| Passion | Aggression, Energy refunds and spending decisions. |
| Will | Character enhancement and sustained attack pressure. |
| Vigilance | Efficient Reactions and deliberate defensive timing. |
| Purpose | Equipment, Ta'ahma and prepared combinations. |
| Harmony | Cards rewarding relationships across Affinities and the Sequence. |
| Silence | Disruption through modifiers, Energy denial and removal. |

Each AI decklist carries 35 of its 45 cards on its advertised Affinity, against
a target of at least 30.

## 6. Changing any of this

1. Edit the relevant data file.
2. Run the tests: `godot --headless --path . --script tools/run_tests.gd`.
3. If a rules default changed, expect the `rules` suite to tell you exactly
   which behaviour moved. Update the test alongside the ruling; do not rewrite
   unrelated cards or screens.

Bump `profile_version` in `data/rules_profile.json` when a timing default
changes, so matches saved under the old profile stay identifiable.
