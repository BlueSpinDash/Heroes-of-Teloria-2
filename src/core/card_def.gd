class_name CardDef
extends RefCounted

## An editable card definition.
##
## The definition id is immutable and separate from the per-match instance id:
## three copies of a Skill share one definition id and get three instance ids.
## `revision` increments whenever the definition is edited, so a saved match
## can pin the exact revision it started with.

var data: Dictionary = {}
## Cached once per definition: aura lookups happen on every stat query.
var _has_aura: int = -1


func _init(d: Dictionary = {}) -> void:
    data = d.duplicate(true)


## Imported card data is not trusted to hold the right types, so a flag is
## read leniently here. Validation is what rejects the wrong type, and it must
## be able to run without a getter throwing first.
static func _truthy(value) -> bool:
    if value is bool:
        return value
    if value is int or value is float:
        return float(value) != 0.0
    if value is String:
        return ["true", "1", "yes"].has(String(value).strip_edges().to_lower())
    return false


static func from_dict(d: Dictionary) -> CardDef:
    return CardDef.new(d)


func to_dict() -> Dictionary:
    return data.duplicate(true)


func duplicate_def() -> CardDef:
    return CardDef.new(data.duplicate(true))


# ---------------------------------------------------------------- identity ---

var id: String:
    get: return String(data.get("id", ""))

var revision: int:
    get: return int(data.get("revision", 1))

var name: String:
    get: return String(data.get("name", ""))

## How the card refers to itself in its own rules text, such as "Parfait" for
## "Parfait, the Unyielding Flame". Falls back to "this card" when unset.
var short_name: String:
    get: return String(data.get("short_name", ""))

var placeholder: bool:
    get: return _truthy(data.get("placeholder", true))

## True once a real card has replaced the proxy. The catalog generator carries
## an authored definition across untouched instead of regenerating it.
var authored: bool:
    get: return _truthy(data.get("authored", false))

## Which face this card is drawn on. Empty means the painted frame for its
## type, if there is one; "plain" means the laid-out face, which is how a card
## finished before its type had a frame keeps the look it shipped with.
var frame: String:
    get: return String(data.get("frame", ""))

var rarity: String:
    get: return String(data.get("rarity", "common"))

var unique: bool:
    get: return _truthy(data.get("unique", false))

## Non-empty when this card is a specific named character. Two definitions
## sharing a character_id can never both appear in one deck, which is what
## stops a future alternate-art or alternate-stat version from evading the
## named-character restriction.
var character_id: String:
    get: return String(data.get("character_id", ""))

var types: Array:
    get: return data.get("types", [])

var tags: Array:
    get: return data.get("tags", [])

var affinities: Array:
    get: return data.get("affinities", [])

var patterns: Array:
    get: return data.get("patterns", [])

## Tags describing this character's attack, such as Martial and Melee. Printed
## on the attack line. Display only for now: no card in the catalog reads them.
var attack_tags: Array:
    get: return data.get("attack_tags", [])


func has_type(t: String) -> bool:
    return types.has(t)


func has_tag(t: String) -> bool:
    return tags.has(t)


func has_affinity(a: String) -> bool:
    return affinities.has(a)


func is_neutral() -> bool:
    return affinities.is_empty()


func is_named_character() -> bool:
    return character_id != ""


# -------------------------------------------------------------------- stats ---

var attack: int:
    get: return int(data.get("attack", 0))

var defense: int:
    get: return int(data.get("defense", 0))

var attack_cost: int:
    get: return int(data.get("attack_cost", 0))

var hero_max_energy: int:
    get: return int(data.get("hero_max_energy", 0))

## A Companion's contribution to its controller's maximum Energy while in
## play. Deliberately a separate field from its deployment cost and from its
## attack cost, even though the proxies set contribution == deployment cost.
var energy_contribution: int:
    get: return int(data.get("energy_contribution", 0))

var cost: Dictionary:
    get: return data.get("cost", {"kind": "none"})


func cost_kind() -> String:
    return String(cost.get("kind", "none"))


func fixed_cost() -> int:
    return int(cost.get("amount", 0))


func x_min() -> int:
    return int(cost.get("min", 1))


