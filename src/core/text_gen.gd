class_name TextGen
extends RefCounted

## Generates a card's rules text from its structured effects.
##
## Nothing else writes card text. The catalog stores the generated string and
## validation rejects any definition whose stored text differs, so the card
## editor physically cannot advertise an effect the interpreter will not run.

const AFFINITY_LABEL := {
    "devotion": "Devotion", "passion": "Passion", "will": "Will",
    "vigilance": "Vigilance", "purpose": "Purpose", "harmony": "Harmony",
    "silence": "Silence",
}

const TARGET_KIND_PHRASE := {
    "opponent_companion": "target Companion your opponent controls",
    "own_companion": "target Companion you control",
    "any_companion": "target Companion",
    "opponent_character": "target character your opponent controls",
    "own_character": "target character you control",
    "any_character": "target character",
    "own_equipment": "target Equipment you control",
    "opponent_equipment": "target Equipment your opponent controls",
    "any_equipment": "target Equipment",
    "own_taahma": "target Ta'ahma you control",
    "opponent_taahma": "target Ta'ahma your opponent controls",
    "any_taahma": "target Ta'ahma",
    "location": "the active Location",
    "own_character_host": "a character you control",
}

const REF_PHRASE := {
    "self": "this card",
    "host": "its host",
    "self_hero": "your Hero",
    "opponent_hero": "the opposing Hero",
    "all_own_companions": "each Companion you control",
    "all_opponent_companions": "each Companion your opponent controls",
    "all_companions": "each Companion",
    "current_attacker": "the attacking character",
    "current_target": "the attack's target",
}

const AURA_SCOPE_PHRASE := {
    "own_companions": "each Companion you control",
    "opponent_companions": "each Companion your opponent controls",
    "all_companions": "each Companion",
    "own_hero": "your Hero",
    "opponent_hero": "the opposing Hero",
    "own_characters": "each character you control",
    "opponent_characters": "each character your opponent controls",
    "host": "its host",
}


static func render(def: CardDef) -> String:
    var parts: Array = []

    var prefix := _timing_prefix(def)
    var body := render_effects(def.effects, def)
    if prefix != "":
        if body == "":
            parts.append(prefix.trim_suffix(":"))
        else:
            parts.append("%s %s" % [prefix, body])
    elif body != "":
        parts.append(body)

    for trig in def.triggers:
        parts.append(render_trigger(trig, def))

    if def.cost_kind() == "x":
        parts.append("X is equal to the amount of Energy spent to play this card.")

    return " ".join(parts).strip_edges()


static func _timing_prefix(def: CardDef) -> String:
    if not def.allows_reaction_timing():
        return ""
    var window := "before the Action" if def.reaction_window() == "before" else "after the Action"
    if def.allows_action_timing():
        return "Reaction (%s) or Action:" % window
    return "Reaction (%s):" % window


static func render_effects(list: Array, def: CardDef) -> String:
    var out: Array = []
    for e in list:
        var s := render_effect(e, def)
        if s != "":
            out.append(s)
    return " ".join(out)


