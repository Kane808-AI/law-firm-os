#!/bin/bash
# block_protected.sh — PreToolUse guard
# Denies tool calls that ACCESS protected locations (the protected client
# files folder, the practice-management folder, firm-member personal folders,
# co-counsel matter content). Only inspects path-like fields (file_path,
# command, url, pattern, path, glob, etc.). Free-form content/new_string/
# prompt fields are allowed to mention these names — documentation is not
# access. Enforces the Privacy Protocol at runtime.
#
# SANITIZED FOR PUBLIC RELEASE: the real firm-specific folder names have been
# replaced with generic placeholders. The logic is the production logic.

set -euo pipefail

source "$(dirname "$0")/_log_helper.sh"

HOOK_INPUT=$(cat)
export HOOK_INPUT

OUTPUT=$(python3 <<'PY'
import json, os, re, sys
sys.path.insert(0, os.environ["HOOK_DIR"])
from _log_hook import log_event

try:
    d = json.loads(os.environ.get('HOOK_INPUT', '{}'))
except Exception:
    sys.exit(0)

tool_name = d.get('tool_name', '')
ti = d.get('tool_input', {}) or {}

# Fields that represent a *location* the tool will access.
# 'query' was added after review found that a cloud-drive search naming a
# protected folder returns protected content — search is access too.
PATH_FIELDS = ('file_path', 'path', 'url', 'pattern', 'glob', 'command', 'cwd',
               'directory', 'paths', 'file_paths', 'src', 'dst', 'source',
               'destination', 'query')

def collect_paths(obj, in_path_field=False):
    out = []
    if isinstance(obj, dict):
        for k, v in obj.items():
            child_in_path = in_path_field or (k in PATH_FIELDS)
            out.extend(collect_paths(v, child_in_path))
    elif isinstance(obj, list):
        for v in obj:
            out.extend(collect_paths(v, in_path_field))
    elif isinstance(obj, str):
        if in_path_field:
            out.append(obj)
    return out

candidates = collect_paths(ti)

# Built dynamically so the literal token does not appear in this file's
# regex source (so this very file can be edited without self-blocking).
TOKEN = '_' + 'PROTECTED'
# Boundary class: start, end, slash, backslash, whitespace, or quote. This
# catches search query strings where the protected name is quoted rather
# than slash-delimited.
B = r"(?:^|[/\\\s\'\"])"
E = r"(?=[/\\\s\'\"]|$)"
PATTERNS = [
    re.compile(re.escape(TOKEN)),
    re.compile(r'(^|[/\\])Client Files([/\\]|$)'),
    # The practice management system's local folder — the system of record
    # for client cases. Agents operate around it, never inside it.
    re.compile(r'(^|[/\\])Clio([/\\]|$)'),
    # Firm-member personal folders (tax/financial/identity docs) — treated
    # identically to client PII.
    re.compile(r'Firm Partner - Personal'),
    # Jointly-handled matter content carries the co-counsel firm's privilege
    # obligations too — off-limits.
    re.compile(r'Co-Counsel Firm LLP'),
    re.compile(B + r'CCF' + E),
]

hit = None
for s in candidates:
    for pat in PATTERNS:
        if pat.search(s):
            hit = s
            break
    if hit:
        break

if hit:
    reason = (
        f"Privacy Protocol violated: tool call '{tool_name}' would access a "
        f"protected location ({hit!r}). Protected locations include the "
        f"client files folder, the practice-management folder, firm-member "
        f"personal folders, and co-counsel matter content. Flag to the "
        f"operator instead."
    )
    log_event("DENY", "block_protected", tool_name,
              reason="protected-location-access", input_summary=hit)
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }))
else:
    log_event("ALLOW", "block_protected", tool_name)
PY
)

if [[ -n "$OUTPUT" ]]; then
  printf '%s\n' "$OUTPUT"
fi
exit 0
