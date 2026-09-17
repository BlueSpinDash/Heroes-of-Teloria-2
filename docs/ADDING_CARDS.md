# Replacing proxy cards with real ones

All 300 cards in `data/catalog/` are proxies. They exist so the engine has
something to run, and they are meant to be replaced one at a time as real cards
are designed. Nothing has to be replaced in bulk, and the game stays playable
throughout.

## What replacing a card does and does not touch

Every card has an immutable id such as `PAS_SKILL_01`. Collections and saved
decks reference that id, never the name. So replacing the card behind an id:

* **keeps** owned copies, every saved deck that uses it, and match history;
* **keeps** any match already in progress on the old version, because a match
  snapshot pins the card revisions it started with;
* **changes** what the card is called, costs, does and looks like from then on;
* **may** make a saved deck illegal, for example if two cards end up sharing a
  name and so exceed the three-copies limit. That is reported with the exact
  reason and the deck is never deleted.

If you would rather add a card alongside the proxies instead of replacing one,
say so. It means growing the catalog past 300, which changes the totals the
tests assert, so it is a deliberate decision rather than a silent one.

## What to send me for each card

Send as much as you have. Anything you leave out, I will keep from the proxy or
ask about.

| Field | Example | Notes |
| --- | --- | --- |
| Which proxy it replaces | `PAS_SKILL_01` | Or "a Passion skill", and I will pick a slot. |
| Name | Emberfall Strike | Must be unique across the catalog. |
| Card type | Skill | Hero, Companion, Skill, Equipment, Location or Ta'ahma. |
| Tags | Martial, Melee | Reaction, Martial, Magic, Melee, Ranged. |
| Affinity | Passion | None, one, or several. |
| Rarity | Uncommon | Common, Uncommon, Rare or Legendary. |
| Energy cost | 2 | Or X, with a minimum. |
| Attack / Defense | 3 / 1 | Characters only. Equipment may print modifiers. |
| Attack cost | 1 | Characters only. |
| Max Energy | 4 | Heroes only. |
| Adds to max Energy | 2 | Companions only. |
| Unique or named character | Named: Parfait | Either restricts it to one copy per deck. |
| What it does | "Deal 2 damage to the opposing Hero, then draw a card." | Plain English is fine. |
| Art file | `emberfall_strike.png` | Drop the file in `assets/art/`. A full card face is fine too: I crop the portrait out of it. |
| Flavour text | optional | |

I will turn the plain-English effect into the structured effect data, and the
card's rules text is then generated from that data. That is what guarantees the
printed text and the actual behaviour cannot drift apart.

## A worked example

`PAS_HERO_01` was the proxy "Passion Proxy Hero 01". It is now Parfait, the
Unyielding Flame, taken from a supplied card face:

* the portrait was cropped out of the card face into
  `assets/art/parfait_the_unyielding_flame.png`;
* her statistics, Affinity, rarity and attack tags were read off the card;
* her ability became a trigger, and the rules text was generated from it;
* `short_name` is "Parfait", so her text names her the way the printed card
  does rather than saying "this character";
* the id did not change, so the Passion starter deck and the Passion AI deck
  still reference her without any edit.

`VIG_HERO_01` became Sorbet, the Undone Architect the same way, and needed the
engine extended for it. Her ability names a Card Type and then pays off on it,
which nothing in the vocabulary could say: it took a `choose_card_type` op, a
`chosen_type_card_resolved` trigger, somewhere on the card to remember the
answer for the round, and a way to write "each Vigilance Companion you control"
as a target. Those are all in `docs/EFFECT_SCHEMA.md` now and are available to
any future card. That is the shape of a card that needs engine work: the
vocabulary grows once, deliberately, and the card is then ordinary data.

`PAS_SKILL_01` became Burning Rush, and needed the vocabulary extended once
more: `next_attack_bonus` leaves a bonus for the next attack that qualifies,
claimed once and lapsing at Round End if nothing claims it. Its art came from a
finished card face rather than a blank template, which is fine — the portrait
is cropped out of it the same way.

## What I will tell you back

For each card I will report:

* the exact rules text the engine generated, so you can check the wording;
* whether it validated, and if not, precisely why;
* anything the effect vocabulary cannot express yet, and what extending the
  engine for it would involve;
* any saved deck the change made illegal.

## Effects the engine cannot do yet

