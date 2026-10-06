# Feature: Angular 8 / Angular 21 lint extensions

## Product decisions

Two separate extensions (user request), same monorepo conventions:

- `angular8-lint` (`tcode.angular8lint`): flags modern syntax that does not
  exist in Angular 8. Severity `error`. Keybinding `alt+shift+8`.
- `angular21-lint` (`tcode.angular21lint`): flags legacy patterns deprecated
  or unsupported in Angular 21. Severity `warning` (deprecated) / `error`
  (View Engine). Keybinding `alt+shift+2`.

Both run on `onDidSaveBuffer` + on-demand keybinding, only on buffers that
look like Angular files (decorators or template syntax); any other buffer
is a no-op (never touches diagnostics).

## No-overlap rule

Neither extension checks bracket balance or HTML tag balance. Those stay in
`tcode.errordetector`. The editor merges per-provider diagnostics, so the
extensions compose without stepping on each other.

## Angular 8 checks (error)

| Pattern | Message |
| --- | --- |
| `standalone: true` | standalone components are not compatible with Angular 8 (introduced in v14) |
| `signal(`/`computed(`/`effect(` | signals are not compatible with Angular 8 (introduced in v16) |
| `input(`/`output(` | input()/output() are not compatible with Angular 8, use @Input()/@Output() |
| `@if(`/`@for(`/`@switch(`/`@empty` | native control flow is not compatible with Angular 8, use *ngIf/*ngFor/*ngSwitch |
| `@defer` | deferrable views are not compatible with Angular 8 (introduced in v17) |

## Angular 21 checks (warning, except View Engine = error)

| Pattern | Message |
| --- | --- |
| `@NgModule` | NgModule is deprecated in Angular 21, prefer standalone components |
| `@Input(`/`@Output(` | @Input/@Output are deprecated in Angular 21, use input()/output() |
| `TestBed.configureTestingModule` | legacy test setup, prefer standalone test setup |
| `enableIvy: false` / `ViewEngine` | View Engine is not supported in Angular 21 (Ivy only) |
| `*ngIf` / `*ngFor` / `*ngSwitch` | legacy structural directives are deprecated, prefer @if/@for/@switch |

## Implementation notes

- Line-based scanners with string/comment masking (block comments tracked
  across lines). No language tables.
- Word boundaries via padded `[^%w_]` checks: frontier patterns (`%f[]`)
  are unreliable under gopher-lua (verified empirically).
- Harnesses: `angular8-lint/harness` (8 cases), `angular21-lint/harness`
  (6 cases), same gopher-lua stub pattern as `error-detector/harness`.

## Tasks

1. [x] angular8-lint: manifest + scanner + README + harness (8/8 PASS)
2. [x] angular21-lint: manifest + scanner + README + harness (6/6 PASS)
3. [x] Root README catalog
4. [ ] Commit
