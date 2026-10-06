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
        local j = i + 2
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
          errors[#errors + 1] = { l = line, m = "Empty closing tag '</>'" }
        else
          local top = stack[#stack]
          if top and top[1] == name then
            stack[#stack] = nil
          elseif top then
            errors[#errors + 1] = { l = line, m = "'</" .. name .. ">' closes '<" .. top[1] .. ">'" }
            stack[#stack] = nil
          else
            errors[#errors + 1] = { l = line, m = "'</" .. name .. ">' without opening tag" }
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
        -- Check for malformed tag: space after '<'
        if content:sub(i+1, i+1):match("%s") then
          errors[#errors + 1] = { l = line, m = "Malformed tag: space after '<'" }
        end
        local j = i + 1
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
          errors[#errors + 1] = { l = line, m = "Empty tag '<>'" }
          i = i + 1
        else
          -- Validate tag name starts with letter
          if not name:sub(1,1):match("%a") then
            errors[#errors + 1] = { l = line, m = "Invalid tag name '<" .. name .. ">'" }
          end
          hasContent = true
          -- Find end of tag, skip strings in attributes, validate attributes
          local inStr = false
          local strDelim = nil
          local selfClose = false
          local attrs = {}
          local attrName = nil
          local attrHasValue = false
          local lastNonSpace = j
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
              attrHasValue = true
              j = j + 1
            elseif nc == ">" then
              local prev = content:sub(j-1, j-1)
              if prev == "/" then
                selfClose = true
              end
              -- Check for attribute without value before '>'
              if attrName and not attrHasValue then
                errors[#errors + 1] = { l = line, m = "Attribute '" .. attrName .. "' without value" }
              end
              j = j + 1
              break
            elseif nc == "=" then
              -- Check for malformed attribute: 'class=>'
              local nextChar = content:sub(j+1, j+1)
              if nextChar == ">" then
                errors[#errors + 1] = { l = line, m = "Attribute '" .. attrName .. "' without value" }
              end
              j = j + 1
            elseif nc:match("%s") then
              -- Whitespace: if we had an attribute name, it has no value
              if attrName and not attrHasValue then
                -- This is OK, attribute without value (boolean attribute)
                attrName = nil
              end
              if nc == "\n" then line = line + 1 end
              j = j + 1
            else
              -- Attribute name character
              if not attrName then
                attrName = nc
                attrHasValue = false
                if attrs[nc:lower()] then
                  errors[#errors + 1] = { l = line, m = "Duplicate attribute '" .. nc .. "'" }
                end
                attrs[nc:lower()] = true
              else
                attrName = attrName .. nc
              end
              lastNonSpace = j
              j = j + 1
            end
          end
          if not selfClose and not selfClosing[name:lower()] then
            stack[#stack + 1] = { name:lower(), line }
          end
          i = j
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

-- isHTMLFile checks if the buffer path has an HTML-related extension.
local function isHTMLFile(path)
  local ext = path:match("%.(%w+)$")
  if not ext then
    return false
  end
  ext = ext:lower()
  return ext == "html" or ext == "htm" or ext == "xhtml" or ext == "svg"
end

function check()
  local path, content = tcode.buffer()
  if not path then
    return
  end

  local diags = {}
  local balanceErrors = balanceCheck(content)
  for _, e in ipairs(balanceErrors) do
    diags[#diags + 1] = { line = e.l, message = e.m, severity = "error" }
  end
  -- Only run HTML tag check on HTML files
  if isHTMLFile(path) then
    local htmlErrors = htmlTagCheck(content)
    for _, e in ipairs(htmlErrors) do
      diags[#diags + 1] = { line = e.l, message = e.m, severity = "error" }
    end
  end

  local nerr = #diags
  if nerr == 0 then
    tcode.diagnostics.clear()
    return
  end
  tcode.diagnostics.set(diags)
end