class_name HotRng
extends RefCounted

## Deterministic randomness with independent named streams.
##
## Every system that needs randomness (shuffles, Hero-damage sampling, AI
## tie-breaking, pack openings) pulls from its own named stream so that
## consuming randomness in one system never shifts another system's results.
## The full state is serialisable so an in-progress match can be saved and
## resumed with identical future rolls.

var _root_seed: int = 0
var _streams: Dictionary = {}  # String -> RandomNumberGenerator


func _init(root_seed: int = 0) -> void:
    _root_seed = root_seed


static func mix(seed_value: int, name: String) -> int:
    # FNV-1a style mix so stream seeds are well separated from the root seed.
    var h: int = 0x811C9DC5 ^ (seed_value & 0x7FFFFFFF)
    for i in name.length():
        h = (h ^ name.unicode_at(i)) * 0x01000193
        h = h & 0x7FFFFFFF
    if h == 0:
        h = 1
    return h


func root_seed() -> int:
    return _root_seed


func stream(name: String) -> RandomNumberGenerator:
    if not _streams.has(name):
        var r := RandomNumberGenerator.new()
        r.seed = mix(_root_seed, name)
        _streams[name] = r
    return _streams[name]


func randi_range_in(name: String, from: int, to: int) -> int:
    if to <= from:
        return from
    return stream(name).randi_range(from, to)


func randf_in(name: String) -> float:
    return stream(name).randf()


## Fisher-Yates using a named stream. Never uses Godot's global RNG, so
## results are reproducible from the seed alone.
func shuffled(name: String, items: Array) -> Array:
    var out: Array = items.duplicate()
    var r := stream(name)
    var i := out.size() - 1
    while i > 0:
        var j := r.randi_range(0, i)
        var tmp = out[i]
        out[i] = out[j]
        out[j] = tmp
        i -= 1
    return out


## Remove and return `count` uniformly random elements from `items`
## (mutating it). Used for Hero-damage sampling, which must not reshuffle.
func take_random(name: String, items: Array, count: int) -> Array:
    var taken: Array = []
    var r := stream(name)
    var n: int = min(count, items.size())
    for _i in n:
        var idx := r.randi_range(0, items.size() - 1)
        taken.append(items[idx])
        items.remove_at(idx)
    return taken


func clone() -> HotRng:
    var c := HotRng.new(_root_seed)
    for name in _streams.keys():
        var src: RandomNumberGenerator = _streams[name]
        var dst := c.stream(String(name))
        dst.state = src.state
    return c


func to_dict() -> Dictionary:
    var states: Dictionary = {}
    for name in _streams.keys():
        var r: RandomNumberGenerator = _streams[name]
        states[name] = str(r.state)  # states exceed JSON-safe int range; keep as text
    return {"root_seed": _root_seed, "states": states}


static func from_dict(d: Dictionary) -> HotRng:
    var rng := HotRng.new(int(d.get("root_seed", 0)))
    var states: Dictionary = d.get("states", {})
    for name in states.keys():
        var r: RandomNumberGenerator = rng.stream(name)
        r.state = int(str(states[name]))
    return rng
