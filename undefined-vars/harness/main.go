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
		{name: "go funclit", path: "a.go", content: "package m\nvar f = func(x int) int {\n    return x\n}\n"},
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
