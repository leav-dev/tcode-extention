# Git Changes Extension

## Objetivo

Extensión para tcode que muestre información de cambios de git:
- Cantidad de archivos con cambios (staged + unstaged + untracked)
- Cantidad de líneas modificadas (agregadas + borradas)
- Identificadores visuales en el gutter para líneas nuevas, modificadas y borradas

## Contexto

- tcode no tiene API de git en el sistema de extensiones actual
- Se necesita agregar `tcode.git.status()` al ScriptAPI
- La extensión usa el sistema de diagnostics existente para marcar líneas

## Tareas

### 1. Agregar API de git a tcode (ScriptAPI)

**Archivos:**
- `/home/sistmas/priv/tcode/internal/ext/script.go` - Interfaz ScriptAPI + implementación Lua
- `/home/sistmas/pcode/internal/controller/app.go` - Implementación del controlador

**API propuesta:**
```go
// GitStatus devuelve el estado de git del directorio del buffer activo
GitStatus() (GitInfo, error)

type GitInfo struct {
    StagedFiles    []string  // Archivos en staging area
    UnstagedFiles  []string  // Archivos modificados sin stagear
    UntrackedFiles []string  // Archivos nuevos untracked
    AddedLines     int       // Líneas agregadas (staged + unstaged)
    DeletedLines   int       // Líneas borradas (staged + unstaged)
}
```

**Implementación Lua:**
```lua
tcode.git.status() -- devuelve {staged={}, unstaged={}, untracked={}, added=N, deleted=N}
```

### 2. Crear estructura de la extensión

**Ubicación:** `/home/sistmas/priv/tcode-extention/git-changes/`

**Archivos:**
- `extension.json` - Manifest con comandos y hooks
- `main.lua` - Script principal
- `README.md` - Documentación

### 3. Implementar script Lua

**Funcionalidad:**
- Comando `tcode.gitchanges.status` que muestra el resumen en la barra de estado
- Hook `onDidSaveBuffer` para actualizar automáticamente
- Usar `tcode.diagnostics.set()` para marcar líneas con cambios

**Formato de mensajes:**
- Barra de estado: `Git: 3 files, +15 -8 lines`
- Diagnostics por línea: `+` nueva, `~` modificada, `-` borrada

### 4. Calcular diff por archivo

**Enfoque:**
- Para cada archivo modificado, ejecutar `git diff --numstat` o `git diff --cached --numstat`
- Parsear el output para obtener líneas agregadas/borradas
- Para marcar líneas específicas, usar `git diff` con formato unificado

### 5. Marcar líneas en el gutter

**Estrategia:**
- Usar `tcode.diagnostics.set()` con severity `info` para líneas nuevas/modificadas
- Usar `tcode.diagnostics.set()` con severity `warning` para líneas borradas
- El gutter mostrará `i` (info) o `?` (warning) según la convención existente

### 6. Tests

**Tests de integración:**
- Test con repo git real
- Verificar conteo de archivos y líneas
- Verificar que los diagnostics se marcan correctamente

## Decisiones de diseño

### Alternativa 1: Solo conteo (simple)
- Más fácil de implementar
- No requiere parsear diffs línea por línea
- Menos útil para el usuario

### Alternativa 2: Conteo + marcado de líneas (completo)
- Requiere parsear diffs unificados
- Más complejo pero más útil
- Permite ver exactamente qué líneas cambiaron

**Decisión:** Alternativa 2 (completo) - el usuario pidió identificadores en la numeración de líneas

## Riesgos y mitigaciones

| Riesgo | Mitigación |
|--------|------------|
| Performance en repos grandes | Limitar a archivos del buffer activo + hermanos |
| Dependencia de git externo | Verificar que git esté disponible, mensaje claro si no |
| Complejidad de parsear diffs | Usar formato unificado estándar, tests exhaustivos |

## Criterios de aceptación

- [ ] `tcode.git.status()` devuelve información correcta de git
- [ ] La barra de estado muestra cantidad de archivos y líneas
- [ ] Las líneas con cambios tienen identificadores en el gutter
- [ ] Funciona con staged, unstaged y untracked
- [ ] Se actualiza al guardar el buffer
- [ ] Tests pasan
