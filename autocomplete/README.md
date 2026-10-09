# Autocomplete (`tcode.autocomplete`)

Buffer-word completion for tcode: completes the word under the cursor from
the words found in the open buffer. Manual trigger (`ctrl+space`) plus a
pure `suggest()` provider for editors with ghost completion
(`contributes.suggest`).

## Installation

```sh
tcode --install-extension <path>/autocomplete
```

## Behavior

| Trigger | Action |
| --- | --- |
| `ctrl+space` | Run `complete()`: insert the longest common extension of the candidates |
| Ghost (editor with support) | Editor calls `suggest()` after a typing pause and shows the top candidate dimmed; `Tab` accepts, `Escape` dismisses |

`complete()` reads the cursor (1-indexed line/col) via `tcode.cursor()`,
extracts the `[A-Za-z0-9_]+` prefix before the cursor from `tcode.line()`,
collects candidate words from `tcode.buffer()` that start with the prefix
(case-sensitive, longer than the prefix, exact prefix excluded, deduplicated),
sorts them by frequency (descending) then alphabetically, and:

- inserts the longest common suffix beyond the typed prefix via
  `tcode.insert(suffix)` when the candidates share an extension;
- when they diverge immediately (no shared extension), inserts nothing and
  shows up to 5 candidates with the total count instead.

The script is stateless (no completion cycle state) and validates that the
cursor line/col are integers, rejecting fractional or NaN positions with
`Autocomplete: invalid cursor position`. It never touches diagnostics.

`suggest()` shares the candidate ranking with `complete()` (frequency then
alphabetical) but is pure: it returns at most 32 words, never inserts or
messages. Empty table means no suggestion. Editors without
`contributes.suggest` support ignore the manifest key and keep working with
`ctrl+space` only.

## Limitation

This extension requires the `tcode.cursor()` editor API (line, col,
1-indexed). Until the editor provides it, `complete()` shows an English
message (`Autocomplete: editor cursor API (tcode.cursor) is not available`)
and does nothing. The harness mocks `tcode.cursor`, so `go run .` is green
either way.

## Examples

Buffer `foobar foobaz` with cursor after `foo`:

- candidates: `foobar`, `foobaz`;
- common extension: `ba`;
- `complete()` inserts `ba`.

Buffer `foobar fizz` with cursor after `f`:

- candidates diverge (`foobar`, `fizz`, common prefix is `f` itself);
- `complete()` inserts nothing and shows
  `Autocomplete: 2 candidates for 'f': fizz, foobar`.

Buffer `test test test team text` with cursor after `te`:

- candidates by frequency then alphabetically: `test, team, text`;
- they diverge, so `complete()` shows
  `Autocomplete: 3 candidates for 'te': test, team, text`.

## Development

A gopher-lua harness lives in [`harness/`](harness/) and mirrors the tcode
host (a `tcode.*` stub for `buffer`/`line`/`lineCount`/`insert`/`message`/
`cursor`, then runs the global `complete()`). Run it with:

```sh
cd harness && go run .
```

It prints one line per case and exits non-zero on any failure. Add a case to
`cases` when you add behavior or fix a regression.
