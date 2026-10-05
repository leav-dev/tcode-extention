# Error Detector (`tcode.errordetector`)

Bracket balance + HTML tag balance extension for tcode: correlates `() [] {}`
and HTML tags with string/comment awareness, severity `error` (gutter `!`, red).
Part of the linter trio — [Undefined Variables](../undefined-vars/) and
[Unused Imports](../unused-imports/) run independently and the editor merges
their markers (per-provider diagnostics).

## Installation

```sh
tcode --install-extension <path>/error-detector
```

## Behavior

| Trigger | Action |
| --- | --- |
| On save (`onDidSaveBuffer`) | Runs `check()` and publishes errors |
| `alt+shift+e` | On-demand check |

**Bracket balance:** `'(' never closed`, `'}' without opening`,
`'X' does not match 'Y'`, `unterminated string (delimiter 'X')`.
Strings (`"`, `'`, `` ` `` with `\` escapes) are ignored.

**HTML tags:** `'<div>' never closed`, `'</span>' without opening tag`,
`'</p>' closes '<div>'`, `HTML comment never closed`. Self-closing tags
(`<br>`, `<img>`, `<input>`, etc.) are recognized. Comments (`<!-- ... -->`)
and attribute strings are ignored.

Every message is English. This script is intentionally compact,
language-agnostic, no tables — the RAM-min member of the trio.