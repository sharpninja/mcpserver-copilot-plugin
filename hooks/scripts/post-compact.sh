#!/usr/bin/env bash
# post-compact.sh — PostCompact hook for the McpServer Copilot plugin.
# Re-verifies the marker signature after compaction without emitting
# unsupported PostCompact context.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}}"
export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"  # backward compat

# Source libraries if not already loaded
if ! type full_bootstrap >/dev/null 2>&1; then
    # shellcheck source=../../lib/marker-resolver.sh
    source "$PLUGIN_ROOT/lib/marker-resolver.sh"
fi


# Re-verify the marker after compaction
if ! full_bootstrap 2>/dev/null; then
    printf '{}\n'
    exit 0
fi

# PostCompact cannot inject context; emit schema-valid no-op output.
printf '{}\n'
