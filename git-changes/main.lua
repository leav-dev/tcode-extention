-- Git Changes for tcode (id: tcode.gitchanges)
-- Marca las líneas con cambios en el gutter. No escribe en la barra de
-- estado: el resumen de git se ve con el comando explícito o en el gutter.
--
-- Editor API: tcode.buffer(), tcode.diagnostics.set/clear,
-- tcode.git.status(), tcode.git.file_diff()
--
-- Convention: every message sent to the user is English.

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
