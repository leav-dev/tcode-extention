// Verification harness for git-changes/main.lua: status() and info().
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
	// Pointer fields: nil = absent (older editor without the field).
	branch        *string
	commitHash    *string
	commitSubject *string
	commitAuthor  *string
	commitDate    *string
}

type testCase struct {
	name    string
	fn      string // Lua entry point; "" defaults to "status"
	section string // section id to capture; "" defaults to "tcode.gitchanges"
	hasBuf  bool   // false = tcode.buffer() returns nil (no active buffer)
	git     gitMock
	want    string // expected section text
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
		opt := func(key string, v *string) {
			if v != nil {
				t.RawSetString(key, lua.LString(*v))
			}
		}
		opt("branch", tc.git.branch)
		opt("commit_hash", tc.git.commitHash)
		opt("commit_subject", tc.git.commitSubject)
		opt("commit_author", tc.git.commitAuthor)
		opt("commit_date", tc.git.commitDate)
		L.Push(t)
		return 1
	}))
	L.SetField(git, "file_diff", L.NewFunction(func(L *lua.LState) int {
		return 0
	}))

	statusBar := L.NewTable()
	L.SetField(tcode, "statusBar", statusBar)
	wantSection := tc.section
	if wantSection == "" {
		wantSection = "tcode.gitchanges"
	}
	L.SetField(statusBar, "setSection", L.NewFunction(func(L *lua.LState) int {
		id := L.CheckString(1)
		text := L.CheckString(2)
		if id == wantSection {
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
	fn := tc.fn
	if fn == "" {
		fn = "status"
	}
	if err := L.CallByParam(lua.P{
		Fn:      L.GetGlobal(fn),
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
		{
			name:   "status with commit",
			hasBuf: true,
			git: gitMock{hasGit: true, branch: str("main"),
				commitHash: str("a1b2c3d"), commitSubject: str("Fix login"),
				commitAuthor: str("Ada"), commitDate: str("2026-10-01"),
				unstaged: []string{"b.go"}, added: 3, deleted: 1},
			want: "Git Changes [main a1b2c3d]: Fix login (Ada, 2026-10-01) | 1 files (1 unstaged), +3 -1 lines",
		},
		{
			name:   "status with commit clean tree",
			hasBuf: true,
			git: gitMock{hasGit: true, branch: str("main"),
				commitHash: str("a1b2c3d"), commitSubject: str("Fix login"),
				commitAuthor: str("Ada"), commitDate: str("2026-10-01")},
			want: "Git Changes [main a1b2c3d]: Fix login (Ada, 2026-10-01) | clean working tree",
		},
		{
			name:   "status subject without author date",
			hasBuf: true,
			git: gitMock{hasGit: true, branch: str("main"),
				commitHash: str("a1b2c3d"), commitSubject: str("Fix login")},
			want: "Git Changes [main a1b2c3d]: Fix login | clean working tree",
		},
		{
			name:   "status empty hash keeps branch only",
			hasBuf: true,
			git: gitMock{hasGit: true, branch: str("main"),
				commitHash: str(""), commitSubject: str("Fix login"),
				commitAuthor: str("Ada"), commitDate: str("2026-10-01")},
			want: "Git Changes [main]: Fix login (Ada, 2026-10-01) | clean working tree",
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
