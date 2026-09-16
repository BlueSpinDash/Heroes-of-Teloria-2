# Interface screenshots

Captured from a real run of the application by `tools/ui_drive.gd`, which walks
every screen, plays part of a match, buys a booster and opens the card editor.

Regenerate them with:

```sh
xvfb-run -a godot --path . --resolution 1440x900 --script tools/ui_drive.gd
```

| File | Screen |
| --- | --- |
| `01_home.png` | Home, with the progression summary |
| `02_collection.png` | Collection, with search, filters and owned counts |
| `04_deck_builder.png` | Deck builder, with the Energy curve and live legality |
| `05_opponents.png` | Opponent selection, all seven Affinities |
| `07_battle_sequence.png` | Battle, mid-round, with the Action Sequence and chain |
| `08_battle_effects.png` | Battle, with damage floats and cards in flight to the Wound Deck |
| `09_shop_reveal.png` | Shop, a booster revealed with slots and conversions |
| `10_card_editor.png` | Card editor, with the regenerated rules text and validation |

The battle screen's own artwork lives in `assets/board/`. `board_full.png` is
the painted board; `tools/slice_board.gd` cuts the plates the screen uses out
of it. Re-run it after replacing the painting:

```sh
godot --headless --path . --script tools/slice_board.gd
```
