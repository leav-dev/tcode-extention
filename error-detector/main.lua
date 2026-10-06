-- Error Detector for tcode (id: tcode.errordetector)
-- Bracket balance () [] {} with string awareness + HTML tag balance.
-- Severity "error".
--
-- Editor API: tcode.buffer(), tcode.message(), tcode.diagnostics.set/clear
-- (per-provider: replaces only this extension's diagnostics; the editor
-- merges with the other extensions). Pure Lua: the tcode host exposes no
-- io/os, so the analysis is structural over the buffer content.
--
-- check is GLOBAL on purpose: the backend (ext.Call@tcode) resolves the
-- function by name with GetGlobal(fn).
--
-- Convention: every message sent to the user is English.
-- RAM: this script is language-agnostic and intentionally compact — no
-- language tables, just the scanners.

-- balanceCheck correlates () [] {} ignoring string content (" ' ` with
-- backslash escapes). Returns {l=line, m=message}.
local function balanceCheck(content)
  local closing = { ["("] = ")", ["["] = "]", ["{"] = "}" }
  local opening = { [")"] = "(", ["]"] = "[", ["}"] = "{" }
  local stack, errors, delim = {}, {}, nil
  local line, i, n = 1, 1, #content

  while i <= n do
    local c = content:sub(i, i)
    if delim then
      -- Inside a string: the escape skips the next character.
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

  -- Final state: open string and/or unclosed openers.
  if delim then
    errors[#errors + 1] = { l = line, m = "unterminated string (delimiter '" .. delim .. "')" }
  end
  for _, e in ipairs(stack) do
    errors[#errors + 1] = { l = e[2], m = "'" .. e[1] .. "' never closed" }
  end
  return errors
end

-- parseAttrs validates the attribute portion of an opening tag. `body` is
-- the text between the tag name and the closing '>' (it may start with
-- whitespace and end with '/' for self-closing tags); `startLine` is the
-- line where the tag opened. Returns {l=line, m=message}. Detects attributes
-- without a value, unterminated quoted values and duplicate attributes.
local function parseAttrs(body, startLine)
  local errors, seen = {}, {}
  local line, i, n = startLine, 1, #body
  if body:sub(-1) == "/" then body = body:sub(1, -2) end
  n = #body

  local function skipSpace()
    while i <= n do
      local c = body:sub(i, i)
      if c == "\n" then
        line = line + 1
        i = i + 1
      elseif c:match("%s") then
        i = i + 1
      else
        return
      end
    end
  end

  while i <= n do
    skipSpace()
    if i > n then break end
    -- Read the attribute name.
    local s = i
    while i <= n and body:sub(i, i):match("[%w_%-%.:]") do
      i = i + 1
    end
    local name = body:sub(s, i-1)
    if name == "" then
      -- Stray character (e.g. a quote): skip it and keep scanning.
      i = i + 1
    else
      local lname = name:lower()
      if seen[lname] then
        errors[#errors + 1] = { l = line, m = "Duplicate attribute '" .. name .. "'" }
      end
      seen[lname] = true
      skipSpace()
      if i <= n and body:sub(i, i) == "=" then
        i = i + 1
        skipSpace()
        local q = body:sub(i, i)
        if q == '"' or q == "'" then
          i = i + 1
          local closed = false
          while i <= n do
            local c = body:sub(i, i)
            if c == "\n" then
              line = line + 1
              i = i + 1
            elseif c == q then
              closed = true
              i = i + 1
              break
            else
              i = i + 1
            end
          end
          if not closed then
            errors[#errors + 1] = { l = line, m = "Attribute '" .. name .. "' has an unterminated value" }
          end
        elseif q == "" then
          errors[#errors + 1] = { l = line, m = "Attribute '" .. name .. "' without value" }
        else
          -- Unquoted value: read up to the next whitespace.
          while i <= n and not body:sub(i, i):match("%s") do
            i = i + 1
          end
        end
      end
      -- No '=': boolean attribute, valid.
    end
  end
  return errors
end

-- htmlTagCheck correlates HTML tags ignoring string content and comments.
-- Detects: unclosed tags, mismatched tags, malformed tags, malformed attributes,
-- DOCTYPE issues. Returns {l=line, m=message}.
local function htmlTagCheck(content)
  local stack, errors = {}, {}
  local line, i, n = 1, 1, #content
  local selfClosing = {
    area=true, base=true, br=true, col=true, embed=true, hr=true,
    img=true, input=true, link=true, meta=true, param=true,
    source=true, track=true, wbr=true
  }
  local doctypeSeen = false
  local hasContent = false  -- tracks non-whitespace content for DOCTYPE validation

  while i <= n do
    local c = content:sub(i, i)
    if c == "\n" then
      line = line + 1
      i = i + 1
    elseif c == "<" then
      -- Check for comment
      if content:sub(i, i+3) == "<!--" then
        local e = content:find("-->", i+4, true)
        if e then
          for _ in content:sub(i, e+2):gmatch("\n") do line = line + 1 end
          i = e + 3
        else
          errors[#errors + 1] = { l = line, m = "HTML comment never closed" }
          i = n + 1
        end
      -- Check for DOCTYPE
      elseif content:sub(i, i+8):upper() == "<!DOCTYPE" then
        if doctypeSeen then
          errors[#errors + 1] = { l = line, m = "Duplicate <!DOCTYPE> declaration" }
        elseif hasContent then
          errors[#errors + 1] = { l = line, m = "<!DOCTYPE> must be the first element" }
        end
        local gt = content:find(">", i+9, true)
        if not gt then
          errors[#errors + 1] = { l = line, m = "<!DOCTYPE> never closed" }
          i = n + 1
        else
          local doctypeContent = content:sub(i+9, gt-1):lower()
          if not doctypeContent:match("html") then
            errors[#errors + 1] = { l = line, m = "<!DOCTYPE> must contain 'html'" }
          end
          doctypeSeen = true
          for _ in content:sub(i, gt):gmatch("\n") do line = line + 1 end
          i = gt + 1
        end
      -- Check for closing tag
      elseif content:sub(i+1, i+1) == "/" then
        local tagLine = line
        local j = i + 2
        local spaceErr = false
        if content:sub(j, j):match("%s") then
          errors[#errors + 1] = { l = tagLine, m = "Malformed tag: space after '</'" }
          spaceErr = true
          while j <= n and content:sub(j, j):match("%s") do
            if content:sub(j, j) == "\n" then line = line + 1 end
            j = j + 1
          end
        end
        local name = ""
        while j <= n do
          local nc = content:sub(j, j)
          if nc:match("%a") or nc:match("%d") or nc == "-" then
            name = name .. nc
            j = j + 1
          else
            break
          end
        end
        if name == "" then
          if not spaceErr then
            errors[#errors + 1] = { l = tagLine, m = "Empty closing tag '</>'" }
          end
        else
          local top = stack[#stack]
          if top and top[1] == name then
            stack[#stack] = nil
          elseif top then
            errors[#errors + 1] = { l = tagLine, m = "'</" .. name .. ">' closes '<" .. top[1] .. ">'" }
            stack[#stack] = nil
          else
            errors[#errors + 1] = { l = tagLine, m = "'</" .. name .. ">' without opening tag" }
          end
        end
        local gt = content:find(">", j, true)
        if gt then
          for _ in content:sub(i, gt):gmatch("\n") do line = line + 1 end
          i = gt + 1
        else
          i = n + 1
        end
      -- Opening tag
      else
        local tagLine = line
        local j = i + 1
        local spaceErr = false
        if content:sub(j, j):match("%s") then
          errors[#errors + 1] = { l = tagLine, m = "Malformed tag: space after '<'" }
          spaceErr = true
          while j <= n and content:sub(j, j):match("%s") do
            if content:sub(j, j) == "\n" then line = line + 1 end
            j = j + 1
          end
        end
        local name = ""
        while j <= n do
          local nc = content:sub(j, j)
          if nc:match("%a") or nc:match("%d") or nc == "-" then
            name = name .. nc
            j = j + 1
          else
            break
          end
        end
        if name == "" then
          if not spaceErr then
            errors[#errors + 1] = { l = tagLine, m = "Empty tag '<>'" }
          end
          i = i + 1
        else
          -- Validate tag name starts with a letter.
          if not name:sub(1,1):match("%a") then
            errors[#errors + 1] = { l = tagLine, m = "Invalid tag name '<" .. name .. ">'" }
          end
          hasContent = true
          local bodyStart = j
          local inStr, strDelim = false, nil
          while j <= n do
            local nc = content:sub(j, j)
            if inStr then
              if nc == "\\" then
                j = j + 2
              elseif nc == strDelim then
                inStr = false
                j = j + 1
              else
                if nc == "\n" then line = line + 1 end
                j = j + 1
              end
            elseif nc == '"' or nc == "'" then
              inStr = true
              strDelim = nc
              j = j + 1
            elseif nc == ">" then
              break
            else
              if nc == "\n" then line = line + 1 end
              j = j + 1
            end
          end
          if j > n then
            errors[#errors + 1] = { l = tagLine, m = "Tag '<" .. name .. ">' never closed" }
            i = n + 1
          else
            local body = content:sub(bodyStart, j-1)
            local selfClose = body:sub(-1) == "/"
            for _, e in ipairs(parseAttrs(body, tagLine)) do
              errors[#errors + 1] = e
            end
            if not selfClose and not selfClosing[name:lower()] then
              stack[#stack + 1] = { name:lower(), tagLine }
            end
            i = j + 1
          end
        end
      end
    else
      if not c:match("%s") then
        hasContent = true
      end
      i = i + 1
    end
  end

  -- Final state: unclosed tags
  for _, e in ipairs(stack) do
    errors[#errors + 1] = { l = e[2], m = "'<" .. e[1] .. ">' never closed" }
  end
  return errors
end

-- detectLanguage infers the language from the buffer path, consistent with
-- undefined-vars/unused-imports. Returns "html", "go", "ts", "py" or nil
-- (unknown/unsupported extension).
local function detectLanguage(path)
  if not path then return nil end
  local p = string.lower(path)
  if p:match("%.html?$") or p:match("%.xhtml$") or p:match("%.svg$") then return "html" end
  if p:match("%.go$") then return "go" end
  if p:match("%.m?jsx?$") or p:match("%.m?tsx?$") then return "ts" end
  if p:match("%.py$") or p:match("%.pyw$") then return "py" end
  return nil
end

-- checksByLang maps each detected language to the check functions that apply
-- to it. A language listed here with an empty table means "no specific check
-- yet"; unknown languages get no specific check.
local checksByLang = {
  html = { htmlTagCheck },
  go   = {},
  ts   = {},
  py   = {},
}

function check()
  local path, content = tcode.buffer()
  if not path then
    return
  end

  local diags = {}
  local lang = detectLanguage(path)

  -- balanceCheck is language-agnostic: it runs for every buffer.
  for _, e in ipairs(balanceCheck(content)) do
    diags[#diags + 1] = { line = e.l, message = e.m, severity = "error" }
  end

  -- Language-specific checks run only when the language is detected.
  local langChecks = checksByLang[lang]
  if langChecks then
    for _, fn in ipairs(langChecks) do
      for _, e in ipairs(fn(content)) do
        diags[#diags + 1] = { line = e.l, message = e.m, severity = "error" }
      end
    end
  end

  if #diags == 0 then
    tcode.diagnostics.clear()
    return
  end
  tcode.diagnostics.set(diags)
end