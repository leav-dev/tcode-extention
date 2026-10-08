# Graph Report - tcode-extention  (2026-10-08)

## Corpus Check
- 73 files · ~53,996 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 766 nodes · 766 edges · 61 communities (48 shown, 13 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `93774bcf`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- Feature: Linter de scope — variables definidas/indefinidas e imports (v1)
- Feature: HTML Tag Detection (extensión Lua, v3)
- Feature: Python Lint — detector de indentación y estructura para Python
- Git Changes Extension
- Git Changes
- Feature: Error Detector (extensión Lua, v1)
- python-lint/main.lua
- Feature: Angular 8 / Angular 21 lint extensions
- undefined-vars/main.lua
- unused-imports/main.lua
- Error Detector (`tcode.errordetector`)
- Feature: Diagnósticos inline a la derecha de la línea (editor tcode)
- Angular 21 Lint (`tcode.angular21lint`)
- Angular 8 Lint (`tcode.angular8lint`)
- Emacs-lite (`tcode.emacslite`)
- error-detector/main.lua
- Feature: Lote declarativo de extensiones (batch 1)
- Python Lint (`tcode.pylint`)
- angular21-lint/main.lua
- angular8-lint/main.lua
- python-lint/harness/main.go
- tcode-extensions
- Undefined Variables (`tcode.undefinedvars`)
- Unused Imports (`tcode.unusedimports`)
- Vim-lite (`tcode.vimlite`)
- angular21-lint/harness/main.go
- angular8-lint/harness/main.go
- error-detector/harness/main.go
- git-changes/main.lua
- angular21-lintharness
- angular8-lintharness
- edharness
- pylintharness
- Git Changes: status bar section
- undefined-vars/harness/main.go
- undefinedvarsharness
- util.ts
- unused-imports/harness/main.go
- base.ts
- helpers.py
- types.ts
- unusedimportsharness
- data-lint/main.lua
- Feature: Data Lint — validator for YAML / JSON / XML
- Data Lint (`tcode.datalint`)
- data-lint/harness/main.go
- dlharness
- Fix: undefined-vars flags `obj.ATTR,` as undefined
- Fix: undefined-vars must support multiline imports (all languages)
- AGENTS.md — tcode-extention conventions
- big.ts
- Fix: registry overflow en table.concat (todas las extensiones)
- Git Changes: show current branch
- Fix: undefined-vars flags comprehension vars used before `for` (py)
- git-changes/harness/main.go
- Git Changes: rama + ultimo commit encadenados al status
- longline.ts
- gcharness

## God Nodes (most connected - your core abstractions)
1. `Feature: Linter de scope — variables definidas/indefinidas e imports (v1)` - 17 edges
2. `Feature: HTML Tag Detection (extensión Lua, v3)` - 11 edges
3. `Feature: Data Lint — validator for YAML / JSON / XML` - 9 edges
4. `Feature: Error Detector (extensión Lua, v1)` - 9 edges
5. `Feature: Python Lint — detector de indentación y estructura para Python` - 9 edges
6. `Git Changes` - 7 edges
7. `Feature: Angular 8 / Angular 21 lint extensions` - 7 edges
8. `Git Changes Extension` - 7 edges
9. `Tareas` - 7 edges
10. `Spec técnico de checks` - 7 edges

## Surprising Connections (you probably didn't know these)
- None detected - all connections are within the same source files.

## Import Cycles
- None detected.

## Communities (61 total, 13 thin omitted)

### Community 0 - "Feature: Linter de scope — variables definidas/indefinidas e imports (v1)"
Cohesion: 0.09
Nodes (21): Balance, Cross-file de paquete (v1.2.0) — proyecto multi-archivo resuelto, Decisiones de producto (respondidas), Definiciones (qué se define y en qué scope), Evidencia, Feature: Linter de scope — variables definidas/indefinidas e imports (v1), Fix posterior: builtins predeclarados de Go (v1.0.3), Fix posterior: declaración múltiple (a, b := ) — v1.2.1 (+13 more)

### Community 1 - "Feature: HTML Tag Detection (extensión Lua, v3)"
Cohesion: 0.10
Nodes (20): Algoritmo htmlTagCheck, API Lua (sin cambios), Bugfixes encontrados por el harness, Decisiones de producto (v3), Decisión de producto, Decisión de producto, Estado del terreno, Evidencia (+12 more)

### Community 2 - "Feature: Python Lint — detector de indentación y estructura para Python"
Cohesion: 0.11
Nodes (18): API del editor usada, Bugs encontrados y corregidos (registro para el equipo), Decisiones de ambigüedad del spec (del worker, confirmadas), Decisiones de producto (respondidas), Evidencia, Feature: Python Lint — detector de indentación y estructura para Python, Fundamentos reutilizables, I. Indentación (+10 more)

### Community 3 - "Git Changes Extension"
Cohesion: 0.12
Nodes (15): 1. Agregar API de git a tcode (ScriptAPI), 2. Crear estructura de la extensión, 3. Implementar script Lua, 4. Calcular diff por archivo, 5. Marcar líneas en el gutter, 6. Tests, Alternativa 1: Solo conteo (simple), Alternativa 2: Conteo + marcado de líneas (completo) (+7 more)

### Community 4 - "Git Changes"
Cohesion: 0.20
Nodes (9): API utilizada, Características, Comandos, Dependencias, Formato de mensajes, Git Changes, Hooks, Instalación (+1 more)

### Community 5 - "Feature: Error Detector (extensión Lua, v1)"
Cohesion: 0.20
Nodes (9): API Lua (verificada, hito 1), Decisiones de producto (v1), Estado del terreno (contexto obligatorio), Evidencia, Feature: Error Detector (extensión Lua, v1), main.lua (borrador completo), Manifest (borrador), Plan de verificación (E2E, cuando el backend esté commiteado) (+1 more)

### Community 6 - "python-lint/main.lua"
Cohesion: 0.39
Nodes (7): check(), classify(), endsWithBackslash(), isPython(), joinChunks(), scanLine(), tokens()

### Community 7 - "Feature: Angular 8 / Angular 21 lint extensions"
Cohesion: 0.25
Nodes (7): Angular 21 checks (warning, except View Engine = error), Angular 8 checks (error), Feature: Angular 8 / Angular 21 lint extensions, Implementation notes, No-overlap rule, Product decisions, Tasks

### Community 8 - "undefined-vars/main.lua"
Cohesion: 0.46
Nodes (6): analyzeScope(), cfgFor(), check(), detectLanguage(), langTable(), scan()

### Community 9 - "unused-imports/main.lua"
Cohesion: 0.36
Nodes (6): analyzeImports(), cfgFor(), check(), detectLanguage(), langTable(), scan()

### Community 10 - "Error Detector (`tcode.errordetector`)"
Cohesion: 0.29
Nodes (6): Behavior, Checks, Development, Error Detector (`tcode.errordetector`), Installation, Language detection

### Community 11 - "Feature: Diagnósticos inline a la derecha de la línea (editor tcode)"
Cohesion: 0.29
Nodes (6): Division of labor, Evidencia de implementación, Feature: Diagnósticos inline a la derecha de la línea (editor tcode), Niveles de severidad (multi-nivel), Pedido del usuario, Respuesta a la duda de diseño: ¿el inline afecta los errores mostrados?

### Community 12 - "Angular 21 Lint (`tcode.angular21lint`)"
Cohesion: 0.33
Nodes (5): Angular 21 Lint (`tcode.angular21lint`), Behavior, Checks, Development, Installation

### Community 13 - "Angular 8 Lint (`tcode.angular8lint`)"
Cohesion: 0.33
Nodes (5): Angular 8 Lint (`tcode.angular8lint`), Behavior, Checks, Development, Installation

### Community 14 - "Emacs-lite (`tcode.emacslite`)"
Cohesion: 0.33
Nodes (5): Authentic chords that are NOT here, Chords, Emacs-lite (`tcode.emacslite`), Installation, Limits

### Community 15 - "error-detector/main.lua"
Cohesion: 0.53
Nodes (5): balanceCheck(), check(), detectLanguage(), htmlTagCheck(), parseAttrs()

### Community 16 - "Feature: Lote declarativo de extensiones (batch 1)"
Cohesion: 0.33
Nodes (5): Cambios posteriores, Description, Evidencia, Feature: Lote declarativo de extensiones (batch 1), Tasks

### Community 17 - "Python Lint (`tcode.pylint`)"
Cohesion: 0.33
Nodes (5): Behavior, Honest limits, Installation, Python Lint (`tcode.pylint`), What it detects

### Community 18 - "angular21-lint/main.lua"
Cohesion: 0.60
Nodes (5): check(), isAngularFile(), joinChunks(), legacyCheck(), maskLine()

### Community 19 - "angular8-lint/main.lua"
Cohesion: 0.60
Nodes (5): check(), isAngularFile(), joinChunks(), maskLine(), modernSyntaxCheck()

### Community 20 - "python-lint/harness/main.go"
Cohesion: 0.80
Nodes (4): buildCases(), testCase, main(), run()

### Community 21 - "tcode-extensions"
Cohesion: 0.40
Nodes (4): Catalog, Installing an extension, Status and roadmap, tcode-extensions

### Community 22 - "Undefined Variables (`tcode.undefinedvars`)"
Cohesion: 0.40
Nodes (4): Behavior, Installation, Notes and limits (v1), Undefined Variables (`tcode.undefinedvars`)

### Community 23 - "Unused Imports (`tcode.unusedimports`)"
Cohesion: 0.29
Nodes (6): Behavior, Development, Installation, Two directions, Unused Imports (`tcode.unusedimports`), What counts as "used"

### Community 24 - "Vim-lite (`tcode.vimlite`)"
Cohesion: 0.40
Nodes (4): Installation, Keybindings, Limits, Vim-lite (`tcode.vimlite`)

### Community 25 - "angular21-lint/harness/main.go"
Cohesion: 0.83
Nodes (3): testCase, main(), run()

### Community 26 - "angular8-lint/harness/main.go"
Cohesion: 0.83
Nodes (3): testCase, main(), run()

### Community 27 - "error-detector/harness/main.go"
Cohesion: 0.83
Nodes (3): testCase, main(), run()

### Community 28 - "git-changes/main.lua"
Cohesion: 0.70
Nodes (4): all(), fileSummary(), mark(), status()

### Community 34 - "Git Changes: status bar section"
Cohesion: 0.40
Nodes (4): Cambios, Convención, Git Changes: status bar section, Objetivo

### Community 35 - "undefined-vars/harness/main.go"
Cohesion: 0.83
Nodes (3): testCase, main(), run()

### Community 38 - "unused-imports/harness/main.go"
Cohesion: 0.83
Nodes (3): testCase, main(), run()

### Community 45 - "data-lint/main.lua"
Cohesion: 0.33
Nodes (11): add_xml(), check(), countQuote(), detectLang(), joinChunks(), jsonCheck(), sortDiags(), stripSpans() (+3 more)

### Community 46 - "Feature: Data Lint — validator for YAML / JSON / XML"
Cohesion: 0.20
Nodes (9): Editor API, Feature: Data Lint — validator for YAML / JSON / XML, Limits v1 (honest), Output, Product decisions (answered), Tasks, Technical spec, User request (+1 more)

### Community 47 - "Data Lint (`tcode.datalint`)"
Cohesion: 0.33
Nodes (5): Behavior, Data Lint (`tcode.datalint`), Honest limits, Installation, What it detects

### Community 48 - "data-lint/harness/main.go"
Cohesion: 0.83
Nodes (3): testCase, main(), run()

### Community 50 - "Fix: undefined-vars flags `obj.ATTR,` as undefined"
Cohesion: 0.29
Nodes (6): Fix, Fix: undefined-vars flags `obj.ATTR,` as undefined, Root cause (traced in analyzeScope, undefined-vars/main.lua), Tasks, User report (Django, Python), Verification

### Community 51 - "Fix: undefined-vars must support multiline imports (all languages)"
Cohesion: 0.29
Nodes (6): Current gaps (traced in undefined-vars/main.lua), Fix scope, Fix: undefined-vars must support multiline imports (all languages), Tasks, User report, Verification

### Community 52 - "AGENTS.md — tcode-extention conventions"
Cohesion: 0.50
Nodes (3): AGENTS.md — tcode-extention conventions, Definition of done for an extension change, Version bump (mandatory)

### Community 53 - "big.ts"
Cohesion: 0.00
Nodes (401): bigVersion, pad0, pad1, pad10, pad100, pad101, pad102, pad103 (+393 more)

### Community 54 - "Fix: registry overflow en table.concat (todas las extensiones)"
Cohesion: 0.29
Nodes (6): Causa raiz, Criterios de aceptacion, Fix: registry overflow en table.concat (todas las extensiones), Plan por extension, Reporte, Sitios (todos per-char + concat sin batch)

### Community 55 - "Git Changes: show current branch"
Cohesion: 0.29
Nodes (6): Alcance (dos repos), Criterios de aceptacion, Diseno, Git Changes: show current branch, Objetivo, Tareas

### Community 56 - "Fix: undefined-vars flags comprehension vars used before `for` (py)"
Cohesion: 0.29
Nodes (6): Fix, Fix: undefined-vars flags comprehension vars used before `for` (py), Root cause, Tasks, User report (Django, Python), Verification

### Community 57 - "git-changes/harness/main.go"
Cohesion: 0.53
Nodes (4): testCase, main(), run(), gitMock

### Community 58 - "Git Changes: rama + ultimo commit encadenados al status"
Cohesion: 0.33
Nodes (5): Criterios de aceptacion, Diseno, Git Changes: rama + ultimo commit encadenados al status, Pedido, Tareas

## Knowledge Gaps
- **590 isolated node(s):** `angular21-lintharness`, `angular8-lintharness`, `dlharness`, `edharness`, `gcharness` (+585 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **13 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **What connects `angular21-lintharness`, `angular8-lintharness`, `dlharness` to the rest of the system?**
  _590 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Feature: Linter de scope — variables definidas/indefinidas e imports (v1)` be split into smaller, more focused modules?**
  _Cohesion score 0.09090909090909091 - nodes in this community are weakly interconnected._
- **Should `Feature: HTML Tag Detection (extensión Lua, v3)` be split into smaller, more focused modules?**
  _Cohesion score 0.09523809523809523 - nodes in this community are weakly interconnected._
- **Should `Feature: Python Lint — detector de indentación y estructura para Python` be split into smaller, more focused modules?**
  _Cohesion score 0.10526315789473684 - nodes in this community are weakly interconnected._
- **Should `Git Changes Extension` be split into smaller, more focused modules?**
  _Cohesion score 0.125 - nodes in this community are weakly interconnected._
- **Should `big.ts` be split into smaller, more focused modules?**
  _Cohesion score 0.004962779156327543 - nodes in this community are weakly interconnected._