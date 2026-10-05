# Feature: Linter de scope — variables definidas/indefinidas e imports (v1)

## Pedido del usuario

Detectar en el editor: **variables usadas sin estar definidas** y **estado de
los imports** (import sin usar / paquete usado sin importar). Se extiende la
extensión `error-detector` (no se crea otra): pasa a ser un linter
multi-chequeo.

## Decisiones de producto (respondidas)

- **Lenguajes v1:** Go, JS, TS (Angular usa las reglas TS). HTML y Docker:
  solo el detector de balance existente en v1 (sin análisis de scope),
  documentado como límite.
- **Severidad:** TODOS los hallazgos de scope como **warning** (análisis
  heurístico, cauteloso; menos falso-positivo molesto). El balance de
  corchetes Sigue siendo **error** (es estructural, no heurístico).
- **Scope v1:** por función con bloques `{}` anidados para go/js/ts;
  Python lineal de todo el archivo (una sola scope, límite documentado —
  sin indentación v1).
- **Extensión:** se extiende `tcode.errordetector`; se renombra el campo
  `name` del manifest a "Code Linter" (el id no cambia, la instalación y los
  hábitos de las otras extensiones siguen igual).

## Reglas v1 por lenguaje

### Definiciones (qué se define y en qué scope)

| Lenguaje | Definen | Notas |
| --- | --- | --- |
| Go | `var/const/type` (single y bloque `( )`), LHS de `:=`, nombre de `func` + params + named returns + receiver, params de literales/for/if/switch/range/case, nombres de import (`import "x"` → último segmento; alias `import f "fmt"` → `f`) | `=` no define. `import . "x"` → wildcard: se desactivan los avisos de indefinido v1. `_` no se define |
| JS/TS | `let x`, `const x`, `var x`, desestructuración simple `{a, b}` / `[a, b]`, funciones (nombre + params), arrow (params), class + métodos, params de catch/for/of, bindings de import (`import {a} from`, `import a from`, `import * as ns from`; `import "x"` sin binding) | `x = v` sin keyword define en v1 (falso global implícito, documentado) |
| Python | Cualquier asignación `x = ...` (define), `def name(params)`, `class Name`, `import x` / `from x import y, z as w`, params de lambda/with-as/except-as/for | Scope única de archivo v1; forward-references válidas en py pueden marcar falso indefinido (documentado) |

### Usos (qué se chequea)

Identificadores fuera de comentarios/strings/literales. `pkg.Fn`, `obj.attr`,
`a.b.c`: solo se chequea el PRIMER identificador de la cadena (el resto son
selectores o atributos). Keywords por lenguaje se ignoran.

### Hallazgos (todos warning)

1. Identificador usado y no definido en ningún scope visible → warning
   "undefined 'name'" (con la línea): en Go cubre también "paquete usado sin
   importar". Se muestra `?` en el gutter + inline a la derecha.
2. Import nunca usado al final del archivo → warning "unused import 'x'"
   (go/js/ts/py). El uso cuenta si el nombre aparece en cualquier scope
   después de la declaración.

### Balance

Sin cambios: `() [] {}` con strings, severity error — corre en TODOS los
lenguajes (html/docker incluidos).

## Límites honestos (v1)

- Sin análisis de tipos, sin shadowing avanzado (definición en scope interno
  que oscurece una externa: se resuelve por el más interno, correcto para lo
  común; la re-uso tras salir del bloque se resuelve por la externa — el
  motor de scopes maneja el caso básico, no el flujo complejo de go).
- Go: requiere import de la lista (imports no importados, alias), pero los
  usos dentro de literales tipo `map[string]int{}` (las llaves { } de
  literales confunden el block-tracking del scope — si aparecen corchetes de
  literal se tratan como bloque; se documenta el límite).
- Python: scope única de archivo (no indentación), forward-refs → posibles
  falsos positivos.
