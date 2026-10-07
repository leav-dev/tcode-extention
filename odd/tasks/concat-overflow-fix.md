# Fix: registry overflow en table.concat (todas las extensiones)

## Reporte

Editor vivo, hook `tcode.unusedimports.check` reventando en cada save con
`registry overflow` + traceback en la barra, editando
`pedido.component.ts` (Angular, 86KB). Reproducido con el `main.lua` real.

## Causa raiz

`table.concat` en gopher-lua pushea cada elemento al registry (tope fijo).
`maskContent` (unused-imports) arma UNA entrada por caracter y concatena de
una: cualquier archivo > ~5KB revienta. Detonante: `./pedido-flujo` (6.9KB)
leido por direccion 2 via `tcode.read_file`. El harness nunca lo vio:
fixtures chicos + direccion 2 solo corre en el editor real.

`python-lint` ya habia sufrido el mismo bug y lo fijo con `joinChunks`
(lotes de 400). Este cambio lleva ese patron a los sitios sin proteccion.

## Sitios (todos per-char + concat sin batch)

- unused-imports: `maskContent` (archivo entero, el crash), `maskSeg` (por
  linea: lineas larguisimas), `ups` en resolvePyModule (puntos lideres).
- angular8-lint / angular21-lint: `maskLine` (por linea).
- data-lint: `stripSpans` (por linea).
- Fuera de alcance (acotados, se dejan): specparts/parts/path segs,
  git-changes (3 items), python-lint (ya tiene joinChunks).

## Plan por extension

1. Agregar helper `joinChunks` puro Lua (copia del de python-lint).
2. Reemplazar el `table.concat` del sitio.
3. Bump patch (bug fix, sin checks nuevos).
4. Caso de regresion en el harness con input grande (falla antes, pasa
   despues). unused-imports: fixture .ts >8KB con exports + import que lo
   persigue; resto: linea larga >8KB.
5. Harness en verde.

Bumps: unused-imports 1.1.0->1.1.1, angular8 1.0.0->1.0.1,
angular21 1.0.0->1.0.1, data-lint <ver>+patch.

## Criterios de aceptacion

- [ ] Repro con pedido.component.ts real: check() sin error.
- [ ] Los 4 harnesses en verde con casos grandes nuevos.
- [ ] main.lua puros (sin io/os/require), mensajes en ingles.
- [ ] Sin commits (reportar y ofrecer).
