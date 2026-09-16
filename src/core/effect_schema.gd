class_name EffectSchema
extends RefCounted

## The complete vocabulary of executable card instructions.
##
## This file is the single source of truth shared by three consumers:
##   * catalog validation (no card may claim an op that is not listed here),
##   * the effect interpreter (src/core/effects.gd),
##   * the rules-text generator (src/core/text_gen.gd).
##
## Adding a genuinely new mechanic means adding an entry here AND implementing
## it in the interpreter AND giving it a text template. Changing a card's
## numbers, targets, costs, tags or Affinity needs none of that — see
## docs/EFFECT_SCHEMA.md.

const AFFINITIES := ["devotion", "passion", "will", "vigilance", "purpose", "harmony", "silence"]
const CARD_TYPES := ["hero", "companion", "skill", "equipment", "location", "taahma"]
const TAGS := ["reaction", "martial", "magic", "melee", "ranged"]
## Tags that describe a character's attack, printed on its attack line.
## Separate from card TAGS because Martial and Magic are Skill tags: a Hero is
## not a Martial card, but its attack can be a Martial Melee attack.
const ATTACK_TAGS := ["martial", "magic", "melee", "ranged"]
const RARITIES := ["common", "uncommon", "rare", "legendary"]
const DURATIONS := ["step", "round", "permanent"]
const WHO := ["self", "opponent"]
const SCOPES := ["controller", "opponent", "either"]
const CHOOSERS := ["controller", "opponent"]

## Target kinds a card may ask the player to choose on commitment.
const TARGET_KINDS := [
    "opponent_companion", "own_companion", "any_companion",
    "opponent_character", "own_character", "any_character",
    "own_equipment", "opponent_equipment", "any_equipment",
    "own_taahma", "opponent_taahma", "any_taahma",
    "location",
    "own_character_host",
]

## Symbolic target references usable inside effects.
##
## A target is either one of these names, or an object {"ref": name, ...} that
## narrows it — currently only by Affinity, as in every Vigilance Companion you
## control. Narrowing an already-single reference is allowed and simply makes
## the effect do nothing when that card does not carry the Affinity.
const TARGET_REFS := [
    "chosen", "self", "host",
    "self_hero", "opponent_hero",
    "all_own_companions", "all_opponent_companions", "all_companions",
    "current_attacker", "current_target",
]

## Where a dynamic amount can be read from.
const AMOUNT_SOURCES := ["x", "chain_count", "count"]
const COUNT_OF := [
    "own_companions", "opponent_companions",
    "own_hand", "opponent_hand",
    "own_exhaust", "opponent_exhaust",
    # Slots of the Action Sequence that resolved before the one being read.
    # The Sequence resolves in order, so everything earlier has resolved and
    # nothing later has: it is the round's own record of what has happened.
    # Narrowed by "types" (card types) and "scope" (whose slots).
    "resolved_before",
]

const AURA_SCOPES := [
    "own_companions", "opponent_companions", "all_companions",
    "own_hero", "opponent_hero", "own_characters", "opponent_characters",
    "host",
]

## op -> {required: [...], optional: [...], persistent_only: bool}
const OPS := {
    "damage_hero": {"required": ["who", "amount"], "optional": []},
    "direct_damage": {"required": ["target", "amount", "ignores_defense"], "optional": []},
    "destroy": {"required": ["target"], "optional": []},
    "bounce": {"required": ["target"], "optional": []},
    "draw": {"required": ["who", "amount"], "optional": []},
    "energy_gain": {"required": ["who", "amount"], "optional": []},
    "energy_drain": {"required": ["who", "amount"], "optional": []},
    "energy_max_mod": {"required": ["who", "amount", "duration"], "optional": []},
    "stat_mod": {"required": ["target", "duration"], "optional": ["attack", "defense"]},
    "prevent_damage": {"required": ["target", "amount", "duration"], "optional": []},
    "mill": {"required": ["who", "amount"], "optional": []},
    "recover_from_exhaust": {"required": ["who", "amount"], "optional": []},
    "exhaust_from_hand": {"required": ["who", "amount", "chooser"], "optional": []},
    "random_exhaust_from_hand": {"required": ["who", "amount"], "optional": []},
    "deploy_from_hand": {"required": ["who"], "optional": []},
    "choose_card_type": {"required": ["chooser"], "optional": []},
    "next_attack_bonus": {"required": ["amount", "scope"], "optional": ["affinity"]},
    "conditional": {"required": ["cond", "then"], "optional": ["otherwise"]},
    "chain_reward": {"required": ["require", "then"], "optional": []},
    "repeat": {"required": ["amount", "effects"], "optional": []},
    "aura_stat_mod": {"required": ["scope"], "optional": ["attack", "defense"], "persistent_only": true},
    "aura_energy_max": {"required": ["who", "amount"], "optional": [], "persistent_only": true},
}

