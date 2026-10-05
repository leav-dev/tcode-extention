# Error Detector (`tcode.errordetector`)

Bracket balance extension for tcode: correlates `() [] {}` with string
awareness, severity `error` (gutter `!`, red). Part of the linter trio —
[Undefined Variables](../undefined-vars/) and [Unused Imports](../unused-imports/)
run independently and the editor merges their markers (per-provider
diagnostics).

## Installation

```sh
tcode --install-extension <path>/error-detector
```

## Behavior

| Trigger | Action |
| --- | --- |
| On save (`onDidSaveBuffer`) | Runs `check()` and publishes errors |
| `alt+shift+e` | On-demand check |

Detects: `'(' never closed`, `'}' without opening`, `'X' does not match 'Y'`,
`unterminated string (delimiter 'X')`. Strings (`"`, `'`, `` ` `` with `\`
escapes) are ignored. Works on any language (HTML/Docker included).

Every message is English. This script is intentionally small (~90 lines,
language-agnostic, no tables) — the RAM-min member of the trio.