## True when this definition prints a continuous aura effect.
func has_aura() -> bool:
    if _has_aura < 0:
        _has_aura = 0
        for e in effects:
            if e is Dictionary and EffectSchema.op_is_persistent_only(String((e as Dictionary).get("op", ""))):
                _has_aura = 1
                break
    return _has_aura == 1


func is_character() -> bool:
    return has_type("hero") or has_type("companion")


func is_persistent() -> bool:
    return has_type("companion") or has_type("equipment") or has_type("location") \
        or has_type("taahma") or has_type("hero")


func is_attachment() -> bool:
    return has_type("equipment") or has_type("taahma")


func attachment_slot() -> String:
    if has_type("equipment"):
        return "equipment"
    if has_type("taahma"):
        return "taahma"
    return ""


# ------------------------------------------------------------------- timing ---

var timing: Array:
    get:
        if has_type("hero"):
            return []
        return data.get("timing", ["action"])


func allows_action_timing() -> bool:
    return timing.has("action")


func allows_reaction_timing() -> bool:
    return timing.has("reaction")


## "before" or "after" the Action it responds to. Reaction cards declare this
## so the Reaction window can order them per the provisional profile.
func reaction_window() -> String:
    return String(data.get("reaction_window", "before"))


var target_spec:
    get: return data.get("target", null)

var effects: Array:
    get: return data.get("effects", [])

var triggers: Array:
    get: return data.get("triggers", [])

var text: String:
    get: return String(data.get("text", ""))

var flavor: String:
    get: return String(data.get("flavor", ""))

var art: Dictionary:
    get: return data.get("art", {})

var ai_hints: Dictionary:
    get: return data.get("ai_hints", {})


# --------------------------------------------------------------- validation ---

