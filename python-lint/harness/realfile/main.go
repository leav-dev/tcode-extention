// Temporary runner: lints a real .py file with python-lint/main.lua.
// Usage: go run ./realfile <path.py>
package main

import (
	"fmt"
	"os"
	"sort"

	lua "github.com/yuin/gopher-lua"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("usage: realfile <path.py>")
		os.Exit(2)
	}
	path := os.Args[1]
	data, err := os.ReadFile(path)
	if err != nil {
		fmt.Println("read error:", err)
		os.Exit(2)
	}

	L := lua.NewState()
	defer L.Close()
	tcode := L.NewTable()
	L.SetGlobal("tcode", tcode)
	L.SetField(tcode, "buffer", L.NewFunction(func(L *lua.LState) int {
		L.Push(lua.LString(path))
		L.Push(lua.LString(string(data)))
		return 2
	}))
	diags := L.NewTable()
	L.SetField(tcode, "diagnostics", diags)
	var out []string
	L.SetField(diags, "set", L.NewFunction(func(L *lua.LState) int {
		tbl := L.CheckTable(1)
		tbl.ForEach(func(_, v lua.LValue) {
			lt := v.(*lua.LTable)
			out = append(out, fmt.Sprintf("%d:%s:%s",
				int(lua.LVAsNumber(L.GetField(lt, "line"))),
				lua.LVAsString(L.GetField(lt, "severity")),
				lua.LVAsString(L.GetField(lt, "message"))))
		})
		return 0
	}))
	L.SetField(diags, "clear", L.NewFunction(func(L *lua.LState) int { return 0 }))

	if err := L.DoFile("../main.lua"); err != nil {
		fmt.Println("lua load error:", err)
		os.Exit(1)
	}
	if err := L.CallByParam(lua.P{Fn: L.GetGlobal("check"), NRet: 0, Protect: true}); err != nil {
		fmt.Println("lua run error:", err)
		os.Exit(1)
	}
	sort.Slice(out, func(i, j int) bool { return out[i] < out[j] })
	for _, o := range out {
		fmt.Println(o)
	}
	fmt.Printf("(%d finding(s))\n", len(out))
}
