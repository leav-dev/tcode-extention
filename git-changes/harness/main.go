// Verification harness for git-changes/main.lua: status(), mark(), toggle().
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

type diffEntry struct {
	Line int
	Type string
}

type wantDiag struct {
	Line     int
	Message  string
	Severity string
}

type diagTestCase struct {
	name      string
	fn        string // "mark", "toggle", or "all"; "" defaults to "mark"
	hasBuf    bool
	unstaged  []diffEntry
	staged    []diffEntry
	wantDiags []wantDiag // expected diagnostics passed to set; nil = set must not be called
	wantClear bool       // true = clear must be called at least once
}

type diagResult struct {
	setCalls   [][]wantDiag
	clearCalls int
}

func setupState(L *lua.LState, tc testCase, unstaged, staged []diffEntry, res *diagResult) (called *bool, actual *string) {
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
	pushDiff := func(entries []diffEntry) *lua.LTable {
		tbl := L.NewTable()
		for i, e := range entries {
			d := L.NewTable()
			d.RawSetString("line", lua.LNumber(e.Line))
			d.RawSetString("type", lua.LString(e.Type))
			tbl.RawSetInt(i+1, d)
		}
		return tbl
	}
	L.SetField(git, "file_diff", L.NewFunction(func(L *lua.LState) int {
		stagedArg := false
		if L.GetTop() >= 2 {
			if bv, ok := L.Get(2).(lua.LBool); ok {
				stagedArg = bool(bv)
			}
		}
		if stagedArg {
			L.Push(pushDiff(staged))
		} else {
			L.Push(pushDiff(unstaged))
		}
		return 1
	}))

	statusBar := L.NewTable()
	L.SetField(tcode, "statusBar", statusBar)
	wantSection := tc.section
	if wantSection == "" {
		wantSection = "tcode.gitchanges"
	}
	var calledFlag bool
	var actualText string
	L.SetField(statusBar, "setSection", L.NewFunction(func(L *lua.LState) int {
		id := L.CheckString(1)
		text := L.CheckString(2)
		if id == wantSection {
			calledFlag = true
			actualText = text
		}
		return 0
	}))

	diags := L.NewTable()
	L.SetField(tcode, "diagnostics", diags)
	L.SetField(diags, "set", L.NewFunction(func(L *lua.LState) int {
		tbl := L.CheckTable(1)
		var got []wantDiag
		for i := 1; i <= tbl.Len(); i++ {
			d := tbl.RawGetInt(i).(*lua.LTable)
			got = append(got, wantDiag{
				Line:     int(d.RawGetString("line").(lua.LNumber)),
				Message:  string(d.RawGetString("message").(lua.LString)),
				Severity: string(d.RawGetString("severity").(lua.LString)),
			})
		}
		if res != nil {
			res.setCalls = append(res.setCalls, got)
		}
		return 0
	}))
	L.SetField(diags, "clear", L.NewFunction(func(L *lua.LState) int {
		if res != nil {
			res.clearCalls++
		}
		return 0
	}))

	return &calledFlag, &actualText
}

func run(tc testCase) (actual string, called bool, err error) {
	L := lua.NewState()
	defer L.Close()

	calledP, actualP := setupState(L, tc, nil, nil, nil)

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
	return *actualP, *calledP, nil
}

func runDiag(tc diagTestCase) (res diagResult, err error) {
	L := lua.NewState()
	defer L.Close()

	base := testCase{hasBuf: tc.hasBuf, git: gitMock{hasGit: true, branch: str("main")}}
	setupState(L, base, tc.unstaged, tc.staged, &res)

	if err := L.DoFile("../main.lua"); err != nil {
		return res, err
	}
	fn := tc.fn
	if fn == "" {
		fn = "mark"
	}
	if err := L.CallByParam(lua.P{
		Fn:      L.GetGlobal(fn),
		NRet:    0,
		Protect: true,
	}, lua.LNil, lua.LNil); err != nil {
		return res, err
	}
	return res, nil
}

