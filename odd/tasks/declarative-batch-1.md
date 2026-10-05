# Feature: Lote declarativo de extensiones (batch 1)

## Description

Primer lote del workspace `tcode-extentions` con el sistema declarativo de
extensiones de `tcode` (editor TUI en Go). El modelo es declarativo por
diseño: una extensión es un repo git con `extension.json` en su raíz que
declara comandos (stubs), keybindings y hooks — sin ejecutar código (el
backend de scripting WASM/Lua es un milestone posterior).

Estas tres extensiones ejercen TODA la superficie actual: keybindings
simples con mods, chords de dos tiempos, y el bus de hooks de buffer.

Decisiones de producto (usuario):

- **vim-lite** (`tcode.vimlite`): atajos con memoria muscular de vim
  (`alt+h/l` pestañas, `alt+e` explorador, `alt+w` guardar, `alt+shift+w`
  guardar como). Todos con modificador: una letra sin mod colisionaría con
  el tecleo normal del documento (regla del resolver de tcode).
- **emacs-lite** (`tcode.emacslite`): chords `ctrl+x <tecla>` al estilo
  emacs. Los chords auténticos cuyo segundo tiempo es una tecla del núcleo
  (C-x C-s, C-x C-w, C-x C-k) NO se declaran: el núcleo gana siempre y el
  binding quedaría muerto. Se documenta el límite en el README.
- **autosave** (`tcode.autosave`): hook `onDidCloseBuffer → tcode.save` —
  al cerrar una pestaña guarda el buffer que queda activo (hábito "no
  perder trabajo"). Límite documentado: cerrar la última pestaña deja el
  workspace vacío y el save no aplica (mensaje honesto en la barra).
  Incluye `alt+shift+s → tcode.saveAs` como camino alternativo.

Estructura: un repo git por extensión (el instalador clona un repo con
`extension.json` en su raíz; no hay marketplace). Cada repo lleva su README
y su manifest validado contra el esquema real de `internal/ext`.

Verificación E2E: instalar las tres desde la ruta local con
`tcode --install-extension`, listar, remover y reinstalar — el validador
real del editor es el test de verdad.

## Tasks

1. Scaffold del workspace: README raíz y la estructura de 3 subrepos.
2. Extensión `tcode.vimlite` (manifest + README + commit).
3. Extensión `tcode.emacslite` (manifest + README + commit).
4. Extensión `tcode.autosave` (manifest + README + commit).
5. Verificación E2E con el editor: install, list, remove, reinstall.

## Evidencia

Commits por extensión (un work-unit cada uno, en su propio repo):

- `vim-lite/` — `82c04af` feat: extension vim-lite con keybindings de memoria vim
- `emacs-lite/` — `da8b6b0` feat: extension emacs-lite con chords ctrl+x
- `autosave/` — `f164f92` feat: extension autosave con hook onDidCloseBuffer

Verificación E2E (binario compilado del fuente `tcode`):

- install de las 3 desde ruta local → validadas ("Instalada" + id).
- `--list-extensions` → `tcode.autosave`, `tcode.emacslite`, `tcode.vimlite`
  (nombre + v1.0.0).
- remove `tcode.autosave` → reinstall → reemplazo OK.
- Negativo: manifest con `meta+w` (modificador desconocido) → rechazado con
  error claro, exit 1, sin tocar las instaladas.
- `go test ./internal/ext/...` → ok.

Hallazgo del negativo: una tecla letra sin modificador (`w`) es gramática
VÁLIDA para el validator (la colisión con el tecleo normal es un problema del
resolver, no de validación). El lote la evita por diseño, pero el esquema no
la rechaza — decisión del editor, documentada como límite de estas
extensiones.

## Cambios posteriores

- **Autosave retirado** (decisión del usuario): el comportamiento pasa a ser
  ajuste nativo del editor. Desinstalado del usuario
  (`tcode --remove-extension tcode.autosave`) y carpeta `autosave/` eliminada
  del workspace. Queda la evidencia del commit `f164f92` y el diseño
  (hook `onDidCloseBuffer → tcode.save` + `alt+shift+s → tcode.saveAs`).
- El editor arranca el **milestone de scripting Lua** (gopher-lua, sin cgo;
  `odd/tasks/scripting-backend.md` en el repo tcode, hito 1 en curso): las
  extensiones declarativas podrán correr lógica propia vía tabla `tcode`.
  Con scripting, vim-lite/emacs-lite pueden crecer (modos reales) y llegan
  las extensiones con lógica: error detection, formatter on save, widgets.