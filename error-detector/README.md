# Error Detector (`tcode.errordetector`)

Bracket balance + HTML tag validation extension for tcode: correlates `() [] {}`
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
| On save (`onDidSaveBuffer`) | Runs `check()` and publishes errors to gutter |
| `alt+shift+e` | On-demand check |

**Note:** This extension does not write to the status bar. It only publishes diagnostics to the gutter.

**Bracket balance:** `'(' never closed`, `'}' without opening`,
`'X' does not match 'Y'`, `unterminated string (delimiter 'X')`.
Strings (`"`, `'`, `` ` `` with `\` escapes) are ignored.

**HTML tags** (only on `.html`, `.htm`, `.xhtml`, `.svg` files):
- Unclosed tags: `'<div>' never closed`
- Mismatched tags: `'</span>' without opening tag`, `'</p>' closes '<div>'`
- Malformed tags: `Empty tag '<>'`, `Empty closing tag '</>'`, `Malformed tag: space after '<'`, `Invalid tag name '<123>'`
- Malformed attributes: `Attribute 'class' without value`, `Duplicate attribute 'id'`
- DOCTYPE issues: `Duplicate <!DOCTYPE> declaration`, `<!DOCTYPE> must be the first element`, `<!DOCTYPE> must contain 'html'`, `<!DOCTYPE> never closed`
- Comments: `HTML comment never closed`

Self-closing tags (`<br>`, `<img>`, `<input>`, etc.) are recognized.
Comments (`<!-- ... -->`) and attribute strings are ignored.

Every message is English. This script is intentionally compact,
language-agnostic, no tables — the RAM-min member of the trio.