## condition kind -> required params
const CONDITIONS := {
    "chain_at_least": ["min", "affinity", "scope"],
    "controls_companions": ["who", "min"],
    "energy_at_least": ["who", "min"],
    "hand_size_at_least": ["who", "min"],
    "exhaust_at_least": ["who", "min"],
    "hit_at_most": ["who", "max"],
    "location_active": [],
    "has_attachment": ["target", "of"],
    "target_defense_at_most": ["max"],
    "target_attack_at_least": ["min"],
}

## trigger kind -> required params
const TRIGGERS := {
    "affinity_card_resolved": ["affinity", "scope"],
    "self_deployed": [],
    "self_attack_resolved": [],
    "own_companion_deployed": [],
    "round_end": [],
    "own_hero_damaged": [],
    "opponent_hero_damaged": [],
    "self_leaves_play": [],
    "self_wounded": [],
    "attack_resolved": ["scope"],
    "chosen_type_card_resolved": ["scope"],
}

const ATTACHMENT_OF := ["equipment", "taahma"]


static func is_authorable_op(op: String) -> bool:
    return OPS.has(op)


static func op_is_persistent_only(op: String) -> bool:
    return OPS.has(op) and bool(OPS[op].get("persistent_only", false))


## Ops whose amount may legitimately be negative (a reduction).
const SIGNED_AMOUNT_OPS := ["energy_max_mod", "aura_energy_max"]


## Validate one amount value (plain int or dynamic spec). Returns error list.
static func validate_amount(value, path: String, allow_negative: bool = false) -> Array:
    var errs: Array = []
    if value is int or value is float:
        if int(value) < 0 and not allow_negative:
            errs.append("%s: amount must not be negative" % path)
        return errs
    if not (value is Dictionary):
        errs.append("%s: amount must be an integer or a dynamic amount object" % path)
        return errs
    var src := String(value.get("from", ""))
    if not AMOUNT_SOURCES.has(src):
        errs.append("%s: unknown amount source '%s'" % [path, src])
        return errs
    match src:
        "chain_count":
            var aff := String(value.get("affinity", ""))
            if aff != "any" and not AFFINITIES.has(aff):
                errs.append("%s: chain_count affinity '%s' is not an Affinity" % [path, aff])
            if not SCOPES.has(String(value.get("scope", ""))):
                errs.append("%s: chain_count needs a valid scope" % path)
        "count":
            var of := String(value.get("of", ""))
            if not COUNT_OF.has(of):
                errs.append("%s: count 'of' must be one of %s" % [path, str(COUNT_OF)])
            elif of == "resolved_before":
                if value.has("scope") and not SCOPES.has(String(value["scope"])):
                    errs.append("%s: count scope must be one of %s" % [path, str(SCOPES)])
                for t in value.get("types", []):
                    if not CARD_TYPES.has(String(t)):
                        errs.append("%s: '%s' is not a card type" % [path, str(t)])
    if value.has("multiplier") and not (value["multiplier"] is int or value["multiplier"] is float):
        errs.append("%s: multiplier must be numeric" % path)
    return errs


