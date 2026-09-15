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
| Art file | `emberfall_strike.png` | Drop the file in `assets/art/`. |
| Flavour text | optional | |

I will turn the plain-English effect into the structured effect data, and the
card's rules text is then generated from that data. That is what guarantees the
printed text and the actual behaviour cannot drift apart.

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
