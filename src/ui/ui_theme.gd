class_name UiTheme
extends RefCounted

## Shared palette and widget helpers.
##
## Frame colours follow the established card template direction: Skills blue,
## Companions teal, Equipment steel grey, Ta'ahma white. Hero and Location
## colours are provisional. Colour is never the only signal — every Affinity,
## rarity and legality state is also spelled out in text.

const GOLD := Color("#c9a94e")
const GOLD_DIM := Color("#8a7434")
const PARCHMENT := Color("#e7e1d0")
const PARCHMENT_DARK := Color("#cdc5ae")
const INK := Color("#1b1a17")
const BG := Color("#14161b")
const BG_PANEL := Color("#1d212a")
const BG_RAISED := Color("#262b36")
const TEXT := Color("#e6e6e6")
const TEXT_DIM := Color("#9aa0ac")
const DANGER := Color("#c0392b")
const GOOD := Color("#3f8f5a")
const ENERGY := Color("#2a5aa8")
const ATTACK := Color("#8e2b28")
const DEFENSE := Color("#25508c")

const FRAME := {
    "skill": Color("#1b3a63"),
    "companion": Color("#14494b"),
    "equipment": Color("#3a3f45"),
    "taahma": Color("#ded9c9"),
    "hero": Color("#1a1a1e"),
    "location": Color("#1f3a2a"),
}

const AFFINITY_COLOR := {
    "devotion": Color("#d3b04c"),
    "passion": Color("#c0453e"),
    "will": Color("#d07b33"),
    "vigilance": Color("#4b7fc4"),
    "purpose": Color("#7e8a99"),
    "harmony": Color("#3f9e86"),
    "silence": Color("#8b6bb1"),
    "neutral": Color("#9aa0ac"),
}

## A distinct glyph per Affinity so the seven are told apart without colour.
const AFFINITY_GLYPH := {
    "devotion": "✦", "passion": "✹", "will": "▲", "vigilance": "◆",
    "purpose": "⬢", "harmony": "❋", "silence": "◐", "neutral": "◇",
}

const RARITY_COLOR := {
    "common": Color("#9aa0ac"),
    "uncommon": Color("#5f9e6a"),
    "rare": Color("#4b7fc4"),
    "legendary": Color("#c9a94e"),
}

const RARITY_MARK := {
    "common": "●", "uncommon": "◆", "rare": "★", "legendary": "✶",
}

const TYPE_LABEL := {
    "hero": "HERO", "companion": "COMPANION", "skill": "SKILL",
    "equipment": "EQUIPMENT", "location": "LOCATION", "taahma": "TA'AHMA",
}


static func frame_color(def: CardDef) -> Color:
    for t in ["hero", "companion", "equipment", "taahma", "location", "skill"]:
        if def.has_type(t):
            return FRAME[t]
    return FRAME["skill"]


static func primary_type(def: CardDef) -> String:
    for t in ["hero", "companion", "equipment", "taahma", "location", "skill"]:
        if def.has_type(t):
            return t
    return "skill"


static func type_banner(def: CardDef) -> String:
    var parts: Array = []
    for t in def.types:
        parts.append(String(TYPE_LABEL.get(String(t), String(t).to_upper())))
    return " • ".join(parts)


static func affinity_color(affinity: String) -> Color:
    return AFFINITY_COLOR.get(affinity, AFFINITY_COLOR["neutral"])


## "✦ Devotion" or "◇ Neutral", never colour alone.
static func affinity_line(def: CardDef) -> String:
    if def.affinities.is_empty():
        return "%s Neutral" % AFFINITY_GLYPH["neutral"]
    var bits: Array = []
    for a in def.affinities:
        bits.append("%s %s" % [String(AFFINITY_GLYPH.get(String(a), "◇")), String(a).capitalize()])
    return "  ".join(bits)


static func rarity_line(def: CardDef) -> String:
    return "%s %s" % [String(RARITY_MARK.get(def.rarity, "●")), def.rarity.capitalize()]


static func tag_line(def: CardDef) -> String:
    var bits: Array = []
    for t in def.tags:
        bits.append(String(t).capitalize())
    return " • ".join(bits)


static func cost_text(def: CardDef) -> String:
    match def.cost_kind():
        "x": return "X"
        "fixed": return str(def.fixed_cost())
    return "—"


# ------------------------------------------------------------------- widgets ---

## Global text scale, driven by the accessibility setting. Applied wherever a
## font size is chosen so the whole interface grows together.
static var text_scale: float = 1.0


static func fs(size: int) -> int:
    return int(round(float(size) * text_scale))


