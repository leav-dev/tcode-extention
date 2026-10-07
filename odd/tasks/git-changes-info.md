# Git Changes: rama + ultimo commit encadenados al status

## Pedido

El `status` automatico (hook onDidSaveBuffer + `alt+shift+g`) muestra rama +
ultimo commit + estado encadenados en una linea. Sin hooks ni comandos
nuevos: costo cero extra (filosofia de pocos recursos).

> Decision (rev 2): primero se probo un comando `info` separado en seccion
> propia; se descarto por redundante y se encadeno todo al `status`.

## Diseno

- Editor (`../tcode`, preview): `GitInfo` gana `CommitHash` (short),
  `CommitSubject`, `CommitAuthor`, `CommitDate` (short). Un solo spawn
  `git log -1 --format=%h%x1f%s%x1f%an%x1f%ad --date=short`, solo dentro del
  `GitStatus()` que ya existe. Sin commits / error -> strings vacias.
  Binding Lua: `commit_hash`, `commit_subject`, `commit_author`,
  `commit_date` (nil-safe: siempre strings, "" si indeterminado).
- Extension: `status()` encadena el commit al scope existente.
  Formato: `Git Changes [main abc1234]: Subject (Author, 2026-10-01) |
  2 files (1 unstaged), +3 -1 lines`. Sin commit -> sin segmento.
  Sin rama -> sin corchete. Backward compatible con editores sin
  estos campos (nil/""). Helper `fileSummary()` compartido.
- Version 1.4.0 -> 1.5.0 (nueva capacidad = minor).

## Tareas

1. Editor: campos + binding + `getLastCommit()` + test `TestGitStatusCommit`.
2. Extension: commit encadenado en `status()` + `fileSummary()` compartido,
   sin comandos nuevos, bump.
3. Harness: casos status con commit completo / parcial / sin commit /
   editor viejo /
   sin-buffer. READMEs. Repro + `go test` + harness en verde.

## Criterios de aceptacion

- [ ] `tcode.git.status()` expone commit_*; repo sin commits no rompe.
- [ ] `info` y `status` coexisten sin pisarse; `info` no corre en hooks.
- [ ] Harness en verde, Lua puro, mensajes en ingles.
- [ ] Sin commits (reportar y ofrecer, como siempre).
