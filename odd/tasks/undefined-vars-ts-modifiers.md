# undefined-vars: TS modifiers flagged as undefined

## Symptom
In TS/Angular files, class modifiers were reported as undefined variables:
`private foo = 1;` warned `undefined 'private'` (same for `public`,
`protected`, `override`, `accessor`).

## Root cause
The TS keywords set in `undefined-vars/main.lua` listed `static`, `get`,
`set`, `readonly`, `abstract`, `declare` but not `private`, `public`,
`protected`, `override`, `accessor`, so the main loop treated them as
identifier usages. (`constructor(private svc)` never warned only because
the shorthand-method path defines the whole param list, modifiers
included.)

## Fix
Added `private public protected override accessor` to the TS keywords set
(JS untouched: no such modifiers there). Modifiers are skipped like any
other non-handled keyword; member collection already knew them via its
own `mods` set. Bumped `extension.json` patch version (1.0.9 -> 1.0.10)
and added harness regression cases (private field, protected method,
override method, accessor field; all silent).

## Acceptance
- `private foo = 1;` + `this.foo` is silent (was `undefined 'private'`).
- Same for `protected`, `override` (with `extends`), `accessor`.
- The 4 new cases fail pre-fix with the reported symptom, pass post-fix.
- Harness green: `cd undefined-vars/harness && GOFLAGS=-mod=mod GOPROXY=off go run .`
