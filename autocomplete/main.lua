-- Autocomplete for tcode (id: tcode.autocomplete)
-- Buffer-word completion: completes the word under the cursor from the
-- words found in the open buffer. Manual trigger only (keybinding).
--
-- Editor API: tcode.buffer(), tcode.cursor(), tcode.line(n),
-- tcode.lineCount(), tcode.insert(text), tcode.message(text).
-- Cursor is 1-indexed (line, col). Pure Lua: no io/os/require.
--
-- complete is GLOBAL on purpose: the backend resolves the function by
-- name with GetGlobal(fn).
--
-- Convention: every message sent to the user is English.
-- This script never touches the diagnostics API.
--
-- Completion is stateless: it inserts the longest common extension (or lists candidates when they diverge).
--
-- suggest is the ghost provider for editors with contributes.suggest: pure
-- (reads buffer/cursor/line only, never inserts or messages) and returns
-- the candidate words for the prefix under the cursor, best first. Missing
-- cursor API or empty prefix yields an empty table, never an error.

-- prefixAtCursor returns the word prefix under the cursor, or nil plus a
-- kind for messages: "cursor" (API missing/unusable), "position"
-- (fractional), "line" (unreadable) or "prefix" (empty). Shared by
-- complete() (kind -> message) and suggest() (kind ignored, empty table).
-- Also returns the line text and the 1-indexed start col of the prefix
-- (for this./self. context detection).
local function prefixAtCursor()
  if type(tcode.cursor) ~= "function" then
    return nil, "cursor"
  end
  local okCur, curLine, curCol = pcall(tcode.cursor)
  if not okCur or curLine == nil or curCol == nil then
    return nil, "cursor"
  end
  curLine = tonumber(curLine)
  curCol = tonumber(curCol)
  if not curLine or not curCol then
    return nil, "cursor"
  end
  if curLine ~= math.floor(curLine) or curCol ~= math.floor(curCol) then
    return nil, "position"
  end
  if curCol < 1 then
    curCol = 1
  end
  local okLine, curText = pcall(tcode.line, curLine)
  if not okLine or type(curText) ~= "string" then
    return nil, "line"
  end
  local prefix = curText:sub(1, curCol - 1):match("[A-Za-z0-9_]+$") or ""
  if prefix == "" then
    return nil, "prefix"
  end
  return prefix, nil, curText, curCol - #prefix
end

-- langOf infers the provider language from the buffer path.
local function langOf(path)
  if not path then return nil end
  local p = string.lower(path)
  if p:match("%.pyw?$") then return "py" end
  if p:match("%.m?[jt]sx?$") or p:match("%.cjs$") then return "ts" end
  return nil
end

-- thisContext detects `this.` (js/ts) or `self.` (py) right before the
-- prefix start: the only context where member candidates apply.
local function thisContext(lineText, startCol)
  if not lineText or not startCol then return nil end
  local before = lineText:sub(1, startCol - 1)
  if before:match("this%s*%.%s*$") then return "this" end
  if before:match("self%s*%.%s*$") then return "self" end
  return nil
end

-- memberStop are control keywords that the line-name pattern must never
-- take as member names.
local memberStop = {}
for w in ("if for while switch catch with return typeof new delete void in of else do case break continue"):gmatch("%S+") do
  memberStop[w] = true
end

