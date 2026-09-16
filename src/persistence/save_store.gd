class_name SaveStore
extends RefCounted

## Durable, transactional save file handling, one file per save slot.
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

## Saves live one file per slot, so several games can be in progress at once
## and starting a new one never writes over another.
const SLOT_DIR := "user://saves"
const MAX_SLOTS := 6

## The single save file earlier builds wrote. It is adopted into a slot on
## first run rather than abandoned.
const LEGACY_PATH := "user://heroes_of_teloria_save.json"
const LEGACY_BACKUP_PATH := "user://heroes_of_teloria_save.backup.json"

## Set when the last load could not use the file on disk. The UI shows this
## and the original file stays recoverable.
var last_load_problem: String = ""


static func slot_path(slot: int) -> String:
    return "%s/slot_%d.json" % [SLOT_DIR, slot]


static func _backup_path(slot: int) -> String:
    return "%s/slot_%d.backup.json" % [SLOT_DIR, slot]


static func _temp_path(slot: int) -> String:
    return "%s/slot_%d.tmp.json" % [SLOT_DIR, slot]


static func _quarantine_path(slot: int) -> String:
    return "%s/slot_%d.unreadable.json" % [SLOT_DIR, slot]


static func valid_slot(slot: int) -> bool:
    return slot >= 1 and slot <= MAX_SLOTS


func _ensure_dir() -> void:
    if not DirAccess.dir_exists_absolute(SLOT_DIR):
        DirAccess.make_dir_recursive_absolute(SLOT_DIR)


func exists(slot: int) -> bool:
    return FileAccess.file_exists(slot_path(slot))


func any_exists() -> bool:
    for slot in range(1, MAX_SLOTS + 1):
        if exists(slot):
            return true
    return false


## Adopt a save written by an earlier build into the first free slot, so an
## existing game is not stranded by the move to slots. The original file is
## left where it is.
func adopt_legacy_save() -> int:
    if not FileAccess.file_exists(LEGACY_PATH) or any_exists():
        return 0
    var parsed = JSON.parse_string(FileAccess.get_file_as_string(LEGACY_PATH))
    if not (parsed is Dictionary):
        return 0
    var err := commit(1, parsed as Dictionary)
    if err != "":
        push_warning("Could not adopt the previous save: %s" % err)
        return 0
    return 1


## One row per slot, used or not, for the save-select screen. Reading a slot
## here never disturbs it: a slot whose file is unreadable is reported as a
## problem rather than repaired or removed.
func list_slots() -> Array:
    var out: Array = []
    for slot in range(1, MAX_SLOTS + 1):
        var row := {"slot": slot, "used": false, "problem": ""}
        var path := slot_path(slot)
        if FileAccess.file_exists(path):
            var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
            if parsed is Dictionary:
                row["used"] = true
                row.merge(PlayerProfile.summarise(parsed as Dictionary))
            else:
                row["used"] = true
                row["problem"] = "This save could not be read."
        out.append(row)
    return out


## Read one slot. Returns an empty Dictionary when there is nothing usable,
## with `last_load_problem` explaining why and the original file preserved.
func load_slot(slot: int) -> Dictionary:
    last_load_problem = ""
    if not valid_slot(slot):
        last_load_problem = "Slot %d does not exist." % slot
        return {}
    var path := slot_path(slot)
    if not FileAccess.file_exists(path):
        return {}
    var text := FileAccess.get_file_as_string(path)
    var parsed = JSON.parse_string(text)
    if not (parsed is Dictionary):
        _quarantine(slot, "That save could not be read as JSON.")
        return _try_backup(slot)
    var version := int((parsed as Dictionary).get("schema", 0))
    if version > SCHEMA_VERSION:
        last_load_problem = ("That save was written by a newer version of the game "
            + "(save format %d, this build understands %d). It has been left untouched at %s; "
            + "export it or update the game rather than overwriting it.") % [
                version, SCHEMA_VERSION, path]
        return {}
    return parsed


## Remove a slot, keeping its backup so a mistaken delete is recoverable.
func delete_slot(slot: int) -> String:
    if not valid_slot(slot):
        return "Slot %d does not exist." % slot
    if not FileAccess.file_exists(slot_path(slot)):
        return ""
    _ensure_dir()
    var dir := DirAccess.open(SLOT_DIR)
    if dir == null:
        return "Could not open the save folder."
    var live := slot_path(slot).get_file()
    var backup := _backup_path(slot).get_file()
    if dir.file_exists(backup):
        dir.remove(backup)
    var moved := dir.rename(live, backup)
    if moved != OK:
        return "Could not delete that save (error %d)." % moved
    return ""


func _try_backup(slot: int) -> Dictionary:
    if not FileAccess.file_exists(_backup_path(slot)):
        return {}
    var parsed = JSON.parse_string(FileAccess.get_file_as_string(_backup_path(slot)))
    if parsed is Dictionary:
        last_load_problem += " The previous save was recovered from the backup."
        return parsed
    return {}


func _quarantine(slot: int, reason: String) -> void:
    last_load_problem = reason
    var dir := DirAccess.open(SLOT_DIR)
    if dir != null and dir.file_exists(slot_path(slot).get_file()):
        dir.copy(slot_path(slot), _quarantine_path(slot))
        last_load_problem += " A copy was kept at %s." % _quarantine_path(slot)


## Write one slot as a durable transaction. Returns "" on success or an error
## message; on failure the previous contents of that slot are untouched.
func commit(slot: int, raw: Dictionary) -> String:
    if not valid_slot(slot):
        return "Slot %d does not exist." % slot
    _ensure_dir()
    var payload := raw.duplicate(true)
    payload["schema"] = SCHEMA_VERSION
    payload["saved_at"] = Time.get_datetime_string_from_system(true)
    var text := JSON.stringify(payload, "  ")

    var temp := _temp_path(slot)
    var tmp := FileAccess.open(temp, FileAccess.WRITE)
    if tmp == null:
        return "Could not open the save file for writing (error %d)." % FileAccess.get_open_error()
    tmp.store_string(text)
    tmp.flush()
    tmp.close()

    # Verify the temporary file parses before it replaces anything.
    var check = JSON.parse_string(FileAccess.get_file_as_string(temp))
    if not (check is Dictionary):
        return "The save was written but could not be read back; the previous save is unchanged."

    var dir := DirAccess.open(SLOT_DIR)
    if dir == null:
        return "Could not open the save folder."
    var live := slot_path(slot).get_file()
    var backup := _backup_path(slot).get_file()
    if dir.file_exists(live):
        dir.remove(backup)
        var moved := dir.rename(live, backup)
        if moved != OK:
            return "Could not rotate the previous save (error %d)." % moved
    var promoted := dir.rename(temp.get_file(), live)
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
