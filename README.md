# Heroes of Teloria — playable prototype

A two-player Affinity card game: one human against a local computer opponent.
Build a deck, choose an Affinity opponent, play a full match, earn gold for
winning, buy and open packs, improve your decks, play again.

Everything in the card catalog is deliberately replaceable proxy content.
Names, art, numbers, rarities and Affinity playstyles are placeholders and
establish no Teloria lore or final balance.

## What is built

| Area | State |
| --- | --- |
| Rules engine | Shared round, Action Sequence, Reaction windows, Energy, Wound Deck, Affinity chains, loss conditions. Pure and headlessly runnable. |
| Card catalog | 300 validated definitions with generated rules text, plus an in-app editor. |
| Decks | Seven granted starter decks, seven Affinity AI decklists, full deck builder with import and export. |
| Opponents | Seven Affinity AI profiles sharing one legal-command API, with a restricted observation model. |
| Progression | Gold, boosters, duplicate conversion, idempotent rewards, durable pack transactions. |
| Persistence | Versioned save with atomic writes, backup rotation, export and import. |
| Interface | Home, Collection, Deck builder, Opponent selection, Battle, Results, Shop, Card editor, Settings. Cards and attacks can be dragged onto their targets or played by clicking. |
| Tests | 811 assertions across five suites, all passing. |

## Requirements

* **Godot 4.4.1** (standard build, not .NET). Nothing else: no package manager,
  no build step, no backend, no account, no paid service.
* The project uses the GL Compatibility renderer, so it runs on modest hardware.

Download Godot from <https://godotengine.org/download>. The engine version this
project was developed and tested against is recorded in `project.godot`
(`config/features = "4.4"`).

## Running the game

```sh
# From the repository root, with the Godot binary on your PATH:
godot --path .

# Or open project.godot in the Godot editor and press Play.
```

## The battle board

The board reads as two mirrored halves around a shared middle.

```
              opponent's Companion Zone
   Wound | Exhaust | Hero | Hit          (the opponent's decks, mirrored)
  ------------------------------------------------------------------
   Action Sequence  (resolves left to right)        |  Location
  ------------------------------------------------------------------
   Hit | Hero | Exhaust | Wound          (your decks)
              your Companion Zone
                        your hand  (pinned to the bottom)
```

The screen is built from one painted board, sliced into plates by
`tools/slice_board.gd`. Each zone is one of those plates, scaled to cover its
place on screen and clipped rather than squashed, so the artwork and the
caption painted onto it stay true at any size.

Each player has their own Hero, their three decks (Hit, Exhaust and Wound) and
their own Companion Zone. The Action Sequence and the Location sit once in the
middle because the rules give the two players one of each between them, not one
apiece. Your hand is pinned below the board and never scrolls away, so a card
the engine will accept is always reachable. Cards are drawn at standard
trading-card proportions, 2.5 by 3.5.

## Card faces

A card type can have a painted frame. Heroes have one: `assets/frames/` holds
the painted template and the frame built from it by
`tools/prepare_hero_frame.gd`, which paints out the placeholder name, stat
numbers and lorem rules text so the game can fill them in, and leaves
everything that is the same on every Hero — the HERO banner, the MAX ENERGY,
ATTACK and DEFENSE captions, the ornament. The live card then anchors each
value over the region the template painted for it, as a fraction of the card,
so the whole face scales together.

Rebuild the frame after replacing the template:

```sh
godot --headless --path . --script tools/prepare_hero_frame.gd
```

A card can opt out with `"frame": "plain"` in its data, which is how a card
finished before its type had a frame keeps the look it shipped with. Parfait,
the Unyielding Flame is the one card that does.

Cards on the table are drawn small enough to fit it, which leaves their rules
text too small to read, so resting the pointer on one brings the same card up
at a size meant for reading. It works on everything that stands for a card: a
card in hand, a Hero or Companion in play, a step in the Action Sequence, the
Location. Over the hand the reader appears above the row, so it never covers
the cards next to the one being read. It is a reader, not a control — it takes
no input and never touches match state.

Resolution is not silent. When something takes damage the number floats off it,
and the cards it loses fly from the deck they leave into the Wound Deck, so the
count you see tick up has a visible cause. Destruction, exhaustion, shields,
Energy gains and drains, and deployments all get the same treatment. The
animations are cosmetic: they replay what the engine already decided and can
never change an outcome.

## Running the tests

```sh
# Everything (about 90 seconds; the AI suites play real matches):
godot --headless --path . --script tools/run_tests.gd

# One suite at a time:
godot --headless --path . --script tools/run_tests.gd -- rules
godot --headless --path . --script tools/run_tests.gd -- catalog
godot --headless --path . --script tools/run_tests.gd -- progression
godot --headless --path . --script tools/run_tests.gd -- ai
godot --headless --path . --script tools/run_tests.gd -- ui
```

