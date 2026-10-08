# tcode-extensions

Extensions for `tcode` (a Go TUI code editor, sibling project in `../tcode`) —
the author's workspaces for the editor's extensions.

tcode's extension system is **declarative**: an extension is a git repo with an
`extension.json` at its root declaring commands, keybindings and buffer hooks.
Extensions run no code yet unless they use the **Lua scripting backend**
(gopher-lua): a declared command can delegate its implementation to a function
of the extension's script via the `tcode.*` table.

**Convention:** all user-facing messages, code comments, READMEs and
repository artifacts are **English**.

## Installing an extension

```sh
tcode --install-extension <git-url-or-local-path>
tcode --list-extensions
tcode --remove-extension <id>
```

Installation clones the repo (depth 1), validates `extension.json` against the
editor's schema and deploys it to `~/.tcode/extensions/<id>/`. Reinstalling
replaces; an invalid manifest is rejected without touching anything.

This workspace is a **monorepo**: each extension lives in its own subfolder
with its `extension.json` at that subfolder's root. To install from it, point
the CLI at the subfolder, e.g. `tcode --install-extension
<path>/tcode-extentions/error-detector` (or a git URL of that subfolder). A
future catalog/install-by-id milestone may let the CLI resolve extensions
from this repo directly.

## Catalog

| Extension | Id | What it provides |
| --- | --- | --- |
| [vim-lite](vim-lite/) | `tcode.vimlite` | Vim muscle-memory keybindings: tabs (`alt+h`/`alt+l`), explorer (`alt+e`), save (`alt+w`), save as (`alt+shift+w`) |
| [emacs-lite](emacs-lite/) | `tcode.emacslite` | Emacs-style `ctrl+x …` chords: switch buffer, explorer, kill buffer, undo |
| [error-detector](error-detector/) | `tcode.errordetector` | **Error Detector**: bracket balance `() [] {}` with string awareness (severity `error`) — small, language-agnostic script |
| [undefined-vars](undefined-vars/) | `tcode.undefinedvars` | **Undefined Variables**: scope analysis for Go/JS/TS/Python (warning), package-wide in Go (sibling files) |
| [unused-imports](unused-imports/) | `tcode.unusedimports` | **Unused Imports**: import bindings never used (warning), incl. type-only usage in TS |
| [git-changes](git-changes/) | `tcode.gitchanges` | **Git Changes**: status summary in status bar (branch + files + lines), gutter markers for added/deleted/modified lines |
| [angular8-lint](angular8-lint/) | `tcode.angular8lint` | **Angular 8 Lint**: flags post-v8 syntax (standalone, signals, native control flow, `input()`/`output()`, `@defer`) as `error` |
| [angular21-lint](angular21-lint/) | `tcode.angular21lint` | **Angular 21 Lint**: flags legacy patterns (`NgModule`, `@Input`/`@Output`, `*ngIf`/`*ngFor`, View Engine) as `warning`/`error` |
| [data-lint](data-lint/) | `tcode.datalint` | **Data Lint**: syntax + structure for YAML/JSON/XML (duplicate keys as `warning`, broken syntax as `error`) |
| [autocomplete](autocomplete/) | `tcode.autocomplete` | **Autocomplete**: buffer-word completion (`alt+space`), longest common extension or candidate list |

The linter trio replaces the former unified Code Linter; the editor **merges** the markers of every extension (per-provider diagnostics). Each extension is its own git repo with its README and manifest.

<!-- The autosave (tcode.autosave) was retired: the behavior becomes a native
     editor setting. It lives on in the declarative-batch-1 feature history. -->

## Status and roadmap

- **Lua scripting is already in the editor**: tcode implements the backend
  that lets declarative extensions **run their own logic** with gopher-lua
  (no cgo), plus **per-buffer diagnostics** with a gutter and the
  `tcode.diagnostics.set/clear` Lua API.
- **Linter trio implemented** on top of scripting + multi-provider
  diagnostics (Error Detector / Undefined Variables / Unused Imports; feature
  in `odd/tasks/linter-scope.md`); next candidates: formatter on save, status
  bar widgets and git integration as real-Lua extensions.
- Snippets, grammars and declarative themes (editor milestone "language
  contributions").
- The editor's own UI messages and docs are still Spanish: unifying them to
  English is a core pass in tcode, not an extensions task.