static func render_effect(e: Dictionary, def: CardDef) -> String:
    var op := String(e.get("op", ""))
    match op:
        "damage_hero":
            var who := String(e.get("who", "opponent"))
            var tgt := "the opposing Hero" if who == "opponent" else "your own Hero"
            return "Deal %s to %s." % [_damage_amount(e.get("amount"), def), tgt]
        "direct_damage":
            var suffix := ", ignoring its Defense" if bool(e.get("ignores_defense", false)) \
                else ", reduced by its Defense"
            return "Deal %s to %s%s." % [
                _damage_amount(e.get("amount"), def), _target(e.get("target"), def), suffix]
        "destroy":
            return "Destroy %s." % _target(e.get("target"), def)
        "bounce":
            return "If %s is a Companion, return it to its owner's hand." % _target(e.get("target"), def)
        "draw":
            var who2 := String(e.get("who", "self"))
            var subj := "You draw" if who2 == "self" else "Your opponent draws"
            return "%s %s." % [subj, _cards(e.get("amount"), def)]
        "energy_gain":
            var who3 := String(e.get("who", "self"))
            var subj3 := "You gain" if who3 == "self" else "Your opponent gains"
            return "%s %s." % [subj3, _energy(e.get("amount"), def)]
        "energy_drain":
            var who4 := String(e.get("who", "opponent"))
            var subj4 := "You lose" if who4 == "self" else "Your opponent loses"
            return "%s %s." % [subj4, _energy(e.get("amount"), def)]
        "energy_max_mod":
            var who5 := String(e.get("who", "self"))
            var owner := "Your" if who5 == "self" else "Your opponent's"
            var amt: Variant = e.get("amount", 0)
            var dirn := "increases"
            if _is_negative(amt):
                dirn = "decreases"
            return "%s maximum Energy %s by %s%s." % [
                owner, dirn, _abs_amount(amt, def), _duration_suffix(String(e.get("duration", "round")))]
        "stat_mod":
            return "%s %s%s." % [
                _capitalise(_target(e.get("target"), def)),
                _stat_change(e),
                _duration_suffix(String(e.get("duration", "round")))]
        "prevent_damage":
            return "Prevent the next %s that would be dealt to %s%s." % [
                _damage_amount(e.get("amount"), def),
                _target(e.get("target"), def),
                _duration_suffix(String(e.get("duration", "round")))]
        "mill":
            var who6 := String(e.get("who", "opponent"))
            var owner6 := "your" if who6 == "self" else "your opponent's"
            return "Move up to %s from the top of %s Hit Deck to %s Exhaust Deck." % [
                _cards(e.get("amount"), def), owner6, owner6]
        "recover_from_exhaust":
            var who7 := String(e.get("who", "self"))
            var owner7 := "your" if who7 == "self" else "your opponent's"
            var hand7 := "your hand" if who7 == "self" else "their hand"
            return "Return up to %s from %s Exhaust Deck to %s." % [
                _cards(e.get("amount"), def), owner7, hand7]
        "exhaust_from_hand":
            var who8 := String(e.get("who", "self"))
            var chooser := String(e.get("chooser", "controller"))
            var subj8 := "You" if who8 == "self" else "Your opponent"
            var whose := "your hand" if who8 == "self" else "their hand"
            var picker := ""
            if (who8 == "self" and chooser == "controller") or (who8 == "opponent" and chooser == "opponent"):
                picker = " of their choice" if who8 == "opponent" else " of your choice"
            else:
                picker = " chosen by your opponent" if who8 == "self" else " chosen by you"
            return "%s Exhausts %s%s from %s." % [subj8, _cards(e.get("amount"), def), picker, whose]
        "random_exhaust_from_hand":
            var who9 := String(e.get("who", "opponent"))
            var subj9 := "You Exhaust" if who9 == "self" else "Your opponent Exhausts"
            var whose9 := "your hand" if who9 == "self" else "their hand"
            return "%s %s at random from %s." % [subj9, _cards(e.get("amount"), def), whose9]
        "deploy_from_hand":
            var who10 := String(e.get("who", "self"))
            var subj10 := "You may put a Companion from your hand into play" if who10 == "self" \
                else "Your opponent puts a Companion from their hand into play"
            return "%s." % subj10
        "conditional":
            var cnd := render_condition(e.get("cond", {}), def)
            var then_txt := _lower_first(render_effects(e.get("then", []), def))
            var s := "If %s, %s" % [cnd, then_txt]
            if e.has("otherwise"):
                s += " Otherwise, %s" % _lower_first(render_effects(e["otherwise"], def))
            return s
        "chain_reward":
            var req: Dictionary = {"kind": "chain_at_least"}
            req.merge(e.get("require", {}))
            return "If %s, %s" % [render_condition(req, def), _lower_first(render_effects(e.get("then", []), def))]
        "repeat":
            return "Repeat %s times: %s" % [
                _plain_amount(e.get("amount"), def), _lower_first(render_effects(e.get("effects", []), def))]
        "aura_stat_mod":
            return "While this card is in play, %s %s." % [
                AURA_SCOPE_PHRASE.get(String(e.get("scope", "")), "each character"), _stat_change(e)]
        "aura_energy_max":
            var who11 := String(e.get("who", "self"))
            var owner11 := "your" if who11 == "self" else "your opponent's"
            var amt11: Variant = e.get("amount", 0)
            var dirn11 := "increased"
            if _is_negative(amt11):
                dirn11 = "reduced"
            return "While this card is in play, %s maximum Energy is %s by %s." % [
                owner11, dirn11, _abs_amount(amt11, def)]
    return ""


