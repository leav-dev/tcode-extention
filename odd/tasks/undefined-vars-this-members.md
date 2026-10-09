# undefined-vars: this./self. members never warned

## Symptom
In TS/Angular files, `this.anything` never produced a diagnostic, even when
the member did not exist anywhere in the document (e.g. `this.coutn` with a
`count` field, or `this.undefFunc()` with no such method). Same hole for
py `self.name`. Reported against an Angular 21 component.

## Root cause
The main loop skipped every identifier right after a `.` ("member selector
after an expression"), and the builtins branch swallowed py `self.x` chains
(`self` is a builtin). `this`/`self` member names were therefore never
checked against anything.

## Fix
Added a `collectThisMembers` pre-scan in `main.lua` (js/ts/py only):
class-body field/method names (modifiers skipped, get/set unwrapped),
constructor param properties (`constructor(private svc)` defines
`this.svc`), and dynamic assignments (`this.x = ...` / `self.x = ...`,
order-independent, `=>` excluded). The `.`-branch now warns
`undefined 'this.name'` / `undefined 'self.name'` when the member is not in
the set; the py builtins branch does the same for `self.x`. All other member
chains (`pkg.Fn`, `console.log`, `fn().prop`) are still skipped. Applies to
both property reads and calls (`this.foo()`), since the check runs before
the call-detection branch. Bumped `extension.json` patch version
(1.0.8 -> 1.0.9) and added harness regression cases.

## Acceptance
- `this.bar` with no member `bar` warns `undefined 'this.bar'`.
- `this.bar` with field/method/assignment/ctor-prop `bar` is silent.
- `this.undefFunc()` warns; `this.known()` (method) is silent.
- Angular signal `this.name()` with `name = input('')` is silent.
- Harness green: `cd undefined-vars/harness && GOFLAGS=-mod=mod GOPROXY=off go run .`

## Follow-up (review R3-001..R3-003, amended into this commit)
- R3-001: regression case only covered reads. Added `this.nope()` call
  case (warns) plus `this` outside a class (silent).
- R3-002: the class scan mistook `extends M({...})` mixin objects and
  `.class` properties for class bodies. The scan now requires the body
  `{` at heritage paren depth 0 (with `=>` guard) and ignores `class`
  after `.`; it also records class-body ranges.
- R3-003: `this`/`self` outside a class warned without context, and py
  `def` methods didn't count as members. The check is now gated to class
  context (js/ts ranges, py file-level) and py collects `def` names;
  `self.nope` in a class still warns, `self.whatever` with no class in
  the file stays silent.
