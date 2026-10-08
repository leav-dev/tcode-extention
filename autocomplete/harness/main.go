// Temporary verification harness for autocomplete/main.lua.
package main

import (
	"fmt"
	"os"
	"strings"

	lua "github.com/yuin/gopher-lua"
)

type testCase struct {
	name string
	// Buffer setup. When hasBuffer is false, tcode.buffer returns nil.
	hasBuffer bool
	path      string
	content   string
	// Cursor setup. When hasCursor is false, tcode.cursor is left unset.
	hasCursor bool
	curLine   int
	curCol    int
	// Expectations. An empty wantInsert means "no insert expected".
	wantInsert string
	// Substrings that must appear in the joined messages ("" = no message expected).
	// wantOrder, when non-empty, must appear verbatim in the joined messages
	// (used to verify candidate ordering).
	wantMessageSub string
	wantOrder      string
}

type result struct {
	inserted bool
	insert   string
	messages []string
}

func run(tc testCase) (result, error) {
	var res result
	L := lua.NewState()
	defer L.Close()

	tcode := L.NewTable()
	L.SetGlobal("tcode", tcode)

	path, content := tc.path, tc.content
	L.SetField(tcode, "buffer", L.NewFunction(func(L *lua.LState) int {
		if !tc.hasBuffer {
			L.Push(lua.LNil)
			return 1
		}
		L.Push(lua.LString(path))
		L.Push(lua.LString(content))
		return 2
	}))

	lines := strings.Split(content, "\n")
	L.SetField(tcode, "line", L.NewFunction(func(L *lua.LState) int {
		n := L.CheckInt(1)
		if n >= 1 && n <= len(lines) {
			L.Push(lua.LString(lines[n-1]))
		} else {
			L.Push(lua.LNil)
		}
		return 1
	}))
	L.SetField(tcode, "lineCount", L.NewFunction(func(L *lua.LState) int {
		L.Push(lua.LNumber(len(lines)))
		return 1
	}))
	L.SetField(tcode, "insert", L.NewFunction(func(L *lua.LState) int {
		res.inserted = true
		res.insert = L.CheckString(1)
		return 0
	}))
	L.SetField(tcode, "message", L.NewFunction(func(L *lua.LState) int {
		res.messages = append(res.messages, L.CheckString(1))
		return 0
	}))
	if tc.hasCursor {
		curLine, curCol := tc.curLine, tc.curCol
		L.SetField(tcode, "cursor", L.NewFunction(func(L *lua.LState) int {
			L.Push(lua.LNumber(curLine))
			L.Push(lua.LNumber(curCol))
			return 2
		}))
	}

	if err := L.DoFile("../main.lua"); err != nil {
		return res, err
	}
	if err := L.CallByParam(lua.P{
		Fn:      L.GetGlobal("complete"),
		NRet:    0,
		Protect: true,
	}); err != nil {
		return res, err
	}
	return res, nil
}

func main() {
	cases := []testCase{
		{
			name:      "no buffer",
			hasBuffer: false,
			hasCursor: true,
			curLine:   1,
			curCol:    1,
		},
		{
			name:      "missing cursor",
			hasBuffer: true,
			path:      "a.txt",
			content:   "foo foobar\nfoo",
			hasCursor: false,
			wantMessageSub: "cursor",
		},
		{
			name:      "empty prefix",
			hasBuffer: true,
			path:      "a.txt",
			content:   "hello world\n",
			hasCursor: true,
			curLine:   1,
			curCol:    1,
			wantMessageSub: "no word prefix",
		},
		{
			name:      "no candidates",
			hasBuffer: true,
			path:      "a.txt",
			content:   "foo bar\nxyz",
			hasCursor: true,
			curLine:   2,
			curCol:    4,
			wantMessageSub: "no candidates",
		},
		{
			name:      "single candidate",
			hasBuffer: true,
			path:      "a.txt",
			content:   "foobar baz\nfoo",
			hasCursor: true,
			curLine:   2,
			curCol:    4,
			wantInsert: "bar",
		},
		{
			name:      "common extension",
			hasBuffer: true,
			path:      "a.txt",
			content:   "foobar foobaz\nfoo",
			hasCursor: true,
			curLine:   2,
			curCol:    4,
			wantInsert: "ba",
		},
		{
			name:      "divergent list",
			hasBuffer: true,
			path:      "a.txt",
			content:   "foobar fizz\nf",
			hasCursor: true,
			curLine:   2,
			curCol:    2,
			wantMessageSub: "2 candidates",
		},
		{
			name:      "dedupe",
			hasBuffer: true,
			path:      "a.txt",
			content:   "foobar foobar foobar\nfoo",
			hasCursor: true,
			curLine:   2,
			curCol:    4,
			wantInsert: "bar",
		},
		{
			name:      "frequency ordering",
			hasBuffer: true,
			path:      "a.txt",
			content:   "test test test team text\nte",
			hasCursor: true,
			curLine:   2,
			curCol:    3,
			wantMessageSub: "3 candidates",
			wantOrder:      "test, team, text",
		},
	}

	failures := 0
	for _, tc := range cases {
		res, err := run(tc)
		if err != nil {
			fmt.Printf("FAIL %-20s lua error: %v\n", tc.name, err)
			failures++
			continue
		}
		ok := true
		var notes []string
		if tc.wantInsert != "" {
			if !res.inserted || res.insert != tc.wantInsert {
				ok = false
				notes = append(notes, fmt.Sprintf("want insert %q got %q (called=%v)", tc.wantInsert, res.insert, res.inserted))
			}
			if len(res.messages) != 0 {
				ok = false
				notes = append(notes, fmt.Sprintf("want no message got %q", strings.Join(res.messages, " | ")))
			}
		} else {
			if res.inserted {
				ok = false
				notes = append(notes, fmt.Sprintf("want no insert got %q", res.insert))
			}
			joined := strings.Join(res.messages, " | ")
			if tc.wantMessageSub == "" {
				if len(res.messages) != 0 {
					ok = false
					notes = append(notes, fmt.Sprintf("want no message got %q", joined))
				}
			} else {
				if !strings.Contains(joined, tc.wantMessageSub) {
					ok = false
					notes = append(notes, fmt.Sprintf("want message containing %q got %q", tc.wantMessageSub, joined))
				}
			}
			if tc.wantOrder != "" && !strings.Contains(joined, tc.wantOrder) {
				ok = false
				notes = append(notes, fmt.Sprintf("want ordered %q got %q", tc.wantOrder, joined))
			}
			// Divergent case must list both candidates.
			if tc.name == "divergent list" {
				if !strings.Contains(joined, "foobar") || !strings.Contains(joined, "fizz") {
					ok = false
					notes = append(notes, fmt.Sprintf("want both foobar and fizz in %q", joined))
				}
			}
		}
		status := "PASS"
		if !ok {
			status = "FAIL"
			failures++
		}
		detail := "(ok)"
		if len(notes) > 0 {
			detail = strings.Join(notes, "; ")
		}
		fmt.Printf("%s %-20s insert=%q messages=%q :: %s\n", status, tc.name, res.insert, strings.Join(res.messages, " | "), detail)
	}
	fmt.Printf("\n%d case(s), %d failure(s)\n", len(cases), failures)
	if failures > 0 {
		os.Exit(1)
	}
}
