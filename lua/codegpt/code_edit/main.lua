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

**An example of a valid response:**

```xml
<code-edit>
    <action>replace_definition</action>
    <file>utils/helpers.py</file>
    <name>calculate_sum</name>
    <def_type>function</def_type>
    <lang>python</lang>
    <code>
    def calculate_sum(a, b):
        return a + b
    </code>
</code-edit>

<code-edit>
    <action>remove_definition</action>
    <file>services/old_service.py</file>
    <name>OldService</name>
    <def_type>class</def_type>
    <lang>python</lang>
</code-edit>

<code-edit>
    <action>add_at_end</action>
    <file>models/user.py</file>
    <lang>python</lang>
    <code>
    class UserProfile:
        def __init__(self, user_id):
            self.user_id = user_id
    </code>
</code-edit>

<code-edit>
    <action>remove_file</action>
    <file>deprecated/unused_utils.py</file>
</code-edit>

<code-edit>
    <action>replace_snippet</action>
    <file>main.py</file>
    <lang>python</lang>
    <old>
    result = calculate_sum(3, 5)
    print(result)
    </old>
    <new>
    result = calculate_sum(10, 20)
    print("Sum is:", result)
    </new>
</code-edit>
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

local function get_files()
  local rg_check = os.execute("command -v rg > /dev/null 2>&1")
  if not rg_check or rg_check ~= 0 then
    print("Warning: 'rg' is not installed or not in PATH.")
    return ""
  end
  local handle = io.popen("rg --files")
  local file_list = handle:read("*a")
  handle:close()
  return file_list:gsub("%s+$", "")
end

function M.get_prompt()
  local file_list = get_files()
  local file_block = "Files:\n```\n" .. file_list .. "\n```"
  return file_block .. "\n" .. prompt
end

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function write_tempfile(contents)
  local tmpname = os.tmpname()
  if not tmpname:match("%.xml$") then
    tmpname = tmpname .. ".xml"
  end
  local f = assert(io.open(tmpname, "w"))
  for _, line in ipairs(contents) do
    f:write(line, "\n")
  end
  f:close()
  print("Edit instructions saved to: " .. tmpname)
end

function M.parse_and_apply_actions(xml_str)
  local actions = {}

  local ok, err = pcall(function()
    for code_edit_block in xml_str:gmatch("<code%-edit>(.-)</code%-edit>") do
      local t = {}
      for tag in pairs {action=1, file=1, name=1, def_type=1, lang=1, old=1, new=1} do
        local pat = string.format("<%s>(.-)</%s>", tag, tag)
        local val = code_edit_block:match(pat)
        if val then t[tag] = trim(val) end
      end

      local code_start = code_edit_block:find("<code>")
      local code_end = code_edit_block:find("</code>")
      if code_start and code_end and code_end > code_start+5 then
        t.code = code_edit_block:sub(code_start+6, code_end-1)
        t.code = trim(t.code)
      end

      table.insert(actions, t)
    end

    for _, t in ipairs(actions) do
      local act = t.action
      if act == "replace_definition" then
        print(string.format("[replace_definition] file: %s, def_type: %s", tostring(t.file), tostring(t.def_type)))
        M.replace_definition(t.file, t.name, t.def_type, t.code, t.lang)
      elseif act == "remove_definition" then
        print(string.format("[remove_definition] file: %s, def_type: %s", tostring(t.file), tostring(t.def_type)))
        M.remove_definition(t.file, t.name, t.def_type, t.lang)
      elseif act == "add_at_end" then
        print(string.format("[add_at_end] file: %s", tostring(t.file)))
        M.add_content(t.file, t.code)
      elseif act == "remove_file" then
        print(string.format("[remove_file] file: %s", tostring(t.file)))
        M.remove_file(t.file)
      elseif act == "replace_snippet" then
        print(string.format("[replace_snippet] file: %s | old (first 30): %s", tostring(t.file), string.sub(t.old, 1, 30)))
        M.replace_snippet(t.file, t.old, t.new)
      else
        error("Unknown action: " .. tostring(act))
      end
    end
  end)

  write_tempfile(xml_str)
end

return M
