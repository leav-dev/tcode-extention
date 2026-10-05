-- Code Linter for tcode (id: tcode.errordetector)
-- Checks in one pass:
--   1. Bracket balance () [] {} with string awareness  -> severity "error"
--   2. Scope analysis: used-but-undefined variables and unused imports for
--      go/js/ts/py (heuristic; severity "warning").
-- HTML and Docker: balance only in v1 (no scope analysis — documented limit).
--
-- Editor API: tcode.buffer(), tcode.message(), tcode.diagnostics.set/clear.
-- Pure Lua: the tcode host exposes no io/os, so the analysis is structural
-- over the buffer content.
--
-- check is GLOBAL on purpose: the backend (ext.Call@tcode) resolves the
-- function by name with GetGlobal(fn).
--
-- Convention: every message sent to the user is English.
-- Documented v1 limits: no type analysis; struct field names in go bodies
-- may warn; py uses a single file scope (no indentation); js/ts object keys
-- and annotations are skipped; TS generics may false-positive; arrow
-- expression-body params are defined in the enclosing scope.

-- set builds a lookup table from a whitespace-separated word list. Avoids
-- Lua reserved words (break, and, for, ...) as bare table keys.
local function set(words)
  local t = {}
  for w in words:gmatch("%S+") do t[w] = true end
  return t
end

local langCfg = {
  go = {
    lineComment = "//", blockComment = { "/*", "*/" },
    keywords = set("break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var"),
    builtins = set("nil true false iota append cap close complex copy delete imag len make new panic print println real recover error string int int8 int16 int32 int64 uint uint8 uint16 uint32 uint64 uintptr float32 float64 bool byte rune any"),
  },
  js = {
    lineComment = "//", blockComment = { "/*", "*/" },
    keywords = set("break case catch class const continue debugger default delete do else export extends finally for function if import in instanceof let new of return super switch this throw try typeof var void while with yield async await from as static get set"),
    builtins = set("undefined null true false NaN Infinity console window document process require module exports globalThis fetch JSON Math Object Array String Number Boolean Symbol Function Promise Error Date RegExp Map Set WeakMap WeakSet Proxy Reflect parseInt parseFloat isNaN setTimeout setInterval clearTimeout clearInterval localStorage"),
  },
  ts = { -- Angular rides on ts rules.
    lineComment = "//", blockComment = { "/*", "*/" },
    keywords = set("break case catch class const continue debugger default delete do else enum export extends finally for function if import in instanceof let new of return super switch this throw try typeof var void while with yield async await from as static get set type interface implements readonly abstract namespace declare is keyof infer"),
    builtins = set("undefined null true false NaN Infinity console window document process require module exports globalThis fetch JSON Math Object Array String Number Boolean Symbol Function Promise Error Date RegExp Map Set WeakMap WeakSet Proxy Reflect parseInt parseFloat isNaN setTimeout setInterval clearTimeout clearInterval localStorage any unknown never string number boolean object Record Partial Readonly"),
  },
  py = {
    lineComment = "#", blockComment = false,
    keywords = set("and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield"),
    builtins = set("True False None len range print str int float bool list dict set tuple type isinstance enumerate zip map filter sorted sum min max abs any all open input repr format round divmod hash id object property classmethod staticmethod super self Exception ValueError TypeError KeyError IndexError NameError RuntimeError"),
  },
}

-- detectLanguage infers the language from the buffer path (extension-based;
-- Dockerfile has no extension). Unknown language -> nil (balance only).
local function detectLanguage(path)
  if not path then return nil end
  local p = string.lower(path)
  if p:match("%.go$") then return "go" end
  if p:match("%.m?jsx?$") or p:match("%.m?tsx?$") then return "ts" end
  if p:match("%.py$") then return "py" end
  if p:match("%.html?$") then return "html" end
  if p:match("dockerfile") then return "docker" end
  return nil
end