## Full structural validation. Returns a list of human-readable problems;
## an empty list means the definition is playable by the current engine.
func validate() -> Array:
    var errs: Array = []
    var p := "card[%s]" % (id if id != "" else "<missing id>")

    if id == "":
        errs.append("%s: missing id" % p)
    elif not id.is_valid_identifier() and not id.contains("_"):
        errs.append("%s: id should be a stable code such as PAS_SKILL_07" % p)
    if revision < 1:
        errs.append("%s: revision must be 1 or greater" % p)
    if name.strip_edges() == "":
        errs.append("%s: missing display name" % p)

    if types.is_empty():
        errs.append("%s: needs at least one card type" % p)
    for t in types:
        if not EffectSchema.CARD_TYPES.has(String(t)):
            errs.append("%s: unknown card type '%s'" % [p, str(t)])
    var seen_types: Dictionary = {}
    for t in types:
        if seen_types.has(t):
            errs.append("%s: duplicate card type '%s'" % [p, str(t)])
        seen_types[t] = true

    for t in tags:
        if not EffectSchema.TAGS.has(String(t)):
            errs.append("%s: unknown tag '%s'" % [p, str(t)])
    var seen_aff: Dictionary = {}
    for a in affinities:
        if not EffectSchema.AFFINITIES.has(String(a)):
            errs.append("%s: unknown Affinity '%s'" % [p, str(a)])
        if seen_aff.has(a):
            errs.append("%s: duplicate Affinity '%s'" % [p, str(a)])
        seen_aff[a] = true

    if not EffectSchema.RARITIES.has(rarity):
        errs.append("%s: unknown rarity '%s'" % [p, rarity])

    # Martial / Magic / Melee / Ranged are Skill tags.
    if (has_tag("martial") or has_tag("magic")) and not has_type("skill"):
        errs.append("%s: Martial and Magic are Skill tags" % p)

    # Cost and timing per type.
    if has_type("hero"):
        if cost_kind() != "none":
            errs.append("%s: a Hero has no play cost (it starts outside the deck)" % p)
        if hero_max_energy < 1:
            errs.append("%s: a Hero needs a printed maximum Energy of 1 or more" % p)
        if not is_named_character():
            errs.append("%s: a Hero must have a named-character identity" % p)
        if not unique:
            errs.append("%s: a Hero must be Unique" % p)
        if attack_cost < 0:
            errs.append("%s: attack cost must not be negative" % p)
    else:
        if not ["fixed", "x", "none"].has(cost_kind()):
            errs.append("%s: unknown cost kind '%s'" % [p, cost_kind()])
        if cost_kind() == "fixed" and fixed_cost() < 0:
            errs.append("%s: fixed cost must not be negative" % p)
        if cost_kind() == "x" and x_min() < 0:
            errs.append("%s: X cost minimum must not be negative" % p)
        if timing.is_empty():
            errs.append("%s: needs at least one timing permission" % p)
        for t in timing:
            if not ["action", "reaction"].has(String(t)):
                errs.append("%s: unknown timing '%s'" % [p, str(t)])
        # Reaction is a tag; it must agree with the timing permission.
        if has_tag("reaction") and not allows_reaction_timing():
            errs.append("%s: tagged Reaction but does not permit Reaction timing" % p)
        if allows_reaction_timing() and not has_tag("reaction"):
            errs.append("%s: permits Reaction timing but is not tagged Reaction" % p)
        if allows_reaction_timing() and not ["before", "after"].has(reaction_window()):
            errs.append("%s: reaction_window must be 'before' or 'after'" % p)

    if has_type("companion"):
        if energy_contribution < 0:
            errs.append("%s: Companion Energy contribution must not be negative" % p)
        if attack_cost < 0:
            errs.append("%s: attack cost must not be negative" % p)
        if attack < 0 or defense < 0:
            errs.append("%s: Companion Attack/Defense must not be negative" % p)

    # Skills never display Attack/Defense bubbles, so they must not carry them.
    if has_type("skill") and not is_character():
        if int(data.get("attack", 0)) != 0 or int(data.get("defense", 0)) != 0:
            errs.append("%s: a Skill must not carry Attack/Defense (they would not be displayed)" % p)
        if int(data.get("attack_cost", 0)) != 0:
            errs.append("%s: a Skill must not carry an attack cost" % p)
        if int(data.get("energy_contribution", 0)) != 0:
            errs.append("%s: only a Companion contributes maximum Energy" % p)

    if not is_character() and int(data.get("hero_max_energy", 0)) != 0:
        errs.append("%s: only a Hero has a printed maximum Energy" % p)

    # Persistent block must agree with the declared types.
    var persist: Variant = data.get("persistent", null)
    var expect_persist := is_persistent() and not has_type("hero")
    if expect_persist:
        if not (persist is Dictionary):
            errs.append("%s: a persistent card needs a 'persistent' block" % p)
        else:
            var pk := String(persist.get("kind", ""))
            if has_type("companion") and pk != "companion":
                errs.append("%s: Companion needs persistent.kind 'companion'" % p)
            elif has_type("location") and pk != "location":
                errs.append("%s: Location needs persistent.kind 'location'" % p)
            elif is_attachment() and pk != "attachment":
                errs.append("%s: %s needs persistent.kind 'attachment'" % [p, attachment_slot()])
            if pk == "attachment" and String(persist.get("slot", "")) != attachment_slot():
                errs.append("%s: attachment slot must be '%s'" % [p, attachment_slot()])
    elif persist != null and not has_type("hero"):
        errs.append("%s: only a persistent card may declare a 'persistent' block" % p)

    # An attachment must ask for a host on play.
    if is_attachment() and allows_action_timing():
        if not (target_spec is Dictionary) or String(target_spec.get("kind", "")) != "own_character_host":
            errs.append("%s: an attachment played from hand must target own_character_host" % p)

    errs.append_array(EffectSchema.validate_target_spec(target_spec, p + ".target"))
    errs.append_array(EffectSchema.validate_effects(effects, p + ".effects", is_persistent()))

    var ti := 0
    for trig in triggers:
        errs.append_array(EffectSchema.validate_trigger(trig, "%s.triggers[%d]" % [p, ti]))
        ti += 1

    # An effect may only reference "chosen" if the card actually chooses a target.
    if _references_chosen() and target_spec == null:
        errs.append("%s: an effect references the chosen target but the card selects none" % p)
    # "host" only means something on an attachment.
    if _references_ref("host") and not is_attachment():
        errs.append("%s: only an attachment may reference its host" % p)
    # X amounts require an X cost.
    if _references_x() and cost_kind() != "x":
        errs.append("%s: an effect uses X but the card has no X cost" % p)
    if cost_kind() == "x" and not _references_x():
        errs.append("%s: has an X cost but no effect uses X" % p)

    var art_block: Variant = data.get("art", null)
    if art_block != null:
        if not (art_block is Dictionary):
            errs.append("%s: 'art' must be an object" % p)
        else:
            var ab: Dictionary = art_block
            if ab.has("image") and not (ab["image"] is String):
                errs.append("%s: art.image must be a file path written as text" % p)
            if ab.has("fit") and not ["cover", "contain"].has(String(ab["fit"])):
                errs.append("%s: art.fit must be 'cover' or 'contain'" % p)
    # A missing art file is deliberately not an error: the card falls back to
    # its placeholder sigil, so a catalog stays playable while art is in
    # progress. The card editor reports the missing file instead.

    if data.has("short_name") and not (data["short_name"] is String):
        errs.append("%s: 'short_name' must be text" % p)

    if not attack_tags.is_empty():
        if not is_character():
            errs.append("%s: only a Hero or Companion has attack tags" % p)
        var seen_attack_tags: Dictionary = {}
        for at in attack_tags:
            if not EffectSchema.ATTACK_TAGS.has(String(at)):
                errs.append("%s: '%s' is not an attack tag" % [p, str(at)])
            if seen_attack_tags.has(at):
                errs.append("%s: duplicate attack tag '%s'" % [p, str(at)])
            seen_attack_tags[at] = true

    if data.has("authored") and not (data["authored"] is bool):
        errs.append("%s: 'authored' must be true or false" % p)
    if data.has("frame") and not (data["frame"] is String and frame in ["", "plain", "printed"]):
        errs.append("%s: 'frame' must be \"\", \"plain\" or \"printed\"" % p)
    # A printed face is the supplied picture and nothing else, so there has to
    # be one; without it the card would come out blank.
    var face_image: Variant = art.get("image", "")
    if frame == "printed" and not (face_image is String \
            and (face_image as String).strip_edges() != ""):
        errs.append("%s: a printed face needs an 'image' in its art block" % p)
    if authored and placeholder:
        errs.append("%s: a finished card should not also be marked placeholder" % p)

    if patterns.is_empty():
        errs.append("%s: needs at least one behaviour pattern tag for catalog coverage" % p)

    # A card that does nothing is a content bug, not a playable proxy.
    if not is_persistent() and effects.is_empty() and triggers.is_empty():
        errs.append("%s: has no effects and no triggers" % p)
    if has_type("location") and effects.is_empty() and triggers.is_empty():
        errs.append("%s: a Location needs an ongoing effect or a trigger" % p)

    # Displayed text must match generated text so the editor cannot claim an
    # effect the engine does not perform.
    var generated := TextGen.render(self)
    if text.strip_edges() != generated.strip_edges():
        errs.append("%s: rules text does not match its effects.\n  stored:    %s\n  generated: %s" % [p, text, generated])

    return errs


