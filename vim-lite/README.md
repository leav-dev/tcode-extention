# Vim-lite (`tcode.vimlite`)

Vim muscle-memory keybindings for tcode.

## Installation

```sh
tcode --install-extension <git-url-or-local-path-of-this-repo>
```

## Keybindings

| Key | Command | Vim memory |
| --- | --- | --- |
| `alt+h` | `tcode.switchTabPrev` | previous tab |
| `alt+l` | `tcode.switchTabNext` | next tab |
| `alt+e` | `tcode.toggleExplorer` | explorer (vim `:e` opens a file) |
| `alt+w` | `tcode.save` | `:w` |
| `alt+shift+w` | `tcode.saveAs` | `:w <path>` |

## Limits

- Every binding carries a modifier on purpose: a plain-letter key (e.g.
  `w`) would collide with normal document typing — a rule of tcode's
  keybinding resolver, not a choice.
- Core shortcuts (`Ctrl+S`, `Ctrl+W`, `Ctrl+B`, …) always win; this
  extension cannot shadow them.
- There is no "insert vs normal" mode yet: this is a re-mapping pack, not a
  vim emulation. That will come with the scripting backend.