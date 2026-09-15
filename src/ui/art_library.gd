class_name ArtLibrary
extends RefCounted

## Loads real card art supplied as image files, with a cache and a graceful
## fallback to the generated placeholder sigil.
##
## A definition points at its art with an `image` entry in its art block:
##
##     "art": {"image": "pas_skill_01.png", "fit": "cover", "hue": 350, "seed": 285}
##
## A bare filename is looked for in assets/art/. A full res://, user:// or
## absolute path is used as given. Nothing else about the card changes, so
## dropping in real illustration never affects mechanics or identity.

const ART_DIR := "res://assets/art"

static var _cache: Dictionary = {}   # resolved path -> Texture2D
static var _missing: Dictionary = {} # resolved path -> true, so misses are not retried


## Absolute path a definition's `image` entry refers to.
static func resolve_path(image: String) -> String:
    var p := image.strip_edges()
    if p == "":
        return ""
    if p.begins_with("res://") or p.begins_with("user://") or p.begins_with("/"):
        return p
    return ART_DIR.path_join(p)


static func has_image(art: Dictionary) -> bool:
    return String(art.get("image", "")).strip_edges() != ""


## The texture for an art block, or null when there is none or it cannot be
## read. A null result is not an error: the card falls back to placeholder art.
static func texture_for(art: Dictionary) -> Texture2D:
    if not has_image(art):
        return null
    var path := resolve_path(String(art.get("image", "")))
    if path == "":
        return null
    if _cache.has(path):
        return _cache[path]
    if _missing.has(path):
        return null

    var tex: Texture2D = null
    # An imported Godot resource is preferred: it is the only form that survives
    # an export.
    if ResourceLoader.exists(path):
        var res := load(path)
        if res is Texture2D:
            tex = res
        elif res is Image:
            tex = ImageTexture.create_from_image(res)
    if tex == null:
        # Not imported yet. Read it straight off disk so a file dropped into
        # assets/art works immediately, without reopening the editor.
        var img := Image.new()
        if FileAccess.file_exists(path) and img.load(path) == OK:
            tex = ImageTexture.create_from_image(img)

    if tex == null:
        _missing[path] = true
        return null
    _cache[path] = tex
    return tex


## A short status line for the card editor, so a designer can tell the
## difference between "no art yet" and "the file is not where I said it was".
static func describe(art: Dictionary) -> String:
    if not has_image(art):
        return "No art file set. This card uses its generated placeholder sigil."
    var path := resolve_path(String(art.get("image", "")))
    if texture_for(art) != null:
        var tex := texture_for(art)
        return "Art loaded from %s (%d by %d)." % [path, tex.get_width(), tex.get_height()]
    return ("Art file not found at %s. The card falls back to its placeholder sigil. "
        + "Drop the image there, or correct the path.") % path


## Forget what has been loaded. Used after files change on disk.
static func clear_cache() -> void:
    _cache.clear()
    _missing.clear()


## Every art file the catalog refers to that cannot currently be read.
static func missing_for(catalog: Catalog) -> Array:
    var out: Array = []
    for def in catalog.all_defs():
        var d: CardDef = def
        if has_image(d.art) and texture_for(d.art) == null:
            out.append("%s → %s" % [d.id, resolve_path(String(d.art.get("image", "")))])
    return out
