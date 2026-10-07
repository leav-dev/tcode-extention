-- Data Lint for tcode (id: tcode.datalint)
-- Syntax + structure validator for JSON, YAML and XML.
-- Severity "error" for broken syntax/structure, "warning" only for
-- duplicate keys. Any other file is a no-op (diagnostics untouched).
--
-- Editor API: tcode.buffer(), tcode.diagnostics.set/clear (per-provider:
-- replaces only this extension's diagnostics; the editor merges with the
-- other extensions). Pure Lua: no io/os, buffer content only.
--
-- check is GLOBAL on purpose: the backend resolves the function by name.
--
-- Convention: every message sent to the user is English. Lines are 1-indexed.

-- detectLang infers the data language from the buffer path. Returns
-- "yaml", "json", "xml" or nil (anything else, including .svg/.html/.go
-- /.py, is a no-op so providers never double-report).
local function detectLang(path)
  if not path then return nil end
  local p = string.lower(path)
  if p:match("%.ya?ml$") then return "yaml" end
  if p:match("%.json$") then return "json" end
  if p:match("%.xml$") or p:match("%.xsd$") or p:match("%.xsl$") then return "xml" end
  return nil
end

-- sortDiags orders findings by line so the gutter reads top-down.
local function sortDiags(diags)
  table.sort(diags, function(a, b) return a.line < b.line end)
  return diags
end

