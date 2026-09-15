#!/usr/bin/env sh
# Regenerate the 300-card catalog from tools/generate_catalog.py.
#
# Three passes, because the engine owns rules-text generation while Python owns
# the JSON file format:
#   1. write the definitions (effects, costs, stats, tags, rarity)
#   2. let Godot render each card's rules text from its effects
#   3. rewrite the definitions with that text embedded
# Then validate every definition through the real engine.
#
# Usage: GODOT=/path/to/godot tools/build_catalog.sh
set -e
GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "== pass 1: generate definitions =="
python3 tools/generate_catalog.py

echo "\n== pass 2: render rules text =="
"$GODOT" --headless --path . --script tools/dump_card_text.gd

echo "\n== pass 3: embed rules text =="
python3 tools/generate_catalog.py

echo "\n== validate =="
"$GODOT" --headless --path . --script tools/run_tests.gd -- catalog