static func render_condition(cond: Dictionary, def: CardDef) -> String:
    var kind := String(cond.get("kind", ""))
    match kind:
        "chain_at_least":
            var aff := String(cond.get("affinity", "any"))
            var scope := String(cond.get("scope", "either"))
            var what := "Actions" if aff == "any" else "%s Actions" % AFFINITY_LABEL.get(aff, aff)
            var whose := ""
            if scope == "controller":
                whose = " you committed"
            elif scope == "opponent":
                whose = " your opponent committed"
            return "the current chain contains at least %d %s%s" % [int(cond.get("min", 1)), what, whose]
        "controls_companions":
            var who := String(cond.get("who", "self"))
            var subj := "you control" if who == "self" else "your opponent controls"
            return "%s at least %d %s" % [subj, int(cond.get("min", 1)),
                "Companion" if int(cond.get("min", 1)) == 1 else "Companions"]
        "energy_at_least":
            var who2 := String(cond.get("who", "self"))
            var subj2 := "you have" if who2 == "self" else "your opponent has"
            return "%s at least %d Energy" % [subj2, int(cond.get("min", 1))]
        "hand_size_at_least":
            var who3 := String(cond.get("who", "self"))
            var subj3 := "you hold" if who3 == "self" else "your opponent holds"
            return "%s at least %d cards" % [subj3, int(cond.get("min", 1))]
        "exhaust_at_least":
            var who4 := String(cond.get("who", "self"))
            var owner4 := "your" if who4 == "self" else "your opponent's"
            return "%s Exhaust Deck holds at least %d cards" % [owner4, int(cond.get("min", 1))]
        "hit_at_most":
            var who5 := String(cond.get("who", "opponent"))
            var owner5 := "your" if who5 == "self" else "your opponent's"
            return "%s Hit Deck holds %d or fewer cards" % [owner5, int(cond.get("max", 0))]
        "location_active":
            return "a Location is active"
        "has_attachment":
            var of := String(cond.get("of", "equipment"))
            var label := "an Equipment" if of == "equipment" else "a Ta'ahma"
            return "%s has %s" % [_target(cond.get("target"), def), label]
        "target_defense_at_most":
            return "its Defense is %d or less" % int(cond.get("max", 0))
        "target_attack_at_least":
            return "its Attack is %d or more" % int(cond.get("min", 0))
    return kind


static func render_trigger(trig: Dictionary, def: CardDef) -> String:
    var on: Dictionary = trig.get("on", {})
    var kind := String(on.get("kind", ""))
    var body := _lower_first(render_effects(trig.get("effects", []), def))
    var lead := ""
    match kind:
        "affinity_card_resolved":
            var aff := String(on.get("affinity", "any"))
            var scope := String(on.get("scope", "either"))
            var what := "a card" if aff == "any" else "a %s card" % AFFINITY_LABEL.get(aff, aff)
            var whose := ""
            if scope == "controller":
                whose = " you control"
            elif scope == "opponent":
                whose = " your opponent controls"
            if def.is_character():
                lead = "Whenever %s%s resolves while %s is in the Action Sequence," % [
                    what, whose, _self_name(def, "this character")]
            else:
                lead = "Whenever %s%s resolves while %s is in play," % [
                    what, whose, _self_name(def, "this card")]
        "self_deployed":
            lead = "When %s enters play," % _self_name(def, "this Companion")
        "self_attack_resolved":
            lead = "When %s's attack resolves," % _self_name(def, "this character")
        "own_companion_deployed":
            lead = "Whenever a Companion you control enters play,"
        "round_end":
            lead = "At Round End,"
        "own_hero_damaged":
            lead = "Whenever your Hero is damaged,"
        "opponent_hero_damaged":
            lead = "Whenever the opposing Hero is damaged,"
        "self_leaves_play":
            lead = "When %s leaves play," % _self_name(def, "this card")
        "attack_resolved":
            var scope2 := String(on.get("scope", "either"))
            if scope2 == "controller":
                lead = "Whenever an attack you committed resolves,"
            elif scope2 == "opponent":
                lead = "Whenever an attack your opponent committed resolves,"
            else:
                lead = "Whenever any attack resolves,"
    return "%s %s" % [lead, body]


