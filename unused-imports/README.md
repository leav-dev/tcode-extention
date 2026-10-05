# Unused Imports (`tcode.unusedimports`)

Import detector for tcode: import bindings never used in **Go, JS/TS
(Angular) and Python**, severity `warning` (gutter `?`, amber). Part of the
linter trio: [Error Detector](../error-detector/) (balance) and
[Undefined Variables](../undefined-vars/) run independently and the editor
merges their markers (per-provider diagnostics).

## Installation

```sh
tcode --install-extension <path>/unused-imports
```

## Behavior

| Trigger | Action |
| --- | --- |
| On save (`onDidSaveBuffer`) | Runs `check()` and publishes warnings to gutter |
| `alt+shift+i` | On-demand check |

**Note:** This extension does not write to the status bar. It only publishes diagnostics to the gutter.

## What counts as "used"

- go: selector use (`fmt.Println`), alias use (`f.Println`), blank imports
  (`_ "x"`) and dot imports (`. "x"`) are never reported; keywords as path
  segments are ignored.
- js/ts: any identifier occurrence of the binding, including **type-only**
  usage (`let c: Config`, `(x: Item)`, `): MyType`).
- py: `import x` / `from x import y` bindings referenced anywhere; `as`
  renames.

Imports are per-file: only the active buffer is analyzed (no cross-file
needed). Every message is English; the config tables build lazily per
language (RAM-min).