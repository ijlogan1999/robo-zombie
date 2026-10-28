#!/usr/bin/env bash
# Runs the automated co-op check: one host and one client copy of the game, headless.
# Usage: GODOT=/path/to/godot_console.exe bash tests/run_net_test.sh
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
OUT="${TMPDIR:-/tmp}/robozomb_net_test"
mkdir -p "$OUT"
"$GODOT" --headless --path . -- --host --autostart=2 --net-test=host > "$OUT/host.log" 2>&1 &
HOST=$!
sleep 2
"$GODOT" --headless --path . -- --join=127.0.0.1 --net-test=client > "$OUT/client.log" 2>&1 &
CLIENT=$!
wait $CLIENT; C=$?
wait $HOST; H=$?
grep -hE "\[(host|client)\]|SCRIPT ERROR|^ERROR" "$OUT/host.log" "$OUT/client.log"
echo "host exit $H, client exit $C"
