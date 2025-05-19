local util = require "codegpt.code_edit.util"
local go = {}

function go.find_definition(lines, name, type)
  local pattern
  if type == "function" then
    pattern = "^func%s+[%w%*%(%)%s]*" .. name .. "%s*%("
  elseif type == "struct" or type == "class" then
    pattern = "^type%s+" .. name .. "%s+struct%s*{"
  else
    -- variable/object
    pattern = "var%s+" .. name .. "%s"
  end

  local start_idx, end_idx
  for i, line in ipairs(lines) do
    if line:match(pattern) then
      start_idx = i
      -- Find matching braces
      local brace_count = 0
      for j = i, #lines do
        brace_count = brace_count + select(2, lines[j]:gsub("{", "")) - select(2, lines[j]:gsub("}", ""))
        if brace_count > 0 and lines[j]:find("{") then
          -- enter body
        end
        if brace_count == 0 and j ~= i then
          end_idx = j
          break
        end
      end
      break
    end
  end
  if start_idx and end_idx then
    return start_idx, end_idx
  end
  return nil, nil
end

return go
