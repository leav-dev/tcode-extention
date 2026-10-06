-- Angular 8 Lint for tcode (id: tcode.angular8lint)
-- Detects modern Angular syntax not compatible with Angular 8:
-- standalone components, signals, native control flow, input()/output(),
-- deferrable views. Severity "error".
--
-- Editor API: tcode.buffer(), tcode.diagnostics.set/clear (per-provider:
-- replaces only this extension's diagnostics; the editor merges with the
-- other extensions). Pure Lua: the tcode host exposes no io/os, so the
-- analysis is structural over the buffer content.
--
-- check is GLOBAL on purpose: the backend (ext.Call@tcode) resolves the
-- function by name with GetGlobal(fn).
--
-- Convention: every message sent to the user is English.
-- RAM: this script is intentionally compact — no language tables, just
-- the scanners.
--
-- No overlap with error-detector: this extension never checks bracket
-- balance or HTML tag balance. Those stay in tcode.errordetector.

-- isAngularFile checks if the buffer content looks like an Angular file
-- (component, module, service, directive, pipe) or an Angular template.
local function isAngularFile(content)
  if content:match("@Component") or content:match("@NgModule")
    or content:match("@Injectable") or content:match("@Directive")
    or content:match("@Pipe") then
    return true
  end
  if content:match("%*ngIf") or content:match("%*ngFor")
    or content:match("%*ngSwitch") or content:match("%[ngClass%]")
    or content:match("%(click%)") or content:match("ngModel") then
    return true
  end
  return false
end

-- maskLine replaces string literals and line comments with spaces so the
-- pattern checks below never fire inside them. Block comments are handled
-- by the caller via inBlock state. Returns the masked line.
local function maskLine(line)
  local out = {}
  local i, n = 1, #line
  local delim = nil
  while i <= n do
    local c = line:sub(i, i)
    if delim then
      if c == "\\" then
        out[#out + 1] = "  "
        i = i + 2
      elseif c == delim then
        out[#out + 1] = " "
        delim = nil
        i = i + 1
      else
        out[#out + 1] = " "
        i = i + 1
      end
    elseif c == '"' or c == "'" or c == "`" then
      delim = c
      out[#out + 1] = " "
      i = i + 1
    elseif c == "/" and line:sub(i + 1, i + 1) == "/" then
      break -- rest of the line is a comment
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out)
end

-- modernSyntaxCheck detects Angular syntax introduced after v8.
-- Returns {l=line, m=message}.
local function modernSyntaxCheck(content)
  local errors = {}
  local lineNo = 0
  local inBlock = false
  local start = 1
  while true do
    local nl = content:find("\n", start, true)
    local raw
    if nl then
      raw = content:sub(start, nl - 1)
    else
      raw = content:sub(start)
    end
    lineNo = lineNo + 1

    local line = raw
    if inBlock then
      local close = line:find("*/", 1, true)
      if close then
        line = string.rep(" ", close + 1) .. line:sub(close + 2)
        inBlock = false
      else
        line = ""
      end
    end
    if not inBlock then
      local open = line:find("/*", 1, true)
      if open then
        local close = line:find("*/", open + 2, true)
        if close then
          line = line:sub(1, open - 1) .. string.rep(" ", close + 2 - open) .. line:sub(close + 2)
        else
          line = line:sub(1, open - 1)
          inBlock = true
        end
      end
    end

    if line ~= "" then
      -- Pad with spaces so [^%w_] boundaries work at line edges.
      -- (Frontier patterns %f[] are unreliable under gopher-lua.)
      local pm = " " .. maskLine(line) .. " "
      if pm:find("[^%w_]standalone%s*:%s*true[^%w_]") then
        errors[#errors + 1] = { l = lineNo, m = "standalone components are not compatible with Angular 8 (introduced in v14)" }
      end
      if pm:find("[^%w_]signal%s*%(") or pm:find("[^%w_]computed%s*%(")
        or pm:find("[^%w_]effect%s*%(") then
        errors[#errors + 1] = { l = lineNo, m = "signals are not compatible with Angular 8 (introduced in v16)" }
      end
      if pm:find("[^%w_]input%s*%(") or pm:find("[^%w_]output%s*%(") then
        errors[#errors + 1] = { l = lineNo, m = "input()/output() are not compatible with Angular 8, use @Input()/@Output()" }
      end
      if pm:find("@if%s*%(") or pm:find("@for%s*%(")
        or pm:find("@switch%s*%(") or pm:find("@empty[^%w_]") then
        errors[#errors + 1] = { l = lineNo, m = "native control flow is not compatible with Angular 8, use *ngIf/*ngFor/*ngSwitch" }
      end
      if pm:find("@defer[^%w_]") then
        errors[#errors + 1] = { l = lineNo, m = "deferrable views are not compatible with Angular 8 (introduced in v17)" }
      end
    end

    if not nl then break end
    start = nl + 1
  end
  return errors
end

function check()
  local path, content = tcode.buffer()
  if not path then
    return
  end

  -- Only run on Angular files; otherwise leave other providers alone.
  if not isAngularFile(content) then
    return
  end

  local diags = {}
  for _, e in ipairs(modernSyntaxCheck(content)) do
    diags[#diags + 1] = { line = e.l, message = e.m, severity = "error" }
  end

  if #diags == 0 then
    tcode.diagnostics.clear()
    return
  end
  tcode.diagnostics.set(diags)
end
