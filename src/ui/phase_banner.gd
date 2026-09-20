class_name PhaseBanner
extends Control

## The banner that announces each phase of the round, and each step as the
## Action Sequence resolves.
##
## A card game changes state in bursts, and without something saying so out
## loud a player only finds out what phase it is by noticing that their cards
## stopped being playable. So every phase says its own name across the middle
## of the board, and every step of the Resolve Phase names the card that is
## about to happen before it happens.
##
## It is an announcement, never a control: it takes no input, and the match
## does not wait on it. The pacing that makes it readable lives in the battle
## screen, which holds the opponent for as long as the banner is up.

## How long one announcement is on screen, from fade in to gone.
const FADE_IN := 0.18
const HOLD := 0.85
const FADE_OUT := 0.35

## The colour each phase is announced in.
const PHASE_INK := {
    "draw": Color("#6fa8ff"),
    "action": Color("#c9a94e"),
    "resolve": Color("#e08a3c"),
    "round_end": Color("#9aa0ac"),
}

var _current: Control = null


func _init() -> void:
    name = "PhaseBanner"
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_anchors_preset(Control.PRESET_FULL_RECT)


## How long an announcement takes, so the caller can pace the match around it.
static func length() -> float:
    return FADE_IN + HOLD + FADE_OUT


## Announce a phase: the big line, with the round under it.
func phase(phase_name: String, round_number: int, delay: float = 0.0) -> void:
    var ink: Color = PHASE_INK.get(phase_name, UiTheme.GOLD)
    show_banner(_phase_title(phase_name), "Round %d" % round_number, ink, delay)


## Announce one step of the Resolve Phase: which step, and what is resolving.
func step(index: int, total: int, what: String, delay: float = 0.0) -> void:
    show_banner(what, "Resolving %d of %d" % [index, total], PHASE_INK["resolve"], delay)


## The banner itself. A second announcement replaces the first rather than
## queueing behind it, so a fast sequence of phases never falls behind the
## board it is describing.
func show_banner(title: String, subtitle: String, ink: Color, delay: float = 0.0) -> void:
    if _current != null and is_instance_valid(_current):
        _current.queue_free()

    var holder := Control.new()
    holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
    holder.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(holder)
    _current = holder

    var panel := UiTheme.panel(Color(0, 0, 0, 0.72), ink, 2, 8)
    panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var box := UiTheme.vbox(2)
    box.mouse_filter = Control.MOUSE_FILTER_IGNORE

    var head := UiTheme.label(title, 34, ink, HORIZONTAL_ALIGNMENT_CENTER)
    head.mouse_filter = Control.MOUSE_FILTER_IGNORE
    head.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
    head.add_theme_constant_override("shadow_offset_x", 2)
    head.add_theme_constant_override("shadow_offset_y", 2)
    box.add_child(head)

    if subtitle != "":
        var sub := UiTheme.label(subtitle.to_upper(), 13, UiTheme.PARCHMENT_DARK,
            HORIZONTAL_ALIGNMENT_CENTER)
        sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
        box.add_child(sub)
    panel.add_child(box)

    # Centred across the board, a third of the way down: over the Action
    # Sequence rather than over the hand, which is where the player is looking
    # when a phase changes.
    panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
    panel.anchor_left = 0.5
    panel.anchor_right = 0.5
    panel.position = Vector2(0, size.y * 0.24)
    panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
    holder.add_child(panel)

    holder.modulate.a = 0.0
    holder.scale = Vector2(0.94, 0.94)
    holder.pivot_offset = size * 0.5

    var tw := create_tween()
    if delay > 0.0:
        tw.tween_interval(delay)
    tw.tween_property(holder, "modulate:a", 1.0, FADE_IN)
    tw.parallel().tween_property(holder, "scale", Vector2.ONE, FADE_IN) \
        .set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
    tw.tween_interval(HOLD)
    tw.tween_property(holder, "modulate:a", 0.0, FADE_OUT)
    tw.tween_callback(holder.queue_free)


## Whether an announcement is on screen, for the tests and for anything that
## wants to wait for one.
func showing() -> bool:
    return _current != null and is_instance_valid(_current)


static func _phase_title(phase_name: String) -> String:
    match phase_name:
        "draw":
            return "Draw Phase"
        "action":
            return "Action Phase"
        "resolve":
            return "Resolve Phase"
        "round_end":
            return "Round End"
    return phase_name.capitalize()
