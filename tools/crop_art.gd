extends SceneTree

## Crop the portrait window out of a supplied full card face.
##
## Usage: godot --headless --path . --script tools/crop_art.gd -- SRC DST X Y W H [SCALE]
##
## SCALE enlarges the result by a whole number, which is how the edges of a
## card's painted window are read off precisely enough to crop to them.

func _initialize() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() < 6:
        print("need SRC DST X Y W H")
        quit(1)
        return
    var img := Image.new()
    if img.load(String(args[0])) != OK:
        print("could not load ", args[0])
        quit(1)
        return
    print("source ", img.get_width(), "x", img.get_height())
    var rect := Rect2i(int(args[2]), int(args[3]), int(args[4]), int(args[5]))
    var cropped := img.get_region(rect)
    var scale := int(args[6]) if args.size() > 6 else 1
    if scale > 1:
        cropped.resize(cropped.get_width() * scale, cropped.get_height() * scale,
            Image.INTERPOLATE_NEAREST)
    var err := cropped.save_png(String(args[1]))
    print("cropped ", rect, " -> ", args[1], " (", cropped.get_width(), "x", cropped.get_height(), ") err=", err)
    quit(0)
