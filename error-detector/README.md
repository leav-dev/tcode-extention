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

## Language detection

`detectLanguage(path)` maps the buffer extension to a language, consistent with
the sibling extensions:

| Language | Extensions |
| --- | --- |
| `html` | `.html`, `.htm`, `.xhtml`, `.svg` |
| `go` | `.go` |
| `ts` | `.js`, `.jsx`, `.mjs`, `.cjs`, `.ts`, `.tsx`, `.mts`, `.cts` |
| `py` | `.py`, `.pyw` |
| `nil` | anything else (unknown) |

Checks are grouped in two sets:

- **Universal checks** run on every buffer, regardless of language:
  `balanceCheck` (`() [] {}` and strings).
- **Per-language checks** run only when `detectLanguage` matches:
  `html` → `htmlTagCheck`. The `go`, `ts` and `py` entries are reserved and
  currently empty; add a function to `checksByLang[lang]` to extend a language.

## Checks

**Bracket balance** (all files): `'(' never closed`, `'}' without opening`,
`'X' does not match 'Y'`, `unterminated string (delimiter 'X')`.
Strings (`"`, `'`, `` ` `` with `\` escapes) are ignored.

**HTML tags** (HTML files only):
- Unclosed tags: `'<div>' never closed`
- Mismatched tags: `'</span>' without opening tag`, `'</p>' closes '<div>'`
- Malformed tags: `Empty tag '<>'`, `Empty closing tag '</>'`, `Malformed tag: space after '<'`, `Malformed tag: space after '</'`, `Invalid tag name '<123>'`, `Tag '<div>' never closed`
- Malformed attributes: `Attribute 'class' without value`, `Duplicate attribute 'id'`, `Attribute 'class' has an unterminated value`
- DOCTYPE issues: `Duplicate <!DOCTYPE> declaration`, `<!DOCTYPE> must be the first element`, `<!DOCTYPE> must contain 'html'`, `<!DOCTYPE> never closed`
- Comments: `HTML comment never closed`

Self-closing tags (`<br>`, `<img>`, `<input>`, etc.) are recognized.
Comments (`<!-- ... -->`) and attribute strings are ignored.

Every message is English. This script is intentionally compact,
language-agnostic, no tables — the RAM-min member of the trio.
