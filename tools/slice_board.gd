extends SceneTree

## Slices the board artwork into the panel textures the battle screen uses.
##
## The source is one painted board. Each labelled plate on it becomes its own
## texture so the live screen can place, mirror and resize the zones freely
## while still being made of the original art.

const SRC := "res://assets/board/board_full.png"
const OUT := "res://assets/board/"

## name: [x, y, w, h] in source pixels.
const SLICES := {
	# Cropped below the plate's painted caption. A Companion Zone is far wider
	# than it is tall once two of them share the screen, and covering that
	# shape with the whole plate would blow the caption up to fill it, so the
	# screen draws its own caption over a band of the landscape instead.
	"panel_companion": [393, 175, 895, 126],
	"panel_sequence": [237, 325, 1276, 183],
	"panel_hand": [100, 710, 1480, 179],
	# The painted caption on this plate reads "Terrain". The game's term is
	# Location, so the caption is cropped away and the screen draws its own.
	"panel_location": [1304, 175, 209, 126],
	"deck_hit": [150, 528, 330, 162],
	"deck_hero": [630, 528, 405, 162],
	"deck_exhaust": [1072, 528, 253, 162],
	"deck_wound": [1362, 528, 218, 162],
}


func _initialize() -> void:
	var img := Image.new()
	if img.load(ProjectSettings.globalize_path(SRC)) != OK:
		push_error("could not load %s" % SRC)
		quit(1)
		return
	print("source %dx%d" % [img.get_width(), img.get_height()])
	for name in SLICES:
		var r: Array = SLICES[name]
		var rect := Rect2i(int(r[0]), int(r[1]), int(r[2]), int(r[3]))
		var cut := img.get_region(rect)
		var path := ProjectSettings.globalize_path("%s%s.png" % [OUT, name])
		if cut.save_png(path) != OK:
			push_error("could not write %s" % path)
			quit(1)
			return
		print("%-18s %s" % [name, str(rect)])
	quit(0)
