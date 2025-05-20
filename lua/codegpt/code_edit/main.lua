local util = require "codegpt.code_edit.util"
local python = require "codegpt.code_edit.python"
local java = require "codegpt.code_edit.java"
local typescript = require "codegpt.code_edit.typescript"
local go = require "codegpt.code_edit.go"

prompt = [[
**Instructions:**

You are a code refactoring assistant. You have access to tools for editing code files programmatically. You can:

- Replace a function, class, or method definition in a file with new content.
- Remove a specific function, class, or method definition from a file.
- Add content at the end of a file.
- Remove an entire file.
- Replace a specific snippet of code with a new snippet.
- Create a new file with specified content.

You MUST specify the file path, code element name, type (e.g., "function", "class", "method"), and the programming language (python, java, or go) where required.

**An example of a valid response:**

```xml
<code-edit>
    <action>create_file</action>
    <file>utils/math_utils.py</file>
    <lang>python</lang>
    <new>
def multiply(a, b):
    return a * b
    </new>
</code-edit>

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

function M.create_file(file_path, content)
  local dir = file_path:match("(.+)/[^/]+$")
  if dir then
    local current = ""
    for part in dir:gmatch("[^/]+") do
      current = current == "" and part or (current .. "/" .. part)
      os.execute('mkdir -p "' .. current .. '"')
    end
  end
  local f = assert(io.open(file_path, "w"))
  f:write(content)
  if content:sub(-1) ~= "\n" then
    f:write("\n")
  end
  f:close()
end

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

--- Helper: Stack-based extraction of <code-edit> ... </code-edit> blocks
--- @param xml table
--- @return table  -- returns a table (array) of extracted code block strings
local function extract_code_edit_blocks(xml)
  assert(type(xml) == "table" and #xml > 0, "xml must be a non-empty table")
  local results = {}
  local open = 0
  local lines = {}
    -- print("line " .. line)
    -- print("open " .. open)
    -- print(vim.inspect(lines))
    -- print("---")
  for _, line in ipairs(xml) do
    if line:find("<code%-edit>") then
      open = open + 1
      if open == 1 then
        lines = {}
      else
        table.insert(lines, line)
      end
    elseif line:find("</code%-edit>") then
      if open == 1 then
        table.insert(results, table.concat(lines, "\n"))
        lines = {}
        open = 0
      else
        open = open - 1
      end
    elseif open > 0 then
      table.insert(lines, line)
    end
  end
  return results
end

-- Helper: Check if block has both <action> and </action> (opened/closed)
local function has_action_tag(content)
  return content:find("<action>.-</action>")
end

local function parse_action(line)
  return line:match("<action>(.-)</action>")
end

local function parse_create_file_block(lines)
  local t = { action = "create_file" }
  for i = 1, #lines do
    local line = lines[i]
    if line:find("<file>") then t.file = line:match("<file>(.-)</file>"):gsub("^%s+", ""):gsub("%s+$", "") end
    if line:find("<lang>") then t.lang = line:match("<lang>(.-)</lang>"):gsub("^%s+", ""):gsub("%s+$", "") end
    if line:find("<new>") then
      local new_lines = {}
      for j = i+1, #lines - 1 do
        table.insert(new_lines, lines[j])
      end
      t.new = table.concat(new_lines, "\n")
      break
    end
  end
  return t
end

local function parse_replace_definition_block(lines)
  local t = { action = "replace_definition" }
  for i = 1, #lines do
    local line = lines[i]
    if line:find("<file>") then t.file = line:match("<file>(.-)</file>"):gsub("^%s+", ""):gsub("%s+$", "") end
    if line:find("<name>") then t.name = line:match("<name>(.-)</name>"):gsub("^%s+", ""):gsub("%s+$", "") end
    if line:find("<def_type>") then t.def_type = line:match("<def_type>(.-)</def_type>"):gsub("^%s+", ""):gsub("%s+$", "") end
    if line:find("<lang>") then t.lang = line:match("<lang>(.-)</lang>"):gsub("^%s+", ""):gsub("%s+$", "") end
    if line:find("<code>") then
      local code_lines = {}
      for j = i+1, #lines-1 do
        table.insert(code_lines, lines[j])
      end
      t.code = table.concat(code_lines, "\n")
      break
    end
  end
  return t
end

local function parse_remove_definition_block(lines)
  local t = {}
  t["action"] = "remove_definition"
  for i = 1, #lines do
    local line = lines[i]
    if line:find("<file>") then t["file"] = line:match("<file>(.-)</file>"):gsub("^%s+", ""):gsub("%s+$", "") end
    if line:find("<name>") then t["name"] = line:match("<name>(.-)</name>"):gsub("^%s+", ""):gsub("%s+$", "") end
    if line:find("<def_type>") then t["def_type"] = line:match("<def_type>(.-)</def_type>"):gsub("^%s+", ""):gsub("%s+$", "") end
    if line:find("<lang>") then t["lang"] = line:match("<lang>(.-)</lang>"):gsub("^%s+", ""):gsub("%s+$", "") end
  end
  return t
end

local function parse_add_at_end_block(lines)
  local t = {}
  t["action"] = "add_at_end"
  for i = 1, #lines do
    local line = lines[i]
    if line:find("<file>") then t["file"] = line:match("<file>(.-)</file>"):gsub("^%s+", ""):gsub("%s+$", "") end
    if line:find("<lang>") then t["lang"] = line:match("<lang>(.-)</lang>"):gsub("^%s+", ""):gsub("%s+$", "") end
    if line:find("<code>") then
      local code_lines = {}
      for k = i+1, #lines - 1 do
        table.insert(code_lines, lines[k])
      end
      t["code"] = table.concat(code_lines, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
      break
    end
  end
  return t
end

local function parse_remove_file_block(lines)
  local t = {}
  t["action"] = "remove_file"
  for i = 1, #lines do
    local line = lines[i]
    if line:find("<file>") then t["file"] = line:match("<file>(.-)</file>"):gsub("^%s+", ""):gsub("%s+$", "") end
  end
  return t
end

local function parse_replace_snippet_block(lines)
  local t = {}
  t["action"] = "replace_snippet"
  local i = 1
  while i <= #lines do
    local line = lines[i]
    if line:find("<file>") then t["file"] = line:match("<file>(.-)</file>"):gsub("^%s+", ""):gsub("%s+$", "") end
    if line:find("<lang>") then t["lang"] = line:match("<lang>(.-)</lang>"):gsub("^%s+", ""):gsub("%s+$", "") end
    if line:find("<old>") then
      local old_lines = {}
      i = i + 1
      while i <= #lines and not lines[i]:find("</old>") do
        table.insert(old_lines, lines[i])
        i = i + 1
      end
      t["old"] = table.concat(old_lines, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
    end
    if line:find("<new>") then
      local new_lines = {}
      i = i + 1
      while i <= #lines and not lines[i]:find("</new>") do
        table.insert(new_lines, lines[i])
        i = i + 1
      end
      t["new"] = table.concat(new_lines, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
      break
    end
    i = i + 1
  end
  return t
end

local function parse_code_edit_block(content)
  local lines = {}
  lines = vim.fn.split(content, '\n', true)
  for i, line in ipairs(lines) do
    local action = parse_action(line)
    -- if no action then it's not a valid code edit block and
    -- we throw it away
    if action then
      local rest_lines = {}
      for j = i, #lines do table.insert(rest_lines, lines[j]) end
      if action == "create_file" then
        return parse_create_file_block(rest_lines)
      elseif action == "replace_definition" then
        return parse_replace_definition_block(rest_lines)
      elseif action == "remove_definition" then
        return parse_remove_definition_block(rest_lines)
      elseif action == "add_at_end" then
        return parse_add_at_end_block(rest_lines)
      elseif action == "remove_file" then
        return parse_remove_file_block(rest_lines)
      elseif action == "replace_snippet" then
        return parse_replace_snippet_block(rest_lines)
      end
    end
  end
  return {}
end

-- Main parser
---@param xml_table string
---@param will_write_tmp_file boolean
function M.parse_and_apply_actions(xml_table, will_write_tmp_file)
  assert(xml_table ~= nil and next(xml_table) ~= nil, "xml_table must not be nil or empty")
  if will_write_tmp_file == nil then will_write_tmp_file = false end
  local actions = {}

  -- 1. Extract code-edit blocks using stack
  local code_edit_blocks = extract_code_edit_blocks(xml_table)

  -- 2. Only keep blocks with both open and close <action> tags
  for _, block in ipairs(code_edit_blocks) do
    if has_action_tag(block) then
      -- 3. Parse fields from the code-edit block
      local t = parse_code_edit_block(block)
      table.insert(actions, t)
    end
  end

  for _, t in ipairs(actions) do
    local act = t.action
    if act == "create_file" then
      print(string.format("[create_file] file: %s", tostring(t.file)))
      M.create_file(t.file, t.new)
    elseif act == "replace_definition" then
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
      print(string.format("[replace_snippet] file: %s | old (first 30): %s", tostring(t.file), string.sub(t.old or "", 1, 30)))
      M.replace_snippet(t.file, t.old, t.new)
    else
      error("Unknown action: " .. tostring(act))
    end
  end

  if will_write_tmp_file then
    write_tempfile(xml_table)
  end
end

local function test_extract_code_edit_blocks()
  -- Test 1: Single block
  local xml1 = [[
<code-edit>
<action>replace_definition</action>
<file>foo.py</file>
<name>f</name>
<def_type>function</def_type>
<lang>python</lang>
<code>
def f(a): return a+1
</code>
</code-edit>
]]
  local blocks1 = extract_code_edit_blocks(vim.fn.split(vim.trim(xml1), "\n"))
  assert(type(blocks1) == "table", "Should return table of blocks")
  assert(#blocks1 == 1, "Should extract one block")
  assert(blocks1[1]:find("<action>replace_definition"), "Should contain action tag")

  -- Test 2: Multiple blocks
  local xml2 = [[
<code-edit>
<action>replace_definition</action>
<file>foo.py</file>
<name>f</name>
<def_type>function</def_type>
<lang>python</lang>
<code>
def f(a): return a+1
</code>
</code-edit>
<code-edit>
<action>replace_definition</action>
<file>bar.go</file>
<name>Bar</name>
<def_type>class</def_type>
<lang>go</lang>
<code>
type Bar struct{}
</code>
</code-edit>
]]
  local blocks2 = extract_code_edit_blocks(vim.fn.split(vim.trim(xml2), "\n"))
  assert(#blocks2 == 2, "Should extract two blocks")
  assert(blocks2[2]:find("bar.go"), "Second block file should be bar.go")

  -- Test 3: Malformed (no <code-edit> tags)
  local xml3 = [[
<action>replace_definition</action>
<file>foo.py</file>
]]
  local blocks3 = extract_code_edit_blocks(vim.fn.split(vim.trim(xml3), "\n"))
  assert(type(blocks3) == "table", "Should return table even if no blocks")
  assert(#blocks3 == 0, "Should return empty table if no <code-edit> blocks")

end

local function test_extract_code_edit_blocks_nested()
  local input = {
    "<code-edit>",
    "  <action>replace_definition</action>",
    "  <file>foo.py</file>",
    "  <name>f</name>",
    "  <def_type>function</def_type>",
    "  <lang>python</lang>",
    "  <code>",
    "def f():",
    "    x = 1",
    "    # Below is a code-edit tag inside code",
    "    s = \"\"\"",
    "<code-edit>",
    "  <file>should_not_be_counted.py</file>",
    "</code-edit>",
    "\"\"\"",
    "    return x",
    "  </code>",
    "</code-edit>",
  }
  local blocks = extract_code_edit_blocks(input)
  assert(#blocks == 1, "Should extract one outer code-edit block")
  assert(blocks[1]:find("should_not_be_counted") ~= nil, "Embedded <code-edit> inside <code> should be inside the block as string")
end

local function test_parse_code_edit_block_nested()
  local input = [[
<code-edit>
  <action>replace_definition</action>
  <file>foo.py</file>
  <name>f</name>
  <def_type>function</def_type>
  <lang>python</lang>
  <code>
def f():
    x = 1
    # Below is a code-edit tag inside code block
    s = """
<code-edit>
  <file>should_not_be_counted.py</file>
</code-edit>
"""
    return x
  </code>
</code-edit>
]]
  local blocks = extract_code_edit_blocks(vim.fn.split(vim.trim(input), "\n"))
  assert(#blocks == 1, "Expected exactly one code edit block. But saw " .. #blocks)
  local t = parse_code_edit_block(blocks[1])
  assert(t.action == "replace_definition", "Action parse failed for nested test")
  assert(t.file == "foo.py", "File parse failed for nested test")
  assert(t.name == "f", "Name parse failed for nested test")
  assert(t.def_type == "function", "Def type parse failed for nested test")
  assert(t.lang == "python", "Lang parse failed for nested test")
  assert(t.code:find("<code%-edit>") ~= nil, "Nested <code-edit> inside <code> should be included as string")
  assert(t.code:find("should_not_be_counted") ~= nil, "Inner content should stay in code string")
end

-- Helper to simulate code-edit XML block lines and parse
local function test_parse_replace_definition_block()
  -- Test 1: Typical block
  local lines = {
    "<file>utils/helpers.py</file>",
    "<name>calculate_sum</name>",
    "<def_type>function</def_type>",
    "<lang>python</lang>",
    "<code>",
    "def calculate_sum(a, b):",
    "    return a + b",
    "</code>",
  }
  local t = parse_replace_definition_block(lines)
  assert(t.action == "replace_definition", "action should be replace_definition")
  assert(t.file == "utils/helpers.py", "file parsed incorrectly")
  assert(t.name == "calculate_sum", "name parsed incorrectly")
  assert(t.def_type == "function", "def_type parsed incorrectly")
  assert(t.lang == "python", "lang parsed incorrectly")

  -- Test 2: Indented code block
  local lines2 = {
    "<file>foo/bar.go</file>",
    "<name>Foo</name>",
    "<def_type>class</def_type>",
    "<lang>go</lang>",
    "<code>",
    "type Foo struct {",
    "    Value int",
    "}",
    "</code>",
  }
  local t2 = parse_replace_definition_block(lines2)
  assert(t2.file == "foo/bar.go", "file parsed incorrectly")
  assert(t2.name == "Foo", "name parsed incorrectly")
  assert(t2.def_type == "class", "def_type parsed incorrectly")
  assert(t2.lang == "go", "lang parsed incorrectly")
  assert(t2.code:find("Value int"), "code body parsed incorrectly")

  -- Test 3: Missing code tag results in nil code
  local lines3 = {
    "<file>foo.py</file>",
    "<name>f</name>",
    "<def_type>function</def_type>",
    "<lang>python</lang>",
  }
  local t3 = parse_replace_definition_block(lines3)
  assert(t3.code == nil, "code field should be nil if missing")

  -- Test 4: Code block containing HTML tags and nested <code> block
  local lines4 = {
    "<file>web/page.html</file>",
    "<name>render_section</name>",
    "<def_type>function</def_type>",
    "<lang>html</lang>",
    "<code>",
    "",
    "<div>",
    "  <span class=\"label\">Label</span>",
    "  <code>let x = 10;</code>",
    "</div>",
    "",
    "</code>",
  }
  local t4 = parse_replace_definition_block(lines4)
  assert(t4.file == "web/page.html", "file parsed incorrectly")
  assert(t4.name == "render_section", "name parsed incorrectly")
  assert(t4.def_type == "function", "def_type parsed incorrectly")
  assert(t4.lang == "html", "lang parsed incorrectly")
  assert(t4.code:find("<span class=\"label\">Label</span>"), "HTML span not parsed in code")
  assert(t4.code:find("<code>let x = 10;</code>"), "Nested <code> block not parsed in code")
end

local function test_parse_and_apply_actions_from_file()
  local f = io.open("/tmp/edit.xml", "r")
  if not f then
    print("warn: Could not open /tmp/edit.xml for reading")
    return
  end
  local xml_lines = {}
  for line in f:lines() do
    table.insert(xml_lines, line)
  end
  f:close()
  M.parse_and_apply_actions(xml_lines, false)
end

if os.getenv("CODE_GPT_NVIM_UNIT_TEST") then
  test_extract_code_edit_blocks()
  test_parse_code_edit_block_nested()
  test_parse_replace_definition_block()
  test_parse_and_apply_actions_from_file()
  vim.api.nvim_echo({{"tests done", "WarningMsg"}}, true, {})
end

return M