// runToggleTwice calls toggle() twice in the same Lua state: first call
// must show (set), second call must clear.
func runToggleTwice(tc diagTestCase) (first, second diagResult, err error) {
	L := lua.NewState()
	defer L.Close()

	base := testCase{hasBuf: tc.hasBuf, git: gitMock{hasGit: true, branch: str("main")}}
	var combined diagResult
	setupState(L, base, tc.unstaged, tc.staged, &combined)

	if err := L.DoFile("../main.lua"); err != nil {
		return first, second, err
	}
	call := func() (diagResult, error) {
		before_set := len(combined.setCalls)
		before_clear := combined.clearCalls
		if err := L.CallByParam(lua.P{
			Fn:      L.GetGlobal("toggle"),
			NRet:    0,
			Protect: true,
		}, lua.LNil, lua.LNil); err != nil {
			return diagResult{}, err
		}
		var r diagResult
		r.setCalls = append([][]wantDiag(nil), combined.setCalls[before_set:]...)
		r.clearCalls = combined.clearCalls - before_clear
		return r, nil
	}
	if first, err = call(); err != nil {
		return first, second, err
	}
	if second, err = call(); err != nil {
		return first, second, err
	}
	return first, second, nil
}

func diagsEqual(got []wantDiag, want []wantDiag) (bool, string) {
	if len(got) != len(want) {
		return false, fmt.Sprintf("expected %d diagnostics, got %d (%v)", len(want), len(got), got)
	}
	for i := range want {
		if got[i] != want[i] {
			return false, fmt.Sprintf("diag %d: expected %+v, got %+v", i, want[i], got[i])
		}
	}
	return true, fmt.Sprintf("%v", got)
}