func _walk_effects(list: Array, out: Array) -> void:
    for e in list:
        if not (e is Dictionary):
            continue
        out.append(e)
        for key in ["then", "otherwise", "effects"]:
            if e.has(key) and e[key] is Array:
                _walk_effects(e[key], out)


func all_effect_ops() -> Array:
    var flat: Array = []
    _walk_effects(effects, flat)
    for trig in triggers:
        if trig is Dictionary and trig.get("effects", null) is Array:
            _walk_effects(trig["effects"], flat)
    return flat


func _references_chosen() -> bool:
    return _references_ref("chosen")


func _references_ref(ref: String) -> bool:
    for e in all_effect_ops():
        if e.has("target") and _ref_name(e["target"]) == ref:
            return true
        if e.has("scope") and String(e["scope"]) == ref:
            return true
        if e.has("cond") and e["cond"] is Dictionary \
                and _ref_name((e["cond"] as Dictionary).get("target", "")) == ref:
            return true
    return false


## A target is either a reference name or an object that narrows one. Either
## way, this is the name it narrows.
static func _ref_name(target) -> String:
    if target is Dictionary:
        return String((target as Dictionary).get("ref", ""))
    return String(target) if target != null else ""


func _references_x() -> bool:
    for e in all_effect_ops():
        if e.has("amount") and e["amount"] is Dictionary and String((e["amount"] as Dictionary).get("from", "")) == "x":
            return true
    return false
