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
| Card creator | Make your own card: pick its type, Affinity, numbers and features, and the prices they add up to are its Energy cost and its rarity. |
| Interface | Home, Collection, Deck builder, Opponent selection, Battle, Results, Shop, Card creator, Card editor, Settings. A match is played by dragging: a card onto its target or into a zone, a character onto what it attacks. |
| Tests | 1329 assertions across six suites, all passing. |

## Downloading and playing it

The [Releases page](https://github.com/BlueSpinDash/Heroes-of-Teloria-2/releases)
has a build for Windows, macOS and Linux. Nothing needs installing: unzip it and
run it.

| You are on | How to run it |
| --- | --- |
| Windows | Unzip **both files into the same folder** and run `HeroesOfTeloria.exe`. The build is unsigned, so SmartScreen says "Windows protected your PC" the first time — More info → Run anyway. |
| macOS | Unzip and **right-click the app → Open**. Double-clicking is refused, because the app is not signed or notarized. |
| Linux | Unzip both files into the same folder, `chmod +x HeroesOfTeloria.x86_64`, and run it. |

The `.pck` file beside the executable is the game's data; keep the two together.
Saves live in your user data folder rather than inside the download — the Saves
screen prints the exact path — so replacing a build with a later one keeps your
collection and decks.

Builds are made by `.github/workflows/release.yml` from a tagged commit, with
the full test suite passing first, so what you download is what the repository
says it is. To make one yourself:

```sh
godot --headless --path . --export-release "Windows Desktop" build/windows/HeroesOfTeloria.exe
```

`export_presets.cfg` is committed for that reason. Godot needs its export
templates installed for that version before it can export anything.

## Requirements

* **Godot 4.4.1** (standard build, not .NET). Nothing else: no package manager,
  no build step, no backend, no account, no paid service.
* The project uses the GL Compatibility renderer, so it runs on modest hardware.

Download Godot from <https://godotengine.org/download>. The engine version this
project was developed and tested against is recorded in `project.godot`
(`config/features = "4.4"`).

## Running it from source

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

Every card type but the Location has a painted frame: Heroes, Skills,
Companions, Equipment and Ta'ahma. `assets/frames/` holds the painted templates
and the frames built from them by `tools/prepare_card_frames.gd`, which paints
out the placeholder name, stat numbers and lorem rules text so the game can
fill them in, and leaves everything that is the same on every card of the type
— the type banner, the stat captions, the ornament. The live card then anchors
each value over the region the template painted for it, as a fraction of the
card, so the whole face scales together.

Painting out is done two ways. A **patch** stretches a clean piece of the same
surface over the words, which works on parchment and stone. On a cut gem or a
medallion, where every facet is lit differently, a patch taken from elsewhere
lands as a visible block, so an **inpaint** refills that region line by line
between the clean surface on either side of it — down a gem, across a medallion
that carries its icon directly above its number.

Two frames are pale stone rather than dark, so their numbers and footers are
inked dark instead of white. That follows the frame, not the card.

Each window has its corners cut back by a gothic arch, so art is clipped to the
window's shape rather than laid over it as a rectangle. A frame can also hand
back an ornament it paints across the window — the Skill frame's Energy gem —
which is cut out as its own picture and drawn above the artwork, the way the
printed card has it.

Rebuild the frames after replacing a template:

```sh
godot --headless --path . --script tools/prepare_card_frames.gd
```

A card can opt out with `"frame": "plain"` in its data, which is how a card
finished before its type had a frame can keep the look it shipped with. No card
uses it at the moment: every Hero and every Skill is on its frame.

`"frame": "printed"` goes the other way: the supplied card face is drawn whole,
with nothing placed on it. This is how a card supplied as a finished painting
is added — the face goes in `assets/cards/`, `tools/prepare_card_faces.gd`
takes the backdrop off it, and the card is drawn from it. The picture then
carries its own name, numbers and rules text, which means the game can no
longer restate what the card does when the card changes: the face has to be
redrawn instead. The card still carries real effect data underneath, because
that is what the game plays. `docs/ADDING_CARDS.md` sets out the trade.

Everything on the table that stands for a card is drawn as that card: your
Hero, both players' Companions, the Location in play, each step of the Action
Sequence, and your hand. A card in play carries one badge for whatever a player
most needs at a glance — what its statistics are now, what it is preventing,
whether it has already acted — and the rest in its tooltip.

Cards in a Hit, Exhaust or Wound Deck are face down, so those decks show the
card back — `assets/cards/card_back.png` — standing on the plate painted for
them, with how many are in the deck across its foot. A deck with nothing in it
shows its plate alone: there is no card there to be face down.

Cards on the table are drawn small enough to fit it, which leaves their rules
text too small to read, so resting the pointer on one brings the same card up
at a size meant for reading. It works on everything that stands for a card: a
card in hand, a Hero or Companion in play, a step in the Action Sequence, the
Location. Over the hand the reader appears above the row, so it never covers
the cards next to the one being read. It is a reader, not a control — it takes
no input and never touches match state.

**Your opponent holds a hand, and you can see it.** Their cards are face down,
because only how many they hold is public — but how many they hold matters
constantly, so it is a row of card backs on their own plate at the top of the
board, mirroring your hand at the bottom, rather than a number in a bar. Their
backs are drawn at exactly the size of the cards in your own hand: the same
cards, held the other way up.

Neither hand is scaled when the board is fitted to the window, because a hand
is not part of the table. That makes the two hands the one real claim on the
screen's height, and `hand_card_w` — which both of them use — the number that
decides how the height is split between a hand you can read and a table you can
read. It is set where the two are about even; the Layout screen's Board tab
moves it, and `opp_hand_card_w` narrows the opponent's alone if you would
rather spend the room on the table. The
bar at the top no longer repeats either that or the Energy: both are on the
board itself, and a number said in two places is a number that ends up
disagreeing with itself.

**Each player's Energy stands on their own side of the field.** Energy is spent
on nearly every decision in a round, so it is not left to a line of small text:
each half of the board carries the same Energy gem the cards do — the one
`tools/prepare_card_frames.gd` lifts off the card templates — with that player's
current Energy on the stone and their maximum beside it. Yours is at the left of
your deck row, your opponent's at the right of theirs, and the gem swells
briefly whenever the number changes, so Energy being spent or refreshed is seen
rather than noticed later. A player reading 3 here and a card asking for 3 are
looking at the same symbol.

**Every phase announces itself.** A banner crosses the board naming the phase
and the round — Draw, Action, Resolve, Round End — so what the game is doing is
never something you have to infer from your cards going grey.

**The Action Sequence resolves one card at a time.** The engine can hand control
back after each step, and the battle screen uses that: each step is announced by
name, its effects play out, there is a beat, and then the next one starts. It
changes nothing about what happens or in what order — the same steps, the same
results, only where the engine stops. Nothing that is not watching a match
resolves this way; the AI's rollouts run straight through, which is why
`GameState.watch_resolve` is set by the screen and never copied into a search
clone.

**The board fits the window.** Every zone is tall enough to hold a whole card,
and nothing on the table has to be scrolled to be seen. When the window cannot
hold the board at the size the layout asks for — a smaller screen, or the Layout
screen having been told to make the zones bigger — every card on the table is
drawn proportionally smaller instead, so the hand along the bottom is always
reachable. A hand you cannot reach is a game you cannot play.

Resolution is not silent. When something takes damage the number floats off it,
and the cards it loses fly from the deck they leave into the Wound Deck, so the
count you see tick up has a visible cause. Destruction, exhaustion, shields,
Energy gains and drains, and deployments all get the same treatment.

Every card that changes place flies there, drawn as a card rather than as a
marker: face down when it is a card you are not meant to see, face up when it
is. Draws leave the Hit Deck for the hand, milled cards leave it for the
Exhaust Deck, a recovered card comes back out of it, a bounced card returns to
its owner's hand, a deployed Companion flies from the hand into the Companion
Zone, and a card committed to the Action Sequence flies there before it
resolves. While that is playing out the opponent waits, up to a few seconds, so
a round's worth of movement can be watched rather than skipped past — your own
input is never held.

The animations are cosmetic: they replay what the engine already decided and
can never change an outcome.

A zone is a region, not an anchor point. While a card is being dragged, every
zone that would accept it is banded from edge to edge and named with what
dropping there would do, and letting go anywhere inside that band plays the
card — over the cards already standing in the zone, over its painted caption,
over its empty space. Characters are still dropped on individually, because
choosing one is the point.

## Making your own cards

The **Create** screen makes a card of your own, and the card tells you what it
costs.

Pick what it is — Companion, Skill, Equipment, Ta'ahma or Location — give it a
name and an Affinity, set its numbers, and choose from a list of features: deal
damage, draw, destroy a Companion, raise your maximum Energy, buff the
Companions you control, answer your own Affinity in the Action Sequence, and so
on. Import an image and it is copied into that save's own art folder, so moving
the original later cannot blank the card.

**Nothing is free, and you do not set the cost.** Every choice has a price in
points: a Companion's body, each point of Attack or Defense, a second Affinity,
being playable as a Reaction, and each feature — priced per point of whatever
it does, so two damage costs twice what one does. Ten points make one Energy,
and part of a point is still paid for. The card's printed Energy cost is what
the total comes to, and its **rarity follows the same total**, so a card cannot
be made cheaper or commoner than what is on it. The one thing that gives points
back is making its attack cost more to declare.

The ledger down the side itemises every line, so it is always clear which
choice made the card cost what it does.

`src/core/card_forge.gd` holds the whole pricing model — the prices, the
feature table, and the effect data each feature comes to. Changing what a
feature costs, or adding one built from effects the engine already performs, is
an edit to that one file.

What comes out is a real card, not a special case:

* Its rules text is **generated from its effect data** by the same `TextGen` as
  every shipped card, so a created card cannot promise something the engine
  will not do. A feature that cannot be expressed in the vocabulary in
  `docs/EFFECT_SCHEMA.md` is not offered.
* It passes the same `CardDef.validate()` as the shipped catalog. Anything that
  does not validate is refused and the reason is shown.
* It joins the catalog, the collection gets its three copies, and a deck may
  hold it. A match freezes it like any other card, so deleting the card later
  cannot change a game in progress.
* Its face is marked **CUSTOM**, so it is never mistaken for one of the game's
  own cards.
* It belongs to the save it was made in. One save's inventions never appear in
  another's collection.

A created card carries the design it was made from, so it can be reopened and
changed rather than made once and frozen. Deleting one takes its copies with
it, and a deck it leaves illegal is reported rather than quietly edited.

A **Hero** is deliberately not creatable: a Hero has no play cost, so there is
nothing for the prices to land on, and it would also have to be a unique named
character with a place in the deck rules.

## Adjusting the layout

Positions, sizes and stacking order the interface reads — where each piece sits
on a card, the type sizes on a card face, the heights of the board's zones —
are not constants in the screens. They live in `src/ui/layout.gd` as named
values, and the **Layout** screen edits them against the real thing.

It lays out two things, and which one is showing is a tab:

**A card.** The preview is a real `CardView` on its painted frame, so what is
dragged is exactly what a player sees. Drag a box to move it, drag its corner
to resize, nudge with the arrow keys, or type exact fractions. Stepping through
the preview moves the editing to that card's frame, so a Skill's slots are
reached by previewing a Skill.

A card is drawn back to front in the order the layout gives, and the painted
frame is one of the pieces rather than a backdrop. The stacking list moves any
piece forward or back, so artwork can be sent behind the frame, a number
brought in front of a banner, and so on.

**The board.** The preview is the board a match is played on, built from the
same numbers the battle screen reads and standing real cards in its zones. A
gold bar sits on every edge a number controls: the bars across the board set
the heights of its rows, and the upright ones set the width of the Location
plate and of the cards. The preview is drawn at the size a match draws it, so a
bar follows the pointer one pixel to one pixel — no scale to reason about. Each
number is typed beside it as well, and is held inside its stated range however
far it is dragged.

### Where a layout change goes

Saving writes `data/layout.json`, which the game loads at launch. That file is
part of the project, so:

* run from source, saving changes the project on that machine straight away;
* **committing that file is what carries the change to anyone else.** A layout
  saved and not committed stays local;
* an exported build cannot write to itself, so it saves beside the save files
  instead and applies only on that machine. The screen says which happened.

"Copy as code" puts the values on the clipboard as GDScript, for folding back
into the defaults in `src/ui/layout.gd` once a layout has settled. No
`data/layout.json` is committed at the moment, so the values the game ships
with are the defaults in that file.

## Running the tests

```sh
# Everything (about 90 seconds; the AI suites play real matches):
godot --headless --path . --script tools/run_tests.gd

# One suite at a time:
godot --headless --path . --script tools/run_tests.gd -- rules
godot --headless --path . --script tools/run_tests.gd -- catalog
godot --headless --path . --script tools/run_tests.gd -- progression
godot --headless --path . --script tools/run_tests.gd -- ai
godot --headless --path . --script tools/run_tests.gd -- forge
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

There are six save slots, each its own game with its own collection, decks and
gold. Starting one never writes over another, and the game opens on the save
list unless exactly one save exists, in which case it goes straight into it.

**A new save chooses the Affinity it begins in.** It starts with that
Affinity's starter deck and exactly the cards that deck needs — 46 copies
across 16 definitions — and nothing else in the catalog is unlocked. The other
284 definitions are earned with gold and opened from packs, so the shop is the
progression rather than decoration on a collection the save already has. You
can play against all seven Affinity opponents from the first match.

Settings offers Export save, Import save (which writes into the slot you are
playing), Switch save, and Start this save over, which begins the same slot
again in the same Affinity and keeps the previous game as that slot's backup.

Progress is stored in Godot's `user://` directory, one file per slot under
`saves/`:

* Linux: `~/.local/share/godot/app_userdata/Heroes of Teloria/`
* Windows: `%APPDATA%\Godot\app_userdata\Heroes of Teloria\`
* macOS: `~/Library/Application Support/Godot/app_userdata/Heroes of Teloria/`

A save is written as a temporary file and then renamed over the live save, so
an interrupted write leaves either the old save or the new one, never half of
each. The previous version is kept as `slot_N.backup.json`. Deleting a save
moves it to that backup rather than erasing it. A save that cannot be read is
copied aside rather than deleted, and a save written by a newer build is
refused with an explanation rather than overwritten. A single save file from an
earlier build is adopted into slot 1 on first run instead of being stranded.

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
* **A web export has not been built or tested.** The desktop exports are real
  and are what the Releases page carries, but nothing has been built for a
  browser. Godot can export this project to HTML5 and the save layer is written
  with that target in mind; a 4.4 web build also needs its threading and
  cross-origin headers settled before it will load from static hosting. Treat
  the browser build as work not started, not a finished deliverable.
* **The downloads are unsigned.** Windows SmartScreen warns once, and macOS
  refuses a double-click until the app is opened from its context menu. Signing
  needs paid developer certificates, which this prototype has not got.
* **AI thinking is fast enough but not instant.** A decision takes roughly 10 to
  60 milliseconds depending on how crowded the board is. The battle screen
  spreads that work across frames so the interface stays responsive.
* **The card editor edits data, not mechanics.** Any effect outside the
  vocabulary in `docs/EFFECT_SCHEMA.md` needs the engine extended first, and the
  editor will refuse to save a definition the interpreter cannot run.
* **A match is played by dragging, and only by dragging.** The Commit and
  Attack buttons are gone: a card is played by dropping it where it should go
  and a character attacks by being dropped on what it attacks. Buttons are left
  only for answering a question the game asked — passing, choosing cards for an
  effect, or setting an X cost. That is what was asked for, and it reads far
  better, but it does mean a player who cannot drag cannot play. The drag
  system is tested through the same entry points Godot's own input calls, and
  with a simulated mouse drag, but it has not been tried on a touchscreen.
* **No multiplayer.** The blueprint's first release is single-player against AI,
  and that is what this is.
