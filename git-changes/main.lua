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

-- mark marca las líneas con cambios en el gutter usando diagnostics.
-- Las líneas agregadas se marcan con severity "info" (i en el gutter).
-- Las líneas borradas se marcan con severity "warning" (? en el gutter).
function mark()
  local path = tcode.buffer()
  if not path then
    return
  end

  -- Obtener diff unstaged
  local unstaged_diff = tcode.git.file_diff(path, false)
  -- Obtener diff staged
  local staged_diff = tcode.git.file_diff(path, true)

  -- Combinar diffs
  local all_diffs = {}
  for _, d in ipairs(unstaged_diff or {}) do
    table.insert(all_diffs, d)
  end
  for _, d in ipairs(staged_diff or {}) do
    table.insert(all_diffs, d)
  end

  if #all_diffs == 0 then
    tcode.diagnostics.clear()
    return
  end

  -- Convertir a diagnostics
  local diags = {}
  for _, d in ipairs(all_diffs) do
    local severity = "info"
    local marker = "+"
    if d.type == "deleted" then
      severity = "warning"
      marker = "-"
    elseif d.type == "modified" then
      severity = "info"
      marker = "~"
    end

    table.insert(diags, {
      line = d.line,
      message = marker .. " line " .. d.type,
      severity = severity
    })
  end

  tcode.diagnostics.set(diags)
end

-- all ejecuta status y mark juntos (útil para keybinding único).
function all()
  status()
  mark()
end
