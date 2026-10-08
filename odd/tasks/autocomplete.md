# Autocomplete (buffer words)

## Goal
Word-based autocompletion for tcode using only the current buffer words.
Trigger: manual keybinding (no onDidChangeText by editor design, no popup API yet).

## Scope (agreed)
- Type: `Palabras del buffer` — complete word under cursor from words in open buffer.
- Out of scope: IDE popup, LSP, snippets, per-language keywords (future extensions).

## Technical constraint (found in exploration)
- Current `ScriptAPI` (`internal/ext/script.go`) exposes: `buffer()`, `line(n)`, `lineCount()`, `insert(text)` — but NO cursor position.
- Without cursor line/col, Lua cannot know the prefix to complete.
- Decision: extension targets `tcode.cursor()` + `tcode.line()` combo:
  - `complete()` reads cursor (1-indexed line/col, to be added in tcode editor), extracts prefix `[A-Za-z0-9_]+` before cursor from `tcode.line()`, collects candidates from `tcode.buffer()` words, picks longest common extension or cycles, inserts suffix via `tcode.insert()`.
  - If `tcode.cursor` missing (current editor), show English message and no-op (graceful degradation). Harness mocks `cursor`.
- Editor change required (small, separate repo `../tcode`): add `Cursor() (line, col int, ok bool)` to `ScriptAPI` + `tcode.cursor` binding. Not done here.

## Artifacts
- `autocomplete/extension.json` — id `tcode.autocomplete`, v1.0.0, command `tcode.autocomplete.complete` fn `complete`, keybinding `alt+space`, activation onStartup.
- `autocomplete/main.lua` — pure Lua, global `complete()`, English messages.
- `autocomplete/harness/` — Go harness mocking `tcode.{buffer,line,lineCount,insert,message,cursor}`, `go run .` green.
- `autocomplete/README.md` + root `README.md` catalog row.

## Acceptance
- `cd autocomplete/harness && GOFLAGS=-mod=mod GOPROXY=off go run .` → 0 failures.
- Pure Lua (no io/os/require), non-target behavior sane, English messages.
- Root README catalog accurate.

## Tasks
1. Diseñar alcance (this file) — done when worker starts.
2. Implementar extensión (worker: surfaces below).
3. Harness verde + docs y catálogo (worker, same commit scope).

## Evidence
- Commit tagged `autocomplete-v1.0.0` — feat(autocomplete): buffer-word completion with alt+space (8 files).
- Tag `autocomplete-v1.0.0` (lightweight, per-extension convention; matches manifest v1.0.0).
- Harness: 9 cases, 0 failures.
