#!/bin/bash
# memory_log_check.sh — Stop hook
# Blocks session end when a turn performed substantive work (Write/Edit/Bash)
# but didn't append an entry to MEMORY.md, the append-only institutional
# ledger. Enforces the Experience Logging Rule at runtime.
#
# SANITIZED FOR PUBLIC RELEASE: logic is the production logic; internal
# document references are generalized.

set -euo pipefail

source "$(dirname "$0")/_log_helper.sh"

HOOK_INPUT=$(cat)
export HOOK_INPUT

OUTPUT=$(python3 <<'PY'
import json, os, sys
sys.path.insert(0, os.environ["HOOK_DIR"])
from _log_hook import log_event

try:
    d = json.loads(os.environ.get('HOOK_INPUT', '{}'))
except Exception:
    sys.exit(0)

transcript = d.get('transcript_path', '')
if not transcript or not os.path.isfile(transcript):
    sys.exit(0)

substantive = False
memory_touched = False
already_blocked = False

try:
    with open(transcript, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except Exception:
                continue
            msg = rec.get('message') or {}
            content = msg.get('content') or []
            if not isinstance(content, list):
                continue
            for block in content:
                if not isinstance(block, dict):
                    continue
                t = block.get('type')
                if t == 'tool_use':
                    name = block.get('name', '')
                    inp = block.get('input', {}) or {}
                    if name in ('Write', 'Edit', 'Bash'):
                        substantive = True
                    fp = (inp.get('file_path') or '') + ' ' + (inp.get('command') or '')
                    if 'MEMORY.md' in fp:
                        memory_touched = True
                elif t == 'tool_result':
                    txt = block.get('content', '')
                    if isinstance(txt, str) and 'memory_log_check' in txt:
                        already_blocked = True
except Exception:
    sys.exit(0)

if substantive and not memory_touched and not already_blocked:
    log_event("BLOCK", "memory_log_check", "Stop",
              reason="experience-log-missing", input_summary="session_had_writes")
    print(json.dumps({
        "decision": "block",
        "reason": (
            "Experience Logging Rule: this session did substantive work "
            "(Write/Edit/Bash) but no entry was appended to MEMORY.md. Append one line "
            "in the format [YYYY-MM-DD] [Task] -> [Result] -- [Agent] before stopping. "
            "(memory_log_check)"
        )
    }))
else:
    log_event("ALLOW", "memory_log_check", "Stop")
PY
)

if [[ -n "$OUTPUT" ]]; then
  printf '%s\n' "$OUTPUT"
fi
exit 0
