class_name BoardArt
extends RefCounted

## The battle screen is built out of one painted board, sliced into plates by
## `tools/slice_board.gd`.
##
## Every plate is scaled to cover its zone and clipped, never squashed, so the
## artwork and the caption painted onto it stay true whatever size the zone
## ends up. A plate is decoration: every number and name it sits behind is a
## real control drawn on top of it.

const DIR := "res://assets/board/"

## The mat a deck stands on: its plate with the painted name and icon across
## the middle drawn out, cut by `tools/prepare_deck_mats.gd`.
##
## A deck standing in the centre of its zone covers that middle, so paint there
## could only ever be read through the cards. The gold frame stays, and the
## screen writes the name above the cards where nothing covers it.
const DECK_MAT := {"hit": "deck_mat_hit", "exhaust": "deck_mat_exhaust",
	"wound": "deck_mat_wound"}
## How wide a mat is against its height. The mats are cut to this shape; this
## number and `MAT_ASPECT` in the tool are two halves of one decision, and the
## artwork is stretched if they disagree.
const DECK_MAT_ASPECT := 1.15
## The mats say nothing of their own any more, so they are dimmed less than the
## plates behind the zones: it is the deck standing on one that is read, and a
## mat too dark to see is a deck floating in the middle of the row.
const DECK_MAT_TINT := 0.92

## How far each plate is dimmed so text drawn over it stays readable.
const PLATE_TINT := 0.72
## The painted board sits behind everything as texture, not as a second
## board, so it is dimmed far enough that its own captions read as shadow.
const FIELD_TINT := 0.08


static func texture(plate: String) -> Texture2D:
	return load("%s%s.png" % [DIR, plate]) as Texture2D


## A TextureRect that covers whatever rect it is given, cropping rather than
## distorting, and never takes input.
static func plate(name: String, tint: float = PLATE_TINT) -> TextureRect:
	var art := TextureRect.new()
	art.texture = texture(name)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.modulate = Color(tint, tint, tint, 1.0)
	return art


## Lay a plate behind a panel's contents and return the box those contents go
## in.
##
## A PanelContainer fits every child to its content rect, so the art and the
## live controls stack without either one driving the other's size. The panel
## itself carries no padding, so the plate reaches its gold border; the inset
## belongs to the contents instead.
static func back(panel: PanelContainer, name: String, border: Color = UiTheme.GOLD,
		width: int = 2, tint: float = PLATE_TINT) -> VBoxContainer:
	var sb := UiTheme.panel_style(Color(0, 0, 0, 0), border, width, 6)
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	panel.add_theme_stylebox_override("panel", sb)
	panel.clip_contents = true
	panel.add_child(plate(name, tint))

	var inset := MarginContainer.new()
	for side in ["left", "right"]:
		inset.add_theme_constant_override("margin_" + side, 6)
	for side in ["top", "bottom"]:
		inset.add_theme_constant_override("margin_" + side, 4)
	panel.add_child(inset)
	var content := UiTheme.vbox(2)
	inset.add_child(content)
	return content


## A plated zone: the panel, and the box its live contents go in.
static func zone(name: String, border: Color = UiTheme.GOLD, width: int = 2,
		tint: float = PLATE_TINT) -> Array:
	var panel := PanelContainer.new()
	return [panel, back(panel, name, border, width, tint)]


## A caption in the style of the ones painted onto the board.
static func caption(text: String, size: int = 11) -> Label:
	var l := UiTheme.label(text.to_upper(), size, UiTheme.PARCHMENT,
		HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
