// Temporary verification harness for python-lint/main.lua.
// Replicates the tcode host: a tcode.* stub with a fixed buffer that captures
// tcode.diagnostics.set / clear, then runs the global check().
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
	want     []string // "line:severity:message"; nil slice + wantSilent means no call at all
	noCall   bool     // check() must not touch diagnostics at all
	wantCall bool     // set() or clear() must have been called
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
	cases := buildCases()
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
		} else if tc.noCall {
			exp = "(no diagnostics call at all)"
		}
		act := "(none)"
		if len(actual) > 0 {
			act = strings.Join(actual, " | ")
		} else if !called {
			act = "(no diagnostics call at all)"
		} else {
			act = "(clear)"
		}
		fmt.Printf("%s %-30s expected: %s\n     %-30s actual:   %s\n",
			status, tc.name, exp, "", act)
	}
	fmt.Printf("\n%d case(s), %d failure(s)\n", len(cases), failures)
	if failures > 0 {
		os.Exit(1)
	}
}

func buildCases() []testCase {
	return []testCase{
		{
			name:    "1 mixed indentation",
			path:    "test.py",
			content: "def f():\n\t x = 1\n",
			want:    []string{"2:error:mixed indentation (tabs and spaces)"},
		},
		{
			name:    "2 inconsistent indentation",
			path:    "test.py",
			content: "if a:\n    x = 1\nif b:\n\ty = 2\nif c:\n\tz = 3\n",
			want:    []string{"2:error:inconsistent indentation (file uses tabs)"},
		},
		{
			name:    "3 unindent mismatch",
			path:    "test.py",
			content: "def f():\n    x = 1\n  y = 2\n",
			want:    []string{"3:error:unindent does not match any outer indentation level"},
		},
		{
			// I4 (not a multiple of the step) was removed: valid Python with an
			// irregular but consistent indent step is common and not an error.
			name: "4 irregular step is not flagged",
			path: "test.py",
			content: "def f():\n    x = 1\n      y = 2\n    return x\n",
			want: []string{
				"3:error:unexpected indent",
			},
		},
		{
			name:    "5 missing colon",
			path:    "test.py",
			content: "if x\n",
			want:    []string{"1:error:expected ':' at the end of the line"},
		},
		{
			name:    "6 expected block",
			path:    "test.py",
			content: "if x:\ny = 1\n",
			want:    []string{"1:error:expected an indented block"},
		},
		{
			name:    "7 unexpected indent",
			path:    "test.py",
			content: "x = 1\n    y = 2\n",
			want:    []string{"2:error:unexpected indent"},
		},
		{
			name:     "8 clean one-liner",
			path:     "test.py",
			content:  "if x: pass\n",
			want:     nil,
			wantCall: true,
		},
		{
			name:     "9 colon in dict/slice/lambda",
			path:     "test.py",
			content:  "d = {1: 2}\na[1:2]\nf = lambda x: x\n",
			want:     nil,
			wantCall: true,
		},
		{
			name:    "10 return at module",
			path:    "test.py",
			content: "return 1\n",
			want:    []string{"1:error:'return' outside function"},
		},
		{
			name:    "11 yield at module",
			path:    "test.py",
			content: "yield 1\n",
			want:    []string{"1:error:'yield' outside function"},
		},
		{
			name:     "12 return inside def",
			path:     "test.py",
			content:  "def f():\n    return 1\n",
			want:     nil,
			wantCall: true,
		},
		{
			name:    "13 break outside loop",
			path:    "test.py",
			content: "def f():\n    break\n",
			want:    []string{"2:error:'break' outside loop"},
		},
		{
			name:     "14 break inside for",
			path:     "test.py",
			content:  "for i in x:\n    break\n",
			want:     nil,
			wantCall: true,
		},
		{
			name:     "15 continue in while in def",
			path:     "test.py",
			content:  "def f():\n    while x:\n        continue\n",
			want:     nil,
			wantCall: true,
		},
		{
			name:    "16a nonlocal at module",
			path:    "test.py",
			content: "nonlocal x\n",
			want:    []string{"1:error:nonlocal declaration outside nested function"},
		},
		{
			name:     "16b nonlocal in nested def",
			path:     "test.py",
			content:  "def f():\n    def g():\n        nonlocal x\n",
			want:     nil,
			wantCall: true,
		},
		{
			name:    "17 global at module",
			path:    "test.py",
			content: "global x\n",
			want:    []string{"1:warning:global declaration at module level is a no-op"},
		},
		{
			name: "18 triple-quote and comments",
			path: "test.py",
			content: "x = \"\"\"\n  a\n     b\n\tc\n\"\"\"\n" +
				"def f():\n    s = 1\n      # if x\n    return s\n",
			want:     nil,
			wantCall: true,
		},
		{
			name: "19 implicit continuation",
			path: "test.py",
			content: "values = [\n        1,\n\t2,\n    ]\ntotal = 0\nfor v in values:\n    total += v\n",
			want:     nil,
			wantCall: true,
		},
		{
			name:     "20 regression valid file",
			path:     "test.py",
			content:  regression,
			want:     nil,
			wantCall: true,
		},
		{
			name:    "21 non-python path",
			path:    "test.go",
			content: "return 1\nif x\n    y = 2\n",
			noCall:  true,
		},
		{
			name:     "22 def one-liner with return",
			path:     "test.py",
			content:  "def f(): return 1\nreturn 2\n",
			want:     []string{"2:error:'return' outside function"},
			wantCall: true,
		},
		{
			name:     "23 while one-liner with break",
			path:     "test.py",
			content:  "while x: break\nbreak\n",
			want:     []string{"2:error:'break' outside loop"},
			wantCall: true,
		},
		{
			name:     "24 header continued by open bracket",
			path:     "test.py",
			content:  "if (a and\n        b):\n    pass\n",
			want:     nil,
			wantCall: true,
		},
		{
			name:    "25 return in class body",
			path:    "test.py",
			content: "class A:\n    return 1\n",
			want:    []string{"2:error:'return' outside function"},
		},
		{
			name:     "26 backslash continuation",
			path:     "test.py",
			content:  "x = 1 + \\\n  2\nreturn x\n",
			want:     []string{"3:error:'return' outside function"},
			wantCall: true,
		},
		{
			name:     "27 two level dedent",
			path:     "test.py",
			content:  "def f():\n    if x:\n        y = 1\nz = 2\n",
			want:     nil,
			wantCall: true,
		},
		{
			// A docstring is a statement: it IS the body of the block.
			name:     "28 docstring as sole body",
			path:     "test.py",
			content:  "class A:\n    \"\"\"doc\"\"\"\nclass B:\n    \"\"\"\n    multi\n    \"\"\"\ndef f():\n    \"\"\"doc\"\"\"\nx = 1\n",
			want:     nil,
			wantCall: true,
		},
		{
			// A comment is not a statement: Python raises IndentationError.
			name:    "29 comment is not a body",
			path:    "test.py",
			content: "if x:\n    # just a comment\ny = 1\n",
			want:    []string{"1:error:expected an indented block"},
		},
		{
			// Regression: a multi-line dict whose closing line is a bare `}`
			// must NOT keep the logical statement open and swallow the
			// following method (the depth delta must go negative).
			name:     "30 multiline dict closes",
			path:     "test.py",
			content:  "tokens = {\n    'a': [\n        (r'\\s+', Text)\n    ]\n}\ndef f():\n    yield 1\n",
			want:     nil,
			wantCall: true,
		},
		{
			// Regression: statement after a multi-line expression keeps the
			// right indentation context for a `return` inside the function.
			name:     "31 return after multiline expr",
			path:     "test.py",
			content:  "def g():\n    data = [\n        1,\n    ]\n    return data\n",
			want:     nil,
			wantCall: true,
		},
		{
			// Regression: a header closed on a continuation line (`):`)
			// still opens the block.
			name:     "32 header colon on continuation",
			path:     "test.py",
			content:  "def h(\n    a,\n):\n    return a\n",
			want:     nil,
			wantCall: true,
		},
		{
			// Regression: the line that CLOSES a triple-quoted string carries
			// the rest of the statement (`""", (cmd,)).fetchall():`) and must
			// not be skipped as if it were still inside the string.
			name:     "33 triple close with code after",
			path:     "test.py",
			content:  "def f(cmd):\n    for row in c.execute(\n            \"\"\"\n            SELECT 1\n            \"\"\", (cmd,)).fetchall():\n        rows.append(row)\n    return rows\n",
			want:     nil,
			wantCall: true,
		},
		{
			// Regression: a triple-quoted string inside an `if` condition.
			name:     "34 triple inside condition",
			path:     "test.py",
			content:  "def g():\n    if not question(\"\"\"\nsome text\"\"\", True):\n        return False\n    return True\n",
			want:     nil,
			wantCall: true,
		},
		{
			// Regression: a single-quoted string continued by backslash-newline
			// spans physical lines; brackets inside it must stay masked, or a
			// `]` in the string corrupts the depth and the next block header
			// looks like an unexpected indent.
			name:     "35 string continued by backslash",
			path:     "test.py",
			content:  "d = {\n    'a': '[Component(obj,\\\n                 asString(x))]',\n    'b': 1,\n}\ndef h():\n    return d\n",
			want:     nil,
			wantCall: true,
		},
		{
			// Regression: a triple-quoted string that closes and continues with
			// `.format(...)` is a continuation line, not a new statement.
			name:     "36 triple close then .format",
			path:     "test.py",
			content:  "def t(name):\n    template = \"\"\"\nbody\n\"\"\".format(\n               class_name=name)\n    if name:\n        print(template)\n    return template\n",
			want:     nil,
			wantCall: true,
		},
	}
}