static func validate_condition(cond, path: String) -> Array:
    var errs: Array = []
    if not (cond is Dictionary):
        errs.append("%s: condition must be an object" % path)
        return errs
    var kind := String(cond.get("kind", ""))
    if not CONDITIONS.has(kind):
        errs.append("%s: unknown condition kind '%s'" % [path, kind])
        return errs
    for req in CONDITIONS[kind]:
        if not cond.has(req):
            errs.append("%s: condition '%s' is missing '%s'" % [path, kind, req])
    if cond.has("who") and not WHO.has(String(cond["who"])):
        errs.append("%s: condition 'who' must be self or opponent" % path)
    if cond.has("affinity"):
        var aff := String(cond["affinity"])
        if aff != "any" and not AFFINITIES.has(aff):
            errs.append("%s: condition affinity '%s' is not an Affinity" % [path, aff])
    if cond.has("scope") and not SCOPES.has(String(cond["scope"])):
        errs.append("%s: condition scope must be one of %s" % [path, str(SCOPES)])
    if cond.has("target"):
        errs.append_array(validate_target_ref(cond["target"], path + ".target"))
    if cond.has("of") and kind == "has_attachment" and not ATTACHMENT_OF.has(String(cond["of"])):
        errs.append("%s: has_attachment 'of' must be equipment or taahma" % path)
    return errs


static func validate_trigger(trig, path: String) -> Array:
    var errs: Array = []
    if not (trig is Dictionary):
        errs.append("%s: trigger must be an object" % path)
        return errs
    var on: Variant = trig.get("on", null)
    if not (on is Dictionary):
        errs.append("%s: trigger needs an 'on' object" % path)
        return errs
    var kind := String(on.get("kind", ""))
    if not TRIGGERS.has(kind):
        errs.append("%s: unknown trigger kind '%s'" % [path, kind])
        return errs
    for req in TRIGGERS[kind]:
        if not on.has(req):
            errs.append("%s: trigger '%s' is missing '%s'" % [path, kind, req])
    if on.has("affinity"):
        var aff := String(on["affinity"])
        if aff != "any" and not AFFINITIES.has(aff):
            errs.append("%s: trigger affinity '%s' is not an Affinity" % [path, aff])
    if on.has("scope") and not SCOPES.has(String(on["scope"])):
        errs.append("%s: trigger scope must be one of %s" % [path, str(SCOPES)])
    var fx: Variant = trig.get("effects", null)
    if not (fx is Array) or (fx as Array).is_empty():
        errs.append("%s: trigger needs a non-empty 'effects' array" % path)
    else:
        errs.append_array(validate_effects(fx, path + ".effects", false))
    return errs


