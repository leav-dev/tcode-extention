# Emacs-lite (`tcode.emacslite`)

Emacs-style `ctrl+x …` chords for tcode.

## Installation

```sh
tcode --install-extension <git-url-or-local-path-of-this-repo>
```

## Chords

| Key | Command | Emacs memory |
| --- | --- | --- |
| `ctrl+x b` | `tcode.switchTabNext` | `C-x b` switch-to-buffer |
| `ctrl+x ctrl+f` | `tcode.toggleExplorer` | `C-x C-f` find-file |
| `ctrl+x k` | `tcode.closeTab` | `C-x k` kill-buffer |
| `ctrl+x u` | `tcode.undo` | `C-x u` undo |

A chord completes in two strokes: `ctrl+x` first (becomes pending) and the
second key fires it. Any other key cancels the pending chord and evaluates
itself as a new event.

## Authentic chords that are NOT here

The authentic Emacs `C-x C-s` (save), `C-x C-w` (save as) and `C-x C-k`
(kill buffer) are deliberately not declared: their second stroke is a key
the tcode **core** consumes before extensions (`Ctrl+S` saves, `Ctrl+W`
closes), and a binding that never fires is dead config. The core shortcut
already does what Emacs would do.

## Limits

- A chord requires at least one modifier in some stroke (resolver rule to
  avoid colliding with normal typing).
- There is no "minibuffer mode": this is a shortcut re-mapping, not an emacs
  emulation. That will come with the scripting backend.