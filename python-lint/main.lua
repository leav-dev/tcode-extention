-- Python Lint for tcode (id tcode.pylint)
-- Python-specific structural lint: indentation (I1-I3), block structure
-- (E1-E3) and statement context (C1-C4). Only .py / .pyw; any other buffer
-- is a no-op. Severity "error" for everything structural, "warning" for
-- C4 (global at module level).
--
-- Editor API: tcode.buffer(), tcode.diagnostics.set/clear (per-provider:
-- replaces only this extension's diagnostics; the editor merges with the
-- other extensions).
--
-- check is GLOBAL on purpose: the backend resolves the function by name.
-- Convention: every message sent to the user is English.
--
-- RAM: no language tables. Just the line model plus the three check
-- families. The exclusion rule that keeps it quiet: a line that CONTINUES
-- a logical statement (bracket depth > 0, backslash continuation, or
-- inside a triple-quoted string) is never an indentation/block line --
-- Python allows arbitrary indentation there -- but its characters still
-- feed the bracket/triple-quote state machine.

-- set builds a word table from a space-separated string. Lua reserved words
-- (if, for, while, do, then, else, end, in, function, ...) cannot be used as
-- table literal keys, so every keyword set here is tokenized instead.
local function set(words)
  local t = {}
  for w in words:gmatch("%S+") do t[w] = true end
  return t
end

-- Keywords that require a ':' at depth 0 to open a block.
local COMPOUND = set("if elif else for while try except finally with def class")
-- Soft keywords: only open a block, never trigger E1 (an identifier named
-- `match` in another context must not open a block nor report a colon).
local SOFT = set("match case")
-- What may follow `async`.
local AHEAD = set("def for with")
-- Statement keywords checked for context (C1-C4).
local CTXWORD = set("return yield break continue nonlocal global")

