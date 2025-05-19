local util = require "codegpt.code_edit.util"
local java = {}

function java.find_definition(lines, name, type)
  local pattern
  if type == "function" then
    -- function: match return type + name + '('
    pattern = "%f[%w_]([%w_]+)%s+" .. name .. "%s*%("
  elseif type == "class" or type == "struct" then
    pattern = "^%s*class%s+" .. name .. "%s*[{:]"
  else
    -- variable/object: look for type name = or just name =
    pattern = "%s" .. name .. "%s*="
  end

  local start_idx, end_idx
  for i, line in ipairs(lines) do
    if line:match(pattern) then
      start_idx = i
      -- Find matching braces/block (for class/function)
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

return java
