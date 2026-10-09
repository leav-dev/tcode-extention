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

local function candidatesFor(prefix, content)
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
  table.sort(candidates, function(a, b)
    if freq[a] ~= freq[b] then
      return freq[a] > freq[b]
    end
    return a < b
  end)
  return candidates
end

-- prefixAtCursor returns the word prefix under the cursor, or nil plus a
-- kind for messages: "cursor" (API missing/unusable), "position"
-- (fractional), "line" (unreadable) or "prefix" (empty). Shared by
-- complete() (kind -> message) and suggest() (kind ignored, empty table).
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
  return prefix, nil
end

-- suggestCap mirrors the provider contract max (editor CallStrings caps
-- too): the source bounds its own table instead of dumping the buffer's
-- whole vocabulary per keystroke pause.
local suggestCap = 32

function suggest()
  local path, content = tcode.buffer()
  if not path then
    return {}
  end
  local prefix = prefixAtCursor()
  if not prefix then
    return {}
  end
  local candidates = candidatesFor(prefix, content)
  while #candidates > suggestCap do
    candidates[#candidates] = nil
  end
  return candidates
end

function complete()
  local path, content = tcode.buffer()
  if not path then
    return
  end

  local prefix, kind = prefixAtCursor()
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

  local candidates = candidatesFor(prefix, content)
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