- HTML/Docker: sin scope en v1 (balance únicamente).
- Strings: delimitadores " ' ` con escape + comillas triples de py en la
  tokenización ("""/''').

## Plan de verificación

1. Harness réplica del host (como en v1/v2) con casos POR LENGUAJE:
   - go: `:=` definida; uso sin definir; import sin usar; paquete usado sin
     import; params; `_ =`; dot import (sin avisos).
   - js/ts: let/const/var; import con bindings; unused import; destructure
     simple; arrow params.
   - py: `x =` define; def/import/from; undefined; forward-ref (falso
     positivo esperado y documentado).
   - todos: comentarios y strings no cuentan como usos.
2. E2E: install replace en el binario actual, `--list-extensions` muestra el
   nuevo name; negativo manifest sin cambios (ya validado).
3. Verificación visual manual (usuario): archivo go con variable sin definir
   → `?` + inline en ámbar, y balance en `!` rojo a la vez.

## Tareas

1. [x] Decisiones y feature doc.
2. [x] Analizador de scope en main.lua (tokenizer + motor de scopes + imports).
3. [x] Harness con casos por lenguaje.
4. [x] E2E y reinstall.
5. [x] Commit + README + memoria.

## Evidencia

Commit `c7ea470` (repo error-detector). Manifest: name "Code Linter", v1.1.0,
comando "Check code" (id y instalación sin cambios).

**Harness réplica del host (19 casos, todos correctos):**

- go: ok con import+uso; undefined 'missing'; unused import 'strings';
  paquete usado sin importar (`http`); strings/comentarios ignorados; var
  block; método con named returns + receiver (solo marca `fmt1`); alias
  import; dot import (sin avisos).
- js/ts: imports con bindings + unused beta + undefined missing; anotaciones
  de tipos sin avisos; destructure simple; arrows (a,b)=> y x=>; comparación
  `>=` sin definir operandos.
- py: definición por asignación; def con params; import/from; lambda;
  for-in; unused import OrderedDict; sin ruido de keywords ni de límites de
  línea.
- html: balance únicamente (sin avisos de scope).

**Bugs encontrados y corregidos en el camino (registro para el equipo):**

1. Keywords de lenguajes como claves de tabla Lua → palabras reservadas de
   Lua 5.1 (`break=true` no compila). Solución: helper `set(words)` que
   construye los sets desde strings.
2. El tokenizer no emitía newlines → los loops de imports de py/js comían
   statements de otras líneas (`def`/`f` como falsos imports). Solución:
   token `nl` como límite de statement.
3. Cadenas de selectores: `fmt.Println` marcaba `Println` como undefined.
   Solución: solo la base de la cadena se chequea (`.id` pares se saltan).
4. Orden define-vs-uso: py `x = v`/js `x => ...` marcaban `x` undefined
   antes de que el `=` la definiera. Solución: id seguido de `=` define
   (py/js) y no chequea uso; arrow de un param solo en límites de
   statement/expresión (nunca en `>=`).
5. Params de py nunca se definían (no hay `{}` para el flush). Solución:
   definición inmediata en el handler de `def`.

**E2E:** install replace en el binario actual → "Code Linter (v1.1.0)" en
`--list-extensions`; `main.lua` v1.1.0 desplegado. El motor de diagnostics
+ inline del editor no cambió (todo fue de la extensión).
## Fix posterior: imports de Go en bloque `import ( ... )` (v1.1.1)

Reporte del usuario: `import( "import" "import2" "import3")` no se reconocía.
Reproducido con harness → 3 defectos del handler go + 1 general:

1. Paths cuyo último segmento es keyword (`"import"`) se defineImportaban →
   "unused import 'import'" inválido. Fix: defineImport filtra keywords,
   builtins y `_` (blank imports ya no dan falso positivo).
2. dot import en BLOQUE no activaba el wildcard. Fix: `.` en el bloque
   activa wildcard y no trackea el path.
3. (General) cadena de selectores de un builtin (`console.log`) no se
   consumía → "undefined 'log'". Fix: el branch builtin consume la cadena
   igual que el de identificadores.

Commits: `c5e73a0` (fix + v1.1.1) y `8d2e553` (restauración de repos
autor-locales por extensión: el monorepo había roto el install local, que
exige carpeta con .git). Reinstalado: Code Linter v1.1.1. Harness: 10
casos todos correctos (user-exact, block-used/unused/alias/blank/dot,
single-line, js console.log, py from).

## Fix posterior: visibilidad de nivel de paquete en Go (v1.1.2)

Reporte del usuario: "no me detecta cuando algo está dentro del mismo
package". En Go los nombres de paquete son visibles en TODO el archivo sin
importar el orden (`var x = helper()` antes que `func helper()` es válido);
el analizador resolvía en orden de aparición → falsos "undefined 'helper'".

Fix: pre-scan de nivel de paquete (brace depth 0) que registra en la scope
global funcs, métodos (con receiver) y var/const/type (single + bloque)
ANTES del pase secuencial. Los usos en funciones siguen con semántica
before-use (correcto para bloques).

LIMITE HONESTO (documentado): entre ARCHIVOS del mismo paquete no se ve —
el host Lua expone solo el buffer activo y no hay io/os para leer los
otros archivos. Cerrarlo requiere una API del editor (símbolos del
workspace/paquete) o pasar el contexto del paquete al script.

Harness: 9 casos OK (use-before-func, main-usos-later, global, var-block,
método, still-catches-undefined, regressions). Commit `9e2d...`, v1.1.2.

## Cross-file de paquete (v1.2.0) — proyecto multi-archivo resuelto

"Sigue sin detectar las funciones del package, el package abarca varios
archivos". El límite documentado anterior era del host Lua (sin io/os no
puede leer los hermanos) → se resolvió con API del EDITOR:

- tcode: script.go gana `DirFiles()` en ScriptAPI + tabla `tcode.dir_files()`
  (array {path, content}); el controller implementa en host_files.go (nuevo
  archivo: no tocó app.go): solo *.go, máx 64 archivos, 2 MiB, omite el
  buffer activo, degrada en error. Commit `5ae2647` (junto al merge
  multi-proveedor SetDiagnostics(source, ...)).
- extension: pre-scan de nivel de paquete parametrizado por lista y reusable
  → se corre sobre el buffer y sobre cada hermano del MISMO clause package
  (packageNameOf filtra); hermanos de otro paquete se ignoran. Binarios
  viejos sin tcode.dir_files degradan a buffer único (guard `if tcode.dir_files`).
- Bugs cazados: isSym/isId globales leían la lista del buffer activo en el
  pre-scan de hermanos (shadow local isSymArg/isIdArg); readGroup
  parametrizado por lista (antes iteraba la lista externa).

Harness 7/7 (hermano usado limpio; hermano de OTRO paquete no visible;
global/var + func en hermanos; undefined real; regresiones). v1.2.0
instalado. El merge multi-proveedor quedó desbloqueado: el lock de app.go
se liberó y el árbol de tcode volvió a compilar (commit 5ae2647).

## Fix posterior: declaración múltiple (a, b := ) — v1.2.1

Reporte: "var1, var2 :=" marca una de las variables como no definida. El pase
de ids trataba el primer id de la cadena (seguido de ",") como USO antes de
que el handler de "=" definiera la cadena → falso `undefined 'var1'`
(var2 no, porque le sigue ":"). Mismo defecto en py con `a, b =`.

Fix: cadena `id , id ...` que termina en `:=` (go) o `=` (py) = declaración:
salta el chequeo de uso; el handler de "=" define TODA la cadena (ya lo
hacía). Los argumentos de llamada (`fn(a, b)`) y los operadores de coma se
siguen chequeando como usos (regresión cubierta). Harness 13/13, v1.2.1
instalado. Nota del patrón: cadena de dos test que fallaron por expectativa
propia (foo/parse sin definir) — corregidos con la definición real.

## Fix posterior: propiedades tras llamadas + imports tipo-only (v1.2.2)

Reporte: "no detecta las propiedades de las clases de los imports definidos".
Dos defectos reales:

1. Selectores cuyo BASE es una EXPRESIÓN: `new C().prop`, `fn().prop`,
   `arr[i].prop`, `makeT().Field` — el id tras `)`/`]` + `.` caía al chequeo
   de uso → falso `undefined 'prop'`. La regla de cadenas solo cubría el
   `base.member` directo. Fix: id cuyo token previo es `.` = selector
   (nunca variable) → se salta; la base sigue chequeándose.
2. Import usado SOLO como tipo (TS): `let c: Config`, `(x: Item)`,
   `): MyType` — la anotación se saltaba y nunca se marcaba el import como
   usado → falso `unused import`. Fix: el handler let/const/var reconoce la
   anotación tras `:` (markUsed, no define); las anotaciones prev/next `:`
   marcan uso de tipo; los params (readGroup flusheado) también.

Harness 10/10 (new C().prop, static prop, fn().prop, items[i].a, tipo-only
let, tipo en param, base aún chequeada, makeT().Field, regresiones).
v1.2.2 instalado. Nota de proceso: un batch de edits atómico falló (búsqueda
con indentación distinta) y NINGUNO aplicó — el retry por partes evitó
estados a medias.
