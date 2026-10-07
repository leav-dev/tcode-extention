// Verification harness for angular8-lint/main.lua.
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
	noCall   bool
	wantCall bool
}

func run(tc testCase) (actual []string, called bool, err error) {
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
		called = true
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
		called = true
		return 0
	}))

	if err := L.DoFile("../main.lua"); err != nil {
		return nil, false, err
	}
	if err := L.CallByParam(lua.P{
		Fn:      L.GetGlobal("check"),
		NRet:    0,
		Protect: true,
	}, lua.LNil, lua.LNil); err != nil {
		return nil, false, err
	}
	return actual, called, nil
}

func main() {
	cases := []testCase{
		{name: "non-angular noop", path: "a.ts", content: "const x = 1;\n", noCall: true},
		{name: "ng8 component clean", path: "foo.component.ts", content: "import { Component } from '@angular/core';\n@Component({ selector: 'app-foo', template: `<div></div>` })\nexport class FooComponent {}\n", want: nil, wantCall: true},
		{name: "ng8 standalone", path: "foo.component.ts", content: "@Component({ standalone: true, selector: 'app-foo', template: `` })\nexport class FooComponent {}\n", want: []string{"1:error:standalone components are not compatible with Angular 8 (introduced in v14)"}},
		{name: "ng8 signals", path: "foo.component.ts", content: "import { Component, signal } from '@angular/core';\n@Component({ selector: 'app-foo', template: `` })\nexport class FooComponent { count = signal(0); }\n", want: []string{"3:error:signals are not compatible with Angular 8 (introduced in v16)"}},
		{name: "ng8 input fn", path: "foo.component.ts", content: "import { Component, input } from '@angular/core';\n@Component({ selector: 'app-foo', template: `` })\nexport class FooComponent { title = input(''); }\n", want: []string{"3:error:input()/output() are not compatible with Angular 8, use @Input()/@Output()"}},
		{name: "ng8 at-if", path: "foo.component.html", content: "<div *ngIf=\"a\">x</div>\n@if (a) { <span>y</span> }\n", want: []string{"2:error:native control flow is not compatible with Angular 8, use *ngIf/*ngFor/*ngSwitch"}},
		{name: "ng8 defer", path: "foo.component.html", content: "<div *ngIf=\"a\">x</div>\n@defer { <span>y</span> }\n", want: []string{"2:error:deferrable views are not compatible with Angular 8 (introduced in v17)"}},
		{name: "ng8 string masked", path: "foo.component.ts", content: "import { Component } from '@angular/core';\nconst s = \"standalone: true\";\n@Component({ selector: 'app-foo', template: `` })\nexport class FooComponent {}\n", want: nil, wantCall: true},
	}
	// Registry-overflow regression: maskLine builds one table entry per char
	// and table.concat pushes every element onto the VM registry, so a single
	// line past ~5KB blew up with "registry overflow" on every save.
	cases = append(cases, testCase{name: "ng8 long line no overflow", path: "foo.component.ts",
		content: "import { Component } from '@angular/core';\n@Component({ selector: 'app-foo', template: `` })\nexport class FooComponent { s = \"" + strings.Repeat("x", 9000) + "\"; }\n",
		want: nil, wantCall: true})

	failures := 0
	for _, tc := range cases {
		actual, called, err := run(tc)
		if err != nil {
			fmt.Printf("FAIL %-28s lua error: %v\n", tc.name, err)
			failures++
			continue
		}
		sort.Strings(actual)
		want := append([]string(nil), tc.want...)
		sort.Strings(want)
		ok := strings.Join(actual, " | ") == strings.Join(want, " | ")
		if tc.noCall && called {
			ok = false
		}
		if tc.wantCall && !called {
			ok = false
		}
		status := "PASS"
		if !ok {
			status = "FAIL"
			failures++
		}
		exp := "(none)"
		if len(want) > 0 {
			exp = strings.Join(want, " | ")
		}
		act := "(none)"
		if len(actual) > 0 {
			act = strings.Join(actual, " | ")
		} else if called {
			act = "(clear)"
		}
		fmt.Printf("%s %-28s\n     expected: %s\n     actual:   %s\n", status, tc.name, exp, act)
	}
	fmt.Printf("\n%d case(s), %d failure(s)\n", len(cases), failures)
	if failures > 0 {
		os.Exit(1)
	}
}
