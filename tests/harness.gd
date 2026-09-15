class_name TestHarness
extends RefCounted

## Minimal assertion harness for the headless test runner.

var suite: String = ""
## The running SceneTree, for suites that need to build real interface nodes.
var tree: SceneTree = null
var passed: int = 0
var failures: Array = []
var current: String = ""


func begin(case_name: String) -> void:
    current = case_name


func ok(condition: bool, message: String) -> bool:
    if condition:
        passed += 1
        return true
    failures.append("[%s] %s — %s" % [suite, current, message])
    return false


func eq(actual, expected, message: String) -> bool:
    if actual == expected:
        passed += 1
        return true
    failures.append("[%s] %s — %s (expected %s, got %s)" % [suite, current, message, str(expected), str(actual)])
    return false


func ne(actual, forbidden, message: String) -> bool:
    return ok(actual != forbidden, "%s (should not be %s)" % [message, str(forbidden)])


func ge(actual: float, minimum: float, message: String) -> bool:
    return ok(actual >= minimum, "%s (expected >= %s, got %s)" % [message, str(minimum), str(actual)])


func le(actual: float, maximum: float, message: String) -> bool:
    return ok(actual <= maximum, "%s (expected <= %s, got %s)" % [message, str(maximum), str(actual)])


func empty(arr: Array, message: String) -> bool:
    if arr.is_empty():
        passed += 1
        return true
    var shown: Array = arr.slice(0, min(6, arr.size()))
    failures.append("[%s] %s — %s (%d problem(s): %s)" % [suite, current, message, arr.size(), "; ".join(shown)])
    return false
