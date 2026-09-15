# Architecture

## Separation of responsibilities

| Component | Files | Responsibility |
| --- | --- | --- |
| Catalog and schemas | `src/core/effect_schema.gd`, `card_def.gd`, `catalog.gd`, `text_gen.gd` | Validate definitions, overrides, rarity pools and effect data. Generate rules text from effects. |
| Rules profile | `src/core/rules_profile.gd`, `data/rules_profile.json` | Established constants plus explicitly provisional timing settings. |
| Rules engine | `src/core/engine.gd`, `game_state.gd`, `mechanics.gd`, `targeting.gd`, `chain.gd` | Phases, legality, targeting, resolution, loss checks, events. |
| Effect interpreter | `src/core/effects.gd` | Execute supported card instructions and trigger conditions. |
| AI policy | `src/ai/*` | Choose among legal commands from permitted observations. |
| Persistence | `src/persistence/*` | Versioned profile, decks, catalog overrides, economy, match records. |
| Interface | `src/ui/*` | Render state, request validated commands. |
| Simulation and tests | `src/core/match_runner.gd`, `tests/*`, `tools/run_tests.gd` | Reproduce games and check invariants without a browser or a person. |

Dependencies point one way: the interface depends on the engine, the engine
never depends on the interface. `src/core` and `src/ai` have no UI imports at
all, which is why a match is fully playable headlessly.

## One authoritative state

`GameState` is the only game state. The interface renders it and submits
commands; it never keeps a second copy of the rules and no animation decides an
outcome. `MatchRunner` drives the same state with automatic controllers, and the
battle screen drives it with a human on one side.

Every command goes through `GameEngine.submit()`, which validates first and
rejects without partial payment or movement. `GameEngine.legal_commands()`
enumerates exactly what is legal right now; the AI picks from that list and the
interface enables exactly those controls.

## Identifiers

| Kind | Example | Scope |
| --- | --- | --- |
| Card definition | `PAS_SKILL_01` | Permanent. Owned copies and saved decks reference it. |
| Card instance | `c47` | One match. Three copies of a Skill share one definition id and get three instance ids. |
| Action slot | `s12` | One match. |
| Deck | `deck_1758…` | One save. |
| Match | `match_1758…` | Permanent in the reward record, which is how paying twice is prevented. |
| Pack opening | `open_3_profile_…` | Permanent in the opening record. |

Match-scoped ids come from a counter held in the state, so a resumed match keeps
numbering deterministically.

## Randomness

`HotRng` holds independent named streams: shuffles, Hero-damage sampling, AI
tie-breaking and pack openings never shift each other's results. The full state
serialises, so a saved match resumes with identical future rolls. Nothing uses
Godot's global RNG.

Hidden RNG state never reaches the AI. Search runs on a clone with a fresh
stream seeded from the AI's own search seed.

## What the AI may know

`Observation.build()` returns the AI's permitted view: its own hand, every
public zone, visible resources, deck counts, public event history and the
opponent's advertised deck theme. It does not contain the human's hand
contents, either player's Hit order, cards sampled from a Hit Deck, or the RNG.

`Observation.sanitized_clone()` is the forward model the search runs on. Hidden
information is **destroyed** there, not merely ignored:

* both Hit Decks are reshuffled with the AI's own stream, so no policy can read
  a draw order it is not entitled to know, including its own;
* the opponent's hand keeps only its visible size, with plausible cards drawn
  from the public Hit and Exhaust piles substituted in;
* the match RNG is replaced.

`tests/test_ai.gd` asserts all of this, so a future policy change cannot quietly
start cheating.

## Ordering guarantees

The engine maintains these in this order, and `tests/test_rules.gd` pins each:

* Energy is spent on commitment, including for Reactions.
* A pending Companion grants no persistent bonus before its deployment resolves.
* Stat modifiers are applied at attack resolution, not at commitment.
* Resolution triggers are emitted while the resolving character is still in the
  Action Sequence, and those triggers finish before its membership ends.
* After-Action Reactions resolve in their scheduled position.
* Round effects expire and resources refresh only at Round End.
* One primitive effect completes, then its trigger queue is processed, before
  the next primitive starts.

An unsatisfied required draw or removal is checked at the moment it occurs,
before later triggers could restore cards. Failures are gathered and settled at
a boundary so simultaneous failures produce a draw rather than a race.

## Match snapshots

`GameState.to_dict(true)` embeds the exact card definitions the match is using
and the rules profile it started with. Resuming rebuilds a frozen catalog from
that snapshot, so editing a card or a rules default mid-match cannot change a
game in progress. `tests/test_catalog.gd` proves it.

For AI search, `GameState.clone_for_search()` copies field by field and shares
the catalog and rules by reference, dropping the event log and archived round
history. That path is called thousands of times per decision, so the difference
matters: it is roughly twice as fast as a dictionary round trip, and skipping
the growing log is what keeps late rounds affordable.

## Persistence

`SaveStore` writes a temporary file, verifies it parses, rotates the live save
to a backup and renames the temporary file into place. An interrupted write
leaves either the old save or the new one. An unreadable save is copied aside
and the backup is tried; a save from a newer build is refused with an
explanation rather than overwritten.

Catalog imports are schema validated and treated as data. Nothing in a save is
ever executed.

## Interface conventions

Screens are built programmatically from `UiTheme` helpers rather than from
scene files, so a change to spacing or palette lands everywhere at once. Every
screen exposes `setup(app, args)` and is rebuilt on navigation.

Colour is never the only signal: Affinity carries a glyph and a name, rarity
carries a mark and a name, and legality is always spelled out. Every control
works with a click or a tap, and dragging is never required.

The battle screen steps `AiThinker` across frames with a per-frame budget, so
the opponent thinking never blocks the interface, and a decision always
resolves to a legal command or a legal pass.

## Test suites

| Suite | Covers |
| --- | --- |
| `rules` | The engine's timing and legality acceptance checks, including the Parfait Energy-refund fixture. |
| `catalog` | Catalog totals, validation, rarity pools, deck legality, edits preserving references, match snapshots. |
| `progression` | Idempotent rewards, pack transactions, duplicate conversion, save round trips, import refusal. |
| `ai` | Observation restrictions, sanitised search, per-Affinity profiles, legal play, reproducibility, simulation limits. |
| `ui` | The blueprint's manual walkthrough, driven through the real screens. |

`tests/fixtures.gd` holds development-only card definitions. They are built in
code, never written to `data/catalog`, and never counted toward the 300.
