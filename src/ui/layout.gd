class_name Layout
extends RefCounted

## Every position and size the interface reads that is worth adjusting by eye.
##
## These used to be constants scattered through the screens, which meant that
## nudging a card's name banner or the height of the hand meant editing code,
## rebuilding, and looking again. They now live here as named values the Layout
## screen edits live, and that screen writes them back to `data/layout.json`,
## which is ordinary repository content.
##
## The defaults below are the shipped values. A saved file only overrides the
## keys it names, so a value added here later still arrives with a sensible
## default for a save written before it existed.

const BUNDLED_PATH := "res://data/layout.json"
## Where the editor writes when it cannot write to the project, as in an
## exported build.
const USER_PATH := "user://layout.json"

## group -> key -> Rect2, as fractions of the thing they sit on.
const DEFAULT_RECTS := {
    # Where each live value sits on the painted Hero frame, as a fraction of
    # the card. These come from the template: the gem and the two medallions
    # down the left, the art window, the name banner, the rules panel, the
    # Affinity banner and the two footer lines.
    "hero_card": {
        "energy": Rect2(0.100, 0.104, 0.130, 0.062),
        "attack": Rect2(0.100, 0.294, 0.130, 0.050),
        "defense": Rect2(0.100, 0.448, 0.130, 0.050),
        "art": Rect2(0.223, 0.131, 0.617, 0.448),
        "name": Rect2(0.285, 0.582, 0.530, 0.054),
        "rules": Rect2(0.178, 0.662, 0.664, 0.166),
        "affinity": Rect2(0.392, 0.916, 0.208, 0.034),
        "set": Rect2(0.075, 0.933, 0.290, 0.026),
        "rarity": Rect2(0.635, 0.933, 0.290, 0.026),
    },
    # The Skill frame has no Attack or Defense medallion, so its art window is
    # wider and reaches further down the left of the card.
    "skill_card": {
        "energy": Rect2(0.118, 0.134, 0.090, 0.072),
        "energy_gem": Rect2(0.062, 0.080, 0.200, 0.199),
        "art": Rect2(0.176, 0.131, 0.662, 0.446),
        "name": Rect2(0.285, 0.582, 0.530, 0.054),
        "rules": Rect2(0.178, 0.662, 0.664, 0.166),
        "affinity": Rect2(0.392, 0.916, 0.208, 0.034),
        "set": Rect2(0.075, 0.933, 0.290, 0.026),
        "rarity": Rect2(0.635, 0.933, 0.290, 0.026),
    },
}

## group -> key -> where it sits in the stack, back to front. A piece with a
## lower number is drawn first, so everything after it lands on top. The frame
## is in here too: art given a number below the frame's is drawn behind it and
## shows only through whatever the frame leaves open.
const DEFAULT_LAYERS := {
    "hero_card": {
        "frame": 10,
        "art": 20,
        "energy": 30,
        "attack": 40,
        "defense": 50,
        "name": 60,
        "rules": 70,
        "affinity": 80,
        "set": 90,
        "rarity": 100,
        "badges": 110,
    },
    "skill_card": {
        "frame": 10,
        "art": 20,
        "energy_gem": 25,
        "energy": 30,
        "name": 60,
        "rules": 70,
        "affinity": 80,
        "set": 90,
        "rarity": 100,
        "badges": 110,
    },
}

## What each piece in the stack is, for a screen that lists them.
const LAYER_LABELS := {
    "frame": "The painted frame",
    "art": "The card's artwork",
    "energy": "The Energy number",
    "energy_gem": "The Energy gem, cut off the frame to sit over the artwork",
    "attack": "Attack number",
    "defense": "Defense number",
    "name": "Name",
    "rules": "Rules text and attack line",
    "affinity": "Affinity banner",
    "set": "Card id",
    "rarity": "Rarity",
    "badges": "Badges, such as Eligible or Owned",
}

