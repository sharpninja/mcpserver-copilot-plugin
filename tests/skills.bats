#!/usr/bin/env bats

PLUGIN_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SKILL="$PLUGIN_ROOT/skills/workspace/SKILL.md"
SKILLS_DIR="$PLUGIN_ROOT/skills"
WORKFLOW_SKILLS=(sync-logs commit-sync wrap-up)

get_frontmatter() {
    local file="$1"
    awk '/^---$/{count++; if(count==2) exit; next} count==1{print}' "$file"
}

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

@test "workflow skills satisfy AC-SKILLS-001 and AC-SKILLS-002" {
    for skill in "${WORKFLOW_SKILLS[@]}"; do
        local skill_file="$SKILLS_DIR/$skill/SKILL.md"
        [ -s "$skill_file" ]
        get_frontmatter "$skill_file" | grep -Eq "^name:[[:space:]]*.+"
        get_frontmatter "$skill_file" | grep -Eq "^description:[[:space:]]*.+"
    done
}

@test "sync-logs skill documents AC-SKILLS-003" {
    local skill_file="$SKILLS_DIR/sync-logs/SKILL.md"
    grep -Eiq "status check|mcp.*status|Status" "$skill_file"
    grep -Eq "workflow\.sessionlog\.(openSession|beginTurn)|session/turn|turn handling" "$skill_file"
    grep -q "workflow.sessionlog.appendDialog" "$skill_file"
    grep -q "workflow.sessionlog.appendActions" "$skill_file"
    grep -Eiq "background.*session|session.*background" "$skill_file"
    grep -Eiq "factual summary|factual.*summary" "$skill_file"
    grep -Eiq "raw[[:space:]-]*REST" "$skill_file"
}

@test "commit-sync skill documents AC-SKILLS-004" {
    local skill_file="$SKILLS_DIR/commit-sync/SKILL.md"
    grep -Eiq "pause" "$skill_file"
    grep -Eiq "repo-scope|repo scope|dirty tree|dirty-tree" "$skill_file"
    grep -Eiq "acknowledg" "$skill_file"
    grep -Fq "git add -A -- ." "$skill_file"
    grep -Eiq "commit SHA|git rev-parse HEAD" "$skill_file"
    grep -Eiq "push result|git push" "$skill_file"
    grep -Eiq "force|rewrite" "$skill_file"
}

@test "wrap-up skill documents AC-SKILLS-005" {
    local skill_file="$SKILLS_DIR/wrap-up/SKILL.md"
    grep -Eiq "marker trust|trust.*marker" "$skill_file"
    grep -Eiq "requirement reconciliation|requirements.*reconcile|reconcile.*requirements" "$skill_file"
    grep -Eiq "wiki|generateDocument" "$skill_file"
    grep -Eiq "validation" "$skill_file"
    grep -Eiq "commit" "$skill_file"
    grep -Eiq "push" "$skill_file"
    grep -Eiq "session-log reconciliation|session log reconciliation|reconcile.*session" "$skill_file"
    grep -Eq "workflow\.sessionlog\.(completeTurn|failTurn)" "$skill_file"
}

@test "workflow skills are exposed by plugin manifest for AC-SKILLS-006" {
    for skill in "${WORKFLOW_SKILLS[@]}"; do
        grep -q "\"skills/$skill/SKILL.md\"" "$PLUGIN_ROOT/plugin.json"
    done
}

@test "triage skill is exposed and documents async incidental bug reporting for TEST-MCP-PLUGIN-TRIAGE-001" {
    local skill_file="$SKILLS_DIR/triage/SKILL.md"
    [ -s "$skill_file" ]
    grep -q '"skills/triage/SKILL.md"' "$PLUGIN_ROOT/plugin.json"
    grep -Eiq "incidental bug" "$skill_file"
    grep -Eiq "active requested fix" "$skill_file"
    grep -Eiq "not expect immediate resolution" "$skill_file"
    grep -Eiq "continue" "$skill_file"
    grep -q "triage_report" "$skill_file"
    grep -q "triage_status" "$skill_file"
    grep -q "workflow.triage.report" "$skill_file"
}

@test "REPL YAML schema exposes workflow.triage methods for TEST-MCP-PLUGIN-TRIAGE-001" {
    local schema_file="$PLUGIN_ROOT/schemas/repl-yaml-message.schema.json"
    [ -s "$schema_file" ]
    grep -Fq 'workflow\\.(sessionlog|todo|memory|requirements|graphrag|triage)' "$schema_file"
    grep -q '"triageRules"' "$schema_file"
    grep -q 'workflow.triage.report' "$schema_file"
    grep -q 'workflow.triage.getReport' "$schema_file"
    grep -q 'workflow.triage.queryGroups' "$schema_file"
    grep -q 'workflow.triage.getGroup' "$schema_file"
    grep -q 'workflow.triage.flushGroup' "$schema_file"
    grep -q 'workflow.triage.retryGroup' "$schema_file"
}
