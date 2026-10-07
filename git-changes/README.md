# Git Changes

Extensión para tcode que muestra información de cambios de git en la barra de estado y marca las líneas con cambios en el gutter.

## Características

- **Barra de estado**: Muestra rama + último commit (hash, subject, autor, fecha), cantidad de archivos con cambios (S = staged, U = unstaged, ? = untracked) y líneas agregadas/borradas
- **Gutter**: Marca líneas agregadas (`i` = info), borradas (`?` = warning) y modificadas (`~` = info)
- **Auto-actualización**: Se actualiza automáticamente al guardar el buffer

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

### Hooks

- `onDidSaveBuffer`: Ejecuta `status` automáticamente al guardar

## Formato de mensajes

**Barra de estado:**
```
Git Changes [main a1b2c3d]: Fix login (Ada, 2026-10-01) | 3 files (1 S, 2 U), +15 -8 lines
Git Changes [main a1b2c3d]: Fix login (Ada, 2026-10-01) | clean working tree
Git Changes [main]: clean working tree          # repo sin commits
Git Changes: clean working tree                # editor viejo sin rama ni commit
Git Changes: not a git repository
```

En detached HEAD se muestra el SHA corto (`Git Changes [a1b2c3d]: ...`).
Si el editor no expone rama o commit, cada segmento ausente se omite.

**Gutter:**
- `i` (info): Línea agregada o modificada
- `?` (warning): Línea borrada

## Dependencias

- git debe estar disponible en el sistema
- El buffer activo debe estar en un repositorio git

## API utilizada

- `tcode.git.status()`: Información de archivos y líneas con cambios
- `tcode.git.file_diff(path, staged)`: Diff de un archivo específico
- `tcode.diagnostics.set()`: Marcar líneas en el gutter
- `tcode.message()`: Mostrar mensajes en barra de estado
