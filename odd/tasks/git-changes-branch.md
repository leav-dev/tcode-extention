# Git Changes: show current branch

## Objetivo

Mostrar la rama actual en la seccion de status bar de `tcode.gitchanges`,
sin agregar timers, hooks nuevos ni procesos en paralelo: la rama se lee
con un `git` barato dentro del `GitStatus()` que ya corre en `onDidSaveBuffer`
y por keybinding manual. Cero costo cuando no se usa.

## Alcance (dos repos)

- `../tcode` (editor, branch `preview`): `ext.GitInfo.Branch` + binding Lua
  `tcode.git.status().branch` + implementacion + test Go.
- `git-changes/` (este repo, branch `main`): `status()` muestra la rama,
  version bump 1.3.0 -> 1.4.0 (nueva capacidad = minor), harness nuevo con
  regresiones, README al dia.

Quedo descartado (a pedido): blame de la linea con idle de 10s en paralelo.
Motivo: Lua es puro (sin io/os/timers), el editor no expone cursor ni blame
ni hook idle; hacerlo bien implicaria superficie nueva en el editor que va en
contra de la idea de pocos recursos.

## Diseno

- `GitStatus()` agrega UN spawn: `git branch --show-current`.
  Vacio (detached HEAD) -> fallback `git rev-parse --short HEAD`.
  Si todo falla -> `Branch == ""` y la extension omite la rama.
- Lua: `t.RawSetString("branch", ...)` junto a staged/untracked/added/deleted.
- Extension `status()` (backward compatible con editores viejos sin `branch`):
  - `Git Changes [main]: clean working tree`
  - `Git Changes [main]: 3 files (1 staged, 2 unstaged), +15 -8 lines`
  - Sin rama (nil/"") -> formato anterior sin corchetes.
  - `not a git repository` / `no active buffer` sin cambios.
- Mensajes al usuario en ingles (convencion del repo).

## Tareas

1. Editor: `Branch` en `GitInfo`, binding Lua, `getBranch()` en
   `controller/git_status.go`, test `TestGitStatusBranch` (+ detached).
2. Extension: `status()` con rama y fallback.
3. `extension.json` 1.4.0 + `git-changes/harness/` (mock de
   `tcode.buffer`/`tcode.git.status`/`tcode.statusBar.setSection`) con casos:
   rama+clean, rama+cambios, sin rama (compat), sin buffer, no-repo.
4. README de la extension (formato con rama) + catalogo del root si aplica.
5. Verificar: `go test ./internal/...` en tcode (paquetes tocados) y
   `cd git-changes/harness && GOFLAGS=-mod=mod GOPROXY=off go run .`.

## Criterios de aceptacion

- [ ] `tcode.git.status().branch` devuelve la rama en repo normal.
- [ ] Detached HEAD muestra SHA corto; repo sin commits no rompe.
- [ ] La barra muestra `[rama]`; editores viejos (sin campo) siguen andando.
- [ ] Harness en verde, `main.lua` sigue puro (sin io/os/require).
- [ ] Sin commits: se reporta y se ofrecen (un commit por repo).
