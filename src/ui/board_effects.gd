class_name BoardEffects
extends Control

## Cosmetic feedback for things that have already happened.
##
## Nothing here touches the match. The engine resolves first and the state is
## final before any of this is drawn, so an animation can never decide an
## outcome, delay one, or be required for play to continue. Every effect frees
## itself when it finishes.

const FLOAT_TIME := 1.0
const FLY_TIME := 0.62
## How wide a card is drawn while it is in flight. Big enough to recognise,
## small enough that several crossing the board at once still read.
const FLY_CARD_W := 54.0


func _init() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_anchors_preset(Control.PRESET_FULL_RECT)


## A number that rises and fades where something happened, such as damage dealt
## or Energy returned.
func float_text(at: Vector2, text: String, colour: Color, font_size: int = 24,
        delay: float = 0.0) -> void:
    var l := UiTheme.label(text, font_size, colour, HORIZONTAL_ALIGNMENT_CENTER)
    l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
    l.add_theme_constant_override("outline_size", 6)
    l.position = at - Vector2(40, 12)
    l.custom_minimum_size = Vector2(80, 0)
    l.size = Vector2(80, 24)
    l.modulate.a = 0.0
    l.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(l)

    var tw := create_tween()
    tw.tween_interval(delay)
    tw.tween_property(l, "modulate:a", 1.0, 0.12)
    tw.parallel().tween_property(l, "position:y", l.position.y - 18.0, 0.12)
    tw.tween_property(l, "position:y", l.position.y - 56.0, FLOAT_TIME)
    tw.parallel().tween_property(l, "modulate:a", 0.0, FLOAT_TIME)
    tw.tween_callback(l.queue_free)


## A card gliding from where it was to where it is going, so a card changing
## hands, decks or zones is something you watch rather than something you
## notice afterwards.
##
## It flies as a card: face down by default, which is what a card in a Hit,
## Exhaust or Wound Deck is, or face up when `face` names the card — a
## Companion coming out of your hand is one you have already seen. The caption
## rides underneath and says what is happening to it.
func fly_card(from: Vector2, to: Vector2, label: String, colour: Color,
        delay: float = 0.0, face: CardDef = null) -> void:
    var card: Control = null
    if face != null:
        card = CardView.create(face, FLY_CARD_W)
    else:
        card = CardView.face_down(FLY_CARD_W)
    if card == null:
        # No back supplied and no card named: fall back to a plain marker
        # rather than dropping the movement altogether.
        card = UiTheme.panel(UiTheme.BG_PANEL, colour, 2, 4)
        card.custom_minimum_size = Vector2(FLY_CARD_W, FLY_CARD_W * 1.4)
    card.mouse_filter = Control.MOUSE_FILTER_IGNORE

    var ghost := Control.new()
    var card_h := FLY_CARD_W * CardView.BASE_HEIGHT / CardView.BASE_WIDTH
    ghost.size = Vector2(FLY_CARD_W, card_h + 14.0)
    ghost.pivot_offset = ghost.size * 0.5
    ghost.position = from - ghost.size * 0.5
    ghost.modulate.a = 0.0
    ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
    ghost.add_child(card)
    if label != "":
        var text := UiTheme.label(label, 9, colour, HORIZONTAL_ALIGNMENT_CENTER)
        text.clip_text = true
        text.mouse_filter = Control.MOUSE_FILTER_IGNORE
        text.position = Vector2(-10, card_h + 1.0)
        text.size = Vector2(FLY_CARD_W + 20.0, 13)
        text.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
        text.add_theme_constant_override("outline_size", 4)
        ghost.add_child(text)
    add_child(ghost)

    var tw := create_tween()
    tw.tween_interval(delay)
    tw.tween_property(ghost, "modulate:a", 1.0, 0.12)
    tw.parallel().tween_property(ghost, "scale", Vector2.ONE, 0.12) \
        .from(Vector2(0.7, 0.7))
    tw.tween_property(ghost, "position", to - ghost.size * 0.5, FLY_TIME) \
        .set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
    tw.parallel().tween_property(ghost, "scale", Vector2(0.62, 0.62), FLY_TIME)
    tw.tween_property(ghost, "modulate:a", 0.0, 0.2)
    tw.tween_callback(ghost.queue_free)


## How long one flight takes from being asked for to being gone, so a caller
## can hold the game still until the player has seen it.
static func fly_length() -> float:
    return 0.12 + FLY_TIME + 0.2


## A brief ring around something that just resolved or was targeted.
func pulse(rect: Rect2, colour: Color, delay: float = 0.0) -> void:
    var ring := Panel.new()
    var sb := StyleBoxFlat.new()
    sb.bg_color = Color(0, 0, 0, 0)
    sb.border_color = colour
    sb.set_border_width_all(3)
    sb.set_corner_radius_all(6)
    ring.add_theme_stylebox_override("panel", sb)
    ring.position = rect.position
    ring.size = rect.size
    ring.modulate.a = 0.0
    ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(ring)

    var tw := create_tween()
    tw.tween_interval(delay)
    tw.tween_property(ring, "modulate:a", 1.0, 0.1)
    tw.tween_interval(0.35)
    tw.tween_property(ring, "modulate:a", 0.0, 0.3)
    tw.tween_callback(ring.queue_free)


## Drop everything still playing, used when the screen is rebuilt or left.
func clear_all() -> void:
    for child in get_children():
        child.queue_free()
