# Git Changes

Extensión para tcode que marca las líneas con cambios en el gutter. No escribe en la barra de estado.

## Características

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
| `tcode.gitchanges.mark` | Marca líneas con cambios en gutter | `alt+shift+m` |

### Hooks

- `onDidSaveBuffer`: Ejecuta `mark` automáticamente al guardar

## Gutter

- `i` (info): Línea agregada o modificada
- `?` (warning): Línea borrada

## Dependencias

- git debe estar disponible en el sistema
- El buffer activo debe estar en un repositorio git

## API utilizada

- `tcode.git.file_diff(path, staged)`: Diff de un archivo específico
- `tcode.diagnostics.set()`: Marcar líneas en el gutter
