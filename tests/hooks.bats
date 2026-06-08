#!/usr/bin/env bats

# Tests for session and compaction hooks.

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
HOOKS_DIR="$SCRIPT_DIR/hooks/scripts"

_assert_syntax() {
    local file="$1"
    run bash -n "$file"
    [ "$status" -eq 0 ]
}

@test "session-start.sh is syntactically valid bash" {
    _assert_syntax "$HOOKS_DIR/session-start.sh"
}

@test "session-start.sh emits no-op JSON on successful bootstrap" {
    TEST_PLUGIN_ROOT="$(mktemp -d)"
    mkdir -p "$TEST_PLUGIN_ROOT/cache"

    run bash -c "
        export PLUGIN_ROOT='$SCRIPT_DIR'
        export PLUGIN_ROOT_OVERRIDE='$TEST_PLUGIN_ROOT'
        export PLUGIN_AGENT_NAME='Copilot'

        full_bootstrap() {
            export MCPSERVER_BASE_URL='http://localhost:7147'
            export MCPSERVER_API_KEY='test-key'
            export MCPSERVER_WORKSPACE='TestWorkspace'
            export MCPSERVER_WORKSPACE_PATH='/tmp/test'
            return 0
        }
        export -f full_bootstrap

        repl_invoke() { echo 'sessionId: stub-session-123'; return 0; }
        export -f repl_invoke

        cache_flush() { echo 'flushed=0 failed=0 pending=0'; return 0; }
        export -f cache_flush

        source '$HOOKS_DIR/session-start.sh'
    "

    [ "$output" = "{}" ]
    [ -f "$TEST_PLUGIN_ROOT/cache/session-state.yaml" ]
    rm -rf "$TEST_PLUGIN_ROOT"
}

@test "session-start.sh emits no-op JSON when bootstrap fails" {
    TEST_PLUGIN_ROOT="$(mktemp -d)"
    mkdir -p "$TEST_PLUGIN_ROOT/cache"

    run bash -c "
        export PLUGIN_ROOT='$SCRIPT_DIR'
        export PLUGIN_ROOT_OVERRIDE='$TEST_PLUGIN_ROOT'

        full_bootstrap() { return 1; }
        export -f full_bootstrap

        repl_invoke() { return 0; }
        export -f repl_invoke

        cache_flush() { echo 'flushed=0 failed=0 pending=0'; return 0; }
        export -f cache_flush

        source '$HOOKS_DIR/session-start.sh'
    " || true

    [ "$output" = "{}" ]
    state_file="$(find "$TEST_PLUGIN_ROOT/cache" -name session-state.yaml | head -1)"
    [ -f "$state_file" ]
    grep -q "MCP_UNTRUSTED" "$state_file"
    rm -rf "$TEST_PLUGIN_ROOT"
}

@test "session-end.sh emits no-op JSON and calls cache_flush" {
    _assert_syntax "$HOOKS_DIR/session-end.sh"
    TEST_PLUGIN_ROOT="$(mktemp -d)"
    mkdir -p "$TEST_PLUGIN_ROOT/cache"
    FLUSH_CALLED="$TEST_PLUGIN_ROOT/cache/flush_called"

    run bash -c "
        export PLUGIN_ROOT='$SCRIPT_DIR'
        export PLUGIN_ROOT_OVERRIDE='$TEST_PLUGIN_ROOT'

        cache_flush() { touch '$FLUSH_CALLED'; echo 'flushed=0 failed=0 pending=0'; }
        export -f cache_flush

        repl_invoke() { return 0; }
        export -f repl_invoke

        source '$HOOKS_DIR/session-end.sh'
    " || true

    [ "$output" = "{}" ]
    [ -f "$FLUSH_CALLED" ]
    rm -rf "$TEST_PLUGIN_ROOT"
}

@test "pre-compact.sh emits no-op JSON and flushes cache" {
    _assert_syntax "$HOOKS_DIR/pre-compact.sh"
    TEST_PLUGIN_ROOT="$(mktemp -d)"
    mkdir -p "$TEST_PLUGIN_ROOT/cache"
    FLUSH_CALLED="$TEST_PLUGIN_ROOT/cache/flush_called"

    cat > "$TEST_PLUGIN_ROOT/cache/session-state.yaml" << 'EOF'
status: verified
sessionId: test-session-001
EOF

    run bash -c "
        export PLUGIN_ROOT='$SCRIPT_DIR'
        export PLUGIN_ROOT_OVERRIDE='$TEST_PLUGIN_ROOT'

        cache_flush() { touch '$FLUSH_CALLED'; echo 'flushed=0 failed=0 pending=0'; }
        export -f cache_flush

        repl_invoke() { return 0; }
        export -f repl_invoke

        source '$HOOKS_DIR/pre-compact.sh'
    " || true

    [ "$output" = "{}" ]
    [ -f "$FLUSH_CALLED" ]
    rm -rf "$TEST_PLUGIN_ROOT"
}

@test "post-compact.sh emits no-op JSON without additionalContext" {
    _assert_syntax "$HOOKS_DIR/post-compact.sh"
    TEST_PLUGIN_ROOT="$(mktemp -d)"
    mkdir -p "$TEST_PLUGIN_ROOT/cache"

    run bash -c "
        export PLUGIN_ROOT='$SCRIPT_DIR'
        export PLUGIN_ROOT_OVERRIDE='$TEST_PLUGIN_ROOT'

        full_bootstrap() { return 0; }
        export -f full_bootstrap

        repl_invoke() { echo 'history: []'; return 0; }
        export -f repl_invoke

        source '$HOOKS_DIR/post-compact.sh'
    "

    [ "$output" = "{}" ]
    [[ "$output" != *"additionalContext"* ]]
    rm -rf "$TEST_PLUGIN_ROOT"
}
