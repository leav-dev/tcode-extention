# Feature: Error Detector (extensión Lua, v1)

## Estado del terreno (contexto obligatorio)

El detector de errores corre **código Lua** — depende del hito 1 del backend
de scripting de tcode (`odd/tasks/scripting-backend.md`, repo tcode), que al
momento de diseñar este feature está **implementado pero sin commitear** y con
un build roto:

- Incidente: `internal/view/editor_view.go` (~639/~671) tiene un **byte CR
  literal (0x0D) dentro de `cl == "<CR>"`** en vez del escape `"\r"` — errores
  `newline in string`; `go build ./...` y el package controller fallan. El
  diff lógico de ese archivo es solo `CursorOffset()` (+7). Entró entre las
  20:46 y 20:53. **Decisión del usuario: la sesión que implementa el backend
  lo corrige; acá no se toca el working tree de tcode.**
- Contrato de la API verificado contra `internal/ext/script.go` (estado
  actual): ver sección API abajo.
- Pendiente para E2E: backend commiteado + build verde + tests.

## API Lua (verificada, hito 1)

| Función | Firma | Notas |
| --- | --- | --- |
| `tcode.buffer()` | `path, content` | `nil,nil` con buffer activo |
| `tcode.command(id)` | — | ejecuta un comando registrado; error → script error |
| `tcode.insert(text)` | — | inserta en el cursor del editor activo |
| `tcode.message(msg)` | — | barra de estado |
| `tcode.error(msg)` | — | fallo declarado del script (causa visible) |

Host: solo librerías base/table/string/math; **sin `io`/`os`** (no hay acceso a
archivos ni procesos). El script vive en `main.lua` (ruta relativa a `e.Dir`),
host cacheado por `e.Dir::script`, reentrada máxima 8 (guard `scriptDepth`).
`Call(fn)` invoca la función global `fn`; un panic del script nunca tumba el
editor.

**Consecuencia de diseño:** el detector v1 tiene que ser **Lua puro sobre el
contenido del buffer**. No puede invocar linters externos (`gopls`, `tsc`,
`go vet`) ni leer config del usuario: eso queda para un hito posterior con
`tcode.*` extendida o procesos. La v1 es un detector **estructural honesto**,
no un linter semántico.

## Decisiones de producto (v1)

1. **Qué detecta:** desbalance de corchetes `() [] {}` con conciencia de
   strings (`"`, `'` con escape `\`, y `` ` ``). Strings multi-línea incluidos
   (paridad a través de líneas). Mensajes con **número de línea**.
2. **Qué NO detecta (límites documentados):**
   - Sin conciencia de comentarios: corchetes dentro de `//` o `/* */`
     cuentan como falsos positivos (docs con `[` son el caso típico). v2:
     estados de comentario.
   - Sin análisis por lenguaje (no hay API de language id): el detector es
     agnóstico del lenguaje; las reglas semánticas (linters reales) quedan
     fuera de esta versión.
   - Sin `onDidChangeText` (deuda de rendimiento del editor, no de la
     extensión): el chequeo corre al **guardar** y **bajo demanda**.
   - La backtick como raw string multi-línea de Go se trata como delimitador
     simple: una backtick colgante al final reporta "string sin cerrar",
     aunque sea sintaxis válida de Go en algunos casos raros — se documenta.
3. **Disparadores:** hook `onDidSaveBuffer → check` (al guardar) + keybinding
   `alt+shift+e → check` (bajo demanda). La barra de estado muestra el
   resumen; el mensaje del guardado es reemplazado por el del detector
   (barra de una sola línea).
4. **UX del mensaje:** sin errores → "no balance errors". Con errores →
   markers por línea + total (`Error Detector: 2 errors marked in the gutter`).
   Los mensajes al usuario (barra y diagnostics) son **en inglés por
   convención** (estándar de los artifacts del workspace).
   El script devuelve limpio (Call sin error): el detector informa, no corta.

## Manifest (borrador)

```json
{
  "id": "tcode.errordetector",
  "name": "Error Detector",
  "version": "1.0.0",
  "activation": ["onStartup"],
  "contributes": {
    "commands": [
      { "id": "tcode.errordetector.check", "title": "Detectar errores",
        "script": "main.lua", "fn": "check" }
    ],
    "keybindings": [
      { "key": "alt+shift+e", "command": "tcode.errordetector.check" }
    ],
    "hooks": [
      { "event": "onDidSaveBuffer", "command": "tcode.errordetector.check" }
    ]
  }
}
```

Valida contra `internal/ext/manifest.go`: id/version/formato ok, comando con
`script`+`fn` juntos, hook con evento del set, keybinding con mods. El id
sigue el convenio publisher.nombre (`tcode.*`).

## main.lua (borrador completo)