-- collectMembers gathers likely member names for this./self. completion.
-- Heuristic and documented as over-approximating: exact `this.X =`
-- assignments, constructor param properties, py `def` names, and
-- declaration-looking line starts at class depth (naive brace count gated
-- on having seen `class`; skew errs toward missing, never inventing
-- depth). A ghost candidate shows dimmed first and needs Tab, so a stray
-- name costs a glance, not a corruption.
local function collectMembers(content, lang)
  local members = {}
  local function add(n)
    if n and n ~= "" and not memberStop[n] then members[n] = true end
  end
  local selfword = (lang == "py") and "self" or "this"
  for name, tail in content:gmatch(selfword .. "%.([A-Za-z0-9_]+)%s*=%s*(%S?)") do
    if tail ~= "=" and tail ~= ">" then add(name) end -- not == or =>
  end
  if lang == "py" then
    for name in content:gmatch("def%s+([A-Za-z0-9_]+)%s*%(") do add(name) end
    return members
  end
  for _, mod in ipairs({ "private", "public", "protected", "readonly" }) do
    for name in content:gmatch(mod .. "%s+([A-Za-z0-9_]+)") do add(name) end
  end
  local seenClass, depth = false, 0
  for line in (content .. "\n"):gmatch("([^\n]*)\n") do
    local code = line
    if not code:match("^%s*//") then
      if code:match("%f[%a]class%f[%A]") then seenClass = true end
      if seenClass and depth == 1 then
        local _, name = code:match("^(.-)([A-Za-z0-9_]+)%s*[:=%<%(]")
        add(name)
      end
    end
    for i = 1, #line do
      local c = line:sub(i, i)
      if c == "{" then depth = depth + 1
      elseif c == "}" then depth = math.max(depth - 1, 0) end
    end
  end
  return members
end

