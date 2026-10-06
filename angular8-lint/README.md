# Angular 8 Lint (`tcode.angular8lint`)

Compatibility lint for Angular 8 codebases: flags modern Angular syntax
that does not exist in v8 (standalone components, signals, native control
flow, `input()`/`output()`, deferrable views), severity `error` (gutter
`!`, red).

Part of the linter family — the editor merges this extension's markers
with the other providers (per-provider diagnostics).

## Installation

```sh
tcode --install-extension <path>/angular8-lint
```

## Behavior

| Trigger | Action |
| --- | --- |
| On save (`onDidSaveBuffer`) | Runs `check()` and publishes errors to gutter |
| `alt+shift+8` | On-demand check |

**Note:** This extension only runs on buffers that look like Angular files
(`@Component`, `@NgModule`, `@Injectable`, `@Directive`, `@Pipe`, or
Angular template syntax). Any other buffer is a no-op: it never touches
diagnostics.

**No overlap with Error Detector:** this extension never checks bracket
balance or HTML tag balance. Those stay in `tcode.errordetector`.

## Checks

| Pattern | Message |
| --- | --- |
| `standalone: true` | `standalone components are not compatible with Angular 8 (introduced in v14)` |
| `signal(`/`computed(`/`effect(` | `signals are not compatible with Angular 8 (introduced in v16)` |
| `input(`/`output(` | `input()/output() are not compatible with Angular 8, use @Input()/@Output()` |
| `@if(`/`@for(`/`@switch(`/`@empty` | `native control flow is not compatible with Angular 8, use *ngIf/*ngFor/*ngSwitch` |
| `@defer` | `deferrable views are not compatible with Angular 8 (introduced in v17)` |

Strings and comments are masked before matching.

Every message is English.

## Development

A gopher-lua harness lives in [`harness/`](harness/). Run it with:

```sh
cd harness && go run .
```
