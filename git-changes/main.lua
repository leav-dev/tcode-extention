-- Git Changes for tcode (id: tcode.gitchanges)
-- Muestra información de cambios de git en la barra de estado y marca
-- las líneas con cambios en el gutter.
--
-- Editor API: tcode.buffer(), tcode.statusBar.setSection(id, text), tcode.diagnostics.set/clear,
-- tcode.git.status(), tcode.git.file_diff()
--
-- Convention: every message sent to the user is English.

-- fileSummary condenses the working-tree state into one line: either
-- "clean working tree" or "N files (...), +a -b lines". Shared by
-- status() and info() so both always agree.
local function fileSummary(git)
  local staged = #git.staged
  local unstaged = #git.unstaged
  local untracked = #git.untracked
  local total_files = staged + unstaged + untracked

  if total_files == 0 then
    return "clean working tree"
  end

  -- Compact states: first letters only (S/U), with git's ? for untracked.
  local parts = {}
  if staged > 0 then
    table.insert(parts, staged .. " S")
  end
  if unstaged > 0 then
    table.insert(parts, unstaged .. " U")
  end
  if untracked > 0 then
    table.insert(parts, untracked .. " ?")
  end

  -- Tiny bounded join (at most 3 items): no registry pressure.
  local file_summary = table.concat(parts, ", ")
  local line_summary = "+" .. git.added .. " -" .. git.deleted

  return total_files .. " files (" .. file_summary .. "), " .. line_summary .. " lines"
end

-- status shows a git summary in the status bar, in its
-- own section (tcode.statusBar.setSection) without overlapping other
-- extensions or editor messages.
-- Runs on buffer save (hook onDidSaveBuffer) or with alt+shift+g.
-- Format is branch scope plus working-tree state only: no commit
-- subject, author, date or hash. Examples:
-- "[main]: clean working tree"
-- "[feat]: 3 files (1 S, 2 U), +15 -8 lines"
-- "clean working tree" (older editor without branch)
function status()
  local path = tcode.buffer()
  if not path then
    tcode.statusBar.setSection("tcode.gitchanges", "no active buffer")
    return
  end

  local git = tcode.git.status()
  if not git then
    tcode.statusBar.setSection("tcode.gitchanges", "not a git repository")
    return
  end

  -- Branch scope only. Missing in old editors (nil) or when it could
  -- not be determined (""): then no scope prefix is shown.
  local scope = ""
  if git.branch ~= nil and git.branch ~= "" then
    scope = "[" .. git.branch .. "]"
  end

  local summary = fileSummary(git)
  if scope ~= "" then
    summary = scope .. ": " .. summary
  end

  tcode.statusBar.setSection("tcode.gitchanges", summary)
end

-- Toggle state for gutter marks. False = hidden, true = visible.
-- toggle() shows on first call and clears on second.
local visible = false

-- mark shows changed lines in the gutter using diagnostics.
-- Added lines use severity "info" (+ in the gutter).
-- Deleted lines use severity "warning" (- in the gutter).
-- Modified lines use severity "info" (~ in the gutter).
-- Every message includes the 1-indexed line number in English:
-- "+ line 12 added", "~ line 7 modified", "- line 3 deleted".
function mark()
  local path = tcode.buffer()
  if not path then
    return
  end

  -- Unstaged diff
  local unstaged_diff = tcode.git.file_diff(path, false)
  -- Staged diff
  local staged_diff = tcode.git.file_diff(path, true)

  -- Combine diffs
  local all_diffs = {}
  for _, d in ipairs(unstaged_diff or {}) do
    table.insert(all_diffs, d)
  end
  for _, d in ipairs(staged_diff or {}) do
    table.insert(all_diffs, d)
  end

  if #all_diffs == 0 then
    tcode.diagnostics.clear()
    visible = false
    return
  end

  -- Coalesce deleted+added pairs on the same line into a single
  -- modified entry: the editor diff emits only added/deleted, so an
  -- edited line arrives as {line N, deleted} plus {line N, added}.
  -- Lines with only one kind keep every entry unchanged.
  local order = {}
  local byLine = {}
  for _, d in ipairs(all_diffs) do
    local bucket = byLine[d.line]
    if not bucket then
      bucket = {}
      byLine[d.line] = bucket
      table.insert(order, d.line)
    end
    table.insert(bucket, d)
  end

  local coalesced = {}
  for _, line in ipairs(order) do
    local bucket = byLine[line]
    local hasAdded = false
    local hasDeleted = false
    for _, d in ipairs(bucket) do
      if d.type == "deleted" then
        hasDeleted = true
      elseif d.type == "added" then
        hasAdded = true
      end
    end
    if hasAdded and hasDeleted then
      table.insert(coalesced, { line = line, type = "modified" })
    else
      for _, d in ipairs(bucket) do
        table.insert(coalesced, d)
      end
    end
  end

  -- Convert to diagnostics
  local diags = {}
  for _, d in ipairs(coalesced) do
    local severity = "info"
    local marker = "+"
    local kind = d.type
    if d.type == "deleted" then
      severity = "warning"
      marker = "-"
    elseif d.type == "modified" then
      severity = "info"
      marker = "~"
    else
      severity = "info"
      marker = "+"
      kind = "added"
    end

    table.insert(diags, {
      line = d.line,
      message = marker .. " line " .. d.line .. " " .. kind,
      severity = severity
    })
  end

  tcode.diagnostics.set(diags)
  visible = true
end

-- toggle shows gutter marks on first call and clears them on second.
-- Safe with no active buffer or empty diff: never raises.
function toggle()
  if visible then
    tcode.diagnostics.clear()
    visible = false
  else
    mark()
  end
end

-- all runs status and mark together (useful for a single keybinding).
function all()
  status()
  mark()
end