The vocabulary in `docs/EFFECT_SCHEMA.md` covers twenty operations, ten
conditions and nine triggers. Things it deliberately does not cover include
cancelling an Action outright, reordering the Action Sequence, copying another
card, searching a Hit Deck for a named card, and stealing control of a
Companion. The first three need further timing decisions before they would be
safe to add.

If a card you send needs one of those, I will say so rather than approximate it,
and we can decide whether to extend the engine or adjust the card.

## Marking a card finished

A real card should carry `"authored": true` and `"placeholder": false`. That
matters for one reason: `tools/build_catalog.sh` regenerates the proxies, and it
carries any authored definition across untouched instead of overwriting it. Real
art is preserved on proxies too, so pointing a proxy at an image is safe even
before the card itself is rewritten.

You can set the flag yourself in the card editor with the "Finished card"
checkbox, and I set it whenever I replace a card.

## Which face a card is drawn on

A card type can have a painted frame, and a card of that type is drawn on it
automatically. Every type but the Location has one: Hero, Skill, Companion,
Equipment and Ta'ahma. The frame carries everything that is the same
on every card of its type — the type banner, the stat captions, the ornament —
and the live card fills in the name, the numbers, the art, the rules text, the
Affinity and the footer, each anchored over the region the template painted for
it.

A card opts out with `"frame": "plain"`, which draws the laid-out face instead.
That is for a card finished before its type has a frame, so it can keep the look
it shipped with. No card uses it at the moment.

### Using a card face as it was drawn

`"frame": "printed"` draws a supplied card face whole, exactly as it arrived,
with nothing placed on it but the badges that describe *this copy* of the card
(Eligible, Owned). This is how every card supplied as a finished face is added.

Drop the face in `assets/cards/`, run the trimmer, and point the card at it:

```sh
godot --headless --path . --script tools/prepare_card_faces.gd
```

```json
"frame": "printed",
"art": {"style": "supplied", "image": "res://assets/cards/young_blood.png",
        "fit": "contain"}
```

A face arrives as a picture *of* a card, sitting on whatever the renderer put
behind it. `tools/prepare_card_faces.gd` takes that backdrop off: it is only
reachable from the edges, so a flood fill from the four corners finds exactly
it, and what is left is cropped to the card. That is not a choice about what to
keep — the whole card survives, with its own rounded corners as transparency.

The face is then fitted **whole** (`"fit": "contain"`), not filled to the box.
These are pictures of cards and they do not all come out at exactly 5:7;
filling the box would take a slice off a card's own banner or footer, which is
the one thing a printed face is for keeping.

The trade is worth understanding before using it:

* **The rules text becomes a picture.** Everywhere else, what a card says is
  generated from its effect data and checked against it, which is what lets a
  card be rebalanced without being repainted, and what stops a card saying one
  thing and doing another. A printed face still has to carry correct effect
  data — that is what the game plays — but the words on the picture are no
  longer kept honest by anything. Change the card and the face has to be
  redrawn to match.
* **The Layout screen cannot touch it.** There are no pieces to move, so the
  card is not listed there.
* **The footer is whatever was drawn.** The supplied faces carry placeholder
  set and rarity lines (`SET • 001/000`, `RARITY`), which ship as-is.

The card still needs real effect data underneath, because that is what the game
plays. The generated text is kept in the definition and is what the rest of the
interface quotes; the printed words are what the player reads on the face. They
should say the same thing, and the generated line is the one that is checked.

Every card supplied so far is drawn this way. They occupy proxy slots rather
than being appended, because the catalog's shape — 300 cards, 40 per Affinity,
5 Reaction Skills each, a fixed rarity spread — is a design constraint the
generator asserts. A finished Reaction takes a Reaction slot, and a finished
card keeps the rarity of the slot it replaces until a printed rarity says
otherwise; the supplied faces all carry a placeholder `RARITY` line.

### The window is not a rectangle

Each painted window has its corners cut back by a gothic arch, so artwork laid
over it as a plain rectangle squares those arches off. The card clips its art
to the window's shape instead (`art_radius` in `FRAMES`, a fraction of the
card's width), which leaves the frame's own corners showing.

The Affinity is the one thing no frame can have painted out cleanly: its
ribbon is an arc, so there is no straight clean band to stretch across the
placeholder word. Every card lays its own small parchment label over it
instead, which reads as a printed one and works the same on all five frames.

