#!/usr/bin/env bash
# Shared logging helpers for the enforcement hooks.
#
# Bash-only hooks: source this and call
#   log_event_sh "<action>" "<hook>" "<tool>" [reason] [input_summary]
# Python-heredoc hooks: source the bash side for the HOOK_DIR export, then:
#   import sys, os
#   sys.path.insert(0, os.environ["HOOK_DIR"])
#   from _log_hook import log_event
#
# SANITIZED FOR PUBLIC RELEASE: log paths generalized to a workspace-relative
# location.

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export HOOK_DIR
WORKSPACE_ROOT="${WORKSPACE_ROOT:-$(cd "$HOOK_DIR/.." && pwd)}"
export WORKSPACE_ROOT
mkdir -p "$WORKSPACE_ROOT/logs/hooks/denials" \
         "$WORKSPACE_ROOT/logs/hooks/actions"

log_event_sh() {
  python3 -c 'import sys, os
sys.path.insert(0, os.environ["HOOK_DIR"])
from _log_hook import log_event
log_event(*sys.argv[1:])' "$@"
}
