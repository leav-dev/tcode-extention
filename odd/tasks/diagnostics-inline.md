# Feature: Diagnósticos inline a la derecha de la línea (editor tcode)

## Pedido del usuario

El error debe verse **a la derecha de la línea** (no en la barra de estado
activa) para poder mostrar **varios errores a la vez** (uno por línea).
Decisión de sesión: se está ajustando el editor para eso — este doc fija el
contrato para que el editor y la extensión queden alineados.

## Respuesta a la duda de diseño: ¿el inline afecta los errores mostrados?

**No afecta el modelo ni los mensajes.** El dato sigue siendo
`view.Diagnostic {Line, Message, Severity}` (deduplicado por línea: gana la
mayor severidad, empate el primero). El inline es solo render. Las únicas
interacciones reales con el texto:

| Interacción | Comportamiento propuesto |
| --- | --- |
| **Espacio** | El mensaje se dibuja después del texto, desde `finDeTexto + separador` hasta `gutter + viewport.Width`; si no entra completo, se trunca con `…`. Si queda < ~10 columnas útiles, se omite (o se trunca igual). |
| **Wrap** | Con word-wrap, el mensaje va en la **última fila visual** de la línea lógica (donde termina el texto). En `drawSoftLine` hay que saber si el slice es el último; v1 puede renderizarlo en la última fila visible o omitirlo si la fila está llena. |
| **Mismo nivel / varias líneas** | Un mensaje por línea (varios a la vez = varias líneas visibles). Si una línea tiene 2+ diagnostics, el editor elige el de mayor severidad (regla actual `diagAt`); opcional futuro: unirlos `msg1; msg2` en el inline. |
| **Colores por severidad** | El mensaje inline usa los roles del tema `DiagError/DiagWarning/DiagInfo` (mismos que el marcador del gutter: en el tema hex `#D6140F` / `#B25D00` / `#005FB8`), con el fondo de la línea (docBg o CursorLineBg). |
| **Barra de estado** | Se **quita** el mensaje nativo por línea del cursor (bloque `DiagAtCursor` en `app.go` ~764-769). Quedan los mensajes transitorios de la extensión (resumen al guardar). |
| **Config** | **Siempre encendido** en v1; sin toggle. |

## Niveles de severidad (multi-nivel)

El canal `tcode.diagnostics.set` ya valida y renderiza las tres severidades.
Hoy la extensión manda siempre `"error"`. Plan v3 de la extensión:

| Nivel | Qué lo genera | Estado |
| --- | --- | --- |
| `error` | `never closed`, `without opening`, `does not match`, `unterminated string` | hoy |
| `warning` | (v3) corchetes en comentarios? No — solo si el analizador distingue contexto; si no, quedan falsos positivos y no se emiten | v3 |
| `info` | (v3) marcadores TODO/FIXME detectados en comentarios (requiere **conciencia de comentarios**, pareja natural) | v3 |

El editor no cambia nada para multi-nivel: el inline colorea por severidad con
los roles que ya existen; el gutter ya distingue `!`/`?`/`i`.

## Division of labor

- **Editor (tcode, esta sesión):** render inline (drawSoftLine/drawLineUnwrapped),
  quitar `DiagAtCursor` de la barra.
- **Extensión (tcode-extentions):** v3 para severidades TODO/FIXME + comentarios.
  Sin cambios para inline: los mensajes ya viajan en `Diagnostic.Message`.

## Evidencia de implementación

Commit `bb7dbbf feat(view): diagnostics inline a la derecha de cada línea
anotada` (implementado en esta sesión, sobre el binario del usuario):

- `internal/view/diagnostics.go`: helpers `diagInlineStyle` (color de severidad
  sobre el fondo de la línea) y `drawInlineDiag` (separador de 2 espacios,
  truncado con `…` reservando la última celda, se omite si no quedan ≥2
  celdas).
- `internal/view/editor_view.go`: hook en `drawSoftLine` (solo en la ÚLTIMA
  fila visual: `sl.in+len(sl.text) == len(text)`) y en `drawLineUnwrapped`.
- `internal/controller/app.go`: se eliminó `syncDiagStatus` y su call; la
  barra ya no muestra diagnósticos (decisión de producto). Se eliminó
  `diagSeverityName` (quedaba huérfano).
- Tests del view: `TestDrawInlineDiagnosticAfterText` (output real:
  `2!dos  '(' never closed`), `TestDrawInlineDiagnosticTruncates`,
  `TestDrawInlineDiagnosticSkipsWhenNoRoom` (`1!abcdef`), y
  `TestDrawInlineDiagnosticWithWrapLastRow`. Test del controller reemplazado
  por `TestDiagMessageStaysOffStatusBar` (barra sin diagnóstico).
- `go test ./internal/view/...` ok; controller `-run Diag` ok; `go build` ok;
  `tcode.exe` recompilado (22:06). La extensión no cambió: los mensajes ya
  viajaban en `Diagnostic.Message`.