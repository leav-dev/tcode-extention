# Feature: Data Lint — validator for YAML / JSON / XML

## User request
New extension for yml, json and xml (single extension).

## Product decisions (answered)
- **Single extension**: folder `data-lint/`, id `tcode.datalint`, name "Data Lint",
  command `tcode.datalint.check`, keybinding `alt+shift+d`, hook `onDidSaveBuffer`.
- **Scope v1: syntax + structure** (not style-only):
  - JSON: invalid syntax (brackets, quotes, commas, trailing comma, comments,
    single-quoted strings, missing/extra colon), duplicate keys (warning).
  - YAML: tabs in indentation (error), inconsistent indent step, mixed tabs/spaces,
    bad mapping (`key value` without colon), duplicate keys in same map (warning),
    unterminated block scalar / quoted string.
  - XML: reuse structural idea from error-detector htmlTagCheck but strict XML:
    mismatched/unclosed tags, malformed tags/attrs, duplicate attrs, unclosed
    comment/CDATA/PI, multiple roots (error).
- **Other files**: no-op, never touch diagnostics (consistent with python-lint).
- **Messages**: English (project convention).
- **No status bar**: only `tcode.diagnostics.set/clear` (per-provider).

## Editor API
- `tcode.buffer()` -> `path, content`.
- `tcode.diagnostics.set({line, message, severity})` 1-indexed; `clear()` per-provider.

## Technical spec
- `detectLang(path)`: `.yml/.yaml` -> yaml, `.json` -> json, `.xml/.xsl/.xsd/.svg`? NO svg stays html. Only `.xml/.xsl/.xsd`.
  Note: `.svg` already claimed by error-detector as html — data-lint ignores `.svg` to avoid double diagnostics.
- JSON: hand scanner with string awareness (no decode lib in Lua sandbox).
  Track stack of `{closer, line}`, string state, line numbers. Detect:
  `trailing comma`, `missing comma between members`, `missing colon`, `single-quoted string`,
  `comment not allowed in JSON`, `unterminated string`, `unclosed bracket`, `duplicate key` (map-level key set).
- YAML: line model: indent prefix, blank/comment lines skipped, block scalar `|`/`>` handling,
  quote state per line. Checks: tab indent, mixed indent, inconsistent step, `mapping without colon`,
  duplicate keys at same indent level, unterminated quoted scalar.
- XML: strict tag correlator: open/close stack case-sensitive, self-closing `<x/>`,
  `<?...?>` PI, `<!--...-->` comments, `<![CDATA[...]]>`, `<!DOCTYPE...>` single.
  Errors: mismatch, unclosed, malformed, duplicate attr, unterminated value, multiple roots, text outside root.

## Output
`{line, message, severity}` sorted by line. `error` for broken syntax/structure,
`warning` only for duplicate keys. Empty -> `clear()`.

## Limits v1 (honest)
- No schema validation (no XSD/JSON-Schema), no YAML anchors/merge-key resolution.
- YAML is indentation-based: deep nesting errors may cascade to first bad line.
- JSON duplicate-key detection is structural, not semantic (escaped keys normalized minimally).

## Verification plan
1. Harness `data-lint/harness/` (Go + gopher-lua, same pattern as error-detector):
   JSON valid/invalid/trailing-comma/comments/single-quote/dup-key;
   YAML valid/tab/mixed/no-colon/dup-key/block-scalar;
   XML valid/mismatch/unclosed/dup-attr/multi-root/comment-unclosed;
   non-target file (.go) -> no-op.
2. E2E: `tcode --install-extension <path>/data-lint` + list.
3. Manual: open .json/.yml/.xml broken -> red `!` in gutter.

## Tasks
1. [x] Feature doc + decisions + memory mirror.
2. [x] Implement `data-lint/extension.json` + `data-lint/main.lua`.
3. [x] Write `data-lint/README.md`.
4. [x] Harness with cases, 0 failures (24 cases, verified).
5. [ ] E2E install + commit + close (tcode binary present, install pending user decision).