const regression = `import os


class Point:
    """Docstring with a colon: and a fake 'if x'."""

    kind = "point"

    def __init__(self, x: int, y: int = 0) -> None:
        self.x = x
        self.y = y

    def norm(self) -> float:
        return (self.x ** 2 + self.y ** 2) ** 0.5


def trace(fn):
    return fn


@trace
def make(points):
    result = [p for p in points if p is not None]
    lookup = {p.x: p for p in result}
    total = sum(p.x for p in result)
    return result, lookup, total


async def fetch(url):
    async with open(url) as fh:
        data = fh.read()
    async for chunk in data:
        pass
    return data


def control(xs):
    total = 0
    for i in range(10):
        if i % 2:
            continue
        if i > 5:
            break
        total += i
    else:
        total = -1
    while total > 100:
        total -= 1
    try:
        value = xs[0]
    except IndexError as exc:
        print(exc)
    except (TypeError, KeyError):
        raise
    else:
        value = None
    finally:
        del value
    with open("f") as fh:
        text = fh.read()
    try:
        pass
    finally:
        pass
    match value:
        case 0:
            return "zero"
        case _:
            return "other"
    d = {"a": 1, "b": 2}
    s = d["a"][0:1]
    lam = lambda q: q + 1
    t = (1,
         2,
         3)
    return total + lam(1) + len(s) + t[0]
`
