#!/bin/bash
# scan_write_pii.sh — PreToolUse guard on Write/Edit
# Blocks writes that contain PII patterns (SSN, full DOB).
# Enforces the Privacy Protocol at runtime.
#
# SANITIZED FOR PUBLIC RELEASE: detection logic is the production logic;
# internal document references in comments and messages are generalized.

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
parts = []
for key in ('content', 'new_string', 'file_path'):
    v = ti.get(key)
    if isinstance(v, str):
        parts.append(v)
payload = '\n'.join(parts)

# SSN: 3-2-4 with hyphen or space; reject impossible area numbers (000, 666, 9XX)
SSN = re.compile(r'\b(?!000|666|9)\d{3}[- ]\d{2}[- ]\d{4}\b')
# Full DOB: MM/DD/YYYY or MM-DD-YYYY with year 1900-2029
DOB = re.compile(r'\b(?:0?[1-9]|1[0-2])[/-](?:0?[1-9]|[12]\d|3[01])[/-](?:19\d{2}|20[0-2]\d)\b')

hit = None
if SSN.search(payload):
    hit = "SSN-like pattern (XXX-XX-XXXX)"
elif DOB.search(payload):
    hit = "full date-of-birth pattern (MM/DD/YYYY)"

if hit:
    reason = (
        f"Privacy Protocol violated: {tool_name} payload contains a {hit}. "
        f"No PII may be written to any artifact. Redact and use anonymous "
        f"references (Client A, Case #X) instead."
    )
    log_event("DENY", "scan_write_pii", tool_name,
              reason="pii-pattern-detected", input_summary=hit)
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }))
else:
    log_event("ALLOW", "scan_write_pii", tool_name)
PY
)

if [[ -n "$OUTPUT" ]]; then
  printf '%s\n' "$OUTPUT"
fi
exit 0
