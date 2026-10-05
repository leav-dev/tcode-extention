# Git Changes: status bar section

## Objetivo

`git-changes` escribía su resumen de git con `tcode.message()`, que llama a
`statusBar.SetMessage()`: **reemplaza** el texto de la barra. Con varias
extensiones escribiendo (unused-imports, error-detector, undefined-vars), solo
se veía la última. tcode ahora tiene **secciones**:
`tcode.statusBar.setSection(id, text)` — cada extensión escribe su propia
sección y no pisa a las demás.

Esta migración pasa `git-changes` a la API de secciones. Es la **única**
extensión que escribe en la barra (los linters ya no escriben, `7de79ca`).

## Cambios

- `status()` usa `tcode.statusBar.setSection("tcode.gitchanges", ...)` en las
  cuatro ramas (sin buffer, no es repo git, árbol limpio, y el resumen).
- El id de sección es el manifest id de la extensión (`tcode.gitchanges`).
- Versión: `1.2.0` → `1.3.0`.

## Convención

Los mensajes a la usuaria van en inglés (convención de la extensión). Las
secciones viven entre el nombre del archivo y el mensaje transitorio del
editor; el mensaje conserva su prioridad a la derecha.
