# Feature: HTML Tag Detection (extensión Lua, v3)

## Estado del terreno

El detector de errores (`error-detector/main.lua`) v2 solo verifica balance de
paréntesis, corchetes y llaves `() [] {}` con conciencia de strings. El usuario
reporta que **no detecta etiquetas HTML no cerradas** (ej: `<div>` sin
`</div>`).

## Decisiones de producto (v3)

1. **Qué detecta:** etiquetas HTML no cerradas con conciencia de:
   - Strings (`"`, `'`, `` ` `` con escape `\`)
   - Comentarios HTML (`<!-- ... -->`)
   - Etiquetas self-closing (`<br>`, `<img>`, `<input>`, etc.)
   - Atributos con valores entre comillas
2. **Qué NO detecta (límites documentados):**
   - No valida anidamiento semántico (ej: `<div><span></div></span>`)
   - No detecta etiquetas mal formadas (ej: `< div>`)
   - No valida atributos requeridos o estructura HTML5
3. **Disparadores:** mismos que v2 (hook `onDidSaveBuffer` + keybinding
   `alt+shift+e`)
4. **UX del mensaje:** mismos patrones que v2, con prefijo "HTML:" para
   distinguir de errores de balance

## Plan de implementación

1. [x] Crear documento de feature
2. [ ] Implementar `htmlTagCheck(content)` en `main.lua`
3. [ ] Integrar en `check()` junto a `balanceCheck()`
4. [ ] Actualizar README.md
5. [ ] Commit

## API Lua (sin cambios)

| Función | Firma | Notas |
| --- | --- | --- |
| `tcode.buffer()` | `path, content` | `nil,nil` con buffer activo |
| `tcode.message(msg)` | — | barra de estado |
| `tcode.diagnostics.set(diags)` | — | `{line, message, severity}[]` |
| `tcode.diagnostics.clear()` | — | limpia diagnostics de esta extensión |

## Algoritmo htmlTagCheck

```
1. Escanear contenido carácter por carácter
2. Estados: normal, string, comment, tag
3. En estado "tag":
   - Extraer nombre de etiqueta (letras, números, guiones)
   - Si termina con "/>" → self-closing, no push
   - Si termina con ">" → push a stack con nombre y línea
4. En estado "normal":
   - "</" → extraer nombre, pop del stack (mismo nombre)
   - "<!--" → estado comment hasta "-->"
5. Al final: stack no vacío → errores "etiqueta no cerrada"
```

## Tareas

1. [x] Crear documento de feature
2. [x] Implementar `htmlTagCheck(content)` en `main.lua`
3. [x] Integrar en `check()` junto a `balanceCheck()`
4. [x] Actualizar README.md
5. [ ] Commit

## Evidencia

- Commit previo: `32da1cc` (v2 con diagnostics)
- Usuario reporta: detector no marca `<div>` sin `</div>`
- Implementación: `htmlTagCheck()` con stack de etiquetas, conciencia de
  strings en atributos, comentarios HTML, y self-closing tags
- Integración: `check()` ahora ejecuta `balanceCheck()` + `htmlTagCheck()`
  y publica todos los errores con `tcode.diagnostics.set()`

---

## v4: Mejoras de validación (en progreso)

### Nuevas validaciones solicitadas

1. **Etiquetas mal formadas**: `< div>`, `<div class=>`, `<>`, `</>`, nombres inválidos
2. **Atributos mal formados**: comillas sin cerrar, atributos duplicados, `class=>`
3. **DOCTYPE y estructura**: `<!DOCTYPE>` mal formado, múltiples DOCTYPE, DOCTYPE después de contenido

### Límites documentados (sin cambios)

- No valida anidamiento semántico (ej: `<div><span></div></span>`)
- No valida atributos requeridos o estructura HTML5 semántica
- No valida entidades HTML

### Plan de implementación v4

1. [x] Actualizar documento de feature
2. [x] Implementar detección de etiquetas mal formadas
3. [x] Implementar detección de atributos mal formados
4. [x] Implementar detección de DOCTYPE y estructura
5. [x] Actualizar README.md
6. [x] Commit (`ca28467`)

---

## v5: Registro de checks por lenguaje

### Decisión de producto

Reemplazar el filtro HTML hardcodeado (`isHTMLFile`) por un registro
extensible consistente con `undefined-vars` / `unused-imports`:

- `detectLanguage(path)` mapea extensión → `html` / `go` / `ts` / `py` / `nil`.
- `universalChecks` corre siempre (`balanceCheck`).
- `checksByLang[lang]` corre solo si el lenguaje se detecta.
- Hoy: `html = { htmlTagCheck }`; `go`, `ts`, `py` vacíos (reservados).

### Bugfixes encontrados por el harness

- Atributos duplicados no se detectaban (se registraba solo la primera letra
y `attrName` no se reseteaba).
- `class=>` reportaba el mensaje dos veces.
- `< div>` reportaba `Malformed tag` + `Empty tag` redundante.

### Plan v5

1. [x] Refactor `detectLanguage()` + `checksByLang` + `universalChecks`
2. [x] `parseAttrs()` dedicado: duplicados, valores sin comilla, booleanos
3. [x] Harness Go (gopher-lua) con 25 casos — 25/25 PASS
4. [x] Actualizar README
5. [ ] Commit del refactor

### Evidencia v5

- Harness: `go run .` en harness temporal con gopher-lua v1.1.2, 25 casos,
  0 fallas. Cubre HTML, Go, JS/TS, Python, extensión desconocida, mayúsculas,
  atributos multilínea y booleanos.

---

## v6: Estructura consistente + harness en el repo

### Decisión de producto

Unificar la estructura del `error-detector` con las otras extensiones del
monorepo y dejar el harness en el repo (el usuario eligió la opción A).

Cambios:

1. `check()` sigue el patrón de `undefined-vars` / `unused-imports`:
   `detectLanguage` + lógica inline, sin helper `collect` ni tabla
   `universalChecks`. `balanceCheck` se llama directo (es universal).
2. El harness vive en `error-detector/harness/` (mismo patrón que
   `python-lint/harness/`): `go.mod` + `main.go` con `buildCases()`.
3. README documenta el harness y cómo correrlo.

### Plan v6

1. [x] Unificar `check()` con el patrón de las otras extensiones
2. [x] Mover el harness a `error-detector/harness/`
3. [x] Actualizar README con el harness
4. [x] Verificar: 25 casos, 0 fallas
5. [ ] Commit
