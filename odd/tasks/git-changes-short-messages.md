# git-changes short gutter messages

## User request
Shorten git-changes gutter diagnostic messages: drop the redundant line
number since the mark already sits on that line (toggle presence is
signal enough).

## Decision
- Gutter messages are marker plus kind only: `+ added`, `~ modified`,
  `- deleted`.
- Severities unchanged (info/info/warning). No other behavior change.

## Acceptance
- `main.lua` mark() builds short messages; stays pure Lua, English.
- `extension.json` bumped 1.7.0 to 1.7.1 (patch: message wording).
- README Gutter section documents short messages, no `line N` examples.
- Harness expectations updated to short form; suite green.

## Adjustment: empty message, indicator only

User decision: remove gutter diagnostic message text entirely.
- mark() sets message to the empty string for all kinds
  (added/deleted/modified); line numbers (1-indexed d.line) and
  severities (info/info/warning) unchanged so the gutter indicator
  still renders in the right place with the right style.
- Version stays 1.7.1 (unreleased tree); extension.json untouched.
