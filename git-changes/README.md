# Git Changes

Extensión para tcode que muestra información de cambios de git en la barra de estado y marca las líneas con cambios en el gutter.

## Características

- **Status bar**: Shows branch plus file counts (S = staged, U = unstaged, ? = untracked) and added/deleted lines. Commit subject, author, date and hash are never shown.
- **Gutter**: Marks added lines (`+` = info), deleted lines (`-` = warning) and modified lines (`~` = info), each with its 1-indexed line number
- **Toggle**: Show gutter marks on first call, clear them on the second
- **Auto-update**: Se actualiza automáticamente al guardar el buffer

## Instalación

```sh
tcode --install-extension <path>/tcode-extentions/git-changes
```

## Uso

### Comandos

| Comando | Descripción | Keybinding |
|---------|-------------|------------|
| `tcode.gitchanges.status` | Muestra resumen en barra de estado | `alt+shift+g` |
| `tcode.gitchanges.mark` | Marca líneas con cambios en gutter | `alt+shift+m` |
| `tcode.gitchanges.toggle` | Shows marks on first call, clears on second | `alt+shift+t` |

### Hooks

- `onDidSaveBuffer`: Ejecuta `status` automáticamente al guardar

## Formato de mensajes

**Status bar:**
```
[main]: clean working tree
[feat]: 3 files (1 S, 2 U), +15 -8 lines
clean working tree                # older editor without branch
no active buffer
not a git repository
```

Detached HEAD shows the short SHA as branch (`[a1b2c3d]: ...`).
If the editor does not expose the branch, no scope prefix is shown.
Commit subject, author, date and hash are intentionally omitted.

**Gutter:**
- `+ line 12 added` (info): Línea agregada
- `- line 3 deleted` (warning): Línea borrada
- `~ line 7 modified` (info): Línea modificada

All gutter messages include the 1-indexed line number. Calling
`tcode.gitchanges.toggle` (`alt+shift+t`) shows the marks on the first
call and clears them on the second. With no active buffer or an empty
diff the toggle is a safe no-op (never raises).

## Dependencias

- git debe estar disponible en el sistema
- El buffer activo debe estar en un repositorio git

## API utilizada

- `tcode.git.status()`: Información de archivos y líneas con cambios
- `tcode.git.file_diff(path, staged)`: Diff de un archivo específico
- `tcode.diagnostics.set()`: Marcar líneas en el gutter
- `tcode.message()`: Mostrar mensajes en barra de estado
