-- Unused Imports for tcode (id: tcode.unusedimports)
-- Import bindings collected and never used for go/js/ts/py. Severity
-- "warning". Imports are per-file: no cross-file analysis needed.
--
-- Editor API: tcode.buffer(), tcode.message(), tcode.diagnostics.set/clear
-- (per-provider: replaces only this extension's diagnostics; the editor
-- merges with Error Detector / Undefined Variables).
--
-- check is GLOBAL on purpose: the backend resolves the function by name.
-- Convention: every message sent to the user is English.
-- RAM: language tables build lazily (only on the first file of that
-- language); no undefined-variable findings and no balance scanner here.

local function set(words)
  local t = {}
  for w in words:gmatch("%S+") do t[w] = true end
  return t
end

local function langTable(lang)
  if lang == "go" then
    return {
      lineComment = "//", blockComment = { "/*", "*/" },
      keywords = set("break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var"),
      builtins = set("nil true false iota append cap close complex copy delete imag len make new panic print println real recover error string int int8 int16 int32 int64 uint uint8 uint16 uint32 uint64 uintptr float32 float64 bool byte rune any"),
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

local function detectLanguage(path)
  if not path then return nil end
  local p = string.lower(path)
  if p:match("%.go$") then return "go" end
  if p:match("%.m?jsx?$") or p:match("%.m?tsx?$") then return "ts" end
  if p:match("%.py$") then return "py" end
  return nil
end

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

-- --- Import tracking (go/js/ts/py): collect + mark usage + unused at EOF ---

local function analyzeImports(toks, cfg, path)
  local findings = {}
  local global = {}
  local stack = { global }
  local importBy = {}           -- local name -> { line, used }
  local importSrc = {}          -- local name -> { remote, src } for existence checks
  local wildcard = false        -- go `import . "x"`: names inject, no track
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
  local function defineImport(name, line)
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
  -- defineUsed defines a type param AND marks it used: constraints
  -- (`<T extends Base>`) reference imports. Shadowing an import name
  -- with a type param hides it (accepted, silent, rare).
  local function defineUsed(name)
    if name and name ~= "" and not cfg.keywords[name] and not cfg.builtins[name] then
      cur()[name] = true
      markUsed(name)
    end
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
          markUsed(p) -- TS param type annotations use imported types too
        end
      end
      pendingParams = nil
    end
  end
  -- readAngle collects the ids in a balanced `<...>` group starting at
  -- ii (at `<`): TS type params and friends. `=>` pairs are skipped so
  -- function-type constraints don't end the group early. Returns ids and
  -- the index after the matching `>`, or nil when unbalanced.
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
  -- Returns kind, pos: "body" (pos at `{`), "arrow" (pos at `=` of
  -- `=>`), "end" (pos at `;`: overload/declare), nil (plain call).
  -- An optional TS `: type` annotation is skipped, bracket-aware over
  -- (), [], <>. A top-level `{` is taken as the body block.
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
        -- Generic type params: func f[T any](x T).
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
              defineImport(prevId, tok.line)
            elseif not dotNext then
              local base = goPackageName(t.w)
              if base == "." then
                wildcard = true
              else
                defineImport(base, tok.line)
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
        defineImport(toks[k].w, tok.line)
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
          defineImport(base, tok.line)
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
        local tids, kend = readAngle(k)
        if tids and isSym(kend, "(") then
          for _, t in ipairs(tids) do defineUsed(t) end
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
          local tids, kend = readAngle(k)
          if tids then
            for _, t in ipairs(tids) do defineUsed(t) end
            k = kend
          end
        end
        return k
      end
      return j + 1 -- anonymous: let `{` push its scope normally
    elseif w == "catch" then
      -- catch (e) { ... }: e is scoped to the catch block.
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
            for _, t in ipairs(tids) do defineUsed(t) end
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
            skipType = true -- TS annotation: let c: Config = ... (markUsed
            -- fires on the annotation id below)
          end
          if t.w == ";" and depth == 0 then break end
        elseif t.t == "id" then
          if skipType then
            markUsed(t.w)
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
      -- ESM import: [default] [, * as ns | { ... }] from 'spec'.
      -- Records each LOCAL binding with its REMOTE name and the module
      -- spec, so the existence check can verify `remote` in `spec`.
      -- `import {a as b}` binds b locally; a is what the target must
      -- export. Side-effect imports bind nothing.
      local k = j + 1
      local depth = 0
      local bindings = {}
      local defaultDone, sawBrace, sawStar = false, false, false
      local function reg(localName, remoteName)
        if localName and localName ~= "" then
          bindings[#bindings + 1] = { lname = localName, rname = remoteName or localName }
        end
      end
      if toks[k] and toks[k].t == "id" and toks[k].w == "type" then
        local nx = toks[k + 1]
        if nx and ((nx.t == "sym" and (nx.w == "{" or nx.w == "*")) or nx.t == "id") then
          k = k + 1 -- TS `import type ...` marker
        end
      end
      while toks[k] do
        local t = toks[k]
        if t.t == "sym" then
          if t.w == "{" or t.w == "[" then
            depth = depth + 1
            sawBrace = true
          elseif t.w == "}" or t.w == "]" then
            depth = math.max(depth - 1, 0)
          elseif t.w == "*" and depth == 0 then
            sawStar = true
          elseif t.w == ";" and depth == 0 then
            break
          end
          k = k + 1
        elseif t.t == "id" then
          if t.w == "from" and depth == 0 then
            k = k + 1
            break -- module spec follows
          elseif t.w == "type" and depth > 0 then
            k = k + 1 -- TS `import {type A}` marker
          elseif depth > 0 then
            local remote = t.w
            local nk = k + 1
            if toks[nk] and toks[nk].t == "id" and toks[nk].w == "as"
              and toks[nk + 1] and toks[nk + 1].t == "id" then
              reg(toks[nk + 1].w, remote)
              k = nk + 2
            else
              reg(remote, remote)
              k = k + 1
            end
          else
            if sawStar and t.w == "as" then
              if toks[k + 1] and toks[k + 1].t == "id" then
                reg(toks[k + 1].w, "*")
                k = k + 2
              else
                k = k + 1
              end
            elseif not defaultDone and not sawBrace and not sawStar and t.w ~= "as" then
              reg(t.w, "default")
              defaultDone = true
              k = k + 1
            else
              k = k + 1
            end
          end
        elseif t.t == "str" then
          if depth == 0 then break end -- side-effect import: no bindings
          k = k + 1
        elseif t.t == "nl" then
          if depth == 0 then break end
          k = k + 1
        else
          break
        end
      end
      local src = nil
      if toks[k] and toks[k].t == "str" then src = toks[k].w end
      for _, b in ipairs(bindings) do
        defineImport(b.lname, tok.line)
        if src and not importSrc[b.lname] then
          importSrc[b.lname] = { rname = b.rname, src = src }
        end
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
      -- from <spec> import <names>: <spec> is dots + dotted path
      -- (".y", ".", "..pkg", "os"). Only relative specs (leading
      -- dot) are resolvable; the rest record no src and are skipped by
      -- the existence check. `a as b` binds b locally; a is remote.
      local k = j + 1
      local specparts = {}
      while toks[k] and not (toks[k].t == "id" and toks[k].w == "import") do
        if toks[k].t == "nl" then return k end
        if toks[k].t == "sym" and toks[k].w == "." then
          specparts[#specparts + 1] = "."
        elseif toks[k].t == "id" then
          specparts[#specparts + 1] = toks[k].w
        else
          return k
        end
        k = k + 1
      end
      if not (toks[k] and toks[k].t == "id") then return k end
      k = k + 1 -- skip `import`
      local spec = table.concat(specparts)
      local rel = spec:sub(1, 1) == "."
      local depth = 0
      while toks[k] do
        local t = toks[k]
        if t.t == "sym" then
          if t.w == "(" then
            depth = depth + 1
          elseif t.w == ")" then
            depth = math.max(depth - 1, 0)
          elseif t.w == ";" then
            break
          elseif t.w ~= "," then
            break
          end
          k = k + 1
        elseif t.t == "id" then
          local remote, localName = t.w, t.w
          local nk = k + 1
          if toks[nk] and toks[nk].t == "id" and toks[nk].w == "as"
            and toks[nk + 1] and toks[nk + 1].t == "id" then
            localName = toks[nk + 1].w
            k = nk + 2
          else
            k = k + 1
          end
          defineImport(localName, tok.line)
          if rel and not importSrc[localName] then
            importSrc[localName] = { rname = remote, src = spec }
          end
        elseif t.t == "nl" then
          if depth == 0 then break end -- parenthesized lists may span lines
          k = k + 1
        else
          break -- str, `*` (not a token; absent) ends the list
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
        markUsed(w) -- annotations and x := still USE the imported type
        i = i + 1
      elseif isSym(i + 1, ",") then
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
          if defined(w) then markUsed(w) end
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
        markUsed(w) -- return/annotation types
        i = i + 1
      elseif isSym(i - 1, ".") then
        i = i + 1 -- member selector after an expression: never the binding
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
          define(w)
          for _, t in ipairs(mparams.t) do defineUsed(t) end
          pendingParams = mparams.v
          i = mafter
        elseif mkind == "end" then
          define(w)
          for _, t in ipairs(mparams.t) do defineUsed(t) end
          pendingParams = nil
          i = mafter
        else
          -- Plain call: the callee is a usage.
          if defined(w) then markUsed(w) end
          i = i + 1
        end
      elseif isSym(i + 1, ".") then
        if defined(w) then markUsed(w) end
        i = i + 1
        while isSym(i, ".") and isId(i + 1) do
          i = i + 2
        end
      else
        if defined(w) then markUsed(w) end
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
        -- Anything else falls through untouched.
        local tids, kend = readAngle(i)
        if tids and isSym(kend, "(") then
          local _, gend = readGroup(toks, kend, "(", ")")
          if scanAfterParams(gend) == "arrow" then
            for _, t in ipairs(tids) do defineUsed(t) end
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

  -- --- Direction 2: the imported name must exist in the source module ---
  -- Only relative file imports are resolvable (JS/TS `./x`, Python
  -- `from .y import z`). Anything unreadable is silently skipped: bare
  -- specifiers, stdlib, path aliases, parent escapes, Go packages.
  -- Requires tcode.read_file (newer editors); older ones keep direction 1.
  local fileCache = {} -- relpath -> content or false; fresh per check()
  local canRead = tcode.read_file ~= nil

  local function readCached(rel)
    if fileCache[rel] == nil then
      local r = canRead and tcode.read_file(rel)
      if type(r) == "table" and type(r.content) == "string" then
        fileCache[rel] = r.content
      else
        fileCache[rel] = false
      end
    end
    if fileCache[rel] == false then return nil end
    return fileCache[rel]
  end

  -- joinNorm lexically normalizes a buffer-dir-relative path, resolving
  -- `.`/`..`. Returns nil when it would escape the buffer dir (which
  -- read_file would reject too).
  local function joinNorm(p)
    local parts = {}
    for part in p:gmatch("[^/]+") do
      if part == "." or part == "" then
        -- skip
      elseif part == ".." then
        if #parts == 0 then return nil end
        parts[#parts] = nil
      else
        parts[#parts + 1] = part
      end
    end
    return table.concat(parts, "/")
  end

  local function targetDirOf(rel)
    return rel:match("^(.*)/[^/]*$") or ""
  end

  -- maskContent blanks strings and comments (block-aware) so export/def
  -- patterns never fire inside them. Newlines are preserved; the result
  -- is only ever pattern-matched, never shown.
  local function maskContent(content)
    local out = {}
    local i, n = 1, #content
    local delim = nil
    while i <= n do
      local c = content:sub(i, i)
      if delim then
        if c == "\\" then
          out[#out + 1] = "  "
          i = i + 2
        elseif c == delim then
          out[#out + 1] = " "
          delim = nil
          i = i + 1
        else
          out[#out + 1] = (c == "\n" and "\n" or " ")
          i = i + 1
        end
      elseif c == '"' or c == "'" or c == "`" then
        delim = c
        out[#out + 1] = " "
        i = i + 1
      elseif c == "/" and content:sub(i + 1, i + 1) == "/" then
        local nl = content:find("\n", i, true)
        if nl then
          i = nl
        else
          break
        end
      elseif c == "/" and content:sub(i + 1, i + 1) == "*" then
        local close = content:find("*/", i + 2, true)
        if close then
          for _ in content:sub(i, close + 1):gmatch("\n") do out[#out + 1] = "\n" end
          i = close + 2
        else
          break
        end
      else
        out[#out + 1] = c
        i = i + 1
      end
    end
    return table.concat(out)
  end

  local jsExts = { ".ts", ".tsx", ".mts", ".cts", ".js", ".jsx", ".mjs", ".cjs" }

  -- resolveJs finds a relative spec's target: returns relpath + content.
  -- fromDir is the importing file's dir, "" for the buffer dir.
  local function resolveJs(spec, fromDir)
    if spec:sub(1, 1) ~= "." then return nil end
    local base = spec:gsub("^%./", "")
    local prefix = (fromDir == nil or fromDir == "") and "" or (fromDir .. "/")
    local cands = {}
    if base:match("%.[%w]+$") then cands[#cands + 1] = prefix .. base end
    for _, e in ipairs(jsExts) do cands[#cands + 1] = prefix .. base .. e end
    for _, e in ipairs(jsExts) do cands[#cands + 1] = prefix .. base .. "/index" .. e end
    for _, c in ipairs(cands) do
      local norm = joinNorm(c)
      if norm then
        local content = readCached(norm)
        if content then return norm, content end
      end
    end
    return nil
  end

  -- maskSeg blanks strings and line comments in one line,
  -- length-preserving (block comments are handled by the caller).
  local function maskSeg(line)
    local out = {}
    local i, n = 1, #line
    local delim = nil
    while i <= n do
      local c = line:sub(i, i)
      if delim then
        if c == "\\" then
          out[#out + 1] = "  "
          i = i + 2
        elseif c == delim then
          out[#out + 1] = " "
          delim = nil
          i = i + 1
        else
          out[#out + 1] = " "
          i = i + 1
        end
      elseif c == '"' or c == "'" or c == "`" then
        delim = c
        out[#out + 1] = " "
        i = i + 1
      elseif c == "/" and line:sub(i + 1, i + 1) == "/" then
        break
      else
        out[#out + 1] = c
        i = i + 1
      end
    end
    return table.concat(out)
  end

  -- emitExportList records one `export { ... }` item list: plain names go
  -- to `names`, while a trailing `from 'spec'` turns items into re-export
  -- entries (the pre-as name is what the target must export).
  local function emitExportList(listText, mrest, rrest, names, reexp)
    local gspec = nil
    if mrest and mrest:find("from") then
      gspec = rrest:match("^}%s*from%s*\"([^\"]+)\"")
        or rrest:match("^}%s*from%s*'([^']+)'")
    end
    for item in listText:gmatch("[^,]+") do
      local words = {}
      for w in item:gmatch("%S+") do words[#words + 1] = w end
      local exported, orig = nil, nil
      if #words == 3 and words[2] == "as" then
        exported, orig = words[3], words[1]
      elseif #words == 2 and words[1] == "type" then
        exported, orig = words[2], words[2]
      elseif #words == 1 and words[1] ~= "type" then
        exported, orig = words[1], words[1]
      end
      if exported then
        if gspec then
          reexp[#reexp + 1] = { name = orig, src = gspec }
        else
          names[exported] = true
        end
      end
    end
  end

  -- jsExports parses a module's exports: names set, `export *` specs,
  -- and re-export lists {name, src} (`export {a} from './z'`).
  -- Specs live inside strings, so they are read from the raw line once
  -- the masked line proves a real statement (never the reverse).
  local function jsExports(content)
    local pm = " " .. maskContent(content) .. " "
    local names, stars, reexp = {}, {}, {}
    if pm:find("export%s+default[^%w_]") then names["default"] = true end
    for fn in pm:gmatch("[^%w_]export%s+function%s*%*?%s*([%w_]+)") do names[fn] = true end
    for fn in pm:gmatch("[^%w_]export%s+async%s+function%s*%*?%s*([%w_]+)") do names[fn] = true end
    for cn in pm:gmatch("[^%w_]export%s+abstract%s+class%s+([%w_]+)") do names[cn] = true end
    for cn in pm:gmatch("[^%w_]export%s+class%s+([%w_]+)") do names[cn] = true end
    for _, dk in ipairs({ "const", "let", "var", "enum", "interface", "type", "namespace" }) do
      for dn in pm:gmatch("[^%w_]export%s+" .. dk .. "%s+([%w_]+)") do names[dn] = true end
      for dl in pm:gmatch("[^%w_]export%s+" .. dk .. "%s*{([^}]*)}") do
        for id in dl:gmatch("[%w_]+") do names[id] = true end
      end
    end
    -- Export lists and star re-exports, line by line. `export const {` /
    -- `export type {` destructured declarations are handled by the loops
    -- above (`export type {A}` counts as a plain list);
    -- `export * as ns from` re-exports only ns, so it is not chased.
    local inBlock, acc, start = false, nil, 1
    while true do
      local nl = content:find("\n", start, true)
      local raw = nl and content:sub(start, nl - 1) or content:sub(start)
      local cline = raw
      if inBlock then
        local close = cline:find("*/", 1, true)
        if close then
          cline = string.rep(" ", close + 1) .. cline:sub(close + 2)
          inBlock = false
        else
          cline = ""
        end
      end
      if not inBlock then
        local open = cline:find("/*", 1, true)
        if open then
          local close = cline:find("*/", open + 2, true)
          if close then
            cline = cline:sub(1, open - 1) .. string.rep(" ", close + 2 - open) .. cline:sub(close + 2)
          else
            cline = cline:sub(1, open - 1)
            inBlock = true
          end
        end
      end
      if cline ~= "" then
        local mline = maskSeg(cline)
        if mline:find("export%s*%*%s*from") then
          local sspec = cline:match("export%s*%*%s*from%s*\"([^\"]+)\"")
            or cline:match("export%s*%*%s*from%s*'([^']+)'")
          if sspec then stars[#stars + 1] = sspec end
        end
        if acc then
          local close = mline:find("}", 1, true)
          if close then
            emitExportList(acc .. mline:sub(1, close - 1),
              mline:sub(close + 1), cline:sub(close + 1), names, reexp)
            acc = nil
          else
            acc = acc .. mline
          end
        else
          local os, oe = mline:find("export%s*{")
          -- `export const {` & co. are declarations (handled above);
          -- `export type {A}` is a plain export list.
          if os and (not mline:find("export%s+%w+%s*{") or mline:find("export%s+type%s*{")) then
            local after, rafter = mline:sub(oe + 1), cline:sub(oe + 1)
            local close = after:find("}", 1, true)
            if close then
              emitExportList(after:sub(1, close - 1),
                after:sub(close + 1), rafter:sub(close + 1), names, reexp)
            else
              acc = after
            end
          end
        end
      end
      if not nl then break end
      start = nl + 1
    end
    return { names = names, stars = stars, reexp = reexp }
  end

  local function jsHasExport(content, name, fromDir, depth, seen)
    local ex = jsExports(content)
    if ex.names[name] then return true end
    if depth >= 4 then return false end
    for _, r in ipairs(ex.reexp) do
      if r.name == name then
        local nrel, ncontent = resolveJs(r.src, fromDir)
        if ncontent and not seen[nrel] then
          seen[nrel] = true
          if jsHasExport(ncontent, name, targetDirOf(nrel), depth + 1, seen) then
            return true
          end
        end
      end
    end
    for _, s in ipairs(ex.stars) do
      local nrel, ncontent = resolveJs(s, fromDir)
      if ncontent and not seen[nrel] then
        seen[nrel] = true
        if jsHasExport(ncontent, name, targetDirOf(nrel), depth + 1, seen) then
          return true
        end
      end
    end
    return false
  end

  -- pyDefs collects importable module-level names: every def/class
  -- (any indent: methods share names, and try/except shims define at
  -- indent 1) plus assignments at indent width <= 4 (top level and
  -- try/except fallbacks; deeper function locals are excluded).
  local function pyDefs(content)
    local names = {}
    local inStr = false
    local start = 1
    while true do
      local nl = content:find("\n", start, true)
      local raw = nl and content:sub(start, nl - 1) or content:sub(start)
      local line = raw
      if inStr then
        local q1 = line:find('"""', 1, true)
        local q2 = line:find("'''", 1, true)
        local q = q1 and q2 and math.min(q1, q2) or (q1 or q2)
        if q then
          inStr = false
          line = line:sub(q + 3)
        else
          line = ""
        end
      end
      if not inStr then
        local code = line:gsub("#.*$", "")
        local triple = 0
        for _ in code:gmatch('"""') do triple = triple + 1 end
        for _ in code:gmatch("'''") do triple = triple + 1 end
        local head = code
        if triple % 2 == 1 then
          inStr = true
          local q1 = code:find('"""', 1, true)
          local q2 = code:find("'''", 1, true)
          local q = q1 and q2 and math.min(q1, q2) or (q1 or q2)
          head = code:sub(1, q - 1)
        end
        local indent = head:match("^(%s*)") or ""
        local fn = head:match("^%s*def%s+([%w_]+)")
          or head:match("^%s*async%s+def%s+([%w_]+)")
        if fn then
          names[fn] = true
        else
          local cl = head:match("^%s*class%s+([%w_]+)")
          if cl then
            names[cl] = true
          elseif #indent <= 4 then
            local v = head:match("^%s*([%w_]+)%s*:?%s*=%s*[^=]")
              or head:match("^%s*([%w_]+)%s*:=")
            if v then names[v] = true end
          end
        end
      end
      if not nl then break end
      start = nl + 1
    end
    return names
  end

  -- resolvePyModule finds a same-or-below-dir module file for `from .`
  -- style specs. `dotted` uses dots ("a.b"), `level` counts leading
  -- dots (1 = buffer dir). Returns relpath + content or nil.
  local function resolvePyModule(dotted, level)
    local ups = {}
    for _ = 2, level do ups[#ups + 1] = ".." end
    local prefix = table.concat(ups, "/")
    local modpath = dotted:gsub("%.", "/")
    local base = (prefix == "" and modpath) or (prefix .. "/" .. modpath)
    for _, c in ipairs({ base .. ".py", base .. "/__init__.py" }) do
      local norm = joinNorm(c)
      if norm then
        local content = readCached(norm)
        if content then return norm, content end
      end
    end
    return nil
  end

  -- Unused imports, checked once at EOF.
  for name, rec in pairs(importBy) do
    if not rec.used then
      findings[#findings + 1] = { line = rec.line, msg = "unused import '" .. name .. "'", sev = "warning" }
    end
  end
  -- jsSkippedSpec: specs we must stay silent on. Bare specifiers
  -- (node_modules, aliases) and explicit non-code extensions (.json,
  -- .css) are unreadable by design; flagging them would false-positive.
  -- A missing relative code file, in contrast, is a real error.
  local function jsSkippedSpec(spec)
    if spec:sub(1, 1) ~= "." then return true end
    local base = spec:gsub("^%./", "")
    local ext = base:match("%.([%w]+)$")
    if ext then
      for _, e in ipairs(jsExts) do
        if ("." .. ext) == e then return false end
      end
      return true
    end
    return false
  end
  -- Unresolvable imports (direction 2): the bound name must exist in
  -- the source module. Skipped specs stay silent; missing relative
  -- targets are real errors (version drift), except namespace-package
  -- dirs (no __init__.py), which read_file cannot see: known limitation.
  if canRead then
    for name, rec in pairs(importBy) do
      local spec = importSrc[name]
      if spec then
        local found = nil -- nil = skipped, true/false = checked
        if cfg.lang == "js" or cfg.lang == "ts" then
          if not jsSkippedSpec(spec.src) then
            if spec.rname == "*" then
              found = resolveJs(spec.src, "") ~= nil
            else
              local rel, content = resolveJs(spec.src, "")
              if content then
                found = jsHasExport(content, spec.rname, targetDirOf(rel), 0, { [rel] = true })
              else
                found = false
              end
            end
          end
        elseif cfg.lang == "py" then
          local dots, rest = spec.src:match("^(%.+)(.*)$")
          if dots then
            if rest == "" then
              -- `from . import mod`: the name itself is the module.
              found = resolvePyModule(name, #dots) ~= nil
            else
              local _, content = resolvePyModule(rest, #dots)
              if content then
                found = pyDefs(content)[spec.rname] == true
              else
                found = false
              end
            end
          end
        end
        -- Go imports are package paths: out of scope (the compiler owns that).
        if found == false then
          findings[#findings + 1] = { line = rec.line,
            msg = "unresolved import '" .. spec.rname .. "' from '" .. spec.src .. "'", sev = "error" }
        end
      end
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
      local findings = analyzeImports(scan(content, cfg), cfg, path)
      for _, f in ipairs(findings) do
        diags[#diags + 1] = { line = f.line, message = f.msg, severity = f.sev or "warning" }
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