# ------------------------------------------------------------------ helpers ---

static func _target(ref, def: CardDef) -> String:
    var r := String(ref) if ref != null else "chosen"
    if r == "chosen":
        var spec = def.target_spec
        if spec is Dictionary:
            return TARGET_KIND_PHRASE.get(String(spec.get("kind", "")), "the target")
        return "the target"
    return REF_PHRASE.get(r, r)


static func _plain_amount(amount, def: CardDef) -> String:
    if amount is int or amount is float:
        return str(int(amount))
    if not (amount is Dictionary):
        return str(amount)
    var src := String(amount.get("from", ""))
    match src:
        "x":
            return "X"
        "chain_count":
            var aff := String(amount.get("affinity", "any"))
            var scope := String(amount.get("scope", "either"))
            var what := "Actions" if aff == "any" else "%s Actions" % AFFINITY_LABEL.get(aff, aff)
            var whose := ""
            if scope == "controller":
                whose = " you committed"
            elif scope == "opponent":
                whose = " your opponent committed"
            return "the number of %s%s in the current chain" % [what, whose]
        "count":
            var of := String(amount.get("of", ""))
            match of:
                "own_companions": return "the number of Companions you control"
                "opponent_companions": return "the number of Companions your opponent controls"
                "own_hand": return "the number of cards in your hand"
                "opponent_hand": return "the number of cards in your opponent's hand"
                "own_exhaust": return "the number of cards in your Exhaust Deck"
                "opponent_exhaust": return "the number of cards in your opponent's Exhaust Deck"
    return "an amount"


static func _abs_amount(amount, def: CardDef) -> String:
    if amount is int or amount is float:
        return str(abs(int(amount)))
    return _plain_amount(amount, def)


static func _damage_amount(amount, def: CardDef) -> String:
    if amount is int or amount is float:
        var n := int(amount)
        return "%d damage" % n
    return "damage equal to %s" % _plain_amount(amount, def)


static func _cards(amount, def: CardDef) -> String:
    if amount is int or amount is float:
        var n := int(amount)
        return "1 card" if n == 1 else "%d cards" % n
    return "a number of cards equal to %s" % _plain_amount(amount, def)


static func _energy(amount, def: CardDef) -> String:
    if amount is int or amount is float:
        return "%d Energy" % int(amount)
    return "Energy equal to %s" % _plain_amount(amount, def)


static func _stat_change(e: Dictionary) -> String:
    var bits: Array = []
    if e.has("attack"):
        bits.append("%+d Attack" % int(e["attack"]))
    if e.has("defense"):
        bits.append("%+d Defense" % int(e["defense"]))
    if bits.is_empty():
        return "is unchanged"
    return "gets " + " and ".join(bits)


static func _duration_suffix(duration: String) -> String:
    match duration:
        "step": return " until the end of this step"
        "round": return " for the round"
        "permanent": return " permanently"
    return ""


## What a card calls itself in its own text.
static func _self_name(def: CardDef, fallback: String) -> String:
    return def.short_name if def.short_name.strip_edges() != "" else fallback


static func _is_negative(amount) -> bool:
    return (amount is int or amount is float) and float(amount) < 0.0


static func _capitalise(s: String) -> String:
    if s.is_empty():
        return s
    return s.substr(0, 1).to_upper() + s.substr(1)


static func _lower_first(s: String) -> String:
    if s.is_empty():
        return s
    # Keep proper nouns and X intact.
    var first := s.substr(0, 1)
    var rest := s.substr(1)
    var word := s.split(" ")[0]
    if word in ["You", "Your", "Move", "Deal", "Destroy", "Return", "Prevent", "Repeat", "While", "If", "Each"]:
        return first.to_lower() + rest
    return s
