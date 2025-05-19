local util = require "codegpt.code_edit.util"
local python = require "codegpt.code_edit.python"
local java = require "codegpt.code_edit.java"
local go = require "codegpt.code_edit.go"

prompt = [[
**Instructions:**

You are a code refactoring assistant. You have access to tools for editing code files programmatically. You can:

- Replace a function, class, or method definition in a file with new content.
- Remove a specific function, class, or method definition from a file.
- Add content at the end of a file.
- Remove an entire file.
- Replace a specific snippet of code with a new snippet.

You MUST specify the file path, code element name, type (e.g., "function", "class", "method"), and the programming language (python, java, or go) where required.

**Examples of valid outputs:**

```xml
<action type="replace_definition">
  <file>path/to/file.py</file>
  <name>function_or_class_name</name>
  <def_type>function|class|method</def_type>
  <lang>python|java|go</lang>
  <code>
def func():
    # new content here
  </code>
</action>
<action type="remove_definition">
  <file>path/to/file.go</file>
  <name>function_or_class_name</name>
  <def_type>function|class|method</def_type>
  <lang>go|java|python</lang>
</action>
<action type="add_content">
  <file>path/to/file.java</file>
  <code>
    // code to add at the end of the file
  </code>
</action>
<action type="remove_file">
  <file>path/to/file.py</file>
</action>
<action type="replace_snippet">
  <file>path/to/file.java</file>
  <old_snippet>
    // code to be replaced
  </old_snippet>
  <new_snippet>
    // code to replace with
  </new_snippet>
</action>
```
]]

local M = {}

local handlers = {
  python = python,
  java = java,
  go = go,
}

-- Find and Replace
function M.replace_definition(file_path, name, type, new_content, lang)
  local lines = util.read_lines(file_path)
  local handler = handlers[lang]
  assert(handler, "No handler for lang " .. lang)
  local start_idx, end_idx = handler.find_definition(lines, name, type)
  if not start_idx then
    error("Definition not found")
  end
  -- Replace lines
  local new_lines = {}
  for i = 1, start_idx-1 do table.insert(new_lines, lines[i]) end
  for s in new_content:gmatch("[^\r\n]+") do table.insert(new_lines, s) end
  for i = end_idx+1, #lines do table.insert(new_lines, lines[i]) end
  util.write_lines(file_path, new_lines)
end

function M.remove_definition(file_path, name, type, lang)
  local lines = util.read_lines(file_path)
  local handler = handlers[lang]
  assert(handler, "No handler for lang " .. lang)
  local start_idx, end_idx = handler.find_definition(lines, name, type)
  if not start_idx then
    error("Definition not found")
  end
  local new_lines = {}
  for i = 1, start_idx-1 do table.insert(new_lines, lines[i]) end
  for i = end_idx+1, #lines do table.insert(new_lines, lines[i]) end
  util.write_lines(file_path, new_lines)
end

function M.add_content(file_path, content)
  local f = io.open(file_path, "a")
  f:write(content .. "\n")
  f:close()
end

function M.remove_file(file_path)
  util.remove_file(file_path)
end

function M.replace_snippet(file_path, old_snippet, new_snippet)
  local lines = util.read_lines(file_path)
  local content = table.concat(lines, "\n")
  local pattern = util.escape_pattern(old_snippet)
  local replaced, count = content:gsub(pattern, new_snippet)
  if count == 0 then
    error("Snippet not found")
  end
  util.write_lines(file_path, vim.split(replaced, "\n"))
end

return M
