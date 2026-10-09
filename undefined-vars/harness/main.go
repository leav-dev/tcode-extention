// Verification harness for undefined-vars/main.lua param handling.
package main

import (
	"fmt"
	"os"
	"sort"
	"strings"

	lua "github.com/yuin/gopher-lua"
)

type testCase struct {
	name     string
	path     string
	content  string
	want     []string
	wantCall bool
}

func run(tc testCase) (actual []string, err error) {
	L := lua.NewState()
	defer L.Close()

	tcode := L.NewTable()
	L.SetGlobal("tcode", tcode)
	path, content := tc.path, tc.content
	L.SetField(tcode, "buffer", L.NewFunction(func(L *lua.LState) int {
		L.Push(lua.LString(path))
		L.Push(lua.LString(content))
		return 2
	}))

	diags := L.NewTable()
	L.SetField(tcode, "diagnostics", diags)
	L.SetField(diags, "set", L.NewFunction(func(L *lua.LState) int {
		tbl := L.CheckTable(1)
		var err error
		tbl.ForEach(func(_, v lua.LValue) {
			if err != nil {
				return
			}
			lt, ok := v.(*lua.LTable)
			if !ok {
				err = fmt.Errorf("diagnostic item is not a table")
				return
			}
			actual = append(actual, fmt.Sprintf("%d:%s:%s",
				int(lua.LVAsNumber(L.GetField(lt, "line"))),
				lua.LVAsString(L.GetField(lt, "severity")),
				lua.LVAsString(L.GetField(lt, "message"))))
		})
		return 0
	}))
	L.SetField(diags, "clear", L.NewFunction(func(L *lua.LState) int {
		return 0
	}))

	if err := L.DoFile("../main.lua"); err != nil {
		return nil, err
	}
	if err := L.CallByParam(lua.P{
		Fn:      L.GetGlobal("check"),
		NRet:    0,
		Protect: true,
	}, lua.LNil, lua.LNil); err != nil {
		return nil, err
	}
	return actual, nil
}

