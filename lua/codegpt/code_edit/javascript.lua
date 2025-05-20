local util = require "codegpt.code_edit.util"
local javascript = {}

function javascript.find_definition(lines, name, type)
  local pattern
  if type == "function" then
    -- Match `function name(` or `const name = (` or `let name = (`
    pattern = "^%s*function%s+" .. name .. "%s*%(" -- function declaration
      .. "|^%s*(const|let|var)%s+" .. name .. "%s*=%s*%(" -- function expression
  elseif type == "class" then
    pattern = "^%s*class%s+" .. name .. "%s*%{"
  elseif type == "method" then
    -- method: match inside a class or object; simplified: ^\s*name\s*\(
    pattern = "^%s*" .. name .. "%s*%("
  else
    -- variable or top-level assignment
    pattern = "^%s*[%w_$]*%s*" .. name .. "%s*="
  end

  local function match_any(line, pattern)
    -- support multiple alternative patterns separated by |
    for subpat in pattern:gmatch("[^|]+") do
      if line:match(subpat) then return true end
    end
    return false
  end

  local start_idx, end_idx
  for i, line in ipairs(lines) do
    if match_any(line, pattern) then
      start_idx = i
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

return javascript
