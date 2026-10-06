# Angular 21 Lint (`tcode.angular21lint`)

Compatibility lint for Angular 21 codebases: flags legacy patterns that
are deprecated or unsupported in v21 (NgModule structure, `@Input`/`@Output`
decorators, legacy structural directives, View Engine traces).

Severity `warning` (gutter `?`, amber) for deprecated-but-working patterns,
`error` (gutter `!`, red) for View Engine (unsupported).

Part of the linter family — the editor merges this extension's markers
with the other providers (per-provider diagnostics).

## Installation

```sh
tcode --install-extension <path>/angular21-lint
```

## Behavior

| Trigger | Action |
| --- | --- |
| On save (`onDidSaveBuffer`) | Runs `check()` and publishes diagnostics to gutter |
| `alt+shift+2` | On-demand check |

**Note:** This extension only runs on buffers that look like Angular files
(`@Component`, `@NgModule`, `@Injectable`, `@Directive`, `@Pipe`, or
Angular template syntax). Any other buffer is a no-op: it never touches
diagnostics.

**No overlap with Error Detector:** this extension never checks bracket
balance or HTML tag balance. Those stay in `tcode.errordetector`.

## Checks

| Pattern | Severity | Message |
| --- | --- | --- |
| `@NgModule` | warning | `NgModule is deprecated in Angular 21, prefer standalone components` |
| `@Input(`/`@Output(` | warning | `@Input/@Output are deprecated in Angular 21, use input()/output()` |
| `TestBed.configureTestingModule` | warning | `TestBed.configureTestingModule with NgModules is legacy in Angular 21, prefer standalone test setup` |
| `enableIvy: false` / `ViewEngine` | error | `View Engine is not supported in Angular 21 (Ivy only)` |
| `*ngIf` / `*ngFor` / `*ngSwitch` | warning | `legacy structural directives are deprecated in Angular 21, prefer @if/@for/@switch control flow` |

Strings and comments are masked before matching.

Every message is English.

## Development

A gopher-lua harness lives in [`harness/`](harness/). Run it with:

```sh
cd harness && go run .
```
