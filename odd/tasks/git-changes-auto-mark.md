# Git Changes: auto-mark on save

## Goal

Gutter marks are the standard, frequently used guide. Saving a buffer should
refresh both the status bar summary and the gutter marks in one step.

## Decision

The `onDidSaveBuffer` hook now runs `tcode.gitchanges.all` (status plus mark
together) instead of `tcode.gitchanges.status` alone. Manifest-only change —
`all()` already composes `status()` + `mark()`, and `mark()` keeps the toggle
state consistent (`visible = true` on show, `visible = false` on empty diff),
so no Lua change was needed. Version `1.6.0` → `1.7.0` (minor: new capability).

By design, saving re-shows marks even after a manual toggle-off: marks are on
by default.

## Acceptance

- [ ] `extension.json` hook runs `tcode.gitchanges.all`; version is `1.7.0`
- [ ] Harness green (`cd git-changes/harness && GOFLAGS=-mod=mod GOPROXY=off go run .`),
      including the existing `all runs status and mark` regression case
- [ ] README documents the new hook behavior and the toggle-off re-show