func main() {
	cases := []testCase{
		{name: "js function decl", path: "a.js", content: "function f(x) {\n  return x;\n}\n"},
		{name: "js function expr", path: "a.js", content: "const f = function(x) {\n  return x;\n};\n"},
		{name: "js arrow paren expr", path: "a.js", content: "const f = (x) => x + 1;\n"},
		{name: "js arrow paren block", path: "a.js", content: "const f = (x) => {\n  return x;\n};\n"},
		{name: "js arrow single", path: "a.js", content: "const f = x => x + 1;\n"},
		{name: "js class method", path: "a.js", content: "class A {\n  foo(x) {\n    return x;\n  }\n}\n"},
		{name: "js object method", path: "a.js", content: "const o = {\n  foo(x) {\n    return x;\n  }\n};\n"},
		{name: "ts method typed", path: "a.ts", content: "class A {\n  foo(x: number): number {\n    return x;\n  }\n}\n"},
		{name: "py def", path: "a.py", content: "def f(x):\n    return x\n"},
		{name: "py lambda", path: "a.py", content: "f = lambda x: x + 1\n"},
		{name: "py method", path: "a.py", content: "class A:\n    def foo(self, x):\n        return x\n"},
		{name: "go func", path: "a.go", content: "package m\nfunc f(x int) int {\n    return x\n}\n"},
		{name: "go method", path: "a.go", content: "package m\ntype S struct{}\nfunc (s S) M(x int) int {\n    return x\n}\n"},
		{name: "go generic", path: "a.go", content: "package m\nfunc f[T any](x T) T {\n    return x\n}\n"},
		{name: "js catch param", path: "a.js", content: "function foo() {}\nfunction bar(x) {\n  return x;\n}\ntry {\n  foo();\n} catch (e) {\n  bar(e);\n}\n"},
		{name: "js getter setter", path: "a.js", content: "class A {\n  get foo() {\n    return this._x;\n  }\n  set foo(x) {\n    this._x = x;\n  }\n}\n"},
		{name: "js async method", path: "a.js", content: "class A {\n  async foo(x) {\n    return x;\n  }\n}\n"},
		{name: "js nested arrow", path: "a.js", content: "class A {\n  foo(xs) {\n    return xs.map(x => x + 1);\n  }\n}\n"},
		{name: "js call still flagged", path: "a.js", content: "foo(1);\n", want: []string{"1:warning:undefined 'foo'"}},
		{name: "js if no overdef", path: "a.js", content: "if (x) {\n  y(x);\n}\n", want: []string{"1:warning:undefined 'x'", "2:warning:undefined 'x'", "2:warning:undefined 'y'"}},
		{name: "go generic method", path: "a.go", content: "package m\ntype S struct{}\nfunc (s S) M[T any](x T) T {\n    return x\n}\n"},
		{name: "go generic funclit", path: "a.go", content: "package m\nvar f = func[T any](x T) T {\n    return x\n}\n"},
		{name: "ts method ret type", path: "a.ts", content: "class A {\n  foo(x: number): number {\n    return x;\n  }\n}\n"},
		{name: "ts overload", path: "a.ts", content: "class A {\n  foo(x: string): void;\n  foo(x: any) {\n    return x;\n  }\n}\n"},
		{name: "ts arrow ret type", path: "a.ts", content: "const f = (x: number): number => x + 1;\n"},
		{name: "ts method generic ret", path: "a.ts", content: "class A {\n  foo(x: number): Array<string> {\n    return [x];\n  }\n}\n"},
		{name: "ts abstract method", path: "a.ts", content: "abstract class A {\n  abstract foo(x: number): void;\n}\n"},
		{name: "ts generic fn", path: "a.ts", content: "function foo<T>(x: T): T {\n  return x;\n}\n"},
		{name: "ts generic method", path: "a.ts", content: "class A {\n  foo<T>(x: T): T {\n    return x;\n  }\n}\n"},
		{name: "ts generic arrow", path: "a.ts", content: "const f = <T>(x: T): T => x;\n"},
		{name: "ts generic class", path: "a.ts", content: "class Box<T> {\n  v!: T;\n  get(): T {\n    return this.v;\n  }\n}\n"},
		{name: "ts explicit targs", path: "a.ts", content: "declare function foo<T>(x: T): T;\nfoo<string>('a');\n"},
		{name: "ts ctor private", path: "a.ts", content: "import { Svc } from './svc';\nclass A {\n  constructor(private svc: Svc) {\n    svc.go();\n  }\n}\n"},
		{name: "ts as-expr", path: "a.ts", content: "const x = 1;\nconst y = x as string;\n"},
		{name: "ts targs call", path: "a.ts", content: "import { T } from './t';\ndeclare function foo<U>(x: U): U;\nfoo<T>('a');\n"},
		{name: "ts extends generic", path: "a.ts", content: "import { B } from './b';\nclass A<T> extends B<T> {\n  v!: T;\n}\n"},
		{name: "ts anon class", path: "a.ts", content: "export default class {\n  foo(x) {\n    return x;\n  }\n}\nconst y = 1;\n"},
		{name: "ts tparam constraint", path: "a.ts", content: "function foo<T extends (...args: any[]) => any>(x: T): T {\n  return x;\n}\n"},
		{name: "ts trailing comma", path: "a.tsx", content: "const f = <T,>(x: T): T => x;\n"},
		{name: "ts this undef", path: "a.ts", content: "class A {\n  foo() {\n    return this.bar;\n  }\n}\n", want: []string{"3:warning:undefined 'this.bar'"}},
		{name: "ts this field", path: "a.ts", content: "class A {\n  bar = 1;\n  foo() {\n    return this.bar;\n  }\n}\n"},
		{name: "ts this method", path: "a.ts", content: "class A {\n  bar() {}\n  foo() {\n    return this.bar;\n  }\n}\n"},
		{name: "ts this assigned", path: "a.ts", content: "class A {\n  foo() {\n    this.bar = 1;\n    return this.bar;\n  }\n}\n"},
		{name: "ts this ctor prop", path: "a.ts", content: "import { Svc } from './svc';\nclass A {\n  constructor(private svc: Svc) {\n    return this.svc;\n  }\n}\n"},
		{name: "ts this ctor undef", path: "a.ts", content: "import { Svc } from './svc';\nclass A {\n  constructor(private svc: Svc) {\n    return this.other;\n  }\n}\n", want: []string{"4:warning:undefined 'this.other'"}},
		{name: "ts this call undef", path: "a.ts", content: "class A {\n  foo() {\n    return this.nope();\n  }\n}\n", want: []string{"3:warning:undefined 'this.nope'"}},
		{name: "ts this outside class", path: "a.ts", content: "function f() {\n  return this.whatever;\n}\n"},
		{name: "ts extends mixin obj", path: "a.ts", content: "function M(o) {\n  return o;\n}\nclass A extends M({}) {\n  f = 1;\n  g() {\n    return this.f;\n  }\n}\n"},
		{name: "ts class prop ignored", path: "a.ts", content: "const o = {};\no.class = function(x) {\n  return x;\n};\no.class({bar: 1});\nclass A {\n  f = 1;\n  g() {\n    return this.bar;\n  }\n}\n", want: []string{"9:warning:undefined 'this.bar'"}},
		{name: "py self method", path: "a.py", content: "class A:\n    def bar(self):\n        pass\n    def foo(self):\n        return self.bar\n"},
		{name: "py self undef", path: "a.py", content: "class A:\n    def foo(self):\n        return self.nope\n", want: []string{"3:warning:undefined 'self.nope'"}},
		{name: "py self outside class", path: "a.py", content: "def f():\n    return self.whatever\n"},
		{name: "ts param not member", path: "a.ts", content: "class A {\n  foo(x) {\n    return this.x;\n  }\n}\n", want: []string{"3:warning:undefined 'this.x'"}},
		{name: "ts type not member", path: "a.ts", content: "class A {\n  foo(): Bar {\n    return this.Bar;\n  }\n}\n", want: []string{"3:warning:undefined 'this.Bar'"}},
		{name: "ts static block typo", path: "a.ts", content: "function init() {}\nclass A {\n  static {\n    init();\n  }\n  f = 1;\n  g() {\n    return this.typo;\n  }\n}\n", want: []string{"8:warning:undefined 'this.typo'"}},
		{name: "go funclit", path: "a.go", content: "package m\nvar f = func(x int) int {\n    return x\n}\n"},
		{name: "py member chain trailing comma", path: "a.py", content: "from rest_framework import status\n{'status': status.HTTP_200_OK,}\n"},
		{name: "py loop member trailing comma", path: "a.py", content: "snaps = []\nfor snap in snaps:\n    d = {'grupo_id': snap.grupo_id,}\n"},
		{name: "py undef base trailing comma", path: "a.py", content: "x = foo.bar,\n", want: []string{"1:warning:undefined 'foo'"}},
		{name: "py from multiline parens", path: "a.py", content: "from .models import (\n    A,\n    B,\n)\nprint(A)\nprint(B)\n"},
		{name: "py from single multi", path: "a.py", content: "from .models import A, B\nprint(A)\nprint(B)\n"},
		{name: "py from alias", path: "a.py", content: "from x import y as z\nprint(z)\n"},
		{name: "py import comma", path: "a.py", content: "import os, sys\nprint(os)\nprint(sys)\n"},
		{name: "py import backslash cont", path: "a.py", content: "import os, \\\n    sys\nprint(os)\nprint(sys)\n"},
		{name: "js multiline import", path: "a.js", content: "import {\n  A,\n  B\n} from 'm';\nconsole.log(A, B);\n"},
		{name: "go multiline import", path: "a.go", content: "package m\nimport (\n  \"fmt\"\n  alias \"x/y\"\n)\nfunc f() {\n  fmt.Println(alias.V)\n}\n"},
		{name: "go struct fields", path: "a.go", content: "package m\ntype S struct {\n\tName string\n\tAge int\n}\n"},
		{name: "go interface methods", path: "a.go", content: "package m\ntype I interface {\n\tFoo()\n\tBar(x int) string\n}\n"},
		{name: "go var struct", path: "a.go", content: "package m\nvar V struct {\n\tField string\n}\n"},
		{name: "go generic type", path: "a.go", content: "package m\ntype Box[T any] struct {\n\tV T\n}\n"},
		{name: "go type alias struct", path: "a.go", content: "package m\ntype Alias = struct {\n\tF string\n}\n"},
		{name: "go struct result", path: "a.go", content: "package m\nfunc New() struct {\n\tA int\n} {\n\treturn struct {\n\t\tA int\n\t}{A: 1}\n}\n"},
		{name: "go undef beside struct", path: "a.go", content: "package m\ntype S struct {\n\tName string\n}\nfunc f() {\n\tprintln(nope)\n}\n", want: []string{"6:warning:undefined 'nope'"}},
		{name: "py truly undef", path: "a.py", content: "print(nope)\n", want: []string{"1:warning:undefined 'nope'"}},
		{name: "py listcompr use-before-for", path: "a.py", content: "instituciones = []\nmissing_ids = [\n    str(i['institucion_id'])\n    for i in instituciones\n    if i.get('institucion_id') and not i.get('institucion_dane')\n]\n"},
		{name: "py dictcompr", path: "a.py", content: "items = []\nd = {k: v for k, v in items}\n"},
		{name: "py generator", path: "a.py", content: "items = []\ns = sum(x for x in items)\n"},
		{name: "py regular loop", path: "a.py", content: "items = []\nfor i in items:\n    print(i)\n"},
		{name: "py dunder file", path: "a.py", content: "x = __file__\n"},
		{name: "py dunder name main", path: "a.py", content: "if __name__ == \"__main__\":\n    print(__name__)\n"},
		{name: "py dunder still undef", path: "a.py", content: "print(nope)\n", want: []string{"1:warning:undefined 'nope'"}},
	}
	failures := 0
	for _, tc := range cases {
		actual, err := run(tc)
		if err != nil {
			fmt.Printf("FAIL %-22s lua error: %v\n", tc.name, err)
			failures++
			continue
		}
		sort.Strings(actual)
		want := append([]string(nil), tc.want...)
		sort.Strings(want)
		ok := strings.Join(actual, " | ") == strings.Join(want, " | ")
		if tc.wantCall && len(actual) == 0 && len(want) == 0 {
			// clear() called: run() does not track it here; verified manually
		}
		status := "PASS"
		if !ok {
			status = "FAIL"
			failures++
		}
		fmt.Printf("%s %-22s %s\n", status, tc.name, strings.Join(actual, " | "))
	}
	fmt.Printf("\n%d case(s) with findings/errors\n", failures)
	if failures > 0 {
		os.Exit(1)
	}
}
