# Privacy engineering in a privilege environment

A law firm's AI layer has to survive a hostile question: "what stops the
model from reading a client file?" If the answer is "we told it not to," you
do not have a privacy protocol. You have a wish.

This system's answer is runtime enforcement. Hooks intercept every tool call
before execution and deny the ones that cross a boundary. The model's
cooperation is welcome but not load-bearing.

## Threat model

The protected surfaces:

- **Client case files** and the practice management system's folder, which
  hold privileged matter content
- **Personal document folders** of firm members: tax, banking, medical,
  identity documents, treated identically to client PII
- **Co-counsel matter content** from jointly handled cases, which carries
  another firm's privilege obligations on top of ours
- **PII in transit**: an agent writing a Social Security number or date of
  birth into any artifact, even a draft

The adversary is not a malicious model. It is an obedient one with a broad
instruction, a helpful disposition, and a search tool.

## Enforcement layer

Three hooks, all in [`hooks/`](../hooks/), all writing structured audit
events:

### block_protected.sh — the path guard

Runs before every tool call. Walks the tool input recursively and collects
every path-like field: file paths, shell commands, URLs, globs, and search
queries. If any references a protected location, the call is denied with a
reason that cites the protocol rule.

Two design details earned their place:

- **Search queries count as paths.** A cloud drive search for a protected
  folder name returns the protected content in the result page. Denying
  reads of the folder while allowing searches that name it is a fence with
  an open gate. The `query` field joined the inspected set after exactly
  that gap was found in review.
- **Free-text fields are exempt.** Documentation may mention protected
  folder names. Writing "never access the client files folder" into a
  protocol document is not access. Only fields that direct where a tool
  operates are inspected, which keeps the false-positive rate near zero.

The guard's own patterns are built dynamically so the literal protected
token never appears in its source, letting the hook edit its own file
without self-blocking.

### scan_write_pii.sh — the write scrubber

Runs before every Write and Edit. Scans outgoing content for SSN-shaped
patterns (with impossible area numbers rejected to cut false positives) and
full date-of-birth patterns. A match denies the write.

On day one this caught a real SSN-shaped string in a draft artifact. The
denial is in the audit log. That single event justified the whole layer,
because the write it stopped was exactly the kind nobody would have noticed:
a helpful agent copying a detail into a working document.

A standing precedent bars agents from synthesizing fake PII even to test
the detectors. Test fixtures live outside the workspace, so the test data
can never become the leak.

### memory_log_check.sh — the discipline hook

Runs at session end. If the session performed substantive work but appended
nothing to the institutional memory ledger, the stop is blocked until the
log entry exists. Not a privacy control directly, but the audit story
depends on the ledger being complete, and completeness enforced by a hook
survives busy days in a way that habit does not.

## The audit trail

Every hook decision, allow and deny alike, writes one JSON line with the
hook name, tool, decision, and reason. A daily rollup renders the log to a
human-readable summary. Day one of live operation: 33 decisions, 3 denials,
each denial explainable after the fact. When someone asks what the AI layer
did last Tuesday, the answer is a file, not a recollection.

## Workspace isolation

- The agent workspace lives local-only and never syncs to cloud storage
- A one-way allowlist rsync mirrors only firm-public documents outward, and
  the mirror config is verified so agent internals, scripts, and logs stay
  out
- Credentials live outside the workspace entirely, in a mode-600 config
  directory, imported by scripts and never present in any repository file
- Output convention on top of the hooks: agents reference "Client A" and
  "Case #X," never names, so even permitted writes default to anonymity

## What this buys

The honest claim is not "the system cannot leak." It is: every tool call
crosses a checkpoint, the checkpoint has already caught real attempts, the
audit trail proves both the catches and the ordinary days, and the humans
kept every decision that carries professional-responsibility weight. That
is a claim you can defend to an attorney, which is the standard that
matters here.
