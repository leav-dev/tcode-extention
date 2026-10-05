-- Git Changes for tcode (id: tcode.gitchanges)
-- Muestra información de cambios de git en la barra de estado y marca
-- las líneas con cambios en el gutter.
--
-- Editor API: tcode.buffer(), tcode.message(), tcode.diagnostics.set/clear,
-- tcode.git.status(), tcode.git.file_diff()
--
-- Convention: every message sent to the user is English.

-- status muestra un resumen de cambios de git en la barra de estado.
-- Se ejecuta al guardar el buffer (hook onDidSaveBuffer) o con alt+shift+g.
function status()
  local path = tcode.buffer()
  if not path then
    tcode.message("Git Changes: no active buffer")
    return
  end

  local git = tcode.git.status()
  if not git then
    tcode.message("Git Changes: not a git repository")
    return
  end

  local staged = #git.staged
  local unstaged = #git.unstaged
  local untracked = #git.untracked
  local total_files = staged + unstaged + untracked

  if total_files == 0 then
    tcode.message("Git Changes: clean working tree")
    return
  end

  local parts = {}
  if staged > 0 then
    table.insert(parts, staged .. " staged")
  end
  if unstaged > 0 then
    table.insert(parts, unstaged .. " unstaged")
  end
  if untracked > 0 then
    table.insert(parts, untracked .. " untracked")
  end

  local file_summary = table.concat(parts, ", ")
  local line_summary = "+" .. git.added .. " -" .. git.deleted

  tcode.message("Git Changes: " .. total_files .. " files (" .. file_summary .. "), " .. line_summary .. " lines")
end

-- mark marca las líneas con cambios en el gutter usando diagnostics.
-- Las líneas agregadas se marcan con severity "info" (i en el gutter).
-- Las líneas borradas se marcan con severity "warning" (? en el gutter).
function mark()
  local path = tcode.buffer()
  if not path then
    tcode.message("Git Changes: no active buffer")
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
    tcode.message("Git Changes: no changes to mark")
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
  tcode.message("Git Changes: marked " .. #diags .. " changed lines")
end

-- all ejecuta status y mark juntos (útil para keybinding único).
function all()
  status()
  mark()
end