## group -> key -> [value, minimum, maximum, description]
const DEFAULT_NUMBERS = {
    "card_text": {
        "name_size": [15.0, 6.0, 40.0, "Largest size a Hero's name is set at, before it is fitted to its banner."],
        "stat_size": [24.0, 8.0, 48.0, "The three stat numbers on the gems."],
        "rules_size": [12.0, 6.0, 30.0, "Largest size the rules text is set at, before it is fitted to its panel."],
        "meta_size": [10.0, 6.0, 24.0, "The attack line above the rules text."],
        "small_size": [9.0, 5.0, 20.0, "The Affinity banner and the two footer lines."],
    },
    "battle_board": {
        "hand_card_w": [122.0, 60.0, 260.0, "Width of a card in the hand strip."],
        "hand_strip_h": [218.0, 120.0, 420.0, "Height of the pinned hand strip."],
        "companion_strip_h": [82.0, 50.0, 200.0, "Height of the row inside a Companion Zone."],
        "deck_plate_h": [76.0, 50.0, 160.0, "Height of the deck plates and the Hero plate."],
        "middle_h": [110.0, 70.0, 240.0, "Height of the Action Sequence and Location row."],
        "location_w": [206.0, 120.0, 400.0, "Width of the Location plate."],
    },
}

## The live values, defaults overlaid with whatever was loaded.
static var _rects: Dictionary = {}
static var _numbers: Dictionary = {}
static var _layers: Dictionary = {}
static var _loaded := false
## Where the values in force came from, for the editor to report.
static var source: String = "built in"


static func _ensure() -> void:
    if not _loaded:
        load_saved()


## Start from the shipped values and lay the saved file over them.
static func load_saved() -> void:
    _loaded = true
    _rects = {}
    for group in DEFAULT_RECTS:
        _rects[group] = (DEFAULT_RECTS[group] as Dictionary).duplicate(true)
    _layers = {}
    for group in DEFAULT_LAYERS:
        _layers[group] = (DEFAULT_LAYERS[group] as Dictionary).duplicate(true)
    _numbers = {}
    for group in DEFAULT_NUMBERS:
        var out: Dictionary = {}
        for key in (DEFAULT_NUMBERS[group] as Dictionary):
            out[key] = float((DEFAULT_NUMBERS[group][key] as Array)[0])
        _numbers[group] = out
    source = "built in"
    for path in [BUNDLED_PATH, USER_PATH]:
        if _overlay(String(path)):
            source = String(path)


## Lay one file's values over what is loaded. Public so a test can write and
## read a file of its own rather than the one the game ships.
static func load_from(path: String) -> bool:
    _ensure()
    return _overlay(path)


static func _overlay(path: String) -> bool:
    if not FileAccess.file_exists(path):
        return false
    var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
    if not (parsed is Dictionary):
        push_warning("Layout file is not an object: %s" % path)
        return false
    var d: Dictionary = parsed
    for group in (d.get("rects", {}) as Dictionary):
        if not _rects.has(group):
            continue
        for key in (d["rects"][group] as Dictionary):
            if not (_rects[group] as Dictionary).has(key):
                continue
            var v: Array = d["rects"][group][key]
            if v.size() == 4:
                _rects[group][key] = Rect2(float(v[0]), float(v[1]), float(v[2]), float(v[3]))
    for group in (d.get("layers", {}) as Dictionary):
        if not _layers.has(group):
            continue
        for key in (d["layers"][group] as Dictionary):
            if (_layers[group] as Dictionary).has(key):
                _layers[group][key] = int(d["layers"][group][key])
    for group in (d.get("numbers", {}) as Dictionary):
        if not _numbers.has(group):
            continue
        for key in (d["numbers"][group] as Dictionary):
            if (_numbers[group] as Dictionary).has(key):
                _numbers[group][key] = float(d["numbers"][group][key])
    return true


static func rect(group: String, key: String) -> Rect2:
    _ensure()
    if _rects.has(group) and (_rects[group] as Dictionary).has(key):
        return _rects[group][key]
    push_warning("No layout rect for %s/%s" % [group, key])
    return Rect2(0, 0, 0.1, 0.1)


static func num(group: String, key: String) -> float:
    _ensure()
    if _numbers.has(group) and (_numbers[group] as Dictionary).has(key):
        return _numbers[group][key]
    push_warning("No layout number for %s/%s" % [group, key])
    return 0.0


## Where a piece sits in the stack. Lower is further back.
static func layer(group: String, key: String) -> int:
    _ensure()
    if _layers.has(group) and (_layers[group] as Dictionary).has(key):
        return int(_layers[group][key])
    return 0


## Every piece of `group`, ordered back to front.
static func layer_order(group: String) -> Array:
    _ensure()
    var keys: Array = (_layers.get(group, {}) as Dictionary).keys()
    keys.sort_custom(func(a, b):
        var la := int(_layers[group][a])
        var lb := int(_layers[group][b])
        if la != lb:
            return la < lb
        return String(a) < String(b))
    return keys


## Move a piece `by` places through the stack, forward or back, and renumber so
## the order stays unambiguous.
static func move_layer(group: String, key: String, by: int) -> void:
    _ensure()
    var order := layer_order(group)
    var at := order.find(key)
    if at < 0:
        return
    var to := clampi(at + by, 0, order.size() - 1)
    if to == at:
        return
    order.remove_at(at)
    order.insert(to, key)
    for i in order.size():
        _layers[group][order[i]] = (i + 1) * 10


static func set_rect(group: String, key: String, value: Rect2) -> void:
    _ensure()
    if _rects.has(group) and (_rects[group] as Dictionary).has(key):
        _rects[group][key] = value


static func set_num(group: String, key: String, value: float) -> void:
    _ensure()
    if not (_numbers.has(group) and (_numbers[group] as Dictionary).has(key)):
        return
    var spec: Array = DEFAULT_NUMBERS[group][key]
    _numbers[group][key] = clampf(value, float(spec[1]), float(spec[2]))


static func rect_groups() -> Array:
    _ensure()
    var out: Array = _rects.keys()
    out.sort()
    return out


static func number_groups() -> Array:
    _ensure()
    var out: Array = _numbers.keys()
    out.sort()
    return out


static func keys_of(group: String) -> Array:
    _ensure()
    var src: Dictionary = _rects.get(group, _numbers.get(group, {}))
    var out: Array = src.keys()
    out.sort()
    return out


static func describe(group: String, key: String) -> String:
    if DEFAULT_NUMBERS.has(group) and (DEFAULT_NUMBERS[group] as Dictionary).has(key):
        return String((DEFAULT_NUMBERS[group][key] as Array)[3])
    return ""


static func limits(group: String, key: String) -> Vector2:
    if DEFAULT_NUMBERS.has(group) and (DEFAULT_NUMBERS[group] as Dictionary).has(key):
        var spec: Array = DEFAULT_NUMBERS[group][key]
        return Vector2(float(spec[1]), float(spec[2]))
    return Vector2(0, 1)


## True when this value differs from what the game shipped with.
static func is_changed(group: String, key: String) -> bool:
    _ensure()
    if DEFAULT_RECTS.has(group) and (DEFAULT_RECTS[group] as Dictionary).has(key):
        return not _rects[group][key].is_equal_approx(DEFAULT_RECTS[group][key])
    if DEFAULT_NUMBERS.has(group) and (DEFAULT_NUMBERS[group] as Dictionary).has(key):
        return not is_equal_approx(_numbers[group][key],
            float((DEFAULT_NUMBERS[group][key] as Array)[0]))
    return false


## True when any piece of this group has been moved through the stack.
static func layers_changed(group: String) -> bool:
    _ensure()
    if not DEFAULT_LAYERS.has(group):
        return false
    return layer_order(group) != _default_order(group)


static func _default_order(group: String) -> Array:
    var keys: Array = (DEFAULT_LAYERS[group] as Dictionary).keys()
    keys.sort_custom(func(a, b):
        var la := int(DEFAULT_LAYERS[group][a])
        var lb := int(DEFAULT_LAYERS[group][b])
        if la != lb:
            return la < lb
        return String(a) < String(b))
    return keys


static func reset_layers(group: String) -> void:
    _ensure()
    if DEFAULT_LAYERS.has(group):
        _layers[group] = (DEFAULT_LAYERS[group] as Dictionary).duplicate(true)


static func reset(group: String, key: String) -> void:
    _ensure()
    if DEFAULT_RECTS.has(group) and (DEFAULT_RECTS[group] as Dictionary).has(key):
        _rects[group][key] = DEFAULT_RECTS[group][key]
    elif DEFAULT_NUMBERS.has(group) and (DEFAULT_NUMBERS[group] as Dictionary).has(key):
        _numbers[group][key] = float((DEFAULT_NUMBERS[group][key] as Array)[0])


static func reset_all() -> void:
    _loaded = false
    _rects = {}
    _numbers = {}
    _layers = {}
    _ensure()
    source = "built in"


static func to_dict() -> Dictionary:
    _ensure()
    var rects: Dictionary = {}
    for group in _rects:
        var g: Dictionary = {}
        for key in (_rects[group] as Dictionary):
            var r: Rect2 = _rects[group][key]
            g[key] = [_round(r.position.x), _round(r.position.y),
                _round(r.size.x), _round(r.size.y)]
        rects[group] = g
    var numbers: Dictionary = {}
    for group in _numbers:
        var g2: Dictionary = {}
        for key in (_numbers[group] as Dictionary):
            g2[key] = snappedf(float(_numbers[group][key]), 0.1)
        numbers[group] = g2
    var layers: Dictionary = {}
    for group in _layers:
        layers[group] = (_layers[group] as Dictionary).duplicate()
    return {"rects": rects, "layers": layers, "numbers": numbers}


static func _round(v: float) -> float:
    return snappedf(v, 0.001)


## Write the values where the game will read them next launch. Returns a
## message naming the file, or an error.
static func save_to(path: String) -> bool:
    var f := FileAccess.open(path, FileAccess.WRITE)
    if f == null:
        return false
    f.store_string(JSON.stringify(to_dict(), "  ") + "\n")
    f.close()
    return true


static func save() -> Dictionary:
    # Running from source, this is repository content and the change is real.
    if save_to(BUNDLED_PATH):
        source = BUNDLED_PATH
        return {"ok": true, "path": ProjectSettings.globalize_path(BUNDLED_PATH),
            "in_project": true}
    # An exported build cannot write to itself, so the values go beside the
    # saves instead and are still picked up on the next launch.
    if save_to(USER_PATH):
        source = USER_PATH
        return {"ok": true, "path": ProjectSettings.globalize_path(USER_PATH), "in_project": false}
    return {"ok": false, "path": "", "in_project": false,
        "error": "Could not write the layout file (error %d)." % FileAccess.get_open_error()}


## The same values as the GDScript they replace, for pasting back into the
## defaults above once a layout is settled.
static func as_code() -> String:
    _ensure()
    var lines: Array = ["const DEFAULT_RECTS := {"]
    for group in rect_groups():
        lines.append('    "%s": {' % group)
        for key in keys_of(String(group)):
            var r: Rect2 = _rects[group][key]
            lines.append('        "%s": Rect2(%.3f, %.3f, %.3f, %.3f),' % [
                key, r.position.x, r.position.y, r.size.x, r.size.y])
        lines.append("    },")
    lines.append("}")
    lines.append("")
    lines.append("const DEFAULT_LAYERS := {")
    for group in _layers.keys():
        lines.append('    "%s": {' % group)
        var n := 0
        for key in layer_order(String(group)):
            n += 10
            lines.append('        "%s": %d,' % [key, n])
        lines.append("    },")
    lines.append("}")
    lines.append("")
    lines.append("# numbers")
    for group in number_groups():
        for key in keys_of(String(group)):
            lines.append('%s.%s = %s' % [group, key, str(snappedf(_numbers[group][key], 0.1))])
    return "\n".join(lines)
