extends SceneTree

## Render every bundled definition's rules text and write it to
## build/card_text.json for tools/generate_catalog.py to embed.
##
##   godot --headless --path . --script tools/dump_card_text.gd
##
## Godot's JSON writer turns every number into a float, which would make the
## hand-editable catalog files unpleasant, so the engine only ever produces the
## text here and the Python generator owns the file format.

const DIR := "res://data/catalog"
const OUT := "res://build/card_text.json"


func _initialize() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://build"))
    var dir := DirAccess.open(DIR)
    if dir == null:
        print("cannot open ", DIR)
        quit(1)
        return
    var files: Array = []
    for f in dir.get_files():
        var name := String(f).trim_suffix(".remap")
        if name.ends_with(".json"):
            files.append(name)
    files.sort()

    var texts: Dictionary = {}
    var count := 0
    for fname in files:
        var parsed = JSON.parse_string(FileAccess.get_file_as_string(DIR.path_join(String(fname))))
        if not (parsed is Array):
            continue
        for raw in parsed:
            if not (raw is Dictionary):
                continue
            texts[String((raw as Dictionary).get("id", ""))] = TextGen.render(CardDef.from_dict(raw))
            count += 1

    var out := FileAccess.open(OUT, FileAccess.WRITE)
    if out == null:
        print("cannot write ", OUT)
        quit(1)
        return
    out.store_string(JSON.stringify(texts, "  ", true) + "\n")
    out.close()
    print("rendered rules text for %d definition(s) -> %s" % [count, OUT])
    quit(0)
