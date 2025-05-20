local util = require "codegpt.code_edit.util"
local typescript = {}

function typescript.find_definition(lines, name, type)
  local pattern
  if type == "function" then
    -- Match `function name(` or `name = (`
    pattern = "^%s*function%s+" .. name .. "%s*%(" -- function declaration
  elseif type == "class" then
    pattern = "^%s*class%s+" .. name .. "%s*%{"
  elseif type == "method" then
    -- method: match inside a class; simplified: ^\s*name\s*\(
    pattern = "^%s*" .. name .. "%s*%("
  else
    -- variable or top-level assignment
    pattern = "^%s*[%w_:]*%s*" .. name .. "%s*="
  end

  local start_idx, end_idx
  for i, line in ipairs(lines) do
    if line:match(pattern) then
      start_idx = i
      -- For class/function/method: find matching curly braces
      local brace_count = 0
      local found_body = false
      for j = i, #lines do
        local open, close = select(2, lines[j]:gsub("{", "")), select(2, lines[j]:gsub("}", ""))
        brace_count = brace_count + open - close
        if open > 0 then found_body = true end
        if found_body and brace_count == 0 then
          end_idx = j
          break
        end
      end
      if end_idx then break end
    end
  end
  if start_idx and end_idx then
    return start_idx, end_idx
  end
  return nil, nil
end

return typescript