-- ---------------------------------------------------------------------------
-- JSON: string-aware scanner over {} [] with line tracking.
-- Detects unterminated strings, unclosed/mismatched brackets, missing and
-- trailing commas, missing/unexpected colons, single-quoted strings and
-- comments (both rejected). Duplicate keys in the same object are warnings.
-- ---------------------------------------------------------------------------
local function jsonCheck(content)
  local diags = {}
  local stack = {} -- {ch="{ "/","[", line=line, keys={}, needComma=false}
  local line, i, n = 1, 1, #content

  local function add(l, m, sev)
    diags[#diags + 1] = { l = l, m = m, s = sev or "error" }
  end

  -- Skip whitespace (counting lines). Returns next index.
  local function skipWs(j)
    while j <= n do
      local c = content:sub(j, j)
      if c == "\n" then line = line + 1 j = j + 1
      elseif c:match("%s") then j = j + 1
      else break end
    end
    return j
  end

  -- Parse a double-quoted string starting at i (content:sub(i,i) == '"').
  -- Returns endIndex (first char after closing quote), raw key, ok.
  local function parseString(j)
    local s = j + 1
    while s <= n do
      local c = content:sub(s, s)
      if c == "\n" then return s, nil, false end -- newline inside string
      if c == "\\" then s = s + 2
      elseif c == '"' then return s + 1, content:sub(j + 1, s - 1), true
      else s = s + 1 end
    end
    return s, nil, false -- EOF before close
  end

  -- Mark the just-closed value as complete for comma tracking.
  local function valueDone()
    local top = stack[#stack]
    if top then top.needComma = true end
  end

  -- Reports a missing comma when a complete value already sits in the
  -- current container. Returns true when it fired (for key recovery).
  local function checkNeedComma(top)
    if top and top.needComma then
      add(line, "missing comma between members")
      top.needComma = false
      return true
    end
    return false
  end

  i = skipWs(i)
  while i <= n do
    local c = content:sub(i, i)
    local top = stack[#stack]
    if c == "\n" then
      line = line + 1 i = i + 1
    elseif c:match("%s") then
      i = i + 1
    elseif c == "/" and (content:sub(i + 1, i + 1) == "/" or content:sub(i + 1, i + 1) == "*") then
      -- Comments are not valid JSON: report, then skip them to avoid noise.
      add(line, "comments are not allowed in JSON")
      if content:sub(i + 1, i + 1) == "/" then
        while i <= n and content:sub(i, i) ~= "\n" do i = i + 1 end
      else
        i = i + 2
        local closed = false
        while i <= n do
          local d = content:sub(i, i)
          if d == "\n" then line = line + 1 i = i + 1
          elseif d == "*" and content:sub(i + 1, i + 1) == "/" then i = i + 2 closed = true break
          else i = i + 1 end
        end
        if not closed then add(line, "unclosed comment in JSON") end
      end
    elseif c == "'" then
      -- Single-quoted strings are not valid JSON.
      add(line, "single-quoted strings are not allowed in JSON, use double quotes")
      if top and top.ch == "{" and top.expectKey then
        top.expectKey = false top.expectColon = true
      elseif top and top.ch == "{" and top.expectColon then
        -- stray value where ':' belongs; keep state
      else
        if top and not top.expectKey then checkNeedComma(top) end
      end
      i = i + 1
      local closed = false
      while i <= n do
        local d = content:sub(i, i)
        if d == "\n" then break end
        if d == "\\" then i = i + 2
        elseif d == "'" then closed = true i = i + 1 break
        else i = i + 1 end
      end
      if not closed then add(line, "unterminated string") end
      if top then top.afterComma = false end
      valueDone()
      if top and top.ch == "{" and top.expectColon then top.expectColon = false end
      i = skipWs(i)
    elseif c == '"' then
      local isKey = top and top.ch == "{" and top.expectKey
      local missed = false
      if not isKey then missed = checkNeedComma(top) end
      if top then top.afterComma = false end
      local ni, raw, ok = parseString(i)
      if not ok then
        add(line, "unterminated string")
        i = n + 1
      else
        if isKey then
          if top.keys[raw] then
            add(line, "duplicate key \"" .. raw .. "\" in the same object", "warning")
          else
            top.keys[raw] = true
          end
          top.expectKey = false top.expectColon = true
        elseif missed and top and top.ch == "{" then
          -- Recovery: a string right after a complete member in an
          -- object is the next key (avoids a bogus "unexpected ':'").
          if top.keys[raw] then
            add(line, "duplicate key \"" .. raw .. "\" in the same object", "warning")
          else
            top.keys[raw] = true
          end
          top.expectKey = false top.expectColon = true
        else
          valueDone()
        end
        -- Count embedded lines (should be none, strings are single-line).
        i = ni
      end
      i = skipWs(i)
      -- After an object key, a colon must follow.
      if top and top.ch == "{" and top.expectColon then
        if content:sub(i, i) == ":" then
          top.expectColon = false i = i + 1 i = skipWs(i)
        else
          add(line, "missing ':' after object key")
          top.expectColon = false
        end
      end
    elseif c == "{" or c == "[" then
      if top and not top.expectKey then checkNeedComma(top) end
      if top then top.afterComma = false end
      if top and top.ch == "{" and top.expectColon then
        add(line, "missing ':' after object key")
        top.expectColon = false
      end
      stack[#stack + 1] = { ch = c, line = line, keys = {},
        expectKey = (c == "{"), expectColon = false, needComma = false }
      i = i + 1
      i = skipWs(i)
      -- Empty object/array closes immediately; handled by the loop.
    elseif c == "}" or c == "]" then
      local want = (c == "}") and "{" or "["
      local closer = "'" .. c .. "'"
      top = stack[#stack]
      if not top then
        add(line, closer .. " without opening")
        i = i + 1
      else
        if top.ch ~= want then
          add(line, closer .. " does not match " .. ((top.ch == "{") and "'{'" or "'['"))
        end
        -- Trailing comma: the container ended while still expecting a value
        -- right after a comma.
        if top.afterComma then
          add(line, "trailing comma")
        end
        stack[#stack] = nil
        -- A key still waiting for its colon means "{"k"}" style input.
        i = i + 1
        valueDone()
      end
      i = skipWs(i)
    elseif c == ":" then
      if top and top.ch == "{" and not top.expectColon then
        add(line, "unexpected ':'")
      elseif not top or top.ch ~= "{" then
        add(line, "unexpected ':'")
      end
      if top then top.expectColon = false top.afterColon = true end
      i = i + 1
      i = skipWs(i)
    elseif c == "," then
      if not top then
        add(line, "unexpected ','")
      else
        top.needComma = false
        top.afterComma = true
        if top.ch == "{" then top.expectKey = true end
      end
      i = i + 1
      i = skipWs(i)
      -- A closing bracket right after the comma is reported at '}' / ']'.
    elseif c:match("[%d%-]") or content:sub(i, i + 3) == "true"
        or content:sub(i, i + 4) == "false" or content:sub(i, i + 3) == "null" then
      checkNeedComma(top)
      if top and top.ch == "{" and top.expectColon then
        add(line, "missing ':' after object key")
        top.expectColon = false
      end
      if content:sub(i, i + 3) == "true" then i = i + 4
      elseif content:sub(i, i + 4) == "false" then i = i + 5
      elseif content:sub(i, i + 3) == "null" then i = i + 4
      else
        while i <= n and content:sub(i, i):match("[%d%.eE%+%-]") do i = i + 1 end
      end
      if top then top.afterComma = false top.afterColon = false end
      valueDone()
      i = skipWs(i)
    else
      add(line, "unexpected character '" .. c .. "'")
      i = i + 1
    end
  end

  for _, f in ipairs(stack) do
    add(f.line, "'" .. f.ch .. "' never closed")
  end
  return diags
end

-- ---------------------------------------------------------------------------
-- YAML: line model (1-indexed). Blank and comment lines are skipped. A block
-- scalar header (| or >) consumes the following more-indented lines.
-- Detects tab indentation, mixed tabs/spaces, inconsistent nesting steps,
-- mappings without a colon, duplicate keys at the same indent (warning) and
-- unterminated quoted scalars.
-- ---------------------------------------------------------------------------
-- countQuote counts the unescaped occurrences of q in s.
local function countQuote(s, q)
  local count, esc = 0, false
  for k = 1, #s do
    local ch = s:sub(k, k)
    if q == '"' and ch == "\\" and not esc then esc = true
    elseif ch == q and not esc then count = count + 1 esc = false
    else esc = false end
  end
  return count
end

-- joinChunks concatenates a chunk array in bounded batches. table.concat in
-- gopher-lua PUSHES every element onto the VM registry, so stripping a very
-- long line char-by-char overflows it with "registry overflow". Batching
-- keeps each registry use well under the limit regardless of line length.
-- Same helper as python-lint / unused-imports.
local function joinChunks(chunks, sep)
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
      parts[#parts + 1] = table.concat(batch, sep)
      i = j + 1
    end
    cur = parts -- every level joins with sep, including batch boundaries
  end
  return table.concat(cur, sep)
end

-- stripSpans removes q...q spans so quotes nested inside the other quote
-- kind are not mistaken for delimiters.
local function stripSpans(s, q)
  local out, k = {}, 1
  while k <= #s do
    if s:sub(k, k) == q then
      k = k + 1
      while k <= #s do
        local d = s:sub(k, k)
        if q == '"' and d == "\\" then k = k + 2
        elseif d == q then k = k + 1 break
        else k = k + 1 end
      end
    else
      out[#out + 1] = s:sub(k, k) k = k + 1
    end
  end
  return joinChunks(out)
end

local function yamlCheck(content)
  local diags = {}
  local lines = {}
  for l in (content .. "\n"):gmatch("([^\n]*)\n") do
    lines[#lines + 1] = l
  end

  local function add(l, m, sev)
    diags[#diags + 1] = { l = l, m = m, s = sev or "error" }
  end

  local indentStack = { -1 } -- open nesting widths for step validation
  local keysByIndent = {}   -- indentWidth -> {key=true}
  local skipUntil = 0       -- block scalar body: first line NOT consumed
  local skipIndent = 0      -- header indent of the active block scalar

  for idx, raw in ipairs(lines) do
    if idx <= skipUntil then
      -- Inside a block scalar body: only detect the dedent that ends it.
      local pre = raw:match("^(%s*)") or ""
      if raw:match("^%s*$") then
        -- blank lines belong to the scalar
      elseif #pre > skipIndent then
        -- still body
      else
        skipUntil = 0 -- dedented: reprocess this line normally below
      end
    end
    if idx <= skipUntil then
      -- consumed by the block scalar, no checks
    else
      local line = raw
      if line:match("^%s*$") then
        -- blank: no checks
      else
        local prefix = line:match("^(%s*)") or ""
        local trimmed = line:sub(#prefix + 1)
        if trimmed:sub(1, 1) == "#" then
          -- full-line comment: no checks
        else
          local indent = #prefix
          local hasTab = prefix:find("\t", 1, true) ~= nil
          local hasSpace = prefix:find(" ", 1, true) ~= nil
          if hasTab and not hasSpace then
            add(idx, "tabs are not allowed for indentation, use spaces")
          elseif hasTab and hasSpace then
            add(idx, "mixed tabs and spaces in indentation")
          end
          -- Inconsistent step: dedents must land on a known open level.
          local topW = indentStack[#indentStack]
          if indent > topW then
            indentStack[#indentStack + 1] = indent
          else
            local found = false
            for _, w in ipairs(indentStack) do
              if w == indent then found = true break end
            end
            if not found then
              add(idx, "inconsistent indentation")
              indentStack[#indentStack + 1] = indent
            else
              while indentStack[#indentStack] > indent do
                indentStack[#indentStack] = nil
              end
            end
          end
          -- Strip a "- " list marker for the mapping analysis.
          local item = trimmed
          if item:match("^%-%s") or item == "-" then
            item = item:sub(2):gsub("^%s+", "")
            if item == "" then
              -- bare dash: nothing more to check on this line
              item = nil
            end
          end
          if item and item ~= "" then
            -- Unterminated quoted scalar: odd count of unescaped quotes.
            -- Single quotes nested inside a double-quoted span ("it's")
            -- do not count: they are content, not delimiters.
            if countQuote(item, '"') % 2 == 1 then
              add(idx, "unterminated quoted string")
            elseif countQuote(stripSpans(item, '"'), "'") % 2 == 1 then
              add(idx, "unterminated quoted string")
            end
            -- Block scalar header ("key: |", "key: >" with optional chomping
            -- /indent flags) consumes deeper lines.
            local headerKey = item:match("^(.-):%s*[|>]")
            if headerKey then
              skipUntil = idx
              skipIndent = indent
              -- Extend while following lines are blank or deeper-indented.
              for j = idx + 1, #lines do
                local nxt = lines[j]
                if nxt:match("^%s*$") then skipUntil = j
                else
                  local pre = nxt:match("^(%s*)") or ""
                  if #pre > indent then skipUntil = j
                  else break end
                end
              end
            else
              -- Duplicate keys at the same indent level (warning).
              local key = item:match("^([^:#%s][^:]-)%s*:")
                or item:match("^\"(.-)\"%s*:")
                or item:match("^'(.-)'%s*:")
              if key then
                keysByIndent[indent] = keysByIndent[indent] or {}
                if keysByIndent[indent][key] then
                  add(idx, "duplicate key \"" .. key .. "\" at the same level", "warning")
                else
                  keysByIndent[indent][key] = true
                end
              else
                -- Mapping without colon: "key value" on one line.
                if not item:find(":", 1, true) and item:match("^[%w_%.%-/]+%s+%S") then
                  add(idx, "mapping values require ':' between key and value")
                end
              end
            end
          end
        end
      end
    end
  end
  return diags
end

-- ---------------------------------------------------------------------------
-- XML: strict, case-sensitive tag correlator. Self-closing tags end with
-- "/>", processing instructions <?...?>, comments <!--...-->, CDATA
-- <![CDATA[...]]> and <!DOCTYPE...> are skipped (unclosed ones are errors).
-- Detects mismatched closes, closes without opens, unclosed opens at EOF,
-- malformed tags, duplicate attributes, unterminated attribute values, tags
-- never closed and multiple root elements.
-- ---------------------------------------------------------------------------
local function add_xml(diags, l, m)
  diags[#diags + 1] = { l = l, m = m, s = "error" }
end

local function xmlParseAttrs(body, tagLine, diags)
  local seen = {}
  local i, n = 1, #body
  if body:sub(-1) == "/" then body = body:sub(1, -2) n = #body end

  local function skipWs()
    while i <= n and body:sub(i, i):match("%s") do i = i + 1 end
  end

  while true do
    skipWs()
    if i > n then break end
    local s = i
    while i <= n and body:sub(i, i):match("[%w_%-%.:]") do i = i + 1 end
    local name = body:sub(s, i - 1)
    if name == "" then
      add_xml(diags, tagLine, "malformed tag")
      i = i + 1
    else
      if seen[name] then
        add_xml(diags, tagLine, "duplicate attribute '" .. name .. "'")
      end
      seen[name] = true
      skipWs()
      if body:sub(i, i) == "=" then
        i = i + 1
        skipWs()
        local q = body:sub(i, i)
        if q == '"' or q == "'" then
          i = i + 1
          local closed = false
          while i <= n do
            if body:sub(i, i) == q then closed = true i = i + 1 break end
            i = i + 1
          end
          if not closed then
            add_xml(diags, tagLine, "unterminated attribute value for '" .. name .. "'")
          end
        else
          add_xml(diags, tagLine, "attribute '" .. name .. "' must have a quoted value")
          while i <= n and not body:sub(i, i):match("%s") do i = i + 1 end
        end
      else
        add_xml(diags, tagLine, "attribute '" .. name .. "' without value")
      end
    end
  end
end

local function xmlCheck(content)
  local diags = {}
  local stack = {} -- {name, line}
  local line, i, n = 1, 1, #content
  local roots = 0        -- closed top-level elements
  local seenRoot = false -- any element opened at depth 0 yet
  local outsideText = {} -- lines with text outside any element (deferred)

  local function countLines(a, b)
    for _ in content:sub(a, b):gmatch("\n") do line = line + 1 end
  end

  while i <= n do
    local c = content:sub(i, i)
    if c == "\n" then
      line = line + 1 i = i + 1
    elseif c ~= "<" then
      -- Text: only non-whitespace outside any element matters. Judged
      -- once a root is known, so leading text is caught as well.
      if not c:match("%s") then
        if #stack == 0 then
          outsideText[line] = true
        end
      end
      i = i + 1
    elseif content:sub(i, i + 3) == "<!--" then
      local e = content:find("-->", i + 4, true)
      if e then
        countLines(i, e + 2) i = e + 3
      else
        add_xml(diags, line, "comment never closed")
        i = n + 1
      end
    elseif content:sub(i, i + 8) == "<![CDATA[" then
      local e = content:find("]]>", i + 9, true)
      if e then
        countLines(i, e + 2) i = e + 3
      else
        add_xml(diags, line, "CDATA section never closed")
        i = n + 1
      end
    elseif content:sub(i, i + 1) == "<?" then
      local e = content:find("?>", i + 2, true)
      if e then
        countLines(i, e + 1) i = e + 2
      else
        add_xml(diags, line, "processing instruction never closed")
        i = n + 1
      end
    elseif content:sub(i, i + 8):upper() == "<!DOCTYPE" then
      -- DOCTYPE: skip to the closing '>' honouring quotes.
      local j, q = i + 9, nil
      local closed = false
      local curLine = line
      while j <= n do
        local d = content:sub(j, j)
        if q then
          if d == q then q = nil end
        elseif d == '"' or d == "'" then
          q = d
        elseif d == ">" then
          closed = true
          countLines(i, j) i = j + 1
          break
        end
        j = j + 1
      end
      if not closed then
        add_xml(diags, curLine, "<!DOCTYPE> never closed")
        i = n + 1
      end
    elseif content:sub(i, i + 1) == "<!" then
      add_xml(diags, line, "malformed tag")
      local gt = content:find(">", i + 2, true)
      if gt then
        countLines(i, gt) i = gt + 1
      else
        i = n + 1
      end
    elseif content:sub(i + 1, i + 1) == "/" then
      -- Closing tag.
      local tagLine = line
      local j = i + 2
      if content:sub(j, j):match("%s") then
        add_xml(diags, tagLine, "malformed tag: space after '</'")
        while j <= n and content:sub(j, j):match("%s") do
          if content:sub(j, j) == "\n" then line = line + 1 end
          j = j + 1
        end
      end
      local name = ""
      while j <= n and content:sub(j, j):match("[%w_%-%.:]") do
        name = name .. content:sub(j, j) j = j + 1
      end
      if name == "" then
        add_xml(diags, tagLine, "malformed tag")
      else
        local top = stack[#stack]
        if top and top[1] == name then
          stack[#stack] = nil
          if #stack == 0 then roots = roots + 1 end
        elseif top then
          add_xml(diags, tagLine, "'</" .. name .. ">' does not match '<" .. top[1] .. ">'")
          stack[#stack] = nil
          if #stack == 0 then roots = roots + 1 end
        else
          add_xml(diags, tagLine, "'</" .. name .. ">' without opening tag")
        end
      end
      while j <= n and content:sub(j, j):match("%s") do
        if content:sub(j, j) == "\n" then line = line + 1 end
        j = j + 1
      end
      if content:sub(j, j) == ">" then
        i = j + 1
      else
        add_xml(diags, tagLine, "malformed tag")
        local gt = content:find(">", j, true)
        if gt then
          countLines(j, gt) i = gt + 1
        else
          i = n + 1
        end
      end
    else
      -- Opening tag.
      local tagLine = line
      local j = i + 1
      if content:sub(j, j):match("%s") then
        add_xml(diags, tagLine, "malformed tag: space after '<'")
        while j <= n and content:sub(j, j):match("%s") do
          if content:sub(j, j) == "\n" then line = line + 1 end
          j = j + 1
        end
      end
      local name = ""
      while j <= n and content:sub(j, j):match("[%w_%-%.:]") do
        name = name .. content:sub(j, j) j = j + 1
      end
      if name == "" then
        add_xml(diags, tagLine, "malformed tag")
        i = i + 1
      elseif not name:sub(1, 1):match("[%a_]") then
        add_xml(diags, tagLine, "invalid tag name '<" .. name .. ">'")
        i = i + 1
      else
        -- Scan the attribute body up to '>' honouring quotes.
        local bodyStart = j
        local k, q = j, nil
        local closed = false
        while k <= n do
          local d = content:sub(k, k)
          if q then
            if d == q then q = nil end
          elseif d == '"' or d == "'" then
            q = d
          elseif d == ">" then
            closed = true break
          end
          k = k + 1
        end
        if not closed then
          add_xml(diags, tagLine, "tag '<" .. name .. ">' never closed")
          i = n + 1
        else
          local body = content:sub(bodyStart, k - 1)
          xmlParseAttrs(body, tagLine, diags)
          local selfClose = body:match("/%s*$") ~= nil
          if selfClose then
            if #stack == 0 then
              roots = roots + 1
              seenRoot = true
              if roots > 1 then
                add_xml(diags, tagLine, "multiple root elements")
              end
            end
          else
            if #stack == 0 then
              seenRoot = true
              if roots >= 1 then
                add_xml(diags, tagLine, "multiple root elements")
              end
            end
            stack[#stack + 1] = { name, tagLine }
          end
          countLines(i, k) i = k + 1
        end
      end
    end
  end

  for _, e in ipairs(stack) do
    add_xml(diags, e[2], "'<" .. e[1] .. ">' never closed")
  end
  if seenRoot or roots > 0 then
    for l, _ in pairs(outsideText) do
      add_xml(diags, l, "content outside root element")
    end
  end
  return diags
end

-- ---------------------------------------------------------------------------
-- Entry point.
-- ---------------------------------------------------------------------------
function check()
  local path, content = tcode.buffer()
  if not path then
    return
  end
  local lang = detectLang(path)
  if not lang then
    return -- non-target file: never touch diagnostics
  end

  local raw = {}
  if lang == "json" then raw = jsonCheck(content)
  elseif lang == "yaml" then raw = yamlCheck(content)
  elseif lang == "xml" then raw = xmlCheck(content)
  end

  if #raw == 0 then
    tcode.diagnostics.clear()
    return
  end
  local diags = {}
  for _, e in ipairs(raw) do
    diags[#diags + 1] = { line = e.l, message = e.m, severity = e.s }
  end
  sortDiags(diags)
  tcode.diagnostics.set(diags)
end
