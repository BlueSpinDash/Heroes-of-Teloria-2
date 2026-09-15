class_name SaveStore
extends RefCounted

## Durable, transactional save file handling.
##
## Every commit writes a temporary file and then renames it over the live save,
## so an interrupted write can never leave a half-written save behind: the
## reader either sees the previous version or the new one. The previous version
## is kept as a recoverable backup, and an unreadable or unsupported save is
## quarantined rather than deleted.
##
## Browser storage note: in a web export, user:// lives in the browser's
## IndexedDB-backed virtual filesystem, which is specific to that browser on
## that device. Exported save files are how progress moves between devices.
## Nothing here synchronises to a server.

const SCHEMA_VERSION := 1
const SAVE_PATH := "user://heroes_of_teloria_save.json"
const BACKUP_PATH := "user://heroes_of_teloria_save.backup.json"
const TEMP_PATH := "user://heroes_of_teloria_save.tmp.json"
const QUARANTINE_PATH := "user://heroes_of_teloria_save.unreadable.json"

## Set when the last load could not use the file on disk. The UI shows this
## and the original file stays recoverable.
var last_load_problem: String = ""


func exists() -> bool:
    return FileAccess.file_exists(SAVE_PATH)


## Read the save. Returns an empty Dictionary when there is nothing usable,
## with `last_load_problem` explaining why and the original file preserved.
func load_raw() -> Dictionary:
    last_load_problem = ""
    if not FileAccess.file_exists(SAVE_PATH):
        return {}
    var text := FileAccess.get_file_as_string(SAVE_PATH)
    var parsed = JSON.parse_string(text)
    if not (parsed is Dictionary):
        _quarantine("The save file could not be read as JSON.")
        return _try_backup()
    var version := int((parsed as Dictionary).get("schema", 0))
    if version > SCHEMA_VERSION:
        last_load_problem = ("This save was written by a newer version of the game "
            + "(save format %d, this build understands %d). It has been left untouched at %s; "
            + "export it or update the game rather than overwriting it.") % [version, SCHEMA_VERSION, SAVE_PATH]
        return {}
    return parsed


func _try_backup() -> Dictionary:
    if not FileAccess.file_exists(BACKUP_PATH):
        return {}
    var parsed = JSON.parse_string(FileAccess.get_file_as_string(BACKUP_PATH))
    if parsed is Dictionary:
        last_load_problem += " The previous save was recovered from the backup."
        return parsed
    return {}


func _quarantine(reason: String) -> void:
    last_load_problem = reason
    var dir := DirAccess.open("user://")
    if dir != null and dir.file_exists(SAVE_PATH.trim_prefix("user://")):
        dir.copy(SAVE_PATH, QUARANTINE_PATH)
        last_load_problem += " A copy was kept at %s." % QUARANTINE_PATH


## Write the save as one durable transaction. Returns "" on success or an
## error message; on failure the previous save is untouched.
func commit(raw: Dictionary) -> String:
    var payload := raw.duplicate(true)
    payload["schema"] = SCHEMA_VERSION
    payload["saved_at"] = Time.get_datetime_string_from_system(true)
    var text := JSON.stringify(payload, "  ")

    var tmp := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
    if tmp == null:
        return "Could not open the save file for writing (error %d)." % FileAccess.get_open_error()
    tmp.store_string(text)
    tmp.flush()
    tmp.close()

    # Verify the temporary file parses before it replaces anything.
    var check = JSON.parse_string(FileAccess.get_file_as_string(TEMP_PATH))
    if not (check is Dictionary):
        return "The save was written but could not be read back; the previous save is unchanged."

    var dir := DirAccess.open("user://")
    if dir == null:
        return "Could not open the save directory."
    if dir.file_exists(SAVE_PATH.trim_prefix("user://")):
        dir.remove(BACKUP_PATH.trim_prefix("user://"))
        var moved := dir.rename(SAVE_PATH.trim_prefix("user://"), BACKUP_PATH.trim_prefix("user://"))
        if moved != OK:
            return "Could not rotate the previous save (error %d)." % moved
    var promoted := dir.rename(TEMP_PATH.trim_prefix("user://"), SAVE_PATH.trim_prefix("user://"))
    if promoted != OK:
        return "Could not replace the save file (error %d)." % promoted
    return ""


## Export the current save to an arbitrary path chosen by the player.
func export_to(path: String, raw: Dictionary) -> String:
    var payload := raw.duplicate(true)
    payload["schema"] = SCHEMA_VERSION
    payload["exported_at"] = Time.get_datetime_string_from_system(true)
    var f := FileAccess.open(path, FileAccess.WRITE)
    if f == null:
        return "Could not write %s (error %d)." % [path, FileAccess.get_open_error()]
    f.store_string(JSON.stringify(payload, "  "))
    f.close()
    return ""


## Validate an import before it replaces anything. Returns
## {"ok": bool, "error": String, "data": Dictionary}.
func read_import(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {"ok": false, "error": "No file at %s." % path, "data": {}}
    var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
    if not (parsed is Dictionary):
        return {"ok": false, "error": "That file is not a Heroes of Teloria save.", "data": {}}
    var d: Dictionary = parsed
    var version := int(d.get("schema", 0))
    if version <= 0:
        return {"ok": false, "error": "That save has no format version.", "data": {}}
    if version > SCHEMA_VERSION:
        return {"ok": false, "error":
            "That save uses format %d; this build understands %d." % [version, SCHEMA_VERSION],
            "data": {}}
    for key in ["gold", "owned", "decks"]:
        if not d.has(key):
            return {"ok": false, "error": "That save is missing its '%s' section." % key, "data": {}}
    if not (d["owned"] is Dictionary) or not (d["decks"] is Array):
        return {"ok": false, "error": "That save's collection or deck list is malformed.", "data": {}}
    return {"ok": true, "error": "", "data": d}