```lua
-- Error Detector para tcode — v1: balance () [] {} con conciencia de strings.
-- API: tcode.buffer(), tcode.message(). Lua puro (sin io/os en el host).

local function check()
  local path, content = tcode.buffer()
  if not path then
    tcode.message("Error Detector: no active buffer")
    return
  end

  local closing = { ["("] = ")", ["["] = "]", ["{"] = "}" }
  local opening = { [")"] = "(", ["]"] = "[", ["}"] = "{" }
  local stack, errors, delim = {}, {}, nil
  local line, i, n = 1, 1, #content

  while i <= n do
    local c = content:sub(i, i)
    if delim then
      if c == "\\" then i = i + 2 elseif c == delim then delim = nil end
      if c == "\n" then line = line + 1 end
      i = i + 1
    elseif c == '"' or c == "'" or c == "`" then
      delim = c
      i = i + 1
    elseif c == "\n" then
      line = line + 1
      i = i + 1
    elseif closing[c] then
      stack[#stack + 1] = { c, line }
      i = i + 1
    elseif opening[c] then
      local top = stack[#stack]
      if top and top[1] == opening[c] then
        stack[#stack] = nil
      elseif top then
        errors[#errors + 1] = { l = line, m = "'" .. c .. "' does not match '" .. top[1] .. "'" }
        stack[#stack] = nil
      else
        errors[#errors + 1] = { l = line, m = "'" .. c .. "' without opening" }
      end
      i = i + 1
    else
      i = i + 1
    end
  end

  if delim then
    errors[#errors + 1] = "string sin cerrar (delimitador '" .. delim .. "')"
  end
  for _, e in ipairs(stack) do
    errors[#errors + 1] = { l = e[2], m = "'" .. e[1] .. "' never closed" }
  end

  local nerr = #errors
  if nerr == 0 then
    tcode.message("Error Detector: no balance errors")
    return
  end

  local msg = "Error Detector: " .. nerr .. " error"
  if nerr > 1 then msg = msg .. "es" end
  local shown = 0
  for _, e in ipairs(errors) do
    if shown < 3 then msg = msg .. " · " .. e end
    shown = shown + 1
  end
  if nerr > 3 then msg = msg .. " (+" .. (nerr - 3) .. " más)" end
  tcode.message(msg)
end
```

Notas del algoritmo: escaneo por bytes (utf-8-safe para saltar, los números de
línea no dependen de anchos); `\\` salta el próximo carácter (escape);
mismatch con top → reporta y hace pop (recuperación); fin con string abierta o
stack → errores finales.

## Plan de verificación (E2E, cuando el backend esté commiteado)

1. `go build ./...` verde en tcode y `go test ./internal/...` ok.
2. `tcode --install-extension <ruta-local>/error-detector` → "Instalada" y
   `--list-extensions` la muestra.
3. Negativo del manifest: script sin fn → rechazado ("juntos o ninguno").
4. Integración (recomendada, sigue el patrón del test id: 5 del backend):
   test de controller sobre el detector — buffer con `func f( {` → save →
   la barra muestra el conteo; buffer balanceado → "sin errores". El harness
   de pantalla simulada del controller ya existe.
5. Manual (opcional, del usuario): abrir un .go con `{` desparejo, guardar,
   ver el mensaje; `alt+shift+e` bajo demanda.

## Tareas

1. [x] Materializar `error-detector/` como repo de extensión (extension.json,
   main.lua, README) cuando el backend hito 1 esté commiteado.
2. [x] Verificación E2E (plan arriba) + commit.
3. [x] Publicar diagnostics de línea (v2): el editor ganó la feature
   `feat(view,ext): per-buffer diagnostics with a line-number gutter and Lua
   provider` (`b5ee658`) — API `tcode.diagnostics.set({line,message,severity})`
   (line 1-indexada, severidad `error|warning|info`, validación todo-o-nada)
   + `clear()`, gutter con números de línea, y barra nativa por línea del
   cursor (`línea N: msg (severidad)`). La extensión v2 publica los errores
   con `set` y limpia con `clear`; commit `32da1cc`. Harness con réplica de
   diagnostics: 6/6 casos. Reinstalada (replace) y verificado el main.lua
   v2 desplegado (7 menciones de diagnostics).
4. [ ] v3 (opcional): conciencia de comentarios, heurísticas por lenguaje
   detectado desde `path` (extensión del archivo), reporte de TODO/FIXME
   como info separada (severidad `warning`/`info` ya soportada por el
   editor).

## Evidencia

- Backend de tcode: `86fdf6a feat(ext): Lua scripting backend…` (commiteado
  por la otra sesión; build verde; los tests de scripting de `internal/ext`
  pasan: host call, par script/fn, reentry guard, sin-editor).
- Repo de la extensión: `error-detector/` — commit `52f923c` (amend incluye
  el fix del contrato).
- **Hallazgo de contrato**: `fn` debe ser **función global** — el backend
  resuelve con `L.GetGlobal(fn)`; un `local function check()` no era visible
  y fallaba con "attempt to call a non-function object". El harness lo
  cazó antes del install.
- Harness independiente (replica del host, en `C:/tmp/lua-harness`):
  balanceado → sin errores; desbalanceado → 2 errores con línea;
  string-aware → limpio; string con escape → limpio; sin buffer → mensaje
  honesto; cierre equivocado → mismatch con recuperación. 6/6 pasan.
- E2E con el editor (build fresco post-backend): install →
  "Instalada: tcode.errordetector"; `--list-extensions` la muestra;
  árbol desplegado = extension.json + main.lua + README.md.
- Negativo: manifest con `script` sin `fn` → "script y fn van juntos",
  exit 1, sin tocar nada.
- Nota ambiental: `go test ./internal/...` completo tiene tests de
  detección de cambios externos que fallan en esta máquina Windows
  (sharing violations con mmap/Defender) — pre-existente (fallan también en
  el commit anterior al backend), ajeno a scripting y a esta extensión.
- Pendiente manual: prueba en TUI real (guardar un .go con `{` desparejo y
  ver el mensaje; `alt+shift+e`).