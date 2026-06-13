#!/usr/bin/env bats
# smoke.bats - Model C migration smoke test.
#
# Proves the migrated hook wrappers wire up to the canonical plugin core
# (lib/hook-lib.sh + lib/plugin-env.sh, synced from plugins/core) and emit
# valid host output when NO MCP marker is reachable and there is no network.
#
# This is intentionally host-neutral and dependency-free: it runs the real
# wrappers end to end (no internal mocks), exporting a throwaway HOME/cwd that
# contains no AGENTS-README-FIRST.yaml and pinning PLUGIN_ROOT_OVERRIDE to a
# temp dir so marker resolution fails closed. The canonical lib must then take
# its no-session path, exit 0, and print schema-valid JSON.

PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

# Copilot is a claude-family host: wrappers live under hooks/scripts/.
# (Codex would use lib/<hook>.sh; this repo is hooks/scripts.)
if [ -f "$PLUGIN_ROOT/hooks/scripts/session-start.sh" ]; then
    HOOKS_DIR="$PLUGIN_ROOT/hooks/scripts"
    CLI_MODE=0
else
    HOOKS_DIR="$PLUGIN_ROOT/lib"
    CLI_MODE=1
fi

# Run a wrapper with no marker reachable and empty stdin; capture stdout.
# Sets $status and $output (bats) plus writes stdout to $OUT_FILE.
_run_wrapper_no_marker() {
    local wrapper="$1"
    TEST_ROOT="$(mktemp -d)"
    TEST_HOME="$(mktemp -d)"   # contains no AGENTS-README-FIRST.yaml
    mkdir -p "$TEST_ROOT/cache"
    OUT_FILE="$TEST_ROOT/out.json"

    run env \
        HOME="$TEST_HOME" \
        USERPROFILE="$TEST_HOME" \
        PLUGIN_ROOT_OVERRIDE="$TEST_ROOT" \
        PLUGIN_ROOT="$TEST_ROOT" \
        CLAUDE_PLUGIN_ROOT="$TEST_ROOT" \
        MCPSERVER_WORKSPACE_PATH="$TEST_HOME" \
        MCP_WORKSPACE_PATH="$TEST_HOME" \
        REPL_TIMEOUT=3 \
        REPL_SESSIONLOG_REPL_TIMEOUT=3 \
        bash -c "cd '$TEST_HOME' && bash '$wrapper' < /dev/null > '$OUT_FILE' 2>/dev/null"
}

_cleanup() {
    [ -n "${TEST_ROOT:-}" ] && rm -rf "$TEST_ROOT"
    [ -n "${TEST_HOME:-}" ] && rm -rf "$TEST_HOME"
}

@test "session-start wrapper exits 0 and emits valid JSON with no marker reachable" {
    _run_wrapper_no_marker "$HOOKS_DIR/session-start.sh"
    [ "$status" -eq 0 ]
    if [ "$CLI_MODE" -eq 1 ]; then
        [ -s "$OUT_FILE" ]
    else
        run bash -c "node -e 'JSON.parse(require(\"fs\").readFileSync(0))' < '$OUT_FILE'"
        [ "$status" -eq 0 ]
    fi
    _cleanup
}

@test "session-start wrapper takes the neutral no-session path (empty object)" {
    _run_wrapper_no_marker "$HOOKS_DIR/session-start.sh"
    [ "$status" -eq 0 ]
    if [ "$CLI_MODE" -eq 0 ]; then
        [ "$(cat "$OUT_FILE")" = "{}" ]
    else
        [ -s "$OUT_FILE" ]
    fi
    _cleanup
}

@test "user-prompt-submit wrapper exits 0 and emits valid JSON with no marker reachable" {
    _run_wrapper_no_marker "$HOOKS_DIR/user-prompt-submit.sh"
    [ "$status" -eq 0 ]
    if [ "$CLI_MODE" -eq 1 ]; then
        [ -s "$OUT_FILE" ]
    else
        run bash -c "node -e 'JSON.parse(require(\"fs\").readFileSync(0))' < '$OUT_FILE'"
        [ "$status" -eq 0 ]
    fi
    _cleanup
}