-- importRelpaths lists relative import targets in first-seen order:
-- ts/js `from/import "..."`, py `from .x import` (-> ./x.py, ./x/__init__
-- .py). Bare imports (stdlib/node) are skipped: read_file only resolves
-- inside the buffer dir anyway.
local function importRelpaths(content, lang)
  local out, seen = {}, {}
  local function add(r)
    if r and r ~= "" and not seen[r] then
      seen[r] = true
      out[#out + 1] = r
    end
  end
  if lang == "py" then
    for mod in content:gmatch("from%s+([%.%w]+)%s+import") do
      if mod:sub(1, 1) == "." then
        local dots, rest = mod:match("^(%.+)(.*)$")
        local base = (rest:gsub("%.", "/"))
        if #dots > 1 then base = string.rep("../", #dots - 1) .. base
        else base = "./" .. base end
        add(base .. ".py")
        add(base .. "/__init__.py")
      end
    end
    return out
  end
  for _, pat in ipairs({ "from%s*[\"']([^\"']+)[\"']", "import%s*[\"']([^\"']+)[\"']" }) do
    for raw in content:gmatch(pat) do
      if raw:sub(1, 1) == "." then
        if raw:match("%.%a+$") then
          add(raw)
        else
          add(raw .. ".ts")
          add(raw .. ".tsx")
          add(raw .. ".js")
          add(raw .. "/index.ts")
        end
      end
    end
  end
  return out
end

-- safeReadFile reads one import target (nil when unavailable): old editors
-- lack tcode.read_file and the host maps misses to nil, both degrade here.
local function safeReadFile(rel)
  if type(tcode.read_file) ~= "function" then return nil end
  local ok, f = pcall(tcode.read_file, rel)
  if not ok or type(f) ~= "table" then return nil end
  if type(f.content) ~= "string" then return nil end
  return f.content
end

-- wordsOf accumulates a frequency table from text.
local function wordsOf(content, freq)
  freq = freq or {}
  for w in content:gmatch("[A-Za-z0-9_]+") do
    freq[w] = (freq[w] or 0) + 1
  end
  return freq
end

-- prefixList filters a freq table to longer words with the prefix, sorted
-- by frequency then alphabetically.
local function prefixList(freq, prefix)
  local list = {}
  for w in pairs(freq) do
    if w ~= prefix and #w > #prefix and w:sub(1, #prefix) == prefix then
      list[#list + 1] = w
    end
  end
  table.sort(list, function(a, b)
    if freq[a] ~= freq[b] then
      return freq[a] > freq[b]
    end
    return a < b
  end)
  return list
end

-- fuzzyScore rates subsequence matches (nil when not all chars match in
-- order): fewer gaps and earlier start win. Case-sensitive, like prefix.
local function fuzzyScore(word, prefix)
  local wi, gaps, first = 1, 0, nil
  for pi = 1, #prefix do
    local found = word:find(prefix:sub(pi, pi), wi, true)
    if not found then return nil end
    if not first then first = found end
    gaps = gaps + (found - wi)
    wi = found + 1
  end
  return 100 - gaps * 5 - (first - 1)
end

-- poolCap bounds the ranked pool (mirrors the provider contract max).
local poolCap = 32

-- poolFor builds the ranked suggestion pool, best first: members in
-- this./self. context, same-file prefix words, import-file prefix words,
-- then fuzzy subsequence matches. Deduped (first tier wins), exact prefix
-- excluded, capped. complete() reuses it for its LCP.
local function poolFor(prefix, content, path, lineText, startCol)
  local lang = langOf(path)
  local ctx = thisContext(lineText, startCol)
  local memberSet = {}
  if ctx then memberSet = collectMembers(content, lang) end

  local sameFreq = wordsOf(content)
  local otherFreq = {}
  local reads = 0
  for _, rel in ipairs(importRelpaths(content, lang)) do
    if reads >= 8 then break end
    reads = reads + 1
    local text = safeReadFile(rel)
    if text then wordsOf(text, otherFreq) end
  end
  if type(tcode.dir_files) == "function" then
    local ok, files = pcall(tcode.dir_files)
    if ok and type(files) == "table" then
      for i = 1, #files do
        local f = files[i]
        if type(f) == "table" and type(f.content) == "string" then
          wordsOf(f.content, otherFreq)
        end
      end
    end
  end

  local ranked, seen = {}, {}
  local function push(w)
    if w ~= prefix and not seen[w] and #ranked < poolCap then
      seen[w] = true
      ranked[#ranked + 1] = w
    end
  end
  if ctx then
    local ms = {}
    for w in pairs(memberSet) do
      if w ~= prefix and #w > #prefix and w:sub(1, #prefix) == prefix then
        ms[#ms + 1] = w
      end
    end
    table.sort(ms)
    for _, w in ipairs(ms) do push(w) end
  end
  for _, w in ipairs(prefixList(sameFreq, prefix)) do push(w) end
  for _, w in ipairs(prefixList(otherFreq, prefix)) do push(w) end
  local scored = {}
  local function consider(w)
    if w == prefix or seen[w] then return end
    local s = fuzzyScore(w, prefix)
    if s then scored[#scored + 1] = { w = w, s = s } end
  end
  for w in pairs(memberSet) do consider(w) end
  for w in pairs(sameFreq) do consider(w) end
  for w in pairs(otherFreq) do consider(w) end
  table.sort(scored, function(a, b)
    if a.s ~= b.s then return a.s > b.s end
    return a.w < b.w
  end)
  for _, e in ipairs(scored) do push(e.w) end
  return ranked
end

function suggest()
  local path, content = tcode.buffer()
  if not path then
    return {}
  end
  local prefix, _, lineText, startCol = prefixAtCursor()
  if not prefix then
    return {}
  end
  return poolFor(prefix, content, path, lineText, startCol)
end

function complete()
  local path, content = tcode.buffer()
  if not path then
    return
  end

  local prefix, kind, lineText, startCol = prefixAtCursor()
  if not prefix then
    if kind == "position" then
      tcode.message("Autocomplete: invalid cursor position")
    elseif kind == "line" then
      tcode.message("Autocomplete: cannot read current line")
    elseif kind == "prefix" then
      tcode.message("Autocomplete: no word prefix under cursor")
    else
      tcode.message("Autocomplete: editor cursor API (tcode.cursor) is not available")
    end
    return
  end

  local candidates = poolFor(prefix, content, path, lineText, startCol)
  if #candidates == 0 then
    tcode.message("Autocomplete: no candidates for '" .. prefix .. "'")
    return
  end
  local lcp = candidates[1]
  for i = 2, #candidates do
    local other = candidates[i]
    local m = #lcp
    if #other < m then
      m = #other
    end
    local j = 0
    while j < m and lcp:sub(j + 1, j + 1) == other:sub(j + 1, j + 1) do
      j = j + 1
    end
    lcp = lcp:sub(1, j)
    if lcp == prefix then
      break
    end
  end

  local suffix = lcp:sub(#prefix + 1)
  if suffix ~= "" then
    tcode.insert(suffix)
    return
  end

  local shown = {}
  for i = 1, math.min(5, #candidates) do
    shown[#shown + 1] = candidates[i]
  end
  tcode.message("Autocomplete: " .. #candidates .. " candidates for '" .. prefix .. "': " .. table.concat(shown, ", "))
end
