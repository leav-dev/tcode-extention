-- Error Detector for tcode (id: tcode.errordetector)
-- Bracket balance () [] {} with string awareness. Severity "error".
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
-- RAM: this script is language-agnostic and intentionally ~90 lines — no
-- language tables, just the scanner.

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

function check()
  local path, content = tcode.buffer()
  if not path then
    tcode.message("Error Detector: no active buffer")
    return
  end

  local diags = {}
  local errors = balanceCheck(content)
  for _, e in ipairs(errors) do
    diags[#diags + 1] = { line = e.l, message = e.m, severity = "error" }
  end

  local nerr = #diags
  if nerr == 0 then
    tcode.diagnostics.clear()
    tcode.message("Error Detector: no balance errors")
    return
  end
  tcode.diagnostics.set(diags)
  local noun = "error"
  if nerr > 1 then noun = "errors" end
  tcode.message("Error Detector: " .. nerr .. " " .. noun .. " marked in the gutter")
end