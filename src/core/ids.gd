class_name Ids
extends RefCounted

## Stable id minting. Match-scoped ids are derived from a counter held in the
## game state so that a resumed match keeps numbering deterministically;
## save-scoped ids (decks, matches, transactions) use time + entropy because
## they only need to be unique, not reproducible.

const ALPHABET := "abcdefghijklmnopqrstuvwxyz0123456789"


static func next_in(counters: Dictionary, prefix: String) -> String:
    var n: int = int(counters.get(prefix, 0)) + 1
    counters[prefix] = n
    return "%s%d" % [prefix, n]


static func unique(prefix: String) -> String:
    var t := Time.get_unix_time_from_system()
    var rand := RandomNumberGenerator.new()
    rand.randomize()
    var suffix := ""
    for _i in 6:
        suffix += ALPHABET[rand.randi_range(0, ALPHABET.length() - 1)]
    return "%s_%d_%s" % [prefix, int(t * 1000.0), suffix]
