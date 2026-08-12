"""Shared structured logger for the enforcement hooks.

Hook authors call ``log_event`` once per decision (DENY, BLOCK, ALLOW).
Records are appended one-JSON-per-line to date-stamped files under
``<workspace>/logs/hooks/{denials,actions}/``. A daily rollup renders the
JSONL into a human-readable audit summary.

SANITIZED FOR PUBLIC RELEASE: the log base path is generalized.
"""

import json
import os
from datetime import datetime, timezone

LOG_BASE = os.path.join(
    os.environ.get(
        "WORKSPACE_ROOT",
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    ),
    "logs",
    "hooks",
)


def log_event(action, hook, tool, reason=None, input_summary=None):
    today = datetime.now().strftime("%Y-%m-%d")
    sub = "denials" if action in ("DENY", "BLOCK") else "actions"
    target_dir = os.path.join(LOG_BASE, sub)
    os.makedirs(target_dir, exist_ok=True)
    rec = {
        "ts": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "hook": hook,
        "tool": tool,
        "action": action,
    }
    if reason:
        rec["reason"] = reason
    if input_summary:
        rec["input_summary"] = input_summary
    with open(os.path.join(target_dir, f"{today}.jsonl"), "a") as f:
        f.write(json.dumps(rec) + "\n")
