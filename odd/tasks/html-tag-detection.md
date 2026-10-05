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
