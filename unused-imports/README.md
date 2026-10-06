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
  usage (`let c: Config`, `(x: Item)`, `): MyType`). Method params, `catch`
  bindings, overload signatures and generic type params all count.
- py: `import x` / `from x import y` bindings referenced anywhere; `as`
  renames (only the local name is tracked).

Every message is English; the config tables build lazily per
language (RAM-min).

## Two directions

This extension validates imports both ways:

1. **Unused** (`warning`): a binding never used in the file —
   `unused import 'x'`.
2. **Unresolvable** (`error`): a binding that does not exist in the source
   module — `unresolved import 'foo' from './bar'`. This catches version
   drift (importing something the installed version no longer exports).

Direction 2 only covers **relative file imports** (JS/TS `./x`, Python
`from .y import z`), resolved through `tcode.read_file` (needs a recent
editor; older ones silently keep direction 1). Everything else stays
silent by design: bare specifiers (`react`), stdlib (`os`), path aliases,
parent escapes, `import *`, `require()`, and all Go imports (package
paths belong to the compiler). A missing relative code file is itself
reported; explicit non-code extensions (`.json`, `.css`) are skipped.
Re-exports (`export *`, `export {a} from`) are chased (depth 4, cycle-safe).

## Development

A gopher-lua harness with fixture modules lives in [`harness/`](harness/)
(`testdata/`). Run it with:

```sh
cd harness && go run .
```