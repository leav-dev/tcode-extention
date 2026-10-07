// Verification harness for angular21-lint/main.lua.
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
		{name: "ng21 standalone clean", path: "foo.component.ts", content: "import { Component, input } from '@angular/core';\n@Component({ standalone: true, selector: 'app-foo', template: `@if (a) { <span>x</span> }` })\nexport class FooComponent { title = input(''); }\n", want: nil, wantCall: true},
		{name: "ng21 ngmodule", path: "app.module.ts", content: "import { NgModule } from '@angular/core';\nimport { Component } from '@angular/core';\n@NgModule({ declarations: [] })\nexport class AppModule {}\n", want: []string{"3:warning:NgModule is deprecated in Angular 21, prefer standalone components"}},
		{name: "ng21 input decorator", path: "foo.component.ts", content: "import { Component, Input } from '@angular/core';\n@Component({ selector: 'app-foo', template: `` })\nexport class FooComponent { @Input() title = ''; }\n", want: []string{"3:warning:@Input/@Output are deprecated in Angular 21, use input()/output()"}},
		{name: "ng21 ngif", path: "foo.component.html", content: "<div *ngIf=\"a\">x</div>\n", want: []string{"1:warning:legacy structural directives are deprecated in Angular 21, prefer @if/@for/@switch control flow"}},
		{name: "ng21 viewengine", path: "foo.component.ts", content: "import { Component } from '@angular/core';\n// ViewEngine compat\n@Component({ selector: 'app-foo', template: `` })\nexport class FooComponent {}\n", want: nil, wantCall: true},
	}
	// Registry-overflow regression: maskLine builds one table entry per char
	// and table.concat pushes every element onto the VM registry, so a single
	// line past ~5KB blew up with "registry overflow" on every save.
	cases = append(cases, testCase{name: "ng21 long line no overflow", path: "foo.component.ts",
		content: "import { Component, input } from '@angular/core';\n@Component({ standalone: true, selector: 'app-foo', template: `` })\nexport class FooComponent { s = \"" + strings.Repeat("x", 9000) + "\"; }\n",
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
