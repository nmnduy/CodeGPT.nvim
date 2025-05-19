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

function M.parse_and_apply_actions(xml_str)
  local stack = {}
  local actions = {}

  local i = 1
  local len = #xml_str

  while i <= len do
    local tag_start, tag_end, closing, tag_name, attrs = xml_str:find("<(/?)([%w_]+)(.-)>", i)
    if tag_start then
      if tag_start > i then
        -- Collect text between tags
        local text = xml_str:sub(i, tag_start-1)
        if #stack > 0 then
          local top = stack[#stack]
          if not top.content then top.content = "" end
          top.content = top.content .. text
        end
      end

      if closing == "/" then
        -- Closing tag: pop stack, assign content to parent
        local top = table.remove(stack)
        top.content = top.content or ""
        if #stack > 0 then
          local parent = stack[#stack]
          if not parent.children then parent.children = {} end
          table.insert(parent.children, top)
        else
          table.insert(actions, top)
        end
      else
        -- Opening tag: push to stack
        local node = {tag=tag_name}
        -- parse attributes if needed (not used in examples)
        table.insert(stack, node)
      end
      i = tag_end + 1
    else
      -- No more tags, just trailing text
      if #stack > 0 then
        local top = stack[#stack]
        local text = xml_str:sub(i)
        top.content = (top.content or "") .. text
      end
      break
    end
  end

  -- flatten single-child content fields (e.g. <file>xyz</file>)
  local function node_to_table(node)
    if node.children then
      local t = {}
      for _, child in ipairs(node.children) do
        t[child.tag] = node_to_table(child)
      end
      return t
    else
      return trim(node.content or "")
    end
  end

  for _, act in ipairs(actions) do
    if act.tag == "action" then
      local t = node_to_table(act)
      local action_type = t.type or act.type or ""
      if action_type == "replace_definition" then
        -- <file>, <name>, <def_type>, <lang>, <code>
        M.replace_definition(t.file, t.name, t.def_type, t.code, t.lang)
      elseif action_type == "remove_definition" then
        M.remove_definition(t.file, t.name, t.def_type, t.lang)
      elseif action_type == "add_content" then
        M.add_content(t.file, t.code)
      elseif action_type == "remove_file" then
        M.remove_file(t.file)
      elseif action_type == "replace_snippet" then
        M.replace_snippet(t.file, t.old_snippet, t.new_snippet)
      else
        error("Unknown action type: " .. tostring(action_type))
      end
    end
  end
end

return M
