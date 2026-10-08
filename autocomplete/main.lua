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

function complete()
  local path, content = tcode.buffer()
  if not path then
    return
  end

  if type(tcode.cursor) ~= "function" then
    tcode.message("Autocomplete: editor cursor API (tcode.cursor) is not available")
    return
  end
  local okCur, curLine, curCol = pcall(tcode.cursor)
  if not okCur or curLine == nil or curCol == nil then
    tcode.message("Autocomplete: editor cursor API (tcode.cursor) is not available")
    return
  end
  curLine = tonumber(curLine)
  curCol = tonumber(curCol)
  if not curLine or not curCol then
    tcode.message("Autocomplete: editor cursor API (tcode.cursor) is not available")
    return
  end

  if curLine ~= math.floor(curLine) or curCol ~= math.floor(curCol) then
    tcode.message("Autocomplete: invalid cursor position")
    return
  end

  local okLine, curText = pcall(tcode.line, curLine)
  if not okLine or type(curText) ~= "string" then
    tcode.message("Autocomplete: cannot read current line")
    return
  end

  if curCol < 1 then
    curCol = 1
  end
  local before = curText:sub(1, curCol - 1)
  local prefix = before:match("[A-Za-z0-9_]+$") or ""
  if prefix == "" then
    tcode.message("Autocomplete: no word prefix under cursor")
    return
  end

  local freq = {}
  for w in content:gmatch("[A-Za-z0-9_]+") do
    if w ~= prefix and #w > #prefix and w:sub(1, #prefix) == prefix then
      freq[w] = (freq[w] or 0) + 1
    end
  end

  local candidates = {}
  for w in pairs(freq) do
    candidates[#candidates + 1] = w
  end
  if #candidates == 0 then
    tcode.message("Autocomplete: no candidates for '" .. prefix .. "'")
    return
  end
  table.sort(candidates, function(a, b)
    if freq[a] ~= freq[b] then
      return freq[a] > freq[b]
    end
    return a < b
  end)

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
