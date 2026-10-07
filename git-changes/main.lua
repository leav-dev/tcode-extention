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

  -- Tiny bounded join (at most 3 items): no registry pressure.
  local file_summary = table.concat(parts, ", ")
  local line_summary = "+" .. git.added .. " -" .. git.deleted

  return total_files .. " files (" .. file_summary .. "), " .. line_summary .. " lines"
end

-- status muestra un resumen de cambios de git en la barra de estado, en su
-- propia sección (tcode.statusBar.setSection) para no pisar a las demás
-- extensiones ni a los mensajes del editor.
-- Se ejecuta al guardar el buffer (hook onDidSaveBuffer) o con alt+shift+g.
function status()
  local path = tcode.buffer()
  if not path then
    tcode.statusBar.setSection("tcode.gitchanges", "Git Changes: no active buffer")
    return
  end

  local git = tcode.git.status()
  if not git then
    tcode.statusBar.setSection("tcode.gitchanges", "Git Changes: not a git repository")
    return
  end

  -- Branch + commit encadenados al scope. Informative: faltan en editores
  -- viejos (nil) o cuando no se pudieron determinar (""): cada segmento
  -- ausente se omite sin romper.
  local scope = "Git Changes"
  local where = {}
  if git.branch ~= nil and git.branch ~= "" then
    where[#where + 1] = git.branch
  end
  if git.commit_hash ~= nil and git.commit_hash ~= "" then
    where[#where + 1] = git.commit_hash
  end
  if #where > 0 then
    scope = scope .. " [" .. table.concat(where, " ") .. "]"
  end

  local detail = ""
  if git.commit_subject ~= nil and git.commit_subject ~= "" then
    detail = git.commit_subject
    local by = {}
    if git.commit_author ~= nil and git.commit_author ~= "" then
      by[#by + 1] = git.commit_author
    end
    if git.commit_date ~= nil and git.commit_date ~= "" then
      by[#by + 1] = git.commit_date
    end
    if #by > 0 then
      detail = detail .. " (" .. table.concat(by, ", ") .. ")"
    end
    detail = detail .. " | "
  end

  tcode.statusBar.setSection("tcode.gitchanges", scope .. ": " .. detail .. fileSummary(git))
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
