// Verification harness for unused-imports/main.lua.
// Includes a tcode.read_file stub backed by testdata/ so direction-2
// (existence) checks run exactly like in the editor.
package main

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	lua "github.com/yuin/gopher-lua"
)

type testCase struct {
	name     string
	path     string
	content  string
	want     []string // "line:severity:message"
	wantCall bool
}

var baseDir = "testdata"

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
	// read_file stub: resolves rel against testdata/<bufferdir>, mimics
	// the editor (nil on missing/escape/non-regular).
	L.SetField(tcode, "read_file", L.NewFunction(func(L *lua.LState) int {
		rel := L.CheckString(1)
		dir := filepath.Dir(path)
		full := filepath.Join(baseDir, dir, rel)
		cleanBase, _ := filepath.Abs(filepath.Join(baseDir, dir))
		_ = cleanBase
		info, statErr := os.Stat(full)
		if statErr != nil || !info.Mode().IsRegular() {
			return 0
		}
		data, readErr := os.ReadFile(full)
		if readErr != nil {
			return 0
		}
		t := L.NewTable()
		abs, _ := filepath.Abs(full)
		t.RawSetString("path", lua.LString(abs))
		t.RawSetString("content", lua.LString(string(data)))
		L.Push(t)
		return 1
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
		// Direction 1 basics
		{name: "js unused", path: "proj/a.js", content: "import { helper } from './util';\n", want: []string{"1:warning:unused import 'helper'"}},
		{name: "js used clean", path: "proj/main.ts", content: "import { helper } from './util';\nhelper();\n", want: nil, wantCall: true},
		// Direction 2: JS/TS
		{name: "js named missing", path: "proj/main.ts", content: "import { nope } from './util';\nnope();\n", want: []string{"1:error:unresolved import 'nope' from './util'"}},
		{name: "js default ok", path: "proj/main.ts", content: "import Util from './util';\nnew Util();\n", want: nil, wantCall: true},
		{name: "js default missing", path: "proj/main.ts", content: "import L from './legacy';\nL();\n", want: []string{"1:error:unresolved import 'default' from './legacy'"}},
		{name: "js namespace ok", path: "proj/main.ts", content: "import * as U from './util';\nU.helper();\n", want: nil, wantCall: true},
		{name: "js alias ok", path: "proj/main.ts", content: "import { helper as h } from './util';\nh();\n", want: nil, wantCall: true},
		{name: "js alias missing remote", path: "proj/main.ts", content: "import { nope as h } from './util';\nh();\n", want: []string{"1:error:unresolved import 'nope' from './util'"}},
		{name: "js json skipped", path: "proj/main.ts", content: "import data from './data.json';\nuse(data);\n", want: nil, wantCall: true},
		{name: "js missing file", path: "proj/main.ts", content: "import { a } from './missing';\na();\n", want: []string{"1:error:unresolved import 'a' from './missing'"}},
		{name: "py missing file", path: "proj/main.py", content: "from .nosuch import a\na()\n", want: []string{"1:error:unresolved import 'a' from '.nosuch'"}},
		{name: "js bare skipped", path: "proj/main.ts", content: "import { useState } from 'react';\nuseState(0);\n", want: nil, wantCall: true},
		{name: "js reexport chase", path: "proj/main.ts", content: "import { helper } from './reexp';\nhelper();\n", want: nil, wantCall: true},
		{name: "js both directions", path: "proj/main.ts", content: "import { nope } from './util';\n", want: []string{"1:error:unresolved import 'nope' from './util'", "1:warning:unused import 'nope'"}},
		// Direction 2: Python
		{name: "py from ok", path: "proj/main.py", content: "from .helpers import helper\nhelper()\n", want: nil, wantCall: true},
		{name: "py from missing", path: "proj/main.py", content: "from .helpers import nope\nnope()\n", want: []string{"1:error:unresolved import 'nope' from '.helpers'"}},
		{name: "py from dot ok", path: "proj/main.py", content: "from . import helpers\nhelpers.helper()\n", want: nil, wantCall: true},
		{name: "py from dot missing", path: "proj/main.py", content: "from . import nosuch\n", want: []string{"1:error:unresolved import 'nosuch' from '.'", "1:warning:unused import 'nosuch'"}},
		{name: "py absolute skipped", path: "proj/main.py", content: "from os import path\npath.join(\"a\")\n", want: nil, wantCall: true},
		{name: "py alias ok", path: "proj/main.py", content: "from .helpers import helper as h\nh()\n", want: nil, wantCall: true},
		// Go: direction 2 out of scope
		{name: "ts generic constraint uses import", path: "proj/a.ts", content: "import { Base } from './base';\nfunction foo<T extends Base>(x: T): T {\n  return x;\n}\nfoo(new Base());\n", want: nil, wantCall: true},
		{name: "ts generic method import", path: "proj/a.ts", content: "import { Base } from './base';\nclass A {\n  foo<T extends Base>(x: T): T {\n    return x;\n  }\n}\nnew A().foo(new Base());\n", want: nil, wantCall: true},
		{name: "ts generic class import", path: "proj/a.ts", content: "import { Base } from './base';\nclass Box<T extends Base> {\n  v!: T;\n}\nnew Box<Base>();\n", want: nil, wantCall: true},
		{name: "go imports skipped", path: "a.go", content: "package m\nimport \"fmt\"\nfunc f() {\n    fmt.Println(1)\n}\n", want: nil, wantCall: true},
		// Ported param fixes (usage tracking)
		{name: "js method param type", path: "proj/a.ts", content: "import { Config } from './types';\nclass A {\n  foo(x: Config) {\n    return x;\n  }\n}\n", want: nil, wantCall: true},
		{name: "js catch uses import", path: "proj/a.ts", content: "import { E } from './types';\nfunction foo() {}\ntry {\n  foo();\n} catch (e) {\n  const y: E = e;\n  foo(y);\n}\n", want: nil, wantCall: true},
		{name: "go generic import used", path: "proj/a.go", content: "package m\nimport \"fmt\"\nfunc f[T any](x T) T {\n    fmt.Println(x)\n    return x\n}\n", want: nil, wantCall: true},
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
