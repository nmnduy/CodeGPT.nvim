local util = require "codegpt.code_edit.util"
local python = {}

-- Find (start, end) of function/class/object
function python.find_definition(lines, name, type)
  local pattern
  if type == "function" then
    pattern = "^def%s+" .. name .. "%s*%("
  elseif type == "class" then
    pattern = "^class%s+" .. name .. "%s*%("
  else
    -- object variable (top level assignment)
    pattern = "^" .. name .. "%s*="
  end

  local start_idx, end_idx
  for i, line in ipairs(lines) do
    if line:match(pattern) then
      start_idx = i
      -- naive: function/class ends at next non-indented line or EOF
      local indent = line:match("^(%s*)")
      end_idx = i
      for j = i + 1, #lines do
        local l = lines[j]
        if l:match("^%S") and #l:match("^(%s*)") <= #indent then
          end_idx = j - 1
          break
        end
        end_idx = j
      end
      break
    end
  end
  if start_idx and end_idx then
    return start_idx, end_idx
  end
  return nil, nil
end

return python
