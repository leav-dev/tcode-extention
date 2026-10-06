-- Angular 21 Lint for tcode (id: tcode.angular21lint)
-- Detects legacy Angular patterns deprecated or removed in Angular 21:
-- NgModule-based structure, @Input/@Output decorators, legacy structural
-- directives. Severity "warning" (deprecated but still working) except for
-- View Engine traces, which are "error" (unsupported).
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

-- maskLine replaces string literals with spaces so the pattern checks
-- below never fire inside them. Line comments end the scan; block
-- comments are handled by the caller via inBlock state.
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
      break
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out)
end

-- legacyCheck detects pre-standalone/deprecated Angular patterns.
-- Returns {l=line, m=message, s=severity}.
local function legacyCheck(content)
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
      local pm = " " .. maskLine(line) .. " "
      if pm:find("@NgModule[^%w_]") then
        errors[#errors + 1] = { l = lineNo, m = "NgModule is deprecated in Angular 21, prefer standalone components", s = "warning" }
      end
      if pm:find("@Input%s*%(") or pm:find("@Output%s*%(") then
        errors[#errors + 1] = { l = lineNo, m = "@Input/@Output are deprecated in Angular 21, use input()/output()", s = "warning" }
      end
      if pm:find("[^%w_]TestBed%.configureTestingModule") then
        errors[#errors + 1] = { l = lineNo, m = "TestBed.configureTestingModule with NgModules is legacy in Angular 21, prefer standalone test setup", s = "warning" }
      end
      if pm:find("enableIvy%s*:%s*false") or pm:find("[^%w_]ViewEngine[^%w_]") then
        errors[#errors + 1] = { l = lineNo, m = "View Engine is not supported in Angular 21 (Ivy only)", s = "error" }
      end
      if pm:find("%*ngIf") or pm:find("%*ngFor") or pm:find("%*ngSwitch") then
        errors[#errors + 1] = { l = lineNo, m = "legacy structural directives are deprecated in Angular 21, prefer @if/@for/@switch control flow", s = "warning" }
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
  for _, e in ipairs(legacyCheck(content)) do
    diags[#diags + 1] = { line = e.l, message = e.m, severity = e.s }
  end

  if #diags == 0 then
    tcode.diagnostics.clear()
    return
  end
  tcode.diagnostics.set(diags)
end