A frame can also have **ornaments**: pieces of the painted frame that belong
*over* the artwork rather than behind it. The Skill frame's Energy gem is one —
the printed card paints it across the top-left corner of the art window. It is
cut off the frame by `tools/prepare_card_frames.gd` into its own picture with
everything around it cleared, given a slot and a place in the stacking order
like any other piece, and drawn above the art. Without that, the window would
lose that corner to the gem.

### Cropping the art

A card's art is scaled to **cover** its frame's window and clipped, never
squashed, so a crop of the wrong shape silently loses whatever is nearest the
edges. A frame's window is the `"art"` slot in `src/ui/layout.gd`, which the
**Layout** screen edits. The Hero window is 0.617 of the card wide by 0.448
tall, an aspect of **0.984** on a 5:7 card — very slightly taller than it is
wide. The Skill window is 0.662 by 0.446, an aspect of **1.057**.

When a supplied card face is the source, cut the portrait from **that card's own
art window**, at that aspect:

1. Find the window's inner edges on the supplied image. Crop a narrow strip
   across each edge and read off where the ornate border stops — every card
   face is a different size, so these cannot be assumed from another card.
2. If the window is wider than 0.974, the full height fits and some width has
   to go: choose which side deliberately. Sorbet reaches to the right of her
   window, so her crop is taken flush with the window's right edge and gives up
   background on the left.
3. `tools/crop_art.gd` does the cut:
   `godot --headless --path . --script tools/crop_art.gd -- SRC DST X Y W H`.

The crops in use, for reference:

| Card | Source window | Crop taken |
| --- | --- | --- |
| Parfait | x 217–933, y 170–890 | `221 170 708 720` |
| Sorbet | x 232–975, y 150–875 | `262 150 713 725` |

No card uses a cropped portrait at the moment: every finished card is drawn
from the face it was supplied as. The measurements above are for a card that
goes on a painted frame instead.

Measure the edges at magnification. `tools/crop_art.gd` takes a `SCALE`
argument for exactly this: crop a 40-pixel strip straddling an edge at 7x and
the boundary between the painted border and the artwork is unmistakable.

**Measure at the height the crop is actually taken from.** These windows have
large arched corners, so the sides are further in near the top and bottom than
they are at mid-height. Burning Rush's window is 772 wide across the middle but
only 667 near the top, and a crop cut to the middle measurement caught the
card's own blue frame in its upper corner.
Eyeballing a full-size card face is not good enough — it put the window 26
pixels out, which showed as a pale strip of empty frame down one side of every
Hero.

Getting this wrong is not obvious from a thumbnail. Check it by rendering the
card large and comparing against the supplied face — an arm or a hand reaching
for the edge of the frame is exactly what a too-tight crop takes first.

Locations are the one type still drawn on the laid-out face: no template has
been supplied for them. A UI test pins that, so adding the template and the
frame is all it takes and nothing else has to be remembered.

To give another type a frame: add the painted template to `assets/frames/` as
`_<type>_template_src.png`, add it to the table in
`tools/prepare_card_frames.gd` with the placeholder text to paint out, and add
the type to `FRAMES` in `src/ui/card_view.gd` and its slot rectangles and
stacking order to `src/ui/layout.gd`. A frame whose stone is pale rather than
dark takes `"ink": "dark"` in `FRAMES`, which inks its numbers and footer dark.

Measuring a template goes faster read off the picture than guessed: the
placeholder text is the only dark ink on a pale panel and the only white ink on
a gem, so a scan for either finds every region that has to be painted out, and
the rendered card settles the rest. The **Layout** screen edits the slots on a
real card, so a value that is a pixel or two out is nudged there rather than in
the source.

Painting out is done two ways. A **patch** stretches a clean piece of the same
surface over the words, which works on parchment and stone. On a cut gem, where
every facet is lit differently, a patch cut from elsewhere lands as a visible
block; an **inpaint** is used there instead, refilling the region column by
column between the clean surface above it and the clean surface below.

## Doing it yourself in the app

The card editor covers everything except writing new effect operations:

1. Open Editor and pick the card.
2. Change the name, flavour, rarity, Affinity, tags, cost and statistics.
3. Point it at an art file.
4. Edit the structured effects if you want, then press Preview and validate.
5. Press Save changes.

Edits made in the app are stored in your save as overrides, so the shipped files
stay clean and "Restore bundled version" always works. Edits I make go into
`data/catalog/` and become the shipped card.