The `ui` suite drives the real screens through the blueprint's manual
walkthrough. To watch it instead, run the screenshot driver, which needs a
display (`xvfb-run` works headlessly):

```sh
xvfb-run -a godot --path . --resolution 1440x900 --script tools/ui_drive.gd
# Screenshots land in build/screens/
```

## Regenerating the card catalog

`data/catalog/*.json` is the authoritative, hand-editable card data and is what
the game loads. It can also be regenerated from the generator:

```sh
GODOT=/path/to/godot tools/build_catalog.sh
```

That runs three passes, because the engine owns rules-text generation while the
Python generator owns the JSON file format: write the definitions, let Godot
render each card's text from its effects, then rewrite the definitions with
that text embedded. The decks are regenerated separately with
`python3 tools/generate_decks.py`.

You do not need Python to play, to edit cards in the app, or to run the tests.

## Saves

Progress is stored in Godot's `user://` directory:

* Linux: `~/.local/share/godot/app_userdata/Heroes of Teloria/`
* Windows: `%APPDATA%\Godot\app_userdata\Heroes of Teloria\`
* macOS: `~/Library/Application Support/Godot/app_userdata/Heroes of Teloria/`

A save is written as a temporary file and then renamed over the live save, so
an interrupted write leaves either the old save or the new one, never half of
each. The previous version is kept as `*.backup.json`. A save that cannot be
read is copied aside rather than deleted, and a save written by a newer build is
refused with an explanation rather than overwritten.

**Saves are specific to one device and one installation.** Nothing is
synchronised to a server. Use Settings → Export save to write a save file you
can back up or move elsewhere, and Import save to load one. If you export the
game to the Web, `user://` lives in that browser's IndexedDB-backed virtual
filesystem, so it is specific to that browser on that device too, and the
export button hands you a download instead of a file path.

## Project layout

```
assets/art/      Card art files, with a README on how a card points at one
data/            Hand-editable game data
  catalog/       The 300 card definitions, split by Affinity
  decks/         Starter decks and AI decklists
  rules_profile.json   Established constants plus provisional timing settings
  economy.json         Gold, booster and duplicate-conversion settings
  ai_profiles.json     Per-Affinity strategic weights
src/core/        Rules engine, catalog, effects, targeting, chains, validation
src/ai/          Observation model, policy, incremental thinker, profiles
src/persistence/ Save store, player profile, economy config
src/ui/          Theme, card view, application shell and the nine screens
tests/           Test suites and development-only card fixtures
tools/           Test runner, catalog generator, screenshot driver
docs/            Effect-schema guide and architecture notes
```

## Documentation

* `PROVISIONAL_RULES.md` — every temporary ruling and economy value, and where
  to change it.
* `docs/EFFECT_SCHEMA.md` — how to replace a proxy card and what the engine can
  and cannot be told to do without code changes.
* `docs/ARCHITECTURE.md` — component responsibilities and the invariants the
  engine maintains.
* `docs/ADDING_CARDS.md` — how to replace a proxy with a real card, what to
  send for each one, and what a replacement does to saves and decks.
* `assets/art/README.md` — where art files go and how a card points at one.
* `docs/screens/` — screenshots of every screen, captured from a real run.

## Honest limitations

* **Balance is unverified.** The 300 cards are proxies with numbers set by hand
  to exercise mechanics, not to play well against each other. No balance testing
  has been done, and several cards are almost certainly too strong or too weak.
* **The AI is one competent difficulty.** It uses a heuristic evaluation with a
  bounded one-ply search: it commits an Action, lets the round play out on a
  sanitised clone, and scores the result with its Affinity's weights. It does
  not plan across rounds, and it will miss multi-card combinations.
* **A web export has not been built or tested.** Godot can export this project
  to HTML5, and the save layer is written with that target in mind, but no
  export preset is committed and no browser run has been verified. Treat the
  browser build as untested work, not a finished deliverable.
* **AI thinking is fast enough but not instant.** A decision takes roughly 10 to
  60 milliseconds depending on how crowded the board is. The battle screen
  spreads that work across frames so the interface stays responsive.
* **The card editor edits data, not mechanics.** Any effect outside the
  vocabulary in `docs/EFFECT_SCHEMA.md` needs the engine extended first, and the
  editor will refuse to save a definition the interpreter cannot run.
* **Dragging is an addition, not a replacement.** Every action in a match can
  be taken by clicking, so the game stays usable on a trackpad or a
  touchscreen. The drag system is tested through the same entry points Godot's
  own input calls, and with a simulated mouse drag, but it has not been tried
  on a touchscreen.
* **No multiplayer.** The blueprint's first release is single-player against AI,
  and that is what this is.
