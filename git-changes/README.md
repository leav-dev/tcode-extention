# Git Changes

Extensión para tcode que muestra información de cambios de git en la barra de estado y marca las líneas con cambios en el gutter.

## Características

- **Barra de estado**: Muestra la rama actual, cantidad de archivos con cambios (staged, unstaged, untracked) y líneas agregadas/borradas
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
Git Changes [main]: 3 files (1 staged, 2 unstaged), +15 -8 lines
Git Changes [main]: clean working tree
Git Changes: clean working tree          # older editor without branch support
Git Changes: not a git repository
```

En detached HEAD se muestra el SHA corto (`Git Changes [a1b2c3d]: ...`).
Si el editor no expone la rama, el formato sin corchetes se mantiene.

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
