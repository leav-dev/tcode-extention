// Verification harness for git-changes/main.lua: status().
package main

import (
	"fmt"
	"os"

	lua "github.com/yuin/gopher-lua"
)

type gitMock struct {
	hasGit    bool // false = tcode.git.status() returns nil (not a repo)
	staged    []string
	unstaged  []string
	untracked []string
	added     int
	deleted   int
	branch    *string // nil = field absent (older editor without branch)
}

type testCase struct {
	name    string
	hasBuf  bool // false = tcode.buffer() returns nil (no active buffer)
	git     gitMock
	want    string // expected tcode.gitchanges section text
	wantSet bool   // false = setSection must not be called
}

func str(s string) *string { return &s }

func run(tc testCase) (actual string, called bool, err error) {
	L := lua.NewState()
	defer L.Close()

	tcode := L.NewTable()
	L.SetGlobal("tcode", tcode)

	L.SetField(tcode, "buffer", L.NewFunction(func(L *lua.LState) int {
		if !tc.hasBuf {
			return 0
		}
		L.Push(lua.LString("/repo/test.txt"))
		L.Push(lua.LString("line1\n"))
		return 2
	}))

	git := L.NewTable()
	L.SetField(tcode, "git", git)
	L.SetField(git, "status", L.NewFunction(func(L *lua.LState) int {
		if !tc.git.hasGit {
			return 0
		}
		t := L.NewTable()
		strs := func(ss []string) *lua.LTable {
			tbl := L.NewTable()
			for i, s := range ss {
				tbl.RawSetInt(i+1, lua.LString(s))
			}
			return tbl
		}
		t.RawSetString("staged", strs(tc.git.staged))
		t.RawSetString("unstaged", strs(tc.git.unstaged))
		t.RawSetString("untracked", strs(tc.git.untracked))
		t.RawSetString("added", lua.LNumber(tc.git.added))
		t.RawSetString("deleted", lua.LNumber(tc.git.deleted))
		if tc.git.branch != nil {
			t.RawSetString("branch", lua.LString(*tc.git.branch))
		}
		L.Push(t)
		return 1
	}))
	L.SetField(git, "file_diff", L.NewFunction(func(L *lua.LState) int {
		return 0
	}))

	statusBar := L.NewTable()
	L.SetField(tcode, "statusBar", statusBar)
	L.SetField(statusBar, "setSection", L.NewFunction(func(L *lua.LState) int {
		id := L.CheckString(1)
		text := L.CheckString(2)
		if id == "tcode.gitchanges" {
			called = true
			actual = text
		}
		return 0
	}))

	diags := L.NewTable()
	L.SetField(tcode, "diagnostics", diags)
	L.SetField(diags, "set", L.NewFunction(func(L *lua.LState) int { return 0 }))
	L.SetField(diags, "clear", L.NewFunction(func(L *lua.LState) int { return 0 }))

	if err := L.DoFile("../main.lua"); err != nil {
		return "", false, err
	}
	if err := L.CallByParam(lua.P{
		Fn:      L.GetGlobal("status"),
		NRet:    0,
		Protect: true,
	}, lua.LNil, lua.LNil); err != nil {
		return "", false, err
	}
	return actual, called, nil
}

func main() {
	cases := []testCase{
		{
			name:   "branch clean tree",
			hasBuf: true,
			git:    gitMock{hasGit: true, branch: str("main")},
			want:   "Git Changes [main]: clean working tree",
		},
		{
			name:   "branch with staged and unstaged",
			hasBuf: true,
			git: gitMock{hasGit: true, branch: str("feat"),
				staged: []string{"a.go"}, unstaged: []string{"b.go", "c.go"},
				added: 15, deleted: 8},
			want: "Git Changes [feat]: 3 files (1 staged, 2 unstaged), +15 -8 lines",
		},
		{
			name:   "branch with untracked only",
			hasBuf: true,
			git: gitMock{hasGit: true, branch: str("main"),
				untracked: []string{"new.txt"}},
			want: "Git Changes [main]: 1 files (1 untracked), +0 -0 lines",
		},
		{
			name:   "detached HEAD shows short SHA",
			hasBuf: true,
			git:    gitMock{hasGit: true, branch: str("a1b2c3d")},
			want:   "Git Changes [a1b2c3d]: clean working tree",
		},
		{
			name:   "no branch field stays branchless",
			hasBuf: true,
			git:    gitMock{hasGit: true, branch: nil},
			want:   "Git Changes: clean working tree",
		},
		{
			name:   "empty branch stays branchless",
			hasBuf: true,
			git: gitMock{hasGit: true, branch: str(""),
				unstaged: []string{"b.go"}, added: 2, deleted: 1},
			want: "Git Changes: 1 files (1 unstaged), +2 -1 lines",
		},
		{
			name:   "no active buffer",
			hasBuf: false,
			git:    gitMock{hasGit: true, branch: str("main")},
			want:   "Git Changes: no active buffer",
		},
		{
			name:   "not a git repository",
			hasBuf: true,
			git:    gitMock{hasGit: false},
			want:   "Git Changes: not a git repository",
		},
	}

	failures := 0
	for _, tc := range cases {
		actual, called, err := run(tc)
		status := "PASS"
		detail := ""
		switch {
		case err != nil:
			status, detail = "FAIL", fmt.Sprintf("lua error: %v", err)
		case !called:
			status, detail = "FAIL", "setSection was not called"
		case actual != tc.want:
			status, detail = "FAIL", fmt.Sprintf("expected %q, got %q", tc.want, actual)
		default:
			detail = fmt.Sprintf("%q", actual)
		}
		if status == "FAIL" {
			failures++
		}
		fmt.Printf("%s %-32s %s\n", status, tc.name, detail)
	}
	fmt.Printf("\n%d case(s), %d failure(s)\n", len(cases), failures)
	if failures > 0 {
		os.Exit(1)
	}
}
