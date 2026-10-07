// Temporary verification harness for data-lint/main.lua.
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
		// JSON
		{name: "json valid", path: "a.json", content: "{\"a\": 1}\n", want: nil, wantCall: true},
		{name: "json trailing comma", path: "a.json", content: "{\"a\": 1,}\n", want: []string{"1:error:trailing comma"}},
		{name: "json missing comma", path: "a.json", content: "{\"a\": 1 \"b\": 2}\n", want: []string{"1:error:missing comma between members"}},
		{name: "json missing colon", path: "a.json", content: "{\"a\" 1}\n", want: []string{"1:error:missing ':' after object key"}},
		{name: "json single quote", path: "a.json", content: "{\"a\": 'hi'}\n", want: []string{"1:error:single-quoted strings are not allowed in JSON, use double quotes"}},
		{name: "json comment", path: "a.json", content: "{\"a\": 1} // hi\n", want: []string{"1:error:comments are not allowed in JSON"}},
		{name: "json duplicate key", path: "a.json", content: "{\"a\": 1, \"a\": 2}\n", want: []string{"1:warning:duplicate key \"a\" in the same object"}},
		{name: "json unclosed bracket", path: "a.json", content: "{\"a\": 1\n", want: []string{"1:error:'{' never closed"}},
		// YAML
		{name: "yaml valid", path: "a.yml", content: "a: 1\nb: 2\n", want: nil, wantCall: true},
		{name: "yaml tab indent", path: "a.yml", content: "a: 1\n\tb: 2\n", want: []string{"2:error:tabs are not allowed for indentation, use spaces"}},
		{name: "yaml mixed indent", path: "a.yaml", content: "a:\n \tb: 2\n", want: []string{"2:error:mixed tabs and spaces in indentation"}},
		{name: "yaml mapping no colon", path: "a.yaml", content: "key value\n", want: []string{"1:error:mapping values require ':' between key and value"}},
		{name: "yaml duplicate key", path: "a.yml", content: "a: 1\na: 2\n", want: []string{"2:warning:duplicate key \"a\" at the same level"}},
		{name: "yaml unterminated quote", path: "a.yml", content: "a: \"hi\n", want: []string{"1:error:unterminated quoted string"}},
		{name: "yaml block scalar ok", path: "a.yml", content: "a: |\n  hello\n  world\n", want: nil, wantCall: true},
		{name: "yaml inconsistent indent", path: "a.yml", content: "a:\n    b: 1\n  c: 2\n", want: []string{"3:error:inconsistent indentation"}},
		// Registry-overflow regression: stripSpans builds one table entry per
		// char and table.concat pushes every element onto the VM registry, so a
		// single line past ~5KB blew up with "registry overflow" on every save.
		{name: "yaml long line no overflow", path: "a.yml", content: "data: " + strings.Repeat("x", 9000) + "\n", want: nil, wantCall: true},
		// XML
		{name: "xml valid", path: "a.xml", content: "<a><b/></a>\n", want: nil, wantCall: true},
		{name: "xml mismatch", path: "a.xml", content: "<a></b>\n", want: []string{"1:error:'</b>' does not match '<a>'"}},
		{name: "xml unclosed", path: "a.xml", content: "<a>\n", want: []string{"1:error:'<a>' never closed"}},
		{name: "xml duplicate attr", path: "a.xml", content: "<a id=\"1\" id=\"2\"/>\n", want: []string{"1:error:duplicate attribute 'id'"}},
		{name: "xml multiple roots", path: "a.xml", content: "<a/>\n<b/>\n", want: []string{"2:error:multiple root elements"}},
		{name: "xml unclosed comment", path: "a.xml", content: "<!-- hi\n", want: []string{"1:error:comment never closed"}},
		// no-op files: must not touch diagnostics
		{name: "go no-op", path: "a.go", content: "package main\n", want: nil, noCall: true},
		{name: "svg no-op", path: "a.svg", content: "<circle>\n", want: nil, noCall: true},
	}

	failures := 0
	for _, tc := range cases {
		actual, called, err := run(tc)
		if err != nil {
			fmt.Printf("FAIL %-24s lua error: %v\n", tc.name, err)
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
		fmt.Printf("%s %-24s\n     expected: %s\n     actual:   %s\n", status, tc.name, exp, act)
	}
	fmt.Printf("\n%d case(s), %d failure(s)\n", len(cases), failures)
	if failures > 0 {
		os.Exit(1)
	}
}
