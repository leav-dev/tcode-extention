# Feature: Python Lint — detector de indentación y estructura para Python

## Pedido del usuario

Un detector de errores **específico para Python**, manejado **por separado**
del `error-detector` genérico: Python es delicado con la indentación y merece
lógica propia. Extensión nueva, no un chequeo dentro de otra.

## Decisiones de producto (respondidas)

- **Extensión nueva**: carpeta `python-lint/`, id `tcode.pylint`, nombre
  "Python Lint", comando `tcode.pylint.check`, keybinding `alt+shift+p`,
  hook `onDidSaveBuffer`.
- **Checks v1** (elegidos por la usuaria, tres familias):
  1. **Indentación**: mezcla tab/espacio, estilo inconsistente entre líneas,
     dedent que no coincide con ningún nivel abierto.
  2. **Estructura de bloques**: `:` faltante en línea compuesta, bloque
     esperado tras `:` que no aparece, indentación inesperada sin `:` previo.
  3. **Contexto de sentencias**: `return`/`yield` fuera de función,
     `break`/`continue` fuera de loop, `nonlocal` fuera de función anidada,
     `global` a nivel módulo (warning).
- **Descartado en v1**: checks de espacios (tabs tras espacios, whitespace al
  final de línea, indentación en líneas en blanco). Documentado como límite.
- **Severidad**: `error` para todo lo estructural; `warning` solo para
  `global` a nivel módulo (es válido en Python, no un SyntaxError).
- **Lenguaje**: solo `.py` y `.pyw`. Cualquier otro archivo → no-op, sin
  tocar diagnostics.
- **Mensajes al usuario**: inglés (convención del proyecto).
- **Sin escritura en la barra de estado**: solo `tcode.diagnostics.set/clear`
  (convención del trío linter tras `7de79ca`).

## API del editor usada

- `tcode.buffer()` → `path, content`.
- `tcode.diagnostics.set(lista)` con `{line, message, severity}`; `line`
  **1-indexada** (el host traduce a 0-indexada). `tcode.diagnostics.clear()`
  limpia solo la fuente de este proveedor.

## Spec técnico de checks

### Modelo de línea

Para cada línea física (split por `\n`, 1-indexada) se calcula:

- `indent`: prefijo de tabs/espacios antes del primer carácter no-blanco.
- `code`: la línea sin comentario `#` (respetando strings) y sin el prefijo.
- `bracketDepth` al inicio: profundidad de `()[]{}` arrastrada desde líneas
  anteriores.
