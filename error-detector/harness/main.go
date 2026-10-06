// Temporary verification harness for error-detector/main.lua.
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
	want     []string // "line:severity:message"
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
		{name: "html unclosed div", path: "a.html", content: "<div>\n", want: []string{"1:error:'<div>' never closed"}},
		{name: "html balanced", path: "a.html", content: "<div></div>\n", want: nil, wantCall: true},
		{name: "html doctype ok", path: "a.html", content: "<!DOCTYPE html>\n<html></html>\n", want: nil, wantCall: true},
		{name: "html doctype dup", path: "a.html", content: "<!DOCTYPE html>\n<!DOCTYPE html>\n<html></html>\n", want: []string{"2:error:Duplicate <!DOCTYPE> declaration"}},
		{name: "html doctype late", path: "a.html", content: "<p>x</p>\n<!DOCTYPE html>\n", want: []string{"2:error:<!DOCTYPE> must be the first element"}},
		{name: "html malformed space", path: "a.html", content: "< div></ div>\n", want: []string{"1:error:Malformed tag: space after '<'", "1:error:Malformed tag: space after '</'"}},
		{name: "html tag never closed", path: "a.html", content: "<div\n", want: []string{"1:error:Tag '<div>' never closed"}},
		{name: "html boolean attr ok", path: "a.html", content: "<input disabled>\n", want: nil, wantCall: true},
		{name: "html attr multi line", path: "a.html", content: "<div\n  class=\"a\"\n  id=\"b\">x</div>\n", want: nil, wantCall: true},
		{name: "html empty tag", path: "a.html", content: "<>\n", want: []string{"1:error:Empty tag '<>'"}},
		{name: "html attr no value", path: "a.html", content: "<div class=>x</div>\n", want: []string{"1:error:Attribute 'class' without value"}},
		{name: "html attr dup", path: "a.html", content: "<div id=\"a\" id=\"b\"></div>\n", want: []string{"1:error:Duplicate attribute 'id'"}},
		{name: "go no html check", path: "a.go", content: "func f() {\n\tx := \"<div>\"\n}\n", want: nil, wantCall: true},
		{name: "go unclosed brace", path: "a.go", content: "func f() {\n", want: []string{"1:error:'{' never closed"}},
		{name: "js template literal ok", path: "a.js", content: "const s = `a{b`;\n", want: nil, wantCall: true},
		{name: "js unclosed brace", path: "a.js", content: "function f() {\n", want: []string{"1:error:'{' never closed"}},
		{name: "py mismatch", path: "a.py", content: "x = (]\n", want: []string{"1:error:']' does not match '('"}},
		{name: "ts no html check", path: "a.ts", content: "const x = \"<div>\";\n", want: nil, wantCall: true},
		{name: "txt unknown balance only", path: "a.txt", content: "<div>\n{ x\n", want: []string{"2:error:'{' never closed"}},
		{name: "htm extension", path: "a.htm", content: "<span>\n", want: []string{"1:error:'<span>' never closed"}},
		{name: "xhtml extension", path: "a.xhtml", content: "<span>\n", want: []string{"1:error:'<span>' never closed"}},
		{name: "svg extension", path: "a.svg", content: "<circle>\n", want: []string{"1:error:'<circle>' never closed"}},
		{name: "html comment unterminated", path: "a.html", content: "<!-- x\n", want: []string{"1:error:HTML comment never closed"}},
		{name: "html self closing ok", path: "a.html", content: "<br>\n<img src=\"a\">\n", want: nil, wantCall: true},
		{name: "uppercase ext", path: "A.HTML", content: "<div>\n", want: []string{"1:error:'<div>' never closed"}},
	}

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
