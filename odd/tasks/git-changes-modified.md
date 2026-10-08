# git-changes modified coalescing

## Root cause

The editor `GetFileDiff` (via `parseUnifiedDiff`) emits only `added` and
`deleted` entries, never `modified`. A modified line arrives as
`{line N, deleted}` plus `{line N, added}` (unified `-U0` shows `-old`
then `+new` at the same new-file position), and `mark()` rendered both
instead of one `~ line N modified`.

## Decision

Coalesce extension-side in `mark()`: after combining staged and unstaged
diffs, group entries by line; a line with at least one `deleted` AND at
least one `added` entry collapses to a single `{line N, modified}` entry.
Lines with only one kind keep every entry unchanged. Extension-side
coalescing means old editors benefit too, with no editor change required.

## Acceptance

- Modified single line (deleted+added on the same line) shows one `~ modified`.
- Multi-line replace on one line collapses to one `~ modified`.
- Pure added stays `+`, pure deleted stays `-`.
- Harness green: `cd git-changes/harness && GOFLAGS=-mod=mod GOPROXY=off go run .`
- Extension version stays `1.7.0` (pending release, no bump).
