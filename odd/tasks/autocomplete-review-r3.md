# autocomplete: review advisories R3-001/R3-002 (1.1.0 -> 1.1.1)

## Note
The review receipt carried locations without claim text. Fixes below are
the author's best reading of each spot; both are contract-backed
hardenings, not behavior changes.

## R3-001 (main.lua:40, end of candidatesFor)
`suggest()` returned the buffer's whole vocabulary unbounded while the
provider contract says max 32 (the editor's CallStrings also caps, but the
source should bound its own table per keystroke pause).
Fix: `suggestCap = 32`, truncate best-first (ranking preserved).
Harness: "suggest caps at 32" (40 words -> first 32 alphabetically).

## R3-002 (main.lua:62, shared prefix helper)
`complete()` duplicated the cursor/prefix extraction instead of reusing
`prefixAtCursor()`, inviting divergence.
Fix: `prefixAtCursor()` returns `prefix, kind` with kinds
cursor/position/line/prefix; `complete()` maps kinds to its exact same
messages, `suggest()` ignores the kind. All 11 existing message cases
still green, proving no message changed.

## Acceptance
- Harness green: 11 complete + 7 suggest cases.
- Version bumped 1.1.0 -> 1.1.1 (patch: hardening, no new capability).