static func panel_style(bg: Color, border: Color = Color(0, 0, 0, 0),
        border_width: int = 0, radius: int = 6) -> StyleBoxFlat:
    var sb := StyleBoxFlat.new()
    sb.bg_color = bg
    sb.corner_radius_top_left = radius
    sb.corner_radius_top_right = radius
    sb.corner_radius_bottom_left = radius
    sb.corner_radius_bottom_right = radius
    if border_width > 0:
        sb.border_color = border
        sb.set_border_width_all(border_width)
    sb.content_margin_left = 8
    sb.content_margin_right = 8
    sb.content_margin_top = 5
    sb.content_margin_bottom = 5
    return sb


static func panel(bg: Color, border: Color = Color(0, 0, 0, 0), border_width: int = 0,
        radius: int = 6) -> PanelContainer:
    var p := PanelContainer.new()
    p.add_theme_stylebox_override("panel", panel_style(bg, border, border_width, radius))
    return p


static func label(text: String, size: int = 14, color: Color = TEXT,
        align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
    var l := Label.new()
    l.text = text
    l.add_theme_font_size_override("font_size", fs(size))
    l.add_theme_color_override("font_color", color)
    l.horizontal_alignment = align
    return l


static func wrapped(text: String, size: int = 13, color: Color = TEXT) -> Label:
    var l := label(text, size, color)
    l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    return l


static func heading(text: String, size: int = 22) -> Label:
    return label(text, size, GOLD)


static func button(text: String, tooltip: String = "") -> Button:
    var b := Button.new()
    b.text = text
    if tooltip != "":
        b.tooltip_text = tooltip
    b.add_theme_font_size_override("font_size", fs(14))
    b.add_theme_color_override("font_color", TEXT)
    b.add_theme_color_override("font_hover_color", GOLD)
    b.add_theme_color_override("font_disabled_color", TEXT_DIM)
    b.add_theme_stylebox_override("normal", panel_style(BG_RAISED, GOLD_DIM, 1, 4))
    b.add_theme_stylebox_override("hover", panel_style(BG_RAISED.lightened(0.12), GOLD, 1, 4))
    b.add_theme_stylebox_override("pressed", panel_style(BG_PANEL, GOLD, 1, 4))
    b.add_theme_stylebox_override("disabled", panel_style(BG_PANEL.darkened(0.2), Color("#3a3f45"), 1, 4))
    b.add_theme_stylebox_override("focus", panel_style(Color(0, 0, 0, 0), GOLD, 2, 4))
    b.custom_minimum_size = Vector2(0, 34)
    return b


static func primary_button(text: String, tooltip: String = "") -> Button:
    var b := button(text, tooltip)
    b.add_theme_stylebox_override("normal", panel_style(Color("#3a3520"), GOLD, 2, 4))
    b.add_theme_stylebox_override("hover", panel_style(Color("#4a4328"), GOLD, 2, 4))
    b.add_theme_color_override("font_color", GOLD)
    b.custom_minimum_size = Vector2(0, 40)
    return b


static func separator(height: int = 1) -> Control:
    var c := ColorRect.new()
    c.color = GOLD_DIM
    c.custom_minimum_size = Vector2(0, height)
    c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    return c


static func spacer(height: int) -> Control:
    var c := Control.new()
    c.custom_minimum_size = Vector2(0, height)
    return c


static func hbox(sep: int = 8) -> HBoxContainer:
    var h := HBoxContainer.new()
    h.add_theme_constant_override("separation", sep)
    return h


static func vbox(sep: int = 8) -> VBoxContainer:
    var v := VBoxContainer.new()
    v.add_theme_constant_override("separation", sep)
    return v


static func scroll(child: Control, horizontal: bool = false) -> ScrollContainer:
    var s := ScrollContainer.new()
    s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    s.size_flags_vertical = Control.SIZE_EXPAND_FILL
    s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO if horizontal \
        else ScrollContainer.SCROLL_MODE_DISABLED
    child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    s.add_child(child)
    return s


## A small labelled statistic, used across the battle and shop screens.
static func stat_chip(caption: String, value: String, color: Color = TEXT) -> PanelContainer:
    var p := panel(BG_RAISED, GOLD_DIM, 1, 4)
    var v := vbox(0)
    v.add_child(label(caption.to_upper(), 9, TEXT_DIM, HORIZONTAL_ALIGNMENT_CENTER))
    v.add_child(label(value, 16, color, HORIZONTAL_ALIGNMENT_CENTER))
    p.add_child(v)
    p.custom_minimum_size = Vector2(70, 0)
    return p