func main() {
	failures := 0
	total := 0
	report := func(name, status, detail string) {
		total++
		if status == "FAIL" {
			failures++
		}
		fmt.Printf("%s %-32s %s\n", status, name, detail)
	}

	cases := []testCase{
		{
			name:   "branch clean tree",
			hasBuf: true,
			git:    gitMock{hasGit: true, branch: str("main")},
			want:   "[main]: clean working tree",
		},
		{
			name:   "branch with staged and unstaged",
			hasBuf: true,
			git: gitMock{hasGit: true, branch: str("feat"),
				staged: []string{"a.go"}, unstaged: []string{"b.go", "c.go"},
				added: 15, deleted: 8},
			want: "[feat]: 3 files (1 S, 2 U), +15 -8 lines",
		},
		{
			name:   "branch with untracked only",
			hasBuf: true,
			git: gitMock{hasGit: true, branch: str("main"),
				untracked: []string{"new.txt"}},
			want: "[main]: 1 files (1 ?), +0 -0 lines",
		},
		{
			name:   "detached HEAD shows short SHA",
			hasBuf: true,
			git:    gitMock{hasGit: true, branch: str("a1b2c3d")},
			want:   "[a1b2c3d]: clean working tree",
		},
		{
			name:   "no branch field stays branchless",
			hasBuf: true,
			git:    gitMock{hasGit: true, branch: nil},
			want:   "clean working tree",
		},
		{
			name:   "empty branch stays branchless",
			hasBuf: true,
			git: gitMock{hasGit: true, branch: str(""),
				unstaged: []string{"b.go"}, added: 2, deleted: 1},
			want: "1 files (1 U), +2 -1 lines",
		},
		{
			name:   "no active buffer",
			hasBuf: false,
			git:    gitMock{hasGit: true, branch: str("main")},
			want:   "no active buffer",
		},
		{
			name:   "not a git repository",
			hasBuf: true,
			git:    gitMock{hasGit: false},
			want:   "not a git repository",
		},
		{
			name:   "commit fields are ignored with changes",
			hasBuf: true,
			git: gitMock{hasGit: true, branch: str("main"),
				commitHash: str("a1b2c3d"), commitSubject: str("Fix login"),
				commitAuthor: str("Ada"), commitDate: str("2026-10-01"),
				unstaged: []string{"b.go"}, added: 3, deleted: 1},
			want: "[main]: 1 files (1 U), +3 -1 lines",
		},
		{
			name:   "commit fields are ignored clean tree",
			hasBuf: true,
			git: gitMock{hasGit: true, branch: str("main"),
				commitHash: str("a1b2c3d"), commitSubject: str("Fix login"),
				commitAuthor: str("Ada"), commitDate: str("2026-10-01")},
			want: "[main]: clean working tree",
		},
		{
			name:   "subject without author date is ignored",
			hasBuf: true,
			git: gitMock{hasGit: true, branch: str("main"),
				commitHash: str("a1b2c3d"), commitSubject: str("Fix login")},
			want: "[main]: clean working tree",
		},
		{
			name:   "empty hash keeps branch only",
			hasBuf: true,
			git: gitMock{hasGit: true, branch: str("main"),
				commitHash: str(""), commitSubject: str("Fix login"),
				commitAuthor: str("Ada"), commitDate: str("2026-10-01")},
			want: "[main]: clean working tree",
		},
	}

	for _, tc := range cases {
		actual, called, err := run(tc)
		switch {
		case err != nil:
			report(tc.name, "FAIL", fmt.Sprintf("lua error: %v", err))
		case !called:
			report(tc.name, "FAIL", "setSection was not called")
		case actual != tc.want:
			report(tc.name, "FAIL", fmt.Sprintf("expected %q, got %q", tc.want, actual))
		default:
			report(tc.name, "PASS", fmt.Sprintf("%q", actual))
		}
	}

	diagCases := []diagTestCase{
		{
			name:      "mark added indicator only",
			hasBuf:    true,
			unstaged:  []diffEntry{{Line: 12, Type: "added"}},
			wantDiags: []wantDiag{{Line: 12, Message: "", Severity: "info"}},
		},
		{
			name:      "mark modified indicator only",
			hasBuf:    true,
			unstaged:  []diffEntry{{Line: 7, Type: "modified"}},
			wantDiags: []wantDiag{{Line: 7, Message: "", Severity: "info"}},
		},
		{
			name:      "mark deleted indicator only",
			hasBuf:    true,
			unstaged:  []diffEntry{{Line: 3, Type: "deleted"}},
			wantDiags: []wantDiag{{Line: 3, Message: "", Severity: "warning"}},
		},
		{
			name:     "mark merges staged and unstaged",
			hasBuf:   true,
			unstaged: []diffEntry{{Line: 2, Type: "added"}},
			staged:   []diffEntry{{Line: 5, Type: "deleted"}},
			wantDiags: []wantDiag{
				{Line: 2, Message: "", Severity: "info"},
				{Line: 5, Message: "", Severity: "warning"},
			},
		},
		{
			name:      "mark empty diff clears",
			hasBuf:    true,
			wantClear: true,
		},
		{
			name:      "mark deleted plus added coalesces to modified",
			hasBuf:    true,
			unstaged:  []diffEntry{{Line: 5, Type: "deleted"}, {Line: 5, Type: "added"}},
			wantDiags: []wantDiag{{Line: 5, Message: "", Severity: "info"}},
		},
		{
			name:     "mark multi-entry replace coalesces to one modified",
			hasBuf:   true,
			unstaged: []diffEntry{{Line: 5, Type: "deleted"}, {Line: 5, Type: "deleted"}, {Line: 5, Type: "added"}, {Line: 5, Type: "added"}},
			wantDiags: []wantDiag{{Line: 5, Message: "", Severity: "info"}},
		},
		{
			name:     "mark staged plus unstaged pair coalesces",
			hasBuf:   true,
			unstaged: []diffEntry{{Line: 8, Type: "deleted"}},
			staged:   []diffEntry{{Line: 8, Type: "added"}},
			wantDiags: []wantDiag{{Line: 8, Message: "", Severity: "info"}},
		},
		{
			name:     "mark same-line adds stay separate",
			hasBuf:   true,
			unstaged: []diffEntry{{Line: 2, Type: "added"}},
			staged:   []diffEntry{{Line: 2, Type: "added"}},
			wantDiags: []wantDiag{
				{Line: 2, Message: "", Severity: "info"},
				{Line: 2, Message: "", Severity: "info"},
			},
		},
		{
			name:     "mark same-line deletes stay separate",
			hasBuf:   true,
			unstaged: []diffEntry{{Line: 3, Type: "deleted"}},
			staged:   []diffEntry{{Line: 3, Type: "deleted"}},
			wantDiags: []wantDiag{
				{Line: 3, Message: "", Severity: "warning"},
				{Line: 3, Message: "", Severity: "warning"},
			},
		},
		{
			name:   "mark no buffer is safe",
			hasBuf: false,
			unstaged: []diffEntry{
				{Line: 1, Type: "added"},
			},
		},
	}

	for _, tc := range diagCases {
		res, err := runDiag(tc)
		if err != nil {
			report(tc.name, "FAIL", fmt.Sprintf("lua error: %v", err))
			continue
		}
		if tc.wantDiags == nil && len(tc.wantDiags) == 0 && !tc.wantClear {
			// Expect neither set nor clear.
			if len(res.setCalls) != 0 {
				report(tc.name, "FAIL", fmt.Sprintf("expected no set, got %v", res.setCalls))
			} else if res.clearCalls != 0 {
				report(tc.name, "FAIL", fmt.Sprintf("expected no clear, got %d clear(s)", res.clearCalls))
			} else {
				report(tc.name, "PASS", "no set, no clear")
			}
			continue
		}
		if tc.wantClear && len(tc.wantDiags) == 0 {
			if res.clearCalls < 1 {
				report(tc.name, "FAIL", "expected clear to be called")
			} else if len(res.setCalls) != 0 {
				report(tc.name, "FAIL", fmt.Sprintf("expected no set, got %v", res.setCalls))
			} else {
				report(tc.name, "PASS", "cleared")
			}
			continue
		}
		if len(res.setCalls) != 1 {
			report(tc.name, "FAIL", fmt.Sprintf("expected 1 set call, got %d", len(res.setCalls)))
			continue
		}
		if ok, detail := diagsEqual(res.setCalls[0], tc.wantDiags); !ok {
			report(tc.name, "FAIL", detail)
		} else {
			report(tc.name, "PASS", detail)
		}
	}

	// Toggle: first call shows marks, second call clears.
	toggleDiff := diagTestCase{
		hasBuf:   true,
		unstaged: []diffEntry{{Line: 12, Type: "added"}, {Line: 7, Type: "modified"}, {Line: 3, Type: "deleted"}},
	}
	wantToggle := []wantDiag{
		{Line: 12, Message: "", Severity: "info"},
		{Line: 7, Message: "", Severity: "info"},
		{Line: 3, Message: "", Severity: "warning"},
	}
	first, second, err := runToggleTwice(toggleDiff)
	if err != nil {
		report("toggle shows then clears", "FAIL", fmt.Sprintf("lua error: %v", err))
	} else {
		if len(first.setCalls) != 1 {
			report("toggle first call shows", "FAIL", fmt.Sprintf("expected 1 set, got %d", len(first.setCalls)))
		} else if ok, detail := diagsEqual(first.setCalls[0], wantToggle); !ok {
			report("toggle first call shows", "FAIL", detail)
		} else {
			report("toggle first call shows", "PASS", "marks shown")
		}
		if second.clearCalls < 1 {
			report("toggle second call clears", "FAIL", fmt.Sprintf("expected clear, got %+v", second))
		} else if len(second.setCalls) != 0 {
			report("toggle second call clears", "FAIL", fmt.Sprintf("expected no set on clear, got %v", second.setCalls))
		} else {
			report("toggle second call clears", "PASS", "cleared")
		}
	}

	// Toggle with empty diff is safe (no error, clears or no-ops without raising).
	emptyToggle := diagTestCase{hasBuf: true}
	if _, _, err := runToggleTwice(emptyToggle); err != nil {
		report("toggle empty diff safe", "FAIL", fmt.Sprintf("lua error: %v", err))
	} else {
		report("toggle empty diff safe", "PASS", "no error")
	}

	// Toggle with no buffer is safe (no error).
	noBufToggle := diagTestCase{hasBuf: false, unstaged: []diffEntry{{Line: 1, Type: "added"}}}
	if _, _, err := runToggleTwice(noBufToggle); err != nil {
		report("toggle no buffer safe", "FAIL", fmt.Sprintf("lua error: %v", err))
	} else {
		report("toggle no buffer safe", "PASS", "no error")
	}

	// all() still runs status + mark (sets both section and diagnostics).
	{
		L := lua.NewState()
		base := testCase{hasBuf: true, git: gitMock{hasGit: true, branch: str("main"),
			unstaged: []string{"b.go"}, added: 1, deleted: 0}}
		var res diagResult
		calledP, actualP := setupState(L, base, []diffEntry{{Line: 4, Type: "added"}}, nil, &res)
		var callErr error
		if derr := L.DoFile("../main.lua"); derr != nil {
			callErr = derr
		} else if cerr := L.CallByParam(lua.P{Fn: L.GetGlobal("all"), NRet: 0, Protect: true}, lua.LNil, lua.LNil); cerr != nil {
			callErr = cerr
		}
		L.Close()
		if callErr != nil {
			report("all runs status and mark", "FAIL", fmt.Sprintf("lua error: %v", callErr))
		} else if !*calledP || *actualP == "" {
			report("all runs status and mark", "FAIL", "status section not set")
		} else if len(res.setCalls) != 1 {
			report("all runs status and mark", "FAIL", fmt.Sprintf("expected 1 set, got %d", len(res.setCalls)))
		} else if ok, detail := diagsEqual(res.setCalls[0], []wantDiag{{Line: 4, Message: "", Severity: "info"}}); !ok {
			report("all runs status and mark", "FAIL", detail)
		} else {
			report("all runs status and mark", "PASS", fmt.Sprintf("status %q + marks", *actualP))
		}
	}

	fmt.Printf("\n%d case(s), %d failure(s)\n", total, failures)
	if failures > 0 {
		os.Exit(1)
	}
}
