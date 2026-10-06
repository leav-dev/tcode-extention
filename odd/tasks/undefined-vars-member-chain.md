# Fix: undefined-vars flags `obj.ATTR,` as undefined

## User report (Django, Python)
- `'status': status.HTTP_200_OK,` -> warns `undefined 'HTTP_200_OK'` (should only check base `status`, defined via `from rest_framework import status`).
- `'grupo_id': snap.grupo_id,` -> warns `undefined 'grupo_id'` (should only check base `snap`).
- `from .models import (A, B, ...)` parenthesized multiline import defines nothing (separate bug, same file, do NOT fix in this change — no-goal).

## Root cause (traced in analyzeScope, undefined-vars/main.lua)
For `status.HTTP_200_OK,`:
1. Base `status` is preceded by `:` (dict value) so it takes the `isSym(i-1, ":")` annotation-skip branch and never consumes the `.chain` via the member-chain logic.
2. `.` falls to generic sym handling, so `HTTP_200_OK` is visited standalone.
3. `HTTP_200_OK` is followed by `,` so the `isSym(i+1, ",")` multi-target-decl lookahead branch fires BEFORE the `isSym(i-1, ".")` member-selector skip, and since `HTTP_200_OK` is never defined, it reports `undefined 'HTTP_200_OK'`.

## Fix
In `analyzeScope` main loop, check `isSym(i-1, ".")` (member selector, skip) before the `isSym(i+1, ",")` multi-target-decl branch, for all languages (or at minimum py). No other reordering. Keep Go/JS/TS behavior intact (harness must stay green).

## Verification
- `undefined-vars/harness`: add regression cases:
  - py: `from rest_framework import status` + dict `{'status': status.HTTP_200_OK,}` -> no findings.
  - py: `for snap in snaps:` + `{'grupo_id': snap.grupo_id,}` -> no findings.
  - py: true undefined still flags (`foo.bar,` with no def -> `undefined 'foo'`).
- Run `cd undefined-vars/harness && GOFLAGS=-mod=mod GOPROXY=off go run .` -> 0 failures.
- No-goals: parenthesized from-import, comprehension scope, dict `{}` scope push — untouched.

## Tasks
1. [x] Feature doc + root cause.
2. [x] Reorder branches in `undefined-vars/main.lua`.
3. [x] Harness regression cases + green run (43/43).
4. [x] Verified + closed (verify agent, Django-like snippet clean).
