class_name Catalog
extends RefCounted

## Loads, validates and serves card definitions.
##
## Four layers exist:
##   * bundled   — the JSON files shipped in res://data/catalog (read-only),
##   * overrides — the player's edits from the card editor (saved separately),
##   * customs   — cards the player made in the card creator, which are whole
##                 definitions of their own rather than edits of a shipped one,
##   * effective — all of the above together, which is what play uses.
##
## "Restore to bundled" simply drops an override, so an edit can always be
## undone without touching the shipped files. A custom card has no bundled
## version behind it, so deleting one removes it outright — which is why that
## is the creator's own deliberate action rather than a restore.

const CATALOG_DIR := "res://data/catalog"

var bundled: Dictionary = {}    # def_id -> Dictionary (raw)
var overrides: Dictionary = {}  # def_id -> Dictionary (raw)
var customs: Dictionary = {}    # def_id -> Dictionary (raw), created by the player
var _effective: Dictionary = {} # def_id -> CardDef
var _order: Array = []          # def ids in stable load order
var load_errors: Array = []


static func load_bundled(dir_path: String = CATALOG_DIR) -> Catalog:
    var c := Catalog.new()
    var files: Array = []
    var dir := DirAccess.open(dir_path)
    if dir == null:
        c.load_errors.append("Cannot open catalog directory %s" % dir_path)
        return c
    for f in dir.get_files():
        var fname := String(f)
        # Godot renames .json to .json.remap in some export configurations.
        if fname.ends_with(".json") or fname.ends_with(".json.remap"):
            files.append(fname.trim_suffix(".remap"))
    files.sort()
    for fname in files:
        var full := dir_path.path_join(String(fname))
        var text := FileAccess.get_file_as_string(full)
        if text.strip_edges() == "":
            c.load_errors.append("%s is empty or unreadable" % full)
            continue
        var parsed = JSON.parse_string(text)
        if not (parsed is Array):
            c.load_errors.append("%s must contain a JSON array of card definitions" % full)
            continue
        for entry in parsed:
            if not (entry is Dictionary):
                c.load_errors.append("%s contains a non-object entry" % full)
                continue
            var cid := String(entry.get("id", ""))
            if cid == "":
                c.load_errors.append("%s contains a definition with no id" % full)
                continue
            if c.bundled.has(cid):
                c.load_errors.append("duplicate card id '%s' (second copy in %s)" % [cid, full])
                continue
            c.bundled[cid] = entry
            c._order.append(cid)
    c.rebuild()
    return c


static func from_defs(defs: Array) -> Catalog:
    var c := Catalog.new()
    for d in defs:
        var raw: Dictionary = d.to_dict() if d is CardDef else d
        c.bundled[String(raw.get("id", ""))] = raw
        c._order.append(String(raw.get("id", "")))
    c.rebuild()
    return c


func set_overrides(o: Dictionary) -> void:
    overrides = o.duplicate(true)
    rebuild()


## Load the player's created cards. They join the catalog as ordinary
## definitions: the collection lists them, decks may hold them, and a match
## freezes them like any other card.
func set_customs(c: Dictionary) -> void:
    customs = c.duplicate(true)
    rebuild()


func rebuild() -> void:
    _effective.clear()
    for cid in _order:
        # The load order also holds ids that came from an import or from the
        # card creator, which have no bundled definition behind them. Those are
        # added by the passes below.
        if not bundled.has(cid):
            continue
        var raw: Dictionary = bundled[cid]
        if overrides.has(cid):
            raw = overrides[cid]
        _effective[cid] = CardDef.from_dict(raw)
    # An override may introduce a definition that is not bundled (an import).
    for cid in overrides.keys():
        if not _effective.has(cid):
            _effective[String(cid)] = CardDef.from_dict(overrides[cid])
            _order.append(String(cid))
    # Created cards come last, so they read as the newest thing in the
    # collection, and an override of one still wins.
    var custom_ids: Array = customs.keys()
    custom_ids.sort()
    for cid in custom_ids:
        var raw_custom: Dictionary = overrides.get(cid, customs[cid])
        _effective[String(cid)] = CardDef.from_dict(raw_custom)
        if not _order.has(String(cid)):
            _order.append(String(cid))
    # A card the creator deleted is gone from the catalog, so it must not be
    # left behind in the load order from an earlier rebuild.
    var kept: Array = []
    for cid in _order:
        if _effective.has(cid):
            kept.append(cid)
    _order = kept


func ids() -> Array:
    return _order.duplicate()


func size() -> int:
    return _effective.size()


func has(def_id: String) -> bool:
    return _effective.has(def_id)


func get_def(def_id: String) -> CardDef:
    return _effective.get(def_id, null)


