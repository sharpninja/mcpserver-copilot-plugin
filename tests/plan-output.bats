#!/usr/bin/env bats
# Regression: PostToolUse hookSpecificOutput must carry hookEventName or Claude
# Code rejects it with "missing required field hookEventName" (non-blocking).
# Asserts every plan-modified.sh and plan-approved.sh output path includes
# the PostToolUse event name.

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
HOOKS_DIR="$SCRIPT_DIR/hooks/scripts"

# ---------------------------------------------------------------------------
# plan-modified.sh output — hookEventName in every exit path
# ---------------------------------------------------------------------------

@test "plan-modified.sh no-file-path output includes PostToolUse hookEventName" {
    TEST_PLUGIN_ROOT="$(mktemp -d)"
    mkdir -p "$TEST_PLUGIN_ROOT/cache"

    run bash -c "
        export PLUGIN_ROOT='$TEST_PLUGIN_ROOT'
        export CLAUDE_PLUGIN_ROOT='$TEST_PLUGIN_ROOT'
        export PLUGIN_ROOT_OVERRIDE='$TEST_PLUGIN_ROOT'
        unset TOOL_INPUT

        repl_invoke() { return 0; }
        export -f repl_invoke

        source '$HOOKS_DIR/plan-modified.sh'
    "

    [ "$status" -eq 0 ]
    echo "$output" | grep -qF '"hookEventName":"PostToolUse"'
    rm -rf "$TEST_PLUGIN_ROOT"
}

@test "plan-modified.sh no-map skip output includes PostToolUse hookEventName" {
    TEST_PLUGIN_ROOT="$(mktemp -d)"
    mkdir -p "$TEST_PLUGIN_ROOT/cache"

    run bash -c "
        export PLUGIN_ROOT='$TEST_PLUGIN_ROOT'
        export CLAUDE_PLUGIN_ROOT='$TEST_PLUGIN_ROOT'
        export PLUGIN_ROOT_OVERRIDE='$TEST_PLUGIN_ROOT'
        export TOOL_INPUT='/some/plan/file.md'

        repl_invoke() { return 0; }
        export -f repl_invoke

        source '$HOOKS_DIR/plan-modified.sh'
    "

    [ "$status" -eq 0 ]
    echo "$output" | grep -qF '"hookEventName":"PostToolUse"'
    rm -rf "$TEST_PLUGIN_ROOT"
}

@test "plan-modified.sh no-mapping-for-file output includes PostToolUse hookEventName" {
    TEST_PLUGIN_ROOT="$(mktemp -d)"
    mkdir -p "$TEST_PLUGIN_ROOT/cache"

    # Map exists but does not contain the file — triggers "no mapping for file" path.
    cat > "$TEST_PLUGIN_ROOT/cache/plan-todo-map.yaml" << 'EOF'
entries:
  - planFile: /other/plan.md
    todoId: PLAN-OTHER-001
EOF

    run bash -c "
        export PLUGIN_ROOT='$TEST_PLUGIN_ROOT'
        export CLAUDE_PLUGIN_ROOT='$TEST_PLUGIN_ROOT'
        export PLUGIN_ROOT_OVERRIDE='$TEST_PLUGIN_ROOT'
        export TOOL_INPUT='/some/plan/file.md'

        repl_invoke() { return 0; }
        export -f repl_invoke

        source '$HOOKS_DIR/plan-modified.sh'
    "

    [ "$status" -eq 0 ]
    echo "$output" | grep -qF '"hookEventName":"PostToolUse"'
    rm -rf "$TEST_PLUGIN_ROOT"
}

@test "plan-modified.sh updated output includes PostToolUse hookEventName" {
    TEST_PLUGIN_ROOT="$(mktemp -d)"
    mkdir -p "$TEST_PLUGIN_ROOT/cache"

    PLAN_FILE="/tmp/test-plans/my-plan.md"
    cat > "$TEST_PLUGIN_ROOT/cache/plan-todo-map.yaml" << EOF
entries:
  - planFile: $PLAN_FILE
    todoId: PLAN-FEAT-001
EOF

    run bash -c "
        export PLUGIN_ROOT='$TEST_PLUGIN_ROOT'
        export CLAUDE_PLUGIN_ROOT='$TEST_PLUGIN_ROOT'
        export PLUGIN_ROOT_OVERRIDE='$TEST_PLUGIN_ROOT'
        export TOOL_INPUT='$PLAN_FILE'

        repl_invoke() { return 0; }
        export -f repl_invoke

        source '$HOOKS_DIR/plan-modified.sh'
    "

    [ "$status" -eq 0 ]
    echo "$output" | grep -qF '"hookEventName":"PostToolUse"'
    rm -rf "$TEST_PLUGIN_ROOT"
}

# ---------------------------------------------------------------------------
# plan-approved.sh output — hookEventName in every exit path
# ---------------------------------------------------------------------------

@test "plan-approved.sh no-plan skip output includes PostToolUse hookEventName" {
    TEST_PLUGIN_ROOT="$(mktemp -d)"
    mkdir -p "$TEST_PLUGIN_ROOT/cache"

    run bash -c "
        export PLUGIN_ROOT='$TEST_PLUGIN_ROOT'
        export CLAUDE_PLUGIN_ROOT='$TEST_PLUGIN_ROOT'
        export PLUGIN_ROOT_OVERRIDE='$TEST_PLUGIN_ROOT'
        unset TOOL_INPUT

        repl_invoke() { return 0; }
        export -f repl_invoke

        source '$HOOKS_DIR/plan-approved.sh'
    "

    [ "$status" -eq 0 ]
    echo "$output" | grep -qF '"hookEventName":"PostToolUse"'
    rm -rf "$TEST_PLUGIN_ROOT"
}

@test "plan-approved.sh created output includes PostToolUse hookEventName" {
    TEST_PLUGIN_ROOT="$(mktemp -d)"
    mkdir -p "$TEST_PLUGIN_ROOT/cache"

    PLAN_FILE="$TEST_PLUGIN_ROOT/feature-plan.md"
    cat > "$PLAN_FILE" << 'EOF'
# Add Feature Flags

Simple plan.
EOF

    run bash -c "
        export PLUGIN_ROOT='$TEST_PLUGIN_ROOT'
        export CLAUDE_PLUGIN_ROOT='$TEST_PLUGIN_ROOT'
        export PLUGIN_ROOT_OVERRIDE='$TEST_PLUGIN_ROOT'
        export TOOL_INPUT='$PLAN_FILE'

        repl_invoke() { echo 'id: TODO-FEAT-001'; return 0; }
        export -f repl_invoke

        source '$HOOKS_DIR/plan-approved.sh'
    "

    [ "$status" -eq 0 ]
    echo "$output" | grep -qF '"hookEventName":"PostToolUse"'
    rm -rf "$TEST_PLUGIN_ROOT"
}
