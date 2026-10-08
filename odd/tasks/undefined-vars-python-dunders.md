# undefined-vars: Python dunders flagged as undefined

## Symptom
In Python files, CPython module dunders such as `__file__` and `__name__`
were reported as `undefined '...'` warnings. The `if __name__ == "__main__"`
idiom flagged `__name__` on line 1.

## Root cause
The Python builtins set in `undefined-vars/main.lua` listed builtins like
`True`/`False`/`None`/`print`/`self` but no dunder globals, so every use of
`__file__`, `__name__`, `__doc__`, `__package__`, `__spec__`, `__loader__`,
`__cached__`, `__builtins__`, `__debug__`, `__import__`, `__build_class__`
fell through to the undefined-usage check.

## Fix
Added exactly these names to the Python builtins set in `main.lua`:
`__name__ __doc__ __package__ __loader__ __spec__ __file__ __cached__`
`__builtins__ __debug__ __import__ __build_class__`. No other logic changed.
Bumped `extension.json` patch version (1.0.7 -> 1.0.8) and added harness
regression cases (`x = __file__`, `if __name__ == "__main__"` produce no
diagnostics; `print(nope)` still flags).

## Acceptance
- `x = __file__` produces no diagnostics.
- `if __name__ == "__main__":` idiom produces no diagnostics.
- A truly undefined variable (e.g. `print(nope)`) still flags.
- Harness green: `cd undefined-vars/harness && GOFLAGS=-mod=mod GOPROXY=off go run .`
