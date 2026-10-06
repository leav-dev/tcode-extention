# AGENTS.md — tcode-extention conventions

Read this before touching any extension in this monorepo.

## Version bump (mandatory)

`tcode` detects extension updates **by comparing manifest versions only**.
Any behavior change in an extension that ships without a version bump
never reaches installed users.

Rules:

1. Every change to `<ext>/main.lua` (or its commands, keybindings, hooks)
   MUST bump `<ext>/extension.json` → `version` in the same commit.
2. Bug fixes bump the patch number (`1.0.4` → `1.0.5`).
   New checks or capabilities bump the minor (`1.1.0` → `1.2.0`).
3. New extensions start at `1.0.0`; no bump needed on creation.
4. Never batch a bump "for later" — the behavior change and its bump
   ship together or the change is invisible.

## Definition of done for an extension change

- `main.lua` stays pure Lua (no `io`/`os`/`require`), global `check()`,
  1-indexed diagnostic lines, all user-facing messages in English.
- Non-target files are a no-op: return WITHOUT touching diagnostics.
- The extension's `harness/` runs green:
  `cd <ext>/harness && GOFLAGS=-mod=mod GOPROXY=off go run .` → 0 failures.
- New behavior adds regression cases to the harness.
- `README.md` documents new checks; root `README.md` catalog stays accurate.