-- joinChunks concatenates a chunk array in bounded batches. table.concat in
-- gopher-lua PUSHES every element onto the VM registry, so a generated line
-- with thousands of masked string chunks (e.g. a 72k-char list of string
-- literals) overflows it. Batching keeps each registry use well under the
-- limit regardless of line length.
local function joinChunks(chunks)
  local cur = chunks
  while #cur > 400 do
    local parts = {}
    local n = #cur
    local i = 1
    while i <= n do
      local j = i + 399
      if j > n then j = n end
      local batch = {}
      local b = 1
      for k = i, j do
        batch[b] = cur[k]
        b = b + 1
      end
      parts[#parts + 1] = table.concat(batch)
      i = j + 1
    end
    cur = parts
  end
  return table.concat(cur)
end

local function isPython(path)
  if not path then return false end
  local p = string.lower(path)
  return p:match("%.py$") ~= nil or p:match("%.pyw$") ~= nil
end

-- ---------------------------------------------------------------------------
-- Line model
-- ---------------------------------------------------------------------------

-- endsWithBackslash reports whether the physical line ends (after
-- trailing blanks) with an ODD number of backslashes. Python removes a
-- backslash-newline pair at the physical level BEFORE tokenizing, so the
-- continuation also applies inside a single-quoted string.
local function endsWithBackslash(raw)
  local s = raw:match("^(.-)%s*$")
  if s == "" then return false end
  local k = 0
  local i = #s
  while i >= 1 and s:sub(i, i) == "\\" do
    k = k + 1
    i = i - 1
  end
  return (k % 2) == 1
end

-- scanLine walks one physical line and returns its record plus the updated
-- carry state {triple, depth, cont}. String bodies are blanked with spaces
-- (length preserved) so every later pass works on a comment-free,
-- string-free view of the code; brackets inside strings never count.
--
-- The mask is built in CHUNKS (one entry per plain run or masked region),
-- never one entry per character: a generated file with a 72k-character line
-- would otherwise exhaust the Lua registry.
local function scanLine(raw, st)
  local rec = { raw = raw }
  local triple, simple, depth, cont = st.triple, st.simple, st.depth, st.cont
  local ends = endsWithBackslash(raw)
  rec.depthIn = depth
  rec.inTriple = triple ~= nil -- line starts inside a triple-quoted string
  rec.inSimple = simple ~= nil -- line starts inside a backslash-continued string
  rec.cont = cont

  local chunks = {}
  -- stringStart: the line opens a string literal. A line whose only
  -- content is a string (e.g. a one-line docstring as the sole body of a
  -- block) is NOT blank: it is a statement and must consume a pending block
  -- header. Only lines inside a triple-quoted string are blank for it.
  local stringStart = false
  local i, n = 1, #raw
  while i <= n do
    local c = raw:sub(i, i)
    if triple then
      local e = raw:find(triple, i, true)
      if e then
        chunks[#chunks + 1] = string.rep(" ", e + 3 - i)
        i = e + 3
        triple = nil
      else
        chunks[#chunks + 1] = string.rep(" ", n - i + 1)
        i = n + 1
      end
    elseif simple then
      -- A single-quoted string continued by a backslash-newline. Its body
      -- spans physical lines, so a bracket inside it must stay masked.
      local j = i
      local closed = false
      while j <= n do
        local sc = raw:sub(j, j)
        if sc == "\\" then
          j = j + 2
        elseif sc == simple then
          closed = true
          break
        else
          j = j + 1
        end
      end
      local last = closed and j or n
      chunks[#chunks + 1] = string.rep(" ", last - i + 1)
      if closed then
        simple = nil
        i = j + 1
      else
        i = n + 1
      end
    elseif c == "#" then
      i = n + 1 -- rest of the line is a comment
    elseif c == "'" or c == '"' then
      stringStart = true
      if raw:sub(i, i + 2) == c .. c .. c then
        triple = c .. c .. c
        chunks[#chunks + 1] = "   "
        i = i + 3
      else
        local j = i + 1
        local closed = false
        while j <= n do
          local sc = raw:sub(j, j)
          if sc == "\\" then
            j = j + 2
          elseif sc == c then
            closed = true
            break
          else
            j = j + 1
          end
        end
        local last = closed and j or n
        chunks[#chunks + 1] = string.rep(" ", last - i + 1)
        if closed then
          i = j + 1
        else
          -- Unclosed: Python joins it with the next line only through a
          -- trailing backslash; otherwise it is an error on its own line
          -- and must not leak onto the next one.
          if ends then simple = c end
          i = n + 1
        end
      end
    else
      -- Plain run: copy verbatim up to the next special character.
      local e = n + 1
      local e1 = raw:find("#", i, true)
      local e2 = raw:find("'", i, true)
      local e3 = raw:find('"', i, true)
      if e1 and e1 < e then e = e1 end
      if e2 and e2 < e then e = e2 end
      if e3 and e3 < e then e = e3 end
      chunks[#chunks + 1] = raw:sub(i, e - 1)
      i = e
    end
  end

  local code = joinChunks(chunks):match("^%s*(.-)%s*$")
  rec.code = code
  rec.stringStart = stringStart
  rec.blank = (code == "") and not stringStart
  rec.prefix = raw:match("^[ \t]*")
  rec.width = #rec.prefix
  rec.hasTab = rec.prefix:find("\t", 1, true) ~= nil
  rec.hasSpace = rec.prefix:find(" ", 1, true) ~= nil

  -- bracket delta and the last ':' seen at depth 0 (a ':' inside () [] {}
  -- is a dict / slice / annotation / nested lambda, not a block opener).
  -- The delta must go NEGATIVE for a line that only closes (a bare `}`, `]`
  -- or `)`): clamping it at 0 left depthOut unchanged and a multi-line dict
  -- or list never closed, so the logical statement swallowed the rest of the
  -- file. The colon counts when the GLOBAL depth (entry depth + local delta)
  -- is 0, so a header closed on a continuation line (`):`) still registers.
  local d, colonPos = 0, nil
  for k = 1, #code do
    local ch = code:sub(k, k)
    if ch == "(" or ch == "[" or ch == "{" then
      d = d + 1
    elseif ch == ")" or ch == "]" or ch == "}" then
      d = d - 1
    elseif ch == ":" and (depth + d) == 0 then
      colonPos = k
    end
  end
  rec.depthOut = depth + d
  if rec.depthOut < 0 then rec.depthOut = 0 end
  rec.colonPos = colonPos
  -- openBrackets: the logical statement still has unclosed brackets after
  -- this line (depthOut > 0), not merely a positive delta on this line.
  rec.openBrackets = rec.depthOut > 0

  rec.endsBackslash = ends
  st.triple = triple
  st.simple = simple
  st.depth = rec.depthOut
  st.cont = (triple == nil) and (simple == nil) and rec.endsBackslash
  return rec
end

-- classify reports the block kind a compound header opens and whether the
-- keyword requires a colon. Kinds: fn / loop / class / block.
local function classify(code)
  local w1 = code:match("^([%a_][%w_]*)")
  if not w1 then return nil, false end
  if w1 == "async" then
    local w2 = code:match("^async%s+([%a_][%w_]*)")
    if not w2 or not AHEAD[w2] then return nil, false end
    if w2 == "def" then return "fn", true end
    if w2 == "for" then return "loop", true end
    return "block", true
  end
  if w1 == "def" then return "fn", true end
  if w1 == "for" or w1 == "while" then return "loop", true end
  if w1 == "class" then return "class", true end
  if COMPOUND[w1] then return "block", true end
  if SOFT[w1] then return "block", false end
  return nil, false
end

-- tokens returns identifier tokens of a masked code string with their
-- bracket depth, so C1-C4 only look at depth 0 and never at `x.return`.
local function tokens(code)
  local res = {}
  local d, i, n = 0, 1, #code
  while i <= n do
    local c = code:sub(i, i)
    if c == "(" or c == "[" or c == "{" then
      d = d + 1
      i = i + 1
    elseif c == ")" or c == "]" or c == "}" then
      d = d - 1
      if d < 0 then d = 0 end
      i = i + 1
    elseif c:match("[%a_]") then
      local j = i
      while j <= n and code:sub(j, j):match("[%w_]") do j = j + 1 end
      res[#res + 1] = { w = code:sub(i, j - 1), d = d, prev = code:sub(i - 1, i - 1) }
      i = j
    else
      i = i + 1
    end
  end
  return res
end

-- ---------------------------------------------------------------------------
-- check
-- ---------------------------------------------------------------------------

function check()
  local path, content = tcode.buffer()
  if not path or not isPython(path) then
    return -- not Python: never touch diagnostics
  end

  local lines = {}
  local st = { triple = nil, simple = nil, depth = 0, cont = false }
  local lineNo = 1
  local pos = 1
  local total = #content
  while pos <= total + 1 do
    local nl = content:find("\n", pos, true)
    local raw
    if nl then
      raw = content:sub(pos, nl - 1)
    elseif pos <= total then
      raw = content:sub(pos)
    else
      raw = ""
    end
    if pos <= total or lineNo == 1 then
      local rec = scanLine(raw, st)
      rec.line = lineNo
      lines[#lines + 1] = rec
      lineNo = lineNo + 1
    end
    if not nl then break end
    pos = nl + 1
  end

  local findings, seen = {}, {}
  local function add(line, message, severity)
    local key = line .. "|" .. message
    if not seen[key] then
      seen[key] = true
      findings[#findings + 1] = { line = line, message = message, severity = severity }
    end
  end

  local blocks = {} -- {width, kind, selfLine}
  local levels = { 0 } -- indentation widths of the open levels (I3)
  local pending = nil -- {line, width, kind} block header waiting for a body
  local prevWidth = nil
  local widths = {} -- stmt lines: {line, width, tab, space}

  local function countKind(kind)
    local n = 0
    for _, b in ipairs(blocks) do
      if b.kind == kind then n = n + 1 end
    end
    return n
  end

  -- processLogical closes one LOGICAL statement: the indent/block checks
  -- use the width of its FIRST physical line, while the colon and the
  -- statement keywords may live on any of its lines (a header continued by
  -- a backslash or an open bracket, e.g. `for x in \` ... `]:`).
  local function processLogical(L)
    local w = L.width
    widths[#widths + 1] = { line = L.line, width = w,
      tab = L.hasTab, space = L.hasSpace }

    -- I1 mixed indentation
    if L.hasTab and L.hasSpace then
      add(L.line, "mixed indentation (tabs and spaces)", "error")
    end

    -- close blocks whose body width is deeper than this line (a statement
    -- at the body width itself is still inside the block)
    while #blocks > 0 do
      local b = blocks[#blocks]
      if b.selfLine or b.width > w then
        blocks[#blocks] = nil
      else
        break
      end
    end

    if pending then
      if w > pending.width then
        blocks[#blocks + 1] = { width = w, kind = pending.kind }
      else
        add(pending.line, "expected an indented block", "error")
      end
      pending = nil
    elseif prevWidth and w > prevWidth then
      -- E3 unexpected indent
      add(L.line, "unexpected indent", "error")
    end

    -- I3 unindent mismatch
    if prevWidth and w < prevWidth then
      local found = false
      for _, lv in ipairs(levels) do
        if lv == w then found = true break end
      end
      if not found then
        add(L.line, "unindent does not match any outer indentation level", "error")
      end
    end
    while #levels > 1 and levels[#levels] > w do levels[#levels] = nil end
    if levels[#levels] < w then levels[#levels + 1] = w end

    -- E1 missing colon: the header never got its ':' on ANY of its lines.
    if L.needsColon and L.kind and not L.hasColon then
      add(L.line, "expected ':' at the end of the line", "error")
    end
    if L.kind and L.endsColon then
      pending = { line = L.line, width = w, kind = L.kind }
    elseif L.kind and L.hasColon then
      -- one-liner: `if x: pass`, `def f(): return 1`, `while x: break`
      blocks[#blocks + 1] = { width = w, kind = L.kind, selfLine = true }
    end

    -- C1-C4 statement context. One-liners count too: the keyword is
    -- searched across the whole logical statement at depth 0, not only at
    -- the start (`if x: return`, `while x: break`).
    local fns = countKind("fn")
    local loops = countKind("loop")
    for _, t in ipairs(L.tokens) do
      if t.d == 0 and CTXWORD[t.w] and t.prev ~= "." then
        if t.w == "return" and fns == 0 then
          add(L.line, "'return' outside function", "error")
        elseif t.w == "yield" and fns == 0 then
          add(L.line, "'yield' outside function", "error")
        elseif t.w == "break" and loops == 0 then
          add(L.line, "'break' outside loop", "error")
        elseif t.w == "continue" and loops == 0 then
          add(L.line, "'continue' outside loop", "error")
        elseif t.w == "nonlocal" and fns < 2 then
          add(L.line, "nonlocal declaration outside nested function", "error")
        elseif t.w == "global" and fns == 0 then
          add(L.line, "global declaration at module level is a no-op", "warning")
        end
      end
    end

    prevWidth = w
  end

  -- A logical statement continues while it ends on a backslash or leaves
  -- brackets open; its continuation lines carry the colon and keywords.
  local logical = nil
  local function finishLogical()
    if logical then
      processLogical(logical)
      logical = nil
    end
  end

  for _, rec in ipairs(lines) do
    local continues = rec.inTriple or rec.inSimple
      or (rec.depthIn > 0) or rec.cont
    if rec.blank then
      -- No code on this line: blank, comment-only, or entirely inside a
      -- triple-quoted string. It is not a statement and never consumes a
      -- pending block. A line that OPENS a string is not blank
      -- (stringStart), and a line that CLOSES a triple may still carry code
      -- after the closing delimiter (e.g. `""", args)).fetchall():`).
    elseif continues then
      if logical then
        if rec.colonPos then
          logical.hasColon = true
          logical.endsColon = (rec.colonPos == #rec.code)
        else
          logical.endsColon = false
        end
        for _, t in ipairs(tokens(rec.code)) do
          logical.tokens[#logical.tokens + 1] = t
        end
        if not rec.openBrackets and not rec.endsBackslash then finishLogical() end
      end
    else
      finishLogical()
      local kind, needsColon = classify(rec.code)
      logical = {
        line = rec.line, width = rec.width,
        hasTab = rec.hasTab, hasSpace = rec.hasSpace,
        kind = kind, needsColon = needsColon,
        hasColon = rec.colonPos ~= nil,
        endsColon = (rec.colonPos ~= nil) and (rec.colonPos == #rec.code),
        tokens = tokens(rec.code),
      }
      if not rec.openBrackets and not rec.endsBackslash then finishLogical() end
    end
  end
  finishLogical()

  -- I2 inconsistent indentation (file mixes both styles)
  local nSpace, nTab = 0, 0
  for _, e in ipairs(widths) do
    if e.width > 0 then
      if e.space and not e.tab then nSpace = nSpace + 1 end
      if e.tab and not e.space then nTab = nTab + 1 end
    end
  end
  if nSpace > 0 and nTab > 0 and nSpace ~= nTab then
    local major = nSpace > nTab and "spaces" or "tabs"
    for _, e in ipairs(widths) do
      if e.width > 0 then
        if major == "spaces" and e.tab and not e.space then
          add(e.line, "inconsistent indentation (file uses spaces)", "error")
        elseif major == "tabs" and e.space and not e.tab then
          add(e.line, "inconsistent indentation (file uses tabs)", "error")
        end
      end
    end
  end

  -- stable sort by line
  for i = 2, #findings do
    local cur = findings[i]
    local j = i - 1
    while j >= 1 and findings[j].line > cur.line do
      findings[j + 1] = findings[j]
      j = j - 1
    end
    findings[j + 1] = cur
  end

  if #findings == 0 then
    tcode.diagnostics.clear()
    return
  end
  tcode.diagnostics.set(findings)
end
