# Undefined Variables (`tcode.undefinedvars`)

Scope analysis extension for tcode: flags identifiers used but never defined
in **Go, JS/TS (Angular) and Python**, severity `warning` (gutter `?`, amber).
Part of the linter trio: [Error Detector](../error-detector/) (balance) and
[Unused Imports](../unused-imports/) run independently and the editor merges
their markers (per-provider diagnostics).

## Installation

```sh
tcode --install-extension <path>/undefined-vars
```

## Behavior

| Trigger | Action |
| --- | --- |
| On save (`onDidSaveBuffer`) | Runs `check()` and publishes warnings to gutter |
| `alt+shift+v` | On-demand check |

**Note:** This extension does not write to the status bar. It only publishes diagnostics to the gutter.

Go runs **package-wide**: same-file declarations are order-independent and
sibling `.go` files of the same `package` clause are scanned via
`tcode.dir_files()` (the editor provides them, capped). HTML/Docker are not
analyzed by this extension (no scope rules for them in v1).

## Notes and limits (v1)

- Definitions: go `var/const/type` (single + block), `:=`, funcs/methods with
  receiver, params + named returns, imports (aliased; dot imports disable
  undefined checks); js/ts `let/const/var` (with simple destructuring),
  functions/classes/arrows, import bindings; py any assignment, `def`/`class`,
  `import`/`from`, lambda/for/with-as params.
- Selector/member access checks only the base (`pkg.Fn` → `pkg`); properties
  after calls (`get().prop`) are not variables.
- py uses a single file scope (no indentation); forward references in py can
  warn. TS generics (`<T>`, constraints, generic classes/methods/arrows)
  are supported; JSX markup in `.tsx` still flags (no tag awareness).
- Every message is English. The config tables build lazily per language
  (RAM-min).