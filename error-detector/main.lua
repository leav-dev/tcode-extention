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
-- Returns {l=line, m=message}.
local function htmlTagCheck(content)
  local stack, errors = {}, {}
  local line, i, n = 1, 1, #content
  local selfClosing = {
    area=true, base=true, br=true, col=true, embed=true, hr=true,
    img=true, input=true, link=true, meta=true, param=true,
    source=true, track=true, wbr=true
  }

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
          -- Unterminated comment
          errors[#errors + 1] = { l = line, m = "HTML comment never closed" }
          i = n + 1
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
        if name ~= "" then
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
        -- Skip to end of tag
        local gt = content:find(">", j, true)
        if gt then
          for _ in content:sub(i, gt):gmatch("\n") do line = line + 1 end
          i = gt + 1
        else
          i = n + 1
        end
      -- Opening tag
      else
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
        if name ~= "" then
          -- Find end of tag, skip strings in attributes
          local inStr = false
          local strDelim = nil
          local selfClose = false
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
              -- Check if self-closing (ends with />)
              local prev = content:sub(j-1, j-1)
              if prev == "/" then
                selfClose = true
              end
              j = j + 1
              break
            else
              if nc == "\n" then line = line + 1 end
              j = j + 1
            end
          end
          if not selfClose and not selfClosing[name:lower()] then
            stack[#stack + 1] = { name:lower(), line }
          end
          i = j
        else
          i = i + 1
        end
      end
    else
      i = i + 1
    end
  end

  -- Final state: unclosed tags
  for _, e in ipairs(stack) do
    errors[#errors + 1] = { l = e[2], m = "'<" .. e[1] .. ">' never closed" }
  end
  return errors
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
  local htmlErrors = htmlTagCheck(content)
  for _, e in ipairs(htmlErrors) do
    diags[#diags + 1] = { line = e.l, message = e.m, severity = "error" }
  end

  local nerr = #diags
  if nerr == 0 then
    tcode.diagnostics.clear()
    return
  end
  tcode.diagnostics.set(diags)
end