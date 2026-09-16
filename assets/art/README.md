# Card art

Drop image files here and point a card at one.

## How a card finds its art

A definition's `art` block may name an image:

```json
"art": {
  "image": "passion_hero_01.png",
  "fit": "cover",
  "hue": 350,
  "seed": 285
}
```

* A bare filename is looked for in this folder.
* A full `res://`, `user://` or absolute path is used exactly as written.
* Leave `image` out entirely and the card uses its generated placeholder sigil.
* `hue` and `seed` only drive that placeholder, so they can stay as they are.

`fit` controls how the image sits in the portrait window:

| `fit` | Behaviour |
| --- | --- |
| `cover` (default) | Fills the window and crops the overflow. Best for a painted portrait. |
| `contain` | Shows the whole image on a dark ground. Best when nothing may be cropped. |

## Supplying a full card face

If you have a finished card face rather than a bare portrait, send it as it is.
`tools/crop_art.gd` lifts the portrait out of it:

```sh
godot --headless --path . --script tools/crop_art.gd -- \
    /path/to/card_face.png res://assets/art/name.png X Y WIDTH HEIGHT
```

The portrait window on a rendered card is roughly 1.17 times wider than it is
tall, so a crop at about that ratio fills it without anything being cut off.

## Practical notes

* **A missing file is not an error.** The card falls back to its placeholder
  sigil and still plays. The card editor tells you the exact path it looked in.
* **Any format Godot reads works**: PNG, JPG, WebP, SVG. PNG is the safe choice.
* **The portrait window is landscape**, roughly 300 by 168 as drawn, so around
  900 by 500 pixels is plenty. Larger is fine and scales down cleanly.
* **New files need importing before an export.** Running the game once, or
  `godot --headless --path . --import`, is enough. In the editor it happens
  automatically. Until then the game reads the file straight off disk, so it
  works immediately while you iterate.
* **Art never affects rules.** Cost, stats and rules text are drawn as real
  controls outside the art, so swapping an image cannot change what a card does
  or how it is identified.

## About the card frames

The frame, banners, Energy and stat bubbles, Affinity strip and footer are drawn
by the game from `src/ui/card_view.gd` and `src/ui/ui_theme.gd`, following the
established template direction.

The template images supplied during design are full card faces with sample text
and sample numbers baked in. They are useful as a reference, but they cannot be
used directly as frames: the baked "Equipment Name", "Card Name", placeholder
rules text and the sample 2 and 3 statistics would sit underneath the real live
values. To use them as artwork, export frame-only versions with all text and all
numbers removed, and they can be adopted as card backgrounds.