## Validate a list of effects. `allow_persistent_only` permits aura ops,
## which only make sense on a card that stays in play.
static func validate_effects(effects, path: String, allow_persistent_only: bool) -> Array:
    var errs: Array = []
    if not (effects is Array):
        errs.append("%s: effects must be an array" % path)
        return errs
    var idx := 0
    for e in effects:
        var p := "%s[%d]" % [path, idx]
        idx += 1
        if not (e is Dictionary):
            errs.append("%s: effect must be an object" % p)
            continue
        var op := String(e.get("op", ""))
        if not OPS.has(op):
            errs.append("%s: unknown op '%s' (the engine cannot execute it)" % [p, op])
            continue
        if op_is_persistent_only(op) and not allow_persistent_only:
            errs.append("%s: op '%s' is only valid on a card that stays in play" % [p, op])
        var spec: Dictionary = OPS[op]
        for req in spec["required"]:
            if not e.has(req):
                errs.append("%s: op '%s' is missing required '%s'" % [p, op, req])
        var known: Array = ["op"] + spec["required"] + spec["optional"]
        for k in e.keys():
            if not known.has(String(k)):
                errs.append("%s: op '%s' has unexpected field '%s'" % [p, op, str(k)])
        if e.has("who") and not WHO.has(String(e["who"])):
            errs.append("%s: 'who' must be self or opponent" % p)
        if e.has("affinity") and not AFFINITIES.has(String(e["affinity"])):
            errs.append("%s: '%s' is not an Affinity" % [p, str(e["affinity"])])
        if e.has("chooser") and not CHOOSERS.has(String(e["chooser"])):
            errs.append("%s: 'chooser' must be controller or opponent" % p)
        if e.has("duration") and not DURATIONS.has(String(e["duration"])):
            errs.append("%s: 'duration' must be one of %s" % [p, str(DURATIONS)])
        if e.has("target"):
            errs.append_array(validate_target_ref(e["target"], p + ".target"))
        if e.has("scope") and op == "aura_stat_mod" and not AURA_SCOPES.has(String(e["scope"])):
            errs.append("%s: aura scope must be one of %s" % [p, str(AURA_SCOPES)])
        if e.has("scope") and op == "next_attack_bonus" and not SCOPES.has(String(e["scope"])):
            errs.append("%s: scope must be one of %s" % [p, str(SCOPES)])
        if e.has("amount"):
            errs.append_array(validate_amount(e["amount"], p + ".amount", SIGNED_AMOUNT_OPS.has(op)))
        if e.has("ignores_defense") and not (e["ignores_defense"] is bool):
            errs.append("%s: 'ignores_defense' must be stated explicitly as true or false" % p)
        if op == "stat_mod":
            if not e.has("attack") and not e.has("defense"):
                errs.append("%s: stat_mod needs attack and/or defense" % p)
            for f in ["attack", "defense"]:
                if e.has(f) and not (e[f] is int or e[f] is float):
                    errs.append("%s: stat_mod '%s' must be an integer" % [p, f])
        if op == "aura_stat_mod":
            if not e.has("attack") and not e.has("defense"):
                errs.append("%s: aura_stat_mod needs attack and/or defense" % p)
        if op == "conditional":
            errs.append_array(validate_condition(e.get("cond"), p + ".cond"))
            errs.append_array(validate_effects(e.get("then", []), p + ".then", allow_persistent_only))
            if e.has("otherwise"):
                errs.append_array(validate_effects(e["otherwise"], p + ".otherwise", allow_persistent_only))
        if op == "chain_reward":
            var req_obj: Variant = e.get("require", null)
            if not (req_obj is Dictionary):
                errs.append("%s: chain_reward needs a 'require' object" % p)
            else:
                var c := {"kind": "chain_at_least"}
                c.merge(req_obj)
                errs.append_array(validate_condition(c, p + ".require"))
            errs.append_array(validate_effects(e.get("then", []), p + ".then", allow_persistent_only))
        if op == "repeat":
            errs.append_array(validate_effects(e.get("effects", []), p + ".effects", allow_persistent_only))
    return errs


## A target reference: a plain name, or {"ref": name, "affinity": ...}.
static func validate_target_ref(ref, path: String) -> Array:
    var errs: Array = []
    if ref is Dictionary:
        var d: Dictionary = ref
        if not TARGET_REFS.has(String(d.get("ref", ""))):
            errs.append("%s: target ref '%s' is not a target reference" % [path, str(d.get("ref", ""))])
        for k in d.keys():
            if not ["ref", "affinity"].has(String(k)):
                errs.append("%s: target has unexpected field '%s'" % [path, str(k)])
        if d.has("affinity") and not AFFINITIES.has(String(d["affinity"])):
            errs.append("%s: target affinity '%s' is not an Affinity" % [path, str(d["affinity"])])
        return errs
    if not TARGET_REFS.has(String(ref)):
        errs.append("%s: target '%s' is not a target reference" % [path, str(ref)])
    return errs


static func validate_target_spec(spec, path: String) -> Array:
    var errs: Array = []
    if spec == null:
        return errs
    if not (spec is Dictionary):
        errs.append("%s: target specification must be an object or null" % path)
        return errs
    var kind := String(spec.get("kind", ""))
    if not TARGET_KINDS.has(kind):
        errs.append("%s: unknown target kind '%s'" % [path, kind])
    if spec.has("count") and int(spec["count"]) < 1:
        errs.append("%s: target count must be at least 1" % path)
    if spec.has("optional") and not (spec["optional"] is bool):
        errs.append("%s: target 'optional' must be true or false" % path)
    return errs
