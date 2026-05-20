#!/usr/bin/env bats

PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SKILL="$PLUGIN_ROOT/skills/workspace/SKILL.md"

@test "workspace skill exists and is referenced by plugin manifest" {
    [ -s "$SKILL" ]
    grep -q '"skills/workspace/SKILL.md"' "$PLUGIN_ROOT/plugin.json"
}

@test "workspace skill documents create and init workflow" {
    grep -q "client.Workspace.ListAsync" "$SKILL"
    grep -q "client.Workspace.CreateAsync" "$SKILL"
    grep -q "client.Workspace.InitAsync" "$SKILL"
    grep -q "type: request" "$SKILL"
}
