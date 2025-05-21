local util = require "codegpt.code_edit.util"
local tsx = {}

function tsx.find_definition(lines, name, type)
  local pattern
  if type == "function" then
    pattern =
      "^%s*function%s+" .. name .. "%s*%("                     -- function foo(
      .. "|^%s*const%s+" .. name .. "%s*:?[%w%s%.<>,]+=%s*%("   -- const foo: ... = (
      .. "|^%s*const%s+" .. name .. "%s*:?[%w%s%.<>,]+=%s*%(%s*%)%s*=>%s*%{" -- const foo: ... = () => {
      .. "|^%s*const%s+" .. name .. "%s*:?[%w%s%.<>,]+=%s*%(.+%)%s*=>%s*%{"   -- const foo: ... = (arg) => {
      .. "|^%s*const%s+" .. name .. "%s*=%s*%(%s*%)%s*=>%s*%{"                -- const foo = () => {
      .. "|^%s*const%s+" .. name .. "%s*=%s*%(.+%)%s*=>%s*%{"                 -- const foo = (arg) => {
      .. "|^%s*export%s+function%s+" .. name .. "%s*%("          -- export function foo(
  elseif type == "class" then
    -- class <name> { or export class <name> {
    pattern = "^%s*class%s+" .. name .. "%s*%{"
      .. "|^%s*export%s+class%s+" .. name .. "%s*%{"
  elseif type == "method" then
    -- Inside class: <name>(...
    pattern = "^%s*" .. name .. "%s*%("
  else
    -- variable or top-level assignment (let/const/var or type/interface)
    pattern = "^%s*[localconstvar%s]*" .. name .. "%s*="
      .. "|^%s*type%s+" .. name .. "%s*="
      .. "|^%s*interface%s+" .. name .. "%s*%{"
  end

  local function match_any(line, pattern)
    for pat in pattern:gmatch("[^|]+") do
      if line:match(pat) then return true end
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

return tsx
