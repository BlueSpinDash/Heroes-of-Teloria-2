extends SceneTree

## Headless test runner:
##   godot --headless --path . --script tools/run_tests.gd
## Add a suite name to run only that suite, e.g. `-- rules`.

const SUITES := {
    "rules": "res://tests/test_rules.gd",
    "catalog": "res://tests/test_catalog.gd",
    "progression": "res://tests/test_progression.gd",
    "ai": "res://tests/test_ai.gd",
}


var _finished := false


## If a suite fails to compile, _initialize aborts part-way through. Returning
## true here guarantees the runner still exits instead of hanging a CI job.
func _process(_delta: float) -> bool:
    if not _finished:
        print("\nFAIL — the test runner stopped early; see the script errors above.")
        quit(1)
    return true


func _initialize() -> void:
    var only := ""
    for arg in OS.get_cmdline_user_args():
        only = String(arg)
    var total_passed := 0
    var failures: Array = []
    var ran: Array = []
    var names: Array = SUITES.keys()
    names.sort()
    for name in names:
        if only != "" and String(name) != only:
            continue
        var path := String(SUITES[name])
        if not ResourceLoader.exists(path):
            continue
        var script: Script = load(path)
        if script == null:
            failures.append("could not load suite %s" % path)
            continue
        var suite = script.new()
        if suite == null:
            failures.append("suite %s could not be instantiated" % path)
            continue
        var t := TestHarness.new()
        t.suite = String(name)
        var started := Time.get_ticks_msec()
        suite.run(t)
        var elapsed := Time.get_ticks_msec() - started
        ran.append(name)
        total_passed += t.passed
        failures.append_array(t.failures)
        print("  %-12s %3d passed, %2d failed  (%d ms)" % [name, t.passed, t.failures.size(), elapsed])

    print("")
    _finished = true
    if failures.is_empty():
        print("PASS — %d assertions across %d suite(s): %s" % [total_passed, ran.size(), ", ".join(ran)])
        quit(0)
    else:
        print("FAIL — %d passed, %d failed" % [total_passed, failures.size()])
        for f in failures:
            print("  ✗ ", f)
        quit(1)
