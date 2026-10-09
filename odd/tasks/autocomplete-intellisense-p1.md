# autocomplete intellisense fase 1 (1.1.1 -> 1.2.0)

## Goal
Ghost con pinta de Intellisense sin tocar el editor: miembros de `this.`,
palabras de imports relativos y ranking con tramo fuzzy. Fase 2 (popup con
lista, API de proyecto) queda para el repo tcode.

## Contract
- `suggest()` pura: mismo-file (freq) + miembros (contexto `this.`/`self.`)
  + archivos de imports relativos vía `tcode.read_file` (pcall, máx 8
  intentos; sin la API en editores viejos se degrada a mismo-file) +
  hermanos Go vía `tcode.dir_files` si existe. Sin `read_file`, sin imports.
- Detección de contexto: el char previo al prefijo es `.` y previo a ese
  `this` (js/ts) o `self` (py) en la línea del cursor.
- Miembros (heurística documentada, puede sobre-aproximar; el fantasma
  requiere Tab así que un falso candidato se ve antes de aplicarse):
  `this.X =`/`self.X =` (exacto), `constructor(private X` (seguro),
  nombres a inicio de línea `mod* name [:=(<(]` (métodos/fields).
- Ranking: 1) miembros con prefijo (alfa), 2) mismo-file con prefijo
  (freq, alfa), 3) otros-archivos con prefijo (freq, alfa), 4) fuzzy
  subsecuencia sobre el pozo (score 100 - gaps*5 - firstIndex, alfa).
  Tope 32 total, best-first. `complete()` reusa el pozo (mismo LCP).
- Lua puro, sin io/os/require, global suggest()/complete(), mensajes en
  inglés. Versión minor (nueva capacidad): 1.2.0.

## Acceptance
- Harness verde: casos viejos intactos + imports, members, fuzzy, cap.
- Sin `read_file` (mock ausente) = comportamiento 1.1.x.
- `main.lua` sin cambios salvo lo listado + bump junto (regla AGENTS.md).
