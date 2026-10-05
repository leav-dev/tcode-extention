# Python Lint (`tcode.pylint`)

Python-specific structure lint for tcode: indentation, block structure and
statement context. Severity `error` for the structural findings (gutter `!`,
red) and `warning` for the advisory one (gutter `?`, amber). Only `.py`
and `.pyw` buffers are analyzed; any other file is a no-op. Runs independently
of [Error Detector](../error-detector/) (balance),
[Undefined Variables](../undefined-vars/) and
[Unused Imports](../unused-imports/) — the editor merges their markers
(per-provider diagnostics).

## Installation

```sh
tcode --install-extension <path>/python-lint
```

## Behavior

| Trigger | Action |
| --- | --- |
| On save (`onDidSaveBuffer`) | Runs `check()` and publishes findings to gutter |
| `alt+shift+p` | On-demand check |

**Note:** This extension does not write to the status bar. It only publishes diagnostics to the gutter.

## What it detects

**Indentation**

- `mixed indentation (tabs and spaces)` — the prefix has both (error).
- `inconsistent indentation (file uses spaces|tabs)` — both styles are used
  in the same file; reported on the lines of the minority style (error).
- `unindent does not match any outer indentation level` — the dedent width
  matches no open level (error).

**Block structure**

- `expected ':' at the end of the line` — compound header (`if`, `elif`,
  `else`, `for`, `while`, `try`, `except`, `finally`, `with`, `def`, `class`,
  `async def/for/with`) with no `:` at depth 0 (error). A `:` inside
  `() [] {}` (dict, slice, annotation, nested lambda) does not count.
- `expected an indented block` — header ends with `:` and no code after it,
  but the next statement is not indented (error).
- `unexpected indent` — indentation grows without a header that opened a
  block (error).

**Statement context**

- `'return' outside function` / `'yield' outside function` (error).
- `'break' outside loop` / `'continue' outside loop` (error).
- `nonlocal declaration outside nested function` (error).
- `global declaration at module level is a no-op` (warning).

Every message is English.

## Honest limits

- No flow analysis: `if False: return` is still validated by context
  (correct for a `SyntaxError`, not for reachability).
- Continuation lines (open `() [] {}`, backslash continuation) and lines
  inside triple-quoted strings are excluded from every indentation and block
  check — Python allows arbitrary indentation there — but they still feed the
  bracket/triple-quote state machine.
- No space checks (tabs after spaces, trailing whitespace, indentation in
  blank lines) and no line-length check: deliberately out of v1. An irregular
  but consistent indent step (e.g. a line indented 6 spaces inside a 4-space
  file) is valid Python and is NOT flagged.
- Continuation is handled as Python does: a backslash-newline joins physical
  lines at the lexical level (including inside single-quoted strings), and a
  triple-quoted string may close and continue a statement
  (`"""...""".format(...)`).
- `match` / `case` are soft keywords: they open a block only when the line
  really ends with `:`; an identifier named `match` never opens one.
- A block header at the end of the file with no body is not reported.
- Unbalanced brackets can desalign the model — that is
  [Error Detector](../error-detector/)'s job, not duplicated here.

This script is intentionally compact: no language tables, just the line
model and the three check families (RAM-min).
