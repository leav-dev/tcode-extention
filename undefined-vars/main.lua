-- Undefined Variables for tcode (id: tcode.undefinedvars)
-- Scope analysis for go/js/ts/py: identifiers used but never defined
-- (package-wide in Go: same-file order-independent + sibling files of the
-- same package via tcode.dir_files). Severity "warning".
--
-- Editor API: tcode.buffer(), tcode.message(), tcode.diagnostics.set/clear
-- (per-provider: replaces only this extension's diagnostics; the editor
-- merges with Error Detector / Unused Imports) and tcode.dir_files (the .go
-- siblings of the active buffer's directory).
--
-- check is GLOBAL on purpose: the backend resolves the function by name.
-- Convention: every message sent to the user is English.
-- RAM: language tables build lazily (only on the first file of that
-- language); this script has no unused-import machinery and no balance
-- scanner.

-- set builds a lookup table from a whitespace-separated word list (avoids
-- Lua reserved words as bare table keys).
local function set(words)
  local t = {}
  for w in words:gmatch("%S+") do t[w] = true end
  return t
end

-- langTable builds ONE language's config, only when first requested.
local function langTable(lang)
  if lang == "go" then
    return {
      lineComment = "//", blockComment = { "/*", "*/" },
      keywords = set("break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var"),
      builtins = set("nil true false iota append cap clear close complex complex64 complex128 copy delete imag len make max min new panic print println real recover error string int int8 int16 int32 int64 uint uint8 uint16 uint32 uint64 uintptr float32 float64 bool byte rune any comparable"),
    }
  elseif lang == "js" then
    return {
      lineComment = "//", blockComment = { "/*", "*/" },
      keywords = set("break case catch class const continue debugger default delete do else export extends finally for function if import in instanceof let new of return super switch this throw try typeof var void while with yield async await from as static get set"),
      builtins = set("undefined null true false NaN Infinity console window document process require module exports globalThis fetch JSON Math Object Array String Number Boolean Symbol Function Promise Error Date RegExp Map Set WeakMap WeakSet Proxy Reflect parseInt parseFloat isNaN setTimeout setInterval clearTimeout clearInterval localStorage"),
    }
  elseif lang == "ts" then -- Angular rides on ts rules.
    return {
      lineComment = "//", blockComment = { "/*", "*/" },
      keywords = set("break case catch class const continue debugger default delete do else enum export extends finally for function if import in instanceof let new of return super switch this throw try typeof var void while with yield async await from as static get set type interface implements readonly abstract namespace declare is keyof infer"),
      builtins = set("undefined null true false NaN Infinity console window document process require module exports globalThis fetch JSON Math Object Array String Number Boolean Symbol Function Promise Error Date RegExp Map Set WeakMap WeakSet Proxy Reflect parseInt parseFloat isNaN setTimeout setInterval clearTimeout clearInterval localStorage any unknown never string number boolean object Record Partial Readonly"),
    }
  elseif lang == "py" then
    return {
      lineComment = "#", blockComment = false,
      keywords = set("and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield"),
      builtins = set("True False None len range print str int float bool list dict set tuple type isinstance enumerate zip map filter sorted sum min max abs any all open input repr format round divmod hash id object property classmethod staticmethod super self Exception ValueError TypeError KeyError IndexError NameError RuntimeError"),
    }
  end
  return nil
end

local builtTables = {}
local function cfgFor(lang)
  if not builtTables[lang] then
    local c = langTable(lang)
    if c then
      c.lang = lang
      builtTables[lang] = c
    end
  end
  return builtTables[lang]
end

-- detectLanguage infers the language from the buffer path; nil -> balance
-- is not this extension's job, so nothing runs.
local function detectLanguage(path)
  if not path then return nil end
  local p = string.lower(path)
  if p:match("%.go$") then return "go" end
  if p:match("%.m?jsx?$") or p:match("%.m?tsx?$") then return "ts" end
  if p:match("%.py$") then return "py" end
  return nil
end

-- scan tokenizes content skipping comments and strings per language.
local function scan(content, cfg)
  local toks = {}
  local line = 1
  local n = #content
  local i = 1
  local syms = {
    ["("] = true, [")"] = true, ["["] = true, ["]"] = true, ["{"] = true,
    ["}"] = true, ["."] = true, [","] = true, [":"] = true, ["="] = true,
    [";"] = true, ["+"] = true, [">"] = true, ["<"] = true,
  }
  local function push(t, w)
    toks[#toks + 1] = { t = t, w = w, line = line }
  end
  while i <= n do
    local c = content:sub(i, i)
    if c == "\n" then
      push("nl", "")
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
      if b and (b >= 48 and b <= 57) then
        -- Number literal: consume the whole token (0o644, 0x1F, 0b101,
        -- 1_000, 1e10, 1.5). Without this, 0o644 would leave "o644" as an
        -- identifier and false-flag it as undefined.
        local j = i + 1
        while j <= n do
          local nc = content:sub(j, j)
          local ncb = nc:byte()
          if ncb and ((ncb >= 48 and ncb <= 57) or (ncb >= 97 and ncb <= 122)
            or (ncb >= 65 and ncb <= 90) or nc == "_") then
            j = j + 1
          elseif nc == "." then
            local nx = content:sub(j + 1, j + 1):byte()
            if nx and nx >= 48 and nx <= 57 then
              j = j + 1 -- 1.5: the '.' belongs to the number
            else
              break
            end
          else
            break
          end
        end
        i = j -- no token: a number can never be a variable name
      elseif b and ((b >= 97 and b <= 122) or (b >= 65 and b <= 90) or c == "_") then
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

-- --- Scope analysis (go/js/ts/py): undefined usages only -------------------

local function analyzeScope(toks, cfg)
  local findings = {}
  local global = {}
  local stack = { global }
  local wildcard = false        -- go `import . "x"`
  local pendingParams = nil
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
  local function defineImport(name)
    -- Imports only DEFINE names (package/alias bindings); there is no
    -- unused-import tracking in this script.
    if not name or name == "" then return end
    if cfg.keywords[name] or cfg.builtins[name] or name == "_" then return end
    global[name] = true
  end
  local function defined(name)
    for k = #stack, 1, -1 do
      if stack[k][name] then return true end
    end
    return false
  end
  local function readGroup(list, j, openCh, closeCh)
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
  -- readAngle collects the ids in a balanced `<...>` group starting at
  -- ii (at `<`): TS type params and friends. `=>` pairs are skipped so
  -- function-type constraints don't end the group early. Returns ids and
  -- the index after the matching `>`, or nil when unbalanced. Callers
  -- only invoke it in type-param positions, so comparisons never reach it
  -- as a definition site (a failed match simply falls back to the old path).
  local function readAngle(ii)
    local ids, depth = {}, 1
    local k = ii + 1
    while toks[k] do
      local t = toks[k]
      if t.t == "sym" and t.w == "=" and toks[k + 1]
        and toks[k + 1].t == "sym" and toks[k + 1].w == ">" then
        k = k + 2 -- `=>` inside a constraint: not a closer
      else
        if t.t == "sym" then
          if t.w == "<" then
            depth = depth + 1
          elseif t.w == ">" then
            depth = depth - 1
            if depth == 0 then return ids, k + 1 end
          end
        elseif t.t == "id" then
          ids[#ids + 1] = t.w
        end
        k = k + 1
      end
    end
    return nil
  end
  -- scanAfterParams looks past a `)` closing a JS/TS param group.
  -- Returns kind, pos where kind is:
  --   "body"  -> pos at `{` starting a block body
  --   "arrow" -> pos at `=` of `=>`
  --   "end"   -> pos at `;` (declaration without body: overloads)
  --   nil     -> anything else (plain call)
  -- An optional TS return-type annotation (`: type`) is skipped,
  -- bracket-aware over (), [], <>. A top-level `{` is taken as the body
  -- block; a bare object return type (`): {a: number} {`) is a known
  -- limitation (params may flag there).
  local function scanAfterParams(endj)
    local k = endj + 1
    if isSym(k, "{") then return "body", k end
    if isSym(k, "=") and isSym(k + 1, ">") then return "arrow", k end
    if not isSym(k, ":") then return nil end
    local depth = 0
    local j = k + 1
    while toks[j] do
      local t = toks[j]
      if t.t == "sym" then
        local w = t.w
        if w == "(" or w == "[" or w == "<" then
          depth = depth + 1
        elseif w == ")" or w == "]" or w == ">" then
          depth = math.max(depth - 1, 0)
        elseif depth == 0 then
          if w == "{" then return "body", j end
          if w == "=" and isSym(j + 1, ">") then return "arrow", j end
          if w == ";" then return "end", j end
          if w == "," or w == "=" then return nil end
        end
      end
      j = j + 1
    end
    return nil
  end

  -- Go: package-level names are visible file-wide (order-independent) AND
  -- across the files of the same package (siblings via tcode.dir_files).
  local function preScanPackageLevel(toksArg)
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
          if isSymArg(k, "(") then
            local _, endj = readGroup(toksArg, k, "(", ")")
            k = endj + 1
          end
          if isIdArg(k) then
            define(toksArg[k].w)
          end
        elseif w == "var" or w == "const" or w == "type" then
          local k = j + 1
          if isSymArg(k, "(") then
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

  -- pyForTargets pre-scan: comprehensions use their `for` target before
  -- its textual definition (`[f(x) for x in xs]` visits `f(x)` first).
  -- Walk all tokens once; on every `for` collect target ids up to the
  -- matching `in` on the same logical line (same rule as handlePy `for`)
  -- and define them in global before the single-pass main loop runs.
  local function preScanPyForTargets(toksArg)
    local m = #toksArg
    local j = 1
    while j <= m do
      local t = toksArg[j]
      if t.t == "id" and t.w == "for" then
        local k = j + 1
        while toksArg[k] and not (toksArg[k].t == "id" and toksArg[k].w == "in") do
          if toksArg[k].t == "id" and not cfg.keywords[toksArg[k].w] then
            define(toksArg[k].w)
          end
          if toksArg[k].t == "nl" then break end
          k = k + 1
        end
      end
      j = j + 1
    end
  end

  -- goPackageName: Go import path -> package identifier. The last path
  -- element is the name UNLESS it is a module version suffix (/v2, /v3,
  -- /v2.1.0), in which case the name is the element BEFORE it (Go rule;
  -- /v1 is NOT a suffix: "x/y/v1" names the package v1).
  local function goPackageName(path)
    local base = path:match("([^/]+)$") or path
    local major = base:match("^v(%d+)%.%d+%.%d+$") or base:match("^v(%d+)$")
    if major and tonumber(major) >= 2 then
      local prev = path:match("^(.*)/[^/]+$")
      if prev then
        local p = prev:match("([^/]+)$")
        if p then base = p end
      end
    end
    return base
  end

  local function handleGo(tok, j)
    local w = tok.w
    if w == "func" then
      local k = j + 1
      local ids, endj
      local params = {}
      if isSym(k, "(") then
        ids, endj = readGroup(toks, k, "(", ")")
        for _, rn in ipairs(ids) do params[#params + 1] = rn end
        k = endj + 1
      end
      if isId(k) then
        define(toks[k].w)
        k = k + 1
      end
      if isSym(k, "[") then
        -- Generic type params: func f[T any](x T). Constraints are
        -- over-collected as names (harmless: only suppresses warnings).
        local tids, tendj = readGroup(toks, k, "[", "]")
        for _, t in ipairs(tids) do params[#params + 1] = t end
        k = tendj + 1
      end
      if isSym(k, "(") then
        ids, endj = readGroup(toks, k, "(", ")")
        for _, p in ipairs(ids) do params[#params + 1] = p end
        k = endj + 1
        if isSym(k, "(") then
          local rids
          rids, endj = readGroup(toks, k, "(", ")")
          for _, rn in ipairs(rids) do params[#params + 1] = rn end
          k = endj + 1
        elseif isId(k) then
          k = k + 1
        end
      end
      pendingParams = params
      return k
    elseif w == "package" then
      return j + 2
    elseif w == "import" then
      local k = j + 1
      if isSym(k, "(") then
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
              defineImport(prevId)
            elseif not dotNext then
              local base = goPackageName(t.w)
              if base == "." then
                wildcard = true
              else
                defineImport(base)
              end
            end
            prevId = nil
            dotNext = false
          elseif t.t == "sym" and t.w == "." then
            wildcard = true
            dotNext = true
          end
          g = g + 1
        end
        return endj + 1
      end
      if isId(k) then
        defineImport(toks[k].w)
        return j + 3
      end
      if toks[k] and toks[k].t == "sym" and toks[k].w == "." then
        wildcard = true
        return j + 3
      end
      if toks[k] and toks[k].t == "str" then
        local base = goPackageName(toks[k].w)
        if base == "." then
          wildcard = true
        else
          defineImport(base)
        end
        return j + 1
      end
      return j + 1
    elseif w == "var" or w == "const" or w == "type" then
      local k = j + 1
      if isSym(k, "(") then
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
      if isSym(k, "<") then
        -- Generic function: type params define immediately (return-type
        -- annotations precede `{` and reference them).
        local tids, kend = readAngle(k)
        if tids and isSym(kend, "(") then
          for _, t in ipairs(tids) do define(t) end
          k = kend
        end
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
        k = k + 1
        if isSym(k, "<") then
          -- Generic class: immediate (extends/implements precede `{`).
          local tids, kend = readAngle(k)
          if tids then
            for _, t in ipairs(tids) do define(t) end
            k = kend
          end
        end
        return k
      end
      return j + 1 -- anonymous: let `{` push its scope normally
    elseif w == "catch" then
      -- catch (e) { ... }: e is a definition scoped to the catch block.
      local k = j + 1
      if isSym(k, "(") then
        local ids, endj = readGroup(toks, k, "(", ")")
        pendingParams = ids
        return endj + 1
      end
      return j + 1
    elseif w == "type" or w == "interface" then
      local k = j + 1
      if isId(k) then
        define(toks[k].w)
        k = k + 1
        if isSym(k, "<") then
          local tids, kend = readAngle(k)
          if tids then
            for _, t in ipairs(tids) do define(t) end
            k = kend
          end
        end
        return k
      end
      return j + 1
    elseif w == "let" or w == "const" or w == "var" then
      local k = j + 1
      local depth = 0
      local skipType = false
      while toks[k] do
        local t = toks[k]
        if t.t == "sym" then
          if t.w == "=" then break end
          if t.w == "{" or t.w == "[" then depth = depth + 1 end
          if t.w == "}" or t.w == "]" then depth = math.max(depth - 1, 0) end
          if t.w == ":" and depth == 0 then
            skipType = true -- TS annotation: let c: Config = ...
          end
          if t.w == ";" and depth == 0 then break end
        elseif t.t == "id" then
          if skipType then
            skipType = false
          elseif not cfg.keywords[t.w] then
            define(t.w)
          end
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
            defineImport(t.w)
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
            if isId(k + 1) then defineImport(toks[k + 1].w) end
            k = k + 2
          else
            defineImport(t.w)
            k = k + 1
          end
        elseif t.t == "sym" and (t.w == "." or t.w == ",") then
          k = k + 1
        elseif t.t == "nl" then
          -- Comma/backslash continuation: a `nl` right after `,`
          -- continues the name list (`import os, \n sys`; the `\`
          -- itself emits no token). Any other `nl` ends the statement.
          local p = k - 1
          while p >= 1 and toks[p].t == "nl" do p = p - 1 end
          local pt = toks[p]
          if pt and pt.t == "sym" and pt.w == "," then
            k = k + 1
          else
            break
          end
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
      local depth = 0
      while toks[k] do
        local t = toks[k]
        if t.t == "str" then break end
        if t.t == "nl" then
          -- Inside `(...)` newlines are continuations; outside, only a
          -- trailing `,` (or its `\` form, which emits no token)
          -- continues. Any other `nl` ends the statement so the next
          -- line is never swallowed as an import name.
          if depth > 0 then
            k = k + 1
          else
            local p = k - 1
            while p >= 1 and toks[p].t == "nl" do p = p - 1 end
            local pt = toks[p]
            if pt and pt.t == "sym" and pt.w == "," then
              k = k + 1
            else
              break
            end
          end
        elseif t.t == "id" then
          if t.w == "as" then
            if isId(k + 1) then defineImport(toks[k + 1].w) end
            k = k + 2
          else
            defineImport(t.w)
            k = k + 1
          end
        elseif t.t == "sym" and (t.w == "," or t.w == "(" or t.w == ")") then
          if t.w == "(" then depth = depth + 1 end
          if t.w == ")" then depth = math.max(depth - 1, 0) end
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
    if tcode.dir_files then
      local files = tcode.dir_files()
      if files then
        local activePkg = packageNameOf(toks)
        for f = 1, #files do
          local sibling = scan(files[f].content, cfg)
          if packageNameOf(sibling) == activePkg then
            preScanPackageLevel(sibling)
          end
        end
      end
    end
  end

  if cfg.lang == "py" then
    preScanPyForTargets(toks)
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
        if isSym(i + 1, ".") then
          i = i + 1
          while isSym(i, ".") and isId(i + 1) do
            i = i + 2
          end
        else
          i = i + 1
        end
      elseif (cfg.lang == "go" or cfg.lang == "js" or cfg.lang == "ts") and isSym(i + 1, ":") then
        -- go x := ; js/ts {key: v} or annotation: not a usage
        i = i + 1
      elseif isSym(i - 1, ".") then
        -- member selector after an expression (fn().prop, arr[i].prop)
        i = i + 1
      elseif isSym(i + 1, ",") then
        -- multi-target decl (go a, b := ; py a, b =) vs call args (fn(a, b))
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
          i = i + 1
        else
          if not (defined(w) or wildcard) then
            findings[#findings + 1] = { line = tok.line, msg = "undefined '" .. w .. "'" }
          end
          i = i + 1
        end
      elseif (cfg.lang == "py" or cfg.lang == "js" or cfg.lang == "ts") and isSym(i + 1, "=") then
        if cfg.lang == "py" then
          define(w)
        elseif isSym(i + 2, ">") then
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
        -- annotation types: not usages
        i = i + 1
      elseif (cfg.lang == "js" or cfg.lang == "ts") and (isSym(i + 1, "(") or isSym(i + 1, "<")) then
        -- Shorthand method definition, optionally generic (`foo<T>(...)`).
        -- A failed match (e.g. a comparison) falls back to the plain
        -- usage check below with the index untouched.
        local mkind, mafter, mparams = nil, nil, nil
        do
          local k = i + 1
          local tparams = nil
          if isSym(k, "<") then
            local tids, kend = readAngle(k)
            if not (tids and isSym(kend, "(")) then
              tparams = false -- not type args: plain usage path
            else
              tparams = tids
              k = kend
            end
          end
          if tparams ~= false and isSym(k, "(") then
            local mids, mendj = readGroup(toks, k, "(", ")")
            local kind, kpos = scanAfterParams(mendj)
            if kind == "body" or kind == "end" then
              mkind, mafter, mparams = kind, kpos, { t = tparams or {}, v = mids }
            end
          end
        end
        if mkind == "body" then
          -- `{` is left for the main loop, which pushes the body scope
          -- and defines the value params there. Type params define now:
          -- return-type annotations precede `{` and reference them.
          define(w)
          for _, t in ipairs(mparams.t) do define(t) end
          pendingParams = mparams.v
          i = mafter
        elseif mkind == "end" then
          -- Overload/declare signature: a name definition without body.
          -- The annotation is skipped so type names never flag.
          define(w)
          for _, t in ipairs(mparams.t) do define(t) end
          pendingParams = nil
          i = mafter
        else
          -- Plain call (or comparison): usage check, index untouched.
          if not (defined(w) or wildcard) then
            findings[#findings + 1] = { line = tok.line, msg = "undefined '" .. w .. "'" }
          end
          i = i + 1
        end
      elseif isSym(i + 1, ".") then
        -- member chain: only the base is a variable
        local name = w
        if not (defined(name) or wildcard or (cfg.lang == "py" and name == "self")) then
          findings[#findings + 1] = { line = tok.line, msg = "undefined '" .. name .. "'" }
        end
        i = i + 1
        while isSym(i, ".") and isId(i + 1) do
          i = i + 2
        end
      else
        if not (defined(w) or wildcard) then
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
        if cfg.lang == "js" or cfg.lang == "ts" then
          local ids, endj = readGroup(toks, i, "(", ")")
          -- Arrow params, with optional TS return type in between.
          if scanAfterParams(endj) == "arrow" then
            for _, p in ipairs(ids) do define(p) end
          end
        end
        i = i + 1
      elseif tok.w == "<" and (cfg.lang == "js" or cfg.lang == "ts") then
        -- Possible generic arrow `<T>(x) =>`: define the type params now
        -- (they are visited before the `(` handler confirms the arrow).
        -- Anything else (comparisons, calls with type args, JSX) fails
        -- the lookahead and falls through untouched.
        local tids, kend = readAngle(i)
        if tids and isSym(kend, "(") then
          local _, gend = readGroup(toks, kend, "(", ")")
          if scanAfterParams(gend) == "arrow" then
            for _, t in ipairs(tids) do define(t) end
          end
        end
        i = i + 1
      elseif tok.w == ";" then
        -- A `;` ends any declaration: drop params of bodyless
        -- overloads so they never leak into an unrelated `{` below.
        pendingParams = nil
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
            if isId(i - 1) and not cfg.keywords[toks[i - 1].w] then
              define(toks[i - 1].w)
            end
          else
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
  return findings
end

-- --- Orchestration ---------------------------------------------------------

function check()
  local path, content = tcode.buffer()
  if not path then
    return
  end

  local diags = {}
  local lang = detectLanguage(path)
  if lang then
    local cfg = cfgFor(lang)
    if cfg then
      local findings = analyzeScope(scan(content, cfg), cfg)
      for _, f in ipairs(findings) do
        diags[#diags + 1] = { line = f.line, message = f.msg, severity = "warning" }
      end
    end
  end

  local nerr = #diags
  if nerr == 0 then
    tcode.diagnostics.clear()
    return
  end
  tcode.diagnostics.set(diags)
end