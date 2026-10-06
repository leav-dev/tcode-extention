# Data Lint (`tcode.datalint`)

Syntax + structure lint for tcode: JSON, YAML and XML in a single extension.
Severity `error` for broken syntax/structure (gutter `!`, red) and `warning`
only for duplicate keys (gutter `?`, amber). Only `.json`, `.yml`/`.yaml`
and `.xml`/`.xsl`/`.xsd` buffers are analyzed; any other file (including
`.svg`, `.html`, `.go`, `.py`) is a no-op that never touches diagnostics.
Runs independently of [Error Detector](../error-detector/) and
[Python Lint](../python-lint/) — the editor merges their markers
(per-provider diagnostics).

## Installation

```sh
tcode --install-extension <path>/data-lint
```

## Behavior

| Trigger | Action |
| --- | --- |
| On save (`onDidSaveBuffer`) | Runs `check()` and publishes findings to gutter |
| `alt+shift+d` | On-demand check |

**Note:** This extension does not write to the status bar. It only publishes diagnostics to the gutter.

## What it detects

**JSON** (string-aware scanner, no decode library in the Lua sandbox)

- `unterminated string` (error).
- `'{' never closed` / `'[' never closed` — unclosed bracket at EOF (error).
- `'}' does not match ...` — mismatched bracket (error).
- `'}' without opening` / `']' without opening` (error).
- `missing comma between members` (error).
- `trailing comma` (error).
- `missing ':' after object key` / `unexpected ':'` (error).
- `single-quoted strings are not allowed in JSON, use double quotes` (error).
- `comments are not allowed in JSON` / `unclosed comment in JSON` (error).
- `unexpected character 'x'` (error).
- `duplicate key "x" in the same object` (warning).

**YAML** (line model, 1-indexed; blank and comment lines skipped)

- `tabs are not allowed for indentation, use spaces` (error).
- `mixed tabs and spaces in indentation` (error).
- `inconsistent indentation` — a dedent that lands on no known level (error).
- `mapping values require ':' between key and value` — `key value` without
  a colon (error).
- `unterminated quoted string` (error).
- `duplicate key "x" at the same level` (warning).
- Block scalar headers (`key: |`, `key: >`, with chomping/indent flags)
  consume the following more-indented lines.

**XML** (strict, case-sensitive tag correlator)

- `'</x>' does not match '<y>'` — mismatched close (error).
- `'</x>' without opening tag` (error).
- `'<x>' never closed` — unclosed open at EOF (error).
- `tag '<x>' never closed` — `>` missing (error).
- `malformed tag` / `malformed tag: space after '</'` /
  `malformed tag: space after '<'` / `invalid tag name '<x>'` (error).
- `duplicate attribute 'x'` (error).
- `unterminated attribute value for 'x'` (error).
- `attribute 'x' without value` / `attribute 'x' must have a quoted value`
  — XML requires quoted values (error).
- `comment never closed` / `CDATA section never closed` /
  `processing instruction never closed` / `<!DOCTYPE> never closed` (error).
- `multiple root elements` (error).
- `content outside root element` — non-whitespace text outside the root (error).

Every message is English.

## Honest limits

- No schema validation: no JSON-Schema, XSD or DTD resolution.
- No YAML anchors/aliases/merge-key resolution; duplicate-key detection is
  per indent level, not per semantic map.
- YAML is indentation-based: deep nesting errors may cascade and only the
  first bad line is reported.
- JSON duplicate-key comparison is structural on the raw key text (minimal
  escape normalization).
- XML entities (`&amp;`, ...) are not resolved; only structure is checked.
- `.svg` files stay with [Error Detector](../error-detector/) (HTML mode)
  on purpose — data-lint ignores them to avoid double diagnostics.

This script is intentionally compact: three small scanners over the buffer
content, no dependencies (RAM-min).