func all_defs() -> Array:
    var out: Array = []
    for cid in _order:
        if _effective.has(cid):
            out.append(_effective[cid])
    return out


func is_overridden(def_id: String) -> bool:
    return overrides.has(def_id)


## Whether this definition is a card the player made rather than one the game
## shipped. The card's own face says so too, so it is never mistaken for one of
## the game's own.
func is_custom(def_id: String) -> bool:
    return customs.has(def_id)


## Store a created card, validating it exactly as a shipped definition is
## validated. Returns the problems found, and stores nothing when there are any.
func put_custom(def: CardDef) -> Array:
    var raw := def.to_dict()
    var cid := String(raw.get("id", ""))
    if cid == "":
        return ["A created card needs an id."]
    if bundled.has(cid):
        return ["%s is already a card the game ships." % cid]
    raw["text"] = TextGen.render(CardDef.from_dict(raw))
    var candidate := CardDef.from_dict(raw)
    var errs := candidate.validate()
    if not errs.is_empty():
        return errs
    # A display name shared with another card is a catalog error, so it is
    # refused here rather than saved and reported later.
    for other in all_defs():
        var o: CardDef = other
        if o.id != cid and o.name == candidate.name:
            return ["%s already carries the name '%s'." % [o.id, candidate.name]]
    customs[cid] = raw
    rebuild()
    return []


## Remove a created card from the catalog entirely.
func remove_custom(def_id: String) -> bool:
    if not customs.has(def_id):
        return false
    customs.erase(def_id)
    overrides.erase(def_id)
    _effective.erase(def_id)
    rebuild()
    return true


## Drop an override so the bundled definition applies again.
func restore_bundled(def_id: String) -> bool:
    if not overrides.has(def_id):
        return false
    overrides.erase(def_id)
    rebuild()
    return true


## Save an edited definition as an override, bumping its revision.
func put_override(def: CardDef) -> Array:
    var raw := def.to_dict()
    var cid := String(raw.get("id", ""))
    if cid == "":
        return ["An edited definition must keep its id."]
    var base_rev := 1
    if bundled.has(cid):
        base_rev = int((bundled[cid] as Dictionary).get("revision", 1))
    var current_rev := base_rev
    if overrides.has(cid):
        current_rev = max(current_rev, int((overrides[cid] as Dictionary).get("revision", 1)))
    raw["revision"] = current_rev + 1
    raw["text"] = TextGen.render(CardDef.from_dict(raw))
    var candidate := CardDef.from_dict(raw)
    var errs := candidate.validate()
    if not errs.is_empty():
        return errs
    overrides[cid] = raw
    rebuild()
    return []


func validate_all() -> Array:
    var errs: Array = load_errors.duplicate()
    var by_name: Dictionary = {}
    for def in all_defs():
        errs.append_array(def.validate())
        if by_name.has(def.name):
            errs.append("duplicate display name '%s' shared by %s and %s" % [def.name, by_name[def.name], def.id])
        else:
            by_name[def.name] = def.id
    return errs


# ------------------------------------------------------------- rarity pools ---

func pool_by_rarity(rarity: String) -> Array:
    var out: Array = []
    for def in all_defs():
        if def.rarity == rarity:
            out.append(def.id)
    return out


func rarity_counts() -> Dictionary:
    var counts := {"common": 0, "uncommon": 0, "rare": 0, "legendary": 0}
    for def in all_defs():
        counts[def.rarity] = int(counts.get(def.rarity, 0)) + 1
    return counts


func heroes() -> Array:
    var out: Array = []
    for def in all_defs():
        if def.has_type("hero"):
            out.append(def)
    return out


func deck_eligible() -> Array:
    var out: Array = []
    for def in all_defs():
        if not def.has_type("hero"):
            out.append(def)
    return out


## The collection cap for one definition: Heroes, named characters and Unique
## cards cap at one copy; everything else at three.
func collection_cap(def_id: String) -> int:
    var def := get_def(def_id)
    if def == null:
        return 0
    if def.has_type("hero") or def.is_named_character() or def.unique:
        return 1
    return 3


# --------------------------------------------------------- match snapshots ---

## The exact definitions a match needs, copied by value. A match snapshot
## stores this so later catalog edits cannot change a game in progress.
func freeze_subset(def_ids: Array) -> Dictionary:
    var out: Dictionary = {}
    for cid in def_ids:
        var def := get_def(String(cid))
        if def != null:
            out[String(cid)] = def.to_dict()
    return out


static func from_frozen(frozen: Dictionary) -> Catalog:
    var c := Catalog.new()
    var keys: Array = frozen.keys()
    keys.sort()
    for cid in keys:
        c.bundled[String(cid)] = (frozen[cid] as Dictionary).duplicate(true)
        c._order.append(String(cid))
    c.rebuild()
    return c