- Estado de triple-quote (`'''` / `"""`) y de continuación por backslash `\`.

**Regla clave (evita falsos positivos):** una línea cuyo `bracketDepth` de
entrada es > 0 es **continuación implícita** y también lo es una línea
arrastrada por backslash o dentro de un triple-quote. Esas líneas se excluyen
de TODOS los checks de indentación y de bloque (`IndentError` de Python las
permite con indentación arbitraria). Solo se chequean las que empiezan una
sentencia lógica a nivel de código.

### Fundamentos reutilizables

- `stripComment(line, inString)` → código sin comentario, respetando strings
  (`'`, `"`, `'''`, `"""`, escapes con `\`).
- `bracketDelta(code)` → delta de profundidad y si hay un `:` a profundidad 0
  fuera de strings.
- `lastCodeChar(code)` → último carácter no-blanco del código (para saber si
  termina en `:`).
- `firstKeyword(code)` → primera palabra clave del statement.

### I. Indentación

- **I1 (error) — mixed indentation**: el prefijo contiene tab Y espacio.
  Mensaje: `mixed indentation (tabs and spaces)`.
- **I2 (error) — inconsistent indentation**: hay líneas indentadas con tab y
  con espacio en el archivo (estilos mezclados entre líneas); una línea cuyo
  estilo difiere del mayoritario. Mensaje:
  `inconsistent indentation (file uses spaces|tabs)`.
  Solo se reporta si AMBOS estilos aparecen al menos una vez en el archivo.
- **I3 (error) — unindent mismatch**: al desindentar, el ancho del prefijo no
  coincide con ningún ancho de la pila de bloques abiertos. Mensaje:
  `unindent does not match any outer indentation level`.
- **I4 — RETIRADO durante la verificación.** La regla "no es múltiplo del
  paso" generaba ruido en código Python VÁLIDO con indentación irregular
  pero consistente (8 archivos reales de `orca/*` con cuerpos a 18 espacios
  dentro de un archivo de paso 4). No es un error de Python; se quitó y se
  documentó como límite.

Ancho del prefijo = longitud en caracteres (tab = 1). Con estilo consistente
esto da un nivel por tab o por N espacios.

### II. Estructura de bloques

Keywords compuestas que exigen `:`: `if`, `elif`, `else`, `for`, `while`,
`try`, `except`, `finally`, `with`, `def`, `class`, `async` (cuando sigue
`def`/`for`/`with`), más las soft keywords `match` y `case` (solo cuando
abren bloque).

- **E1 (error) — missing colon**: la línea empieza con una keyword compuesta y
  NO tiene `:` a profundidad 0 después de la keyword. Mensaje:
  `expected ':' at the end of the line`. Un `:` dentro de `()[]{}` (slices,
  dicts, anotaciones, lambda anidada) no cuenta. Si hay código tras el `:`
  (one-liner `if x: pass`) tampoco hay error.
- **E2 (error) — expected indented block**: una línea compuesta termina en `:`
  a profundidad 0 SIN código después, y la siguiente línea lógica no está más
  indentada. Mensaje: `expected an indented block`.
- **E3 (error) — unexpected indent**: una línea incrementa la indentación
  respecto de la anterior, pero la anterior no abrió bloque (no terminó en
  `:`), no es continuación, y no es la primera línea. Mensaje:
  `unexpected indent`.

Control: `expectBlock` se activa al cerrar una línea con `:` y sin código
posterior; la siguiente línea lógica lo consume (con más indentación → abre
bloque; con indentación igual o menor → E2).

### III. Contexto de sentencias

Se recorren los tokens de la línea lógica (fuera de strings/comentarios) y se
busca `return`, `yield`, `break`, `continue`, `nonlocal`, `global` como
identificadores de statement (no precedidos por `.`).

Pila de bloques con tipo: `fn` (`def`), `async fn` (`async def`), `loop`
(`for`/`while`), `class`, `block` (resto). La pila se construye/desarma con
los anchos de indentación (I3).

- **C1 (error)**: `return` o `yield` sin ningún `fn` en la pila →
  `'return' outside function` / `'yield' outside function`.
- **C2 (error)**: `break` o `continue` sin ningún `loop` en la pila →
  `'break' outside loop` / `'continue' outside loop`.
- **C3 (error)**: `nonlocal` con menos de dos `fn` en la pila →
  `nonlocal declaration outside nested function`.
- **C4 (warning)**: `global` sin ningún `fn` en la pila →
  `global declaration at module level is a no-op`.

Los one-liners (`if x: return`, `for i in y: break`) también cuentan: se
busca la keyword en toda la línea lógica a profundidad 0, no solo al inicio.

### Salida

Lista de `{line, message, severity}` ordenada por línea. Si no hay hallazgos,
`tcode.diagnostics.clear()`.

## Límites honestos (v1)

- Sin análisis de flujo: `if False: return` igual se valida por contexto
  (correcto para SyntaxError, no para reachability).
- Continuaciones y triple-quotes se excluyen de indentación, pero un
  desbalance de brackets puede desalinear el modelo (el `error-detector`
  cubre el balance de `()[]{}`, no se duplica).
- Sin checks de espacios (descartados) ni de longitud de línea.
- `match`/`case` como soft keywords: un identificador llamado `match` en
  otros contextos no debe abrir bloque.
- `async` sin `def`/`for`/`with` (`async with`, `async for`) se reconoce; un
  `async` suelto no.

## Plan de verificación

1. **Harness réplica del host**: `python-lint/harness/` (Go + gopher-lua,
   `go.mod`/`go.sum` copiados del editor para resolver del module cache sin
   red; stub de `tcode.*` que captura los diagnostics). Casos:
   - indentación: tab+espacio en una línea; archivo con tabs y espacios;
     dedent a un nivel inexistente; ancho no múltiplo del paso.
   - estructura: `if x` sin `:`; `if x:` sin bloque indentado; indent sin `:`;
     one-liner `if x: pass` limpio; `:` de dict/slice/lambda sin falso E1.
   - contexto: `return` a nivel módulo; `yield` a módulo; `return` dentro de
     `def` limpio; `break` fuera de loop; `break` dentro de `for` limpio;
     `continue` en `while` anidado en `def` limpio; `nonlocal` a módulo;
     `nonlocal` en función anidada limpio; `global` a módulo = warning.
   - no-código: líneas dentro de triple-quote y comentarios no cuentan;
     continuación implícita con indentación arbitraria no dispara I2/I3/E3;
     archivo `.go` → no-op.
   - regresión: archivo Python válido completo → 0 hallazgos.
2. **E2E**: `tcode --install-extension <path>/python-lint` y
   `--list-extensions` muestra "Python Lint".
3. Verificación visual manual (usuaria): archivo `.py` con un dedent inválido
   → `!` rojo en el gutter.

## Tareas

1. [x] Feature doc + decisiones + mirror de memoria.
2. [x] Implementar `python-lint/main.lua` (modelo de línea + I/E/C) y
       `python-lint/extension.json` + `python-lint/README.md`.
3. [x] Harness de verificación con casos (37 casos, 0 fallos).
4. [ ] E2E install + `--list-extensions` (pendiente).
5. [ ] Commit + memoria de cierre.

## Evidencia

`python-lint/main.lua` (id `tcode.pylint`, "Python Lint", v1.0.0), comando
`tcode.pylint.check`, keybinding `alt+shift+p`, hook `onDidSaveBuffer`.
Harness `python-lint/harness/` (Go + gopher-lua v1.1.2, temporal, no
committeado): `cd python-lint/harness && GOFLAGS=-mod=mod GOPROXY=off go run .`
→ **37 casos, 0 fallos**.

### Verificación con código real (la que encontró los bugs)

Además de los casos sintéticos, se corrió el analizador contra **1200
archivos Python reales** de `/usr/lib/python3/dist-packages` (pygments,
orca, duplicity, gi, pyrsistent, CommandNotFound, speechd_config). El
harness sintético del worker pasaba 30/30 con bugs graves presentes; el
corpus real los expuso. Estado final: **solo 1 hallazgo, el warning
`global declaration at module level is a no-op` de
`duplicity/backends/ssh_paramiko_backend.py:40`, que es el comportamiento
especificado** (no un falso positivo).

### Bugs encontrados y corregidos (registro para el equipo)

1. **Delta de brackets clampeado a ≥0** (grave, latente). El delta
   intra-línea no bajaba de 0, así que una línea que solo cierra (`}` o `]`)
   dejaba `depthOut` intacto: todo dict/lista multilínea quedaba "abierto" y
   el statement lógico se tragaba el resto del archivo (419/1200 archivos
   con falsos `return/yield/break outside ...`). El caso 19 del harness
   pasaba por casualidad. Fix: delta con signo y `depthOut` clampeado solo a
   ≥0; el `:` cuenta cuando la profundidad GLOBAL es 0.
2. **`table.concat` de gopher-lua revienta el registry** (`registry
   overflow`). `tableConcat` empuja cada elemento al registro del VM; una
   línea generada de 72.574 chars con ~3000 strings producía ~6000 chunks y
   el script abortaba. Fix: `joinChunks()` concatena en lotes de 400.
3. **Continuación por backslash dentro de strings simples**. Python elimina
   el `\`-newline a nivel físico ANTES del análisis, así que vale también
   dentro de un string de comillas simples. El modelo no trackeaba el string
   abierto: un `]` interno desbalanceaba la profundidad y el header
   siguiente parecía `unexpected indent` (orca/formatting.py). Fix: estado
   `simple` cross-line + `endsBackslash` calculado sobre la línea raw.
4. **Statements lógicos**. Un header multiparámetro (`for x in \` ... `]:`)
   tiene el `:` en una línea de continuación; el modelo línea-a-línea lo
   marcaba `expected ':'`. Fix: loop principal agrupa el statement lógico
   (continúa con backslash o brackets abiertos) y evalúa colon/keywords
   sobre todas sus líneas.
5. **Línea que cierra un triple-quote con código después**
   (`""" , (cmd,)).fetchall():`) se saltaba entera por `rec.inTriple`; el
   `code` enmascarado ya trae el código posterior. Fix: la exclusión se
   decide por `blank` (code vacío y sin apertura de string), y
   `rec.inTriple`/`rec.inSimple` cuentan como continuación.
6. **Docstring como único cuerpo de un bloque** (`class A:\n    """doc"""`)
   contaba como línea blank y no consumía el `pending` → falso
   `expected an indented block`. Fix: un string que abre la línea no es
   blank (`stringStart`).
7. **E1 en header continuado** por backslash u open bracket: el `:` puede
   vivir en una línea posterior. Fix: suprimir E1 si `endsBackslash`.
8. **I4 retirado** (ruido en código válido, ver arriba).

### Decisiones de ambigüedad del spec (del worker, confirmadas)

- E2 se reporta en la línea del header (como Python: "expected an indented
  block after 'if' statement on line N"), no en la línea siguiente.
- Las líneas en blanco no consumen un `pending` (`if x:` / blank / `pass` es
  limpio); tampoco disparan E3/I.
- Un header al final del archivo sin cuerpo no se reporta (falso negativo
  menor, evita ruido).
- `match`/`case` nunca disparan E1 (identificador llamado `match`).
- Una línea dentro de `() [] {}` o de un string triple no participa de
  I1-I3/E1-E3; su contenido sí alimenta el estado de brackets/triple.