-- scan tokenizes content skipping comments and strings per language. String
-- and comment content never produce id tokens (they can't be reads/defines).
-- String tokens carry their content (import paths need it).
local function scan(content, cfg)
  local toks = {}
  local line = 1
  local n = #content
  local i = 1
  local syms = {
    ["("] = true, [")"] = true, ["["] = true, ["]"] = true, ["{"] = true,
    ["}"] = true, ["."] = true, [","] = true, [":"] = true, ["="] = true,
    [";"] = true, ["+"] = true, [">"] = true,
  }
  local function push(t, w)
    toks[#toks + 1] = { t = t, w = w, line = line }
  end
  while i <= n do
    local c = content:sub(i, i)
    if c == "\n" then
      push("nl", "") -- newline: statement boundary for py/js loops
      line = line + 1
      i = i + 1
    elseif cfg.lineComment and content:sub(i, i + #cfg.lineComment - 1) == cfg.lineComment then
      local e = content:find("\n", i, true)
      i = e or (n + 1)
    elseif cfg.blockComment and content:sub(i, i + #cfg.blockComment[1] - 1) == cfg.blockComment[1] then
      local s = i
      local e = content:find(cfg.blockComment[2], i + #cfg.blockComment[1], true)
      local seg = content:sub(s, e and (e + #cfg.blockComment[2] - 1) or n)
      for _ in seg:gmatch("\n") do line = line + 1 end
      i = (e and e + #cfg.blockComment[2]) or (n + 1)
    elseif c == '"' or c == "'" or c == "`" then
      local quote = c
      local triple = false
      if (quote == '"' or quote == "'") and content:sub(i, i + 2) == quote .. quote .. quote then
        triple = true
      end
      local j = i + (triple and 3 or 1)
      local closed = false
      while j <= n do
        local sc = content:sub(j, j)
        if sc == "\\" then
          j = j + 2
        elseif sc == "\n" then
          line = line + 1
          j = j + 1
        elseif (triple and content:sub(j, j + 2) == quote .. quote .. quote)
          or (not triple and sc == quote) then
          closed = true
          break
        else
          j = j + 1
        end
      end
      if closed then
        push("str", content:sub(i + (triple and 3 or 1), j - 1))
        i = j + (triple and 3 or 1)
      else
        push("str", content:sub(i + (triple and 3 or 1), n))
        i = n + 1
      end
    else
      local b = c:byte()
      if b and ((b >= 97 and b <= 122) or (b >= 65 and b <= 90) or c == "_") then
        local j = i + 1
        while j <= n do
          local nb = content:sub(j, j):byte()
          if nb and ((nb >= 97 and nb <= 122) or (nb >= 65 and nb <= 90)
            or (nb >= 48 and nb <= 57) or content:sub(j, j) == "_") then
            j = j + 1
          else
            break
          end
        end
        push("id", content:sub(i, j - 1))
        i = j
      elseif syms[c] then
        push("sym", c)
        i = i + 1
      else
        i = i + 1
      end
    end
  end
  return toks
end

-- --- Balance check (all languages, severity "error") -----------------------

local function balanceCheck(content)
  local closing = { ["("] = ")", ["["] = "]", ["{"] = "}" }
  local opening = { [")"] = "(", ["]"] = "[", ["}"] = "{" }
  local stack, errors, delim = {}, {}, nil
  local line, i, n = 1, 1, #content
  while i <= n do
    local c = content:sub(i, i)
    if delim then
      if c == "\\" then
        i = i + 2
      else
        if c == delim then delim = nil end
        if c == "\n" then line = line + 1 end
        i = i + 1
      end
    elseif c == '"' or c == "'" or c == "`" then
      delim = c
      i = i + 1
    elseif c == "\n" then
      line = line + 1
      i = i + 1
    elseif closing[c] then
      stack[#stack + 1] = { c, line }
      i = i + 1
    elseif opening[c] then
      local top = stack[#stack]
      if top and top[1] == opening[c] then
        stack[#stack] = nil
      elseif top then
        errors[#errors + 1] = { l = line, m = "'" .. c .. "' does not match '" .. top[1] .. "'" }
        stack[#stack] = nil
      else
        errors[#errors + 1] = { l = line, m = "'" .. c .. "' without opening" }
      end
      i = i + 1
    else
      i = i + 1
    end
  end
  if delim then
    errors[#errors + 1] = { l = line, m = "unterminated string (delimiter '" .. delim .. "')" }
  end
  for _, e in ipairs(stack) do
    errors[#errors + 1] = { l = e[2], m = "'" .. e[1] .. "' never closed" }
  end
  return errors
end

-- --- Scope analysis (go/js/ts/py, severity "warning") ----------------------

local function analyzeScope(toks, cfg)
  local findings = {}
  local global = {}
  local stack = { global }      -- stack[1] is global; deeper = blocks
  local importBy = {}           -- name -> { line, used }
  local wildcard = false        -- go `import . "x"`: skip undefined checks
  local pendingParams = nil     -- function params to define in the body scope
  local i, n = 1, #toks

  local function isSym(j, ch)
    local t = toks[j]
    return t and t.t == "sym" and t.w == ch
  end
  local function isId(j)
    local t = toks[j]
    return t and t.t == "id"
  end
  local function cur()
    return stack[#stack]
  end
  local function define(name)
    if name and name ~= "" and not cfg.keywords[name] and not cfg.builtins[name] then
      cur()[name] = true
    end
  end
  local function defineImport(name, line)
    -- Skip names that can never be an import binding: language keywords
    -- (a path whose last segment is a keyword is not referenceable), blank
    -- imports (_ "x") and builtins.
    if not name or name == "" then return end
    if cfg.keywords[name] or cfg.builtins[name] or name == "_" then return end
    global[name] = true
    if not importBy[name] then
      importBy[name] = { line = line, used = false }
    end
  end
  local function defined(name)
    for k = #stack, 1, -1 do
      if stack[k][name] then return true end
    end
    return false
  end
  local function markUsed(name)
    local r = importBy[name]
    if r then r.used = true end
  end
  -- readGroup collects ids inside a balanced group starting at j.
  local function readGroup(list, j, openCh, closeCh)
    if not isSym(j, openCh) then return {}, j end
    local ids = {}
    local depth = 1
    local k = j + 1
    while list[k] do
      local t = list[k]
      if t.t == "sym" then
        if t.w == openCh then
          depth = depth + 1
        elseif t.w == closeCh then
          depth = depth - 1
          if depth == 0 then return ids, k end
        end
      elseif t.t == "id" then
        ids[#ids + 1] = t.w
      end
      k = k + 1
    end
    return ids, k - 1
  end
  local function definePendingParams()
    if pendingParams then
      for _, p in ipairs(pendingParams) do
        if not cfg.keywords[p] and not cfg.builtins[p] then
          cur()[p] = true
        end
      end
      pendingParams = nil
    end
  end

  -- Go: package-level names are visible file-wide regardless of declaration
  -- order AND across the files of the same package (the package spans
  -- multiple files). Pre-scan the top-level (brace depth 0) declarations of
  -- a token list into global so a use before the declaration — or defined
  -- in a sibling file — is not a false positive. The editor provides the
  -- sibling files via tcode.dir_files() (the Lua host has no io/os); only
  -- files with the same package clause are scanned.
  local function preScanPackageLevel(toksArg)
    -- isSym/isId de la lista argumento: los globales leen la lista del
    -- buffer activo y no sirven para pre-scanear archivos hermanos.
    local function isSymArg(j, ch)
      local t = toksArg[j]
      return t and t.t == "sym" and t.w == ch
    end
    local function isIdArg(j)
      local t = toksArg[j]
      return t and t.t == "id"
    end
    local depth = 0
    local j = 1
    local argn = #toksArg
    while j <= argn do
      local t = toksArg[j]
      if t.t == "sym" then
        if t.w == "{" then
          depth = depth + 1
        elseif t.w == "}" then
          depth = math.max(depth - 1, 0)
        end
      elseif t.t == "id" and depth == 0 then
        local w = t.w
        if w == "func" then
          local k = j + 1
          if isSymArg(k, "(") then -- receiver group: func (r *T) M(...)
            local _, endj = readGroup(toksArg, k, "(", ")")
            k = endj + 1
          end
          if isIdArg(k) then -- named function (or method) at package level
            define(toksArg[k].w)
          end
        elseif w == "var" or w == "const" or w == "type" then
          local k = j + 1
          if isSymArg(k, "(") then -- block form: var ( ... )
            local ids, endj = readGroup(toksArg, k, "(", ")")
            for _, v in ipairs(ids) do define(v) end
          else
            while isIdArg(k) do
              define(toksArg[k].w)
              k = k + 1
              if isSymArg(k, ",") then k = k + 1 end
            end
          end
        end
      end
      j = j + 1
    end
  end

  -- packageNameOf devuelve el nombre del clause package de una lista de
  -- tokens, o nil si no lo tiene.
  local function packageNameOf(toksArg)
    for j = 1, #toksArg do
      local t = toksArg[j]
      if t.t == "id" and t.w == "package" then
        local nx = toksArg[j + 1]
        if nx and nx.t == "id" then return nx.w end
        return nil
      end
    end
    return nil
  end

  local function handleGo(tok, j)
    local w = tok.w
    if w == "func" then
      local k = j + 1
      local ids, endj
      local params = {}
      if isSym(k, "(") then -- receiver group: (r *T)
        ids, endj = readGroup(toks, k, "(", ")")
        for _, rn in ipairs(ids) do params[#params + 1] = rn end
        k = endj + 1
      end
      if isId(k) then -- named function
        define(toks[k].w)
        k = k + 1
      end
      if isSym(k, "(") then -- parameters
        ids, endj = readGroup(toks, k, "(", ")")
        for _, p in ipairs(ids) do params[#params + 1] = p end
        k = endj + 1
        if isSym(k, "(") then -- named returns
          local rids
          rids, endj = readGroup(toks, k, "(", ")")
          for _, rn in ipairs(rids) do params[#params + 1] = rn end
          k = endj + 1
        elseif isId(k) then -- bare return type: func f() error { ... }
          k = k + 1
        end
      end
      pendingParams = params
      return k
    elseif w == "package" then
      return j + 2
    elseif w == "import" then
      local k = j + 1
      if isSym(k, "(") then -- import ( ... ): walk ids (aliases), strings
        -- and the dot-import marker
        local _, endj = readGroup(toks, k, "(", ")")
        local g = k + 1
        local prevId
        local dotNext = false
        while g < endj do
          local t = toks[g]
          if t.t == "id" then
            prevId = t.w
          elseif t.t == "str" then
            if prevId then
              defineImport(prevId, tok.line)
            elseif not dotNext then
              local base = t.w:match("([^/]+)$") or t.w
              if base == "." then
                wildcard = true
              else
                defineImport(base, tok.line)
              end
            end
            prevId = nil
            dotNext = false
          elseif t.t == "sym" and t.w == "." then
            wildcard = true -- import ( . "x" ): names inject into the
            dotNext = true  -- namespace; the path is not an unused candidate
          end
          g = g + 1
        end
        return endj + 1
      end
      if isId(k) then -- aliased: import f "fmt"
        defineImport(toks[k].w, tok.line)
        return j + 3
      end
      if toks[k] and toks[k].t == "sym" and toks[k].w == "." then
        wildcard = true
        return j + 3
      end
      if toks[k] and toks[k].t == "str" then
        local base = toks[k].w:match("([^/]+)$") or toks[k].w
        if base == "." then
          wildcard = true
        else
          defineImport(base, tok.line)
        end
        return j + 1
      end
      return j + 1
    elseif w == "var" or w == "const" or w == "type" then
      local k = j + 1
      if isSym(k, "(") then -- var ( ... ) / const ( ... ) / type ( ... )
        local ids, endj = readGroup(toks, k, "(", ")")
        for _, v in ipairs(ids) do define(v) end
        return endj + 1
      end
      while isId(k) do
        define(toks[k].w)
        k = k + 1
        if isSym(k, ",") then k = k + 1 end
      end
      return k
    end
    return j + 1
  end

  local function handleJS(tok, j)
    local w = tok.w
    if w == "function" then
      local k = j + 1
      local ids, endj
      if isId(k) then
        define(toks[k].w)
        k = k + 1
      end
      if isSym(k, "(") then
        ids, endj = readGroup(toks, k, "(", ")")
        pendingParams = ids
        k = endj + 1
      end
      return k
    elseif w == "class" then
      local k = j + 1
      if isId(k) then
        define(toks[k].w)
      end
      return j + 2
    elseif w == "type" or w == "interface" then -- TS type alias / interface
      if isId(j + 1) then define(toks[j + 1].w) end
      return j + 2
    elseif w == "let" or w == "const" or w == "var" then
      local k = j + 1
      local depth = 0
      while toks[k] do
        local t = toks[k]
        if t.t == "sym" then
          if t.w == "=" then break end
          if t.w == "{" or t.w == "[" then depth = depth + 1 end
          if t.w == "}" or t.w == "]" then depth = math.max(depth - 1, 0) end
          if t.w == ";" and depth == 0 then break end
        elseif t.t == "id" then
          if not cfg.keywords[t.w] then define(t.w) end
        elseif t.t == "nl" and depth == 0 then
          break
        end
        k = k + 1
      end
      return k
    elseif w == "import" then
      local k = j + 1
      local depth = 0
      while toks[k] do
        local t = toks[k]
        if t.t == "sym" then
          if t.w == "{" or t.w == "[" then
            depth = depth + 1
          elseif t.w == "}" or t.w == "]" then
            depth = math.max(depth - 1, 0)
          elseif t.w == ";" and depth == 0 then
            break
          end
        elseif t.t == "id" then
          if not (t.w == "as" or t.w == "type" or (t.w == "from" and depth == 0)) then
            defineImport(t.w, tok.line)
          end
        elseif t.t == "str" then
          if depth == 0 then break end
        elseif t.t == "nl" and depth == 0 then
          break
        end
        k = k + 1
      end
      return k
    end
    return j + 1
  end

  local function handlePy(tok, j)
    local w = tok.w
    if w == "def" then
      local k = j + 1
      if isId(k) then
        define(toks[k].w)
        k = k + 1
      end
      if isSym(k, "(") then
        local ids, endj = readGroup(toks, k, "(", ")")
        -- Python has no braces: params are defined immediately in the
        -- current (single, file-level) scope.
        for _, p in ipairs(ids) do define(p) end
        k = endj + 1
      end
      return k
    elseif w == "class" then
      local k = j + 1
      if isId(k) then
        define(toks[k].w)
      end
      return j + 2
    elseif w == "import" then
      local k = j + 1
      while toks[k] do
        local t = toks[k]
        if t.t == "id" then
          if t.w == "as" then
            if isId(k + 1) then defineImport(toks[k + 1].w, tok.line) end
            k = k + 2
          else
            defineImport(t.w, tok.line)
            k = k + 1
          end
        elseif t.t == "sym" and t.w == "." then
          k = k + 1
        elseif t.t == "nl" then
          break
        else
          break
        end
      end
      return k
    elseif w == "from" then
      local k = j + 1
      while toks[k] and not (toks[k].t == "id" and toks[k].w == "import") do
        if toks[k].t == "nl" then return k end
        k = k + 1
      end
      k = k + 1
      while toks[k] do
        local t = toks[k]
        if t.t == "str" or t.t == "nl" then break end
        if t.t == "id" then
          if t.w == "as" then
            if isId(k + 1) then defineImport(toks[k + 1].w, tok.line) end
            k = k + 2
          else
            defineImport(t.w, tok.line)
            k = k + 1
          end
        elseif t.t == "sym" and t.w == "," then
          k = k + 1
        else
          break
        end
      end
      return k
    elseif w == "lambda" then
      local k = j + 1
      while toks[k] and not (toks[k].t == "sym" and toks[k].w == ":") do
        if toks[k].t == "id" then define(toks[k].w) end
        if toks[k].t == "nl" then break end
        k = k + 1
      end
      return k
    elseif w == "for" then
      local k = j + 1
      while toks[k] and not (toks[k].t == "id" and toks[k].w == "in") do
        if toks[k].t == "id" and not cfg.keywords[toks[k].w] then
          define(toks[k].w)
        end
        if toks[k].t == "nl" then break end
        k = k + 1
      end
      return k
    elseif w == "as" then
      if isId(j + 1) then define(toks[j + 1].w) end
      return j + 2
    end
    return j + 1
  end

  if cfg.lang == "go" then
    preScanPackageLevel(toks)
    -- Same-package sibling files: the editor provides the .go files of the
    -- buffer's directory (capped); only files with the same package clause
    -- contribute their top-level names. Older editor binaries without
    -- tcode.dir_files degrade silently to single-file analysis.
    if tcode.dir_files then
      local files = tcode.dir_files()
      if files then
        local activePkg = packageNameOf(toks)
        for i = 1, #files do
          local sibling = scan(files[i].content, cfg)
          if packageNameOf(sibling) == activePkg then
            preScanPackageLevel(sibling)
          end
        end
      end
    end
  end

  while i <= n do
    local tok = toks[i]
    if tok.t == "id" then
      local w = tok.w
      if w == "_" then
        i = i + 1
      elseif cfg.keywords[w] then
        if cfg.lang == "go" then
          i = handleGo(tok, i)
        elseif cfg.lang == "js" or cfg.lang == "ts" then
          i = handleJS(tok, i)
        else
          i = handlePy(tok, i)
        end
      elseif cfg.builtins[w] then
        -- A builtin base (console.log, math.abs) also skips its member chain:
        -- only the base is an identifier.
        if isSym(i + 1, ".") then
          i = i + 1 -- past '.'
          while isSym(i, ".") and isId(i + 1) do
            i = i + 2
          end
        else
          i = i + 1
        end
      elseif (cfg.lang == "go" or cfg.lang == "js" or cfg.lang == "ts") and isSym(i + 1, ":") then
        -- go: x := ...; js/ts: {key: v} or annotation: not a usage
        i = i + 1
      elseif isSym(i + 1, ",") then
        -- Comma-chain: either a multi-target declaration (go `a, b := x`,
        -- py `a, b = x`) or call args / comma operator (fn(a, b) — always
        -- usages). Walk the chain; skip the usage check only when it ends
        -- at the declaration marker (:= for go, = for py). The '=' handler
        -- defines every id of the chain.
        local j = i + 1
        local stopsAtDecl = false
        while toks[j] do
          local t = toks[j]
          if t.t == "id" then
            j = j + 1
          elseif t.t == "sym" then
            if t.w == "," then
              j = j + 1
            else
              stopsAtDecl = (t.w == ":" and isSym(j + 1, "="))
                or (cfg.lang == "py" and t.w == "=" and not isSym(j + 1, ">"))
              break
            end
          else
            break
          end
        end
        if stopsAtDecl then
          i = i + 1 -- defined by the '=' handler below
        else
          -- real usage (call args, commas in expressions)
          if defined(w) or wildcard then
            markUsed(w)
          else
            findings[#findings + 1] = { line = tok.line, msg = "undefined '" .. w .. "'" }
          end
          i = i + 1
        end
      elseif (cfg.lang == "py" or cfg.lang == "js" or cfg.lang == "ts") and isSym(i + 1, "=") then
        -- Assignment defines: py defines on any '=', js/ts v1 treats a plain
        -- assignment as an implicit definition (documented). go keeps the
        -- usage check: assigning to an undeclared var is an error there.
        if cfg.lang == "py" then
          define(w)
        elseif isSym(i + 2, ">") then
          -- single-param arrow x => ... : define only when the id follows a
          -- statement/expression boundary (= ( , [ { or a keyword), so
          -- `a >= b` comparisons don't define the operand.
          local p = toks[i - 1]
          if p == nil
            or (p.t == "sym" and (p.w == "=" or p.w == "(" or p.w == ","
              or p.w == "[" or p.w == "{"))
            or (p.t == "id" and cfg.keywords[p.w]) then
            define(w)
          end
        else
          define(w)
        end
        i = i + 1
      elseif isSym(i - 1, ":") then
        -- return/annotation types (): MyType, x: CustomType: not usages
        i = i + 1
      elseif isSym(i + 1, ".") then
        -- member chain: only the base is a variable; the rest are selectors
        local name = w
        if defined(name) or wildcard or (cfg.lang == "py" and name == "self") then
          markUsed(name)
        else
          findings[#findings + 1] = { line = tok.line, msg = "undefined '" .. name .. "'" }
        end
        i = i + 1 -- past '.'
        while isSym(i, ".") and isId(i + 1) do
          i = i + 2 -- skip .name pairs of the chain
        end
      else
        if defined(w) or wildcard then
          markUsed(w)
        else
          findings[#findings + 1] = { line = tok.line, msg = "undefined '" .. w .. "'" }
        end
        i = i + 1
      end
    elseif tok.t == "nl" then
      i = i + 1
    elseif tok.t == "sym" then
      if tok.w == "{" then
        stack[#stack + 1] = {}
        definePendingParams()
        i = i + 1
      elseif tok.w == "}" then
        if #stack > 1 then stack[#stack] = nil end
        i = i + 1
      elseif tok.w == "(" then
        -- Arrow params: (a, b) => ... (js/ts)
        if cfg.lang == "js" or cfg.lang == "ts" then
          local ids, endj = readGroup(toks, i, "(", ")")
          if isSym(endj + 1, "=") and isSym(endj + 2, ">") then
            for _, p in ipairs(ids) do define(p) end
          end
        end
        i = i + 1
      elseif tok.w == "=" then
        if cfg.lang == "py" then
          local k = i - 1
          while k >= 1 do
            local t = toks[k]
            if t.t == "id" then
              define(t.w)
              k = k - 1
            elseif t.t == "sym" and t.w == "," then
              k = k - 1
            else
              break
            end
          end
          local nx = toks[i + 1]
          if nx and nx.t == "id" and isSym(i + 2, "=") then
            define(nx.w)
          end
        elseif cfg.lang == "go" and isSym(i - 1, ":") then
          local k = i - 2
          while k >= 1 do
            local t = toks[k]
            if t.t == "id" then
              define(t.w)
              k = k - 1
            elseif t.t == "sym" and t.w == "," then
              k = k - 1
            else
              break
            end
          end
        elseif (cfg.lang == "js" or cfg.lang == "ts") then
          if isSym(i + 1, ">") then
            -- arrow with a single bare param: x => ...
            if isId(i - 1) and not cfg.keywords[toks[i - 1].w] then
              define(toks[i - 1].w)
            end
          else
            -- plain assignment defines in v1 (implicit global, documented)
            if isId(i - 1) and not cfg.keywords[toks[i - 1].w] then
              define(toks[i - 1].w)
            end
          end
        end
        i = i + 1
      else
        i = i + 1
      end
    else
      i = i + 1
    end
  end

  -- Unused imports, checked once at EOF.
  for name, rec in pairs(importBy) do
    if not rec.used then
      findings[#findings + 1] = { line = rec.line, msg = "unused import '" .. name .. "'" }
    end
  end
  return findings
end

-- --- Orchestration ---------------------------------------------------------

function check()
  local path, content = tcode.buffer()
  if not path then
    tcode.message("Code Linter: no active buffer")
    return
  end

  local diags = {}
  local errors = balanceCheck(content)
  for _, e in ipairs(errors) do
    diags[#diags + 1] = { line = e.l, message = e.m, severity = "error" }
  end

  local lang = detectLanguage(path)
  if lang and (lang == "go" or lang == "js" or lang == "ts" or lang == "py") then
    local cfg = langCfg[lang]
    cfg.lang = lang
    local findings = analyzeScope(scan(content, cfg), cfg)
    for _, f in ipairs(findings) do
      diags[#diags + 1] = { line = f.line, message = f.msg, severity = "warning" }
    end
  end

  local nerr = #diags
  if nerr == 0 then
    tcode.diagnostics.clear()
    tcode.message("Code Linter: no issues found")
    return
  end
  tcode.diagnostics.set(diags)
  local noun = "issue"
  if nerr > 1 then noun = "issues" end
  tcode.message("Code Linter: " .. nerr .. " " .. noun)
end