class_name EnergyGauge
extends PanelContainer

## How much Energy a player has, on their own side of the field.
##
## Energy is spent on nearly every decision in a round, and until now the only
## place it was written was a line of small text in the bar at the top of the
## screen. So each player gets one of these on their half of the board: the
## same Energy gem the cards carry, with that player's current Energy in it,
## and their maximum beside it.
##
## The gem is the one lifted off the card templates by
## `tools/prepare_card_frames.gd`, so a player reading "3" here and a card
## asking for 3 are looking at the same symbol.

const GEM_PATH := "res://assets/frames/skill_energy_gem.png"
## The gem's own proportions, from the cut ornament.
const GEM_RATIO := 296.0 / 212.0
## Where the number sits inside the gem: centred across and above the painted
## word "Energy", which is the space the stone leaves for it and exactly where
## a card prints its cost.
const NUMBER_CENTRE := Vector2(0.5, 0.38)

var _gem_holder: Control
var _number: Label
var _max_label: Label
var _caption: Label
var _gem_width: float = 52.0
var _last_shown: int = -1


## A gauge drawn with a gem this wide, captioned for whose Energy it is.
static func create(gem_width: float, caption: String) -> EnergyGauge:
    var g := EnergyGauge.new()
    g._gem_width = gem_width
    g._build(caption)
    return g


func _build(caption: String) -> void:
    add_theme_stylebox_override("panel",
        UiTheme.panel_style(UiTheme.BG_PANEL.darkened(0.25), UiTheme.ENERGY.lightened(0.15), 2, 6))
    mouse_filter = Control.MOUSE_FILTER_PASS

    var row := UiTheme.hbox(8)
    add_child(row)

    var gem_h := _gem_width * GEM_RATIO
    _gem_holder = Control.new()
    _gem_holder.custom_minimum_size = Vector2(_gem_width, gem_h)
    _gem_holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    _gem_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
    row.add_child(_gem_holder)

    var gem := TextureRect.new()
    gem.texture = load(GEM_PATH)
    gem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
    gem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
    gem.set_anchors_preset(Control.PRESET_FULL_RECT)
    gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _gem_holder.add_child(gem)

    # The number is laid over the gem the way a card's cost is laid over its
    # own: centred on the stone rather than written beside it.
    _number = UiTheme.label("0", int(_gem_width * 0.58), UiTheme.PARCHMENT,
        HORIZONTAL_ALIGNMENT_CENTER)
    _number.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
    _number.add_theme_constant_override("shadow_offset_x", 2)
    _number.add_theme_constant_override("shadow_offset_y", 2)
    _number.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
    _number.add_theme_constant_override("outline_size", 5)
    _number.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    # Anchored by fraction rather than placed in pixels, so the gauge can be
    # drawn at whatever size the board has room for and the number stays on
    # the same part of the stone.
    _number.anchor_left = 0.0
    _number.anchor_right = 1.0
    _number.anchor_top = NUMBER_CENTRE.y - 0.22
    _number.anchor_bottom = NUMBER_CENTRE.y + 0.22
    _number.offset_left = 0.0
    _number.offset_right = 0.0
    _number.offset_top = 0.0
    _number.offset_bottom = 0.0
    _gem_holder.add_child(_number)

    var text := UiTheme.vbox(0)
    text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    _caption = UiTheme.label(caption.to_upper(), 10, UiTheme.TEXT_DIM)
    text.add_child(_caption)
    _max_label = UiTheme.label("of 0", 15, UiTheme.ENERGY.lightened(0.5))
    text.add_child(_max_label)
    row.add_child(text)


## Draw the gauge at a different size, when the board has been fitted to a
## window that cannot hold it at full size.
func set_gem_width(gem_width: float) -> void:
    if is_equal_approx(gem_width, _gem_width):
        return
    _gem_width = gem_width
    _gem_holder.custom_minimum_size = Vector2(_gem_width, _gem_width * GEM_RATIO)
    _number.add_theme_font_size_override("font_size",
        UiTheme.fs(int(maxf(11.0, _gem_width * 0.58))))


## Show a player's Energy. Called on every refresh; the gauge only animates
## when the number it is showing actually changed, so a redraw that says the
## same thing says it quietly.
func set_energy(current: int, maximum: int) -> void:
    var changed := _last_shown >= 0 and _last_shown != current
    _last_shown = current
    _number.text = str(current)
    _max_label.text = "of %d" % maximum
    # Spent down to nothing is worth seeing at a glance: there is nothing you
    # can do until the round refreshes.
    _number.add_theme_color_override("font_color",
        UiTheme.TEXT_DIM if current <= 0 else UiTheme.PARCHMENT)
    tooltip_text = "%s: %d Energy of a maximum of %d." % [_caption.text.capitalize(),
        current, maximum]
    if changed:
        _flash()


## A brief swell when the number changes, so Energy being spent or refreshed
## is seen rather than noticed later.
func _flash() -> void:
    _gem_holder.pivot_offset = _gem_holder.custom_minimum_size * 0.5
    var tw := create_tween()
    tw.tween_property(_gem_holder, "scale", Vector2(1.18, 1.18), 0.10) \
        .set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    tw.tween_property(_gem_holder, "scale", Vector2.ONE, 0.18) \
        .set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


## What the gauge is showing, for the tests.
func shown_value() -> int:
    return _last_shown
