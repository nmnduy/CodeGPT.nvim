Utils = {}

local ts_utils = require("nvim-treesitter.ts_utils")
local parsers = require("nvim-treesitter.parsers")

function Utils.get_filetype()
    local bufnr = vim.api.nvim_get_current_buf()
    return vim.api.nvim_buf_get_option(bufnr, "filetype")
end

function Utils.get_visual_selection()
    local bufnr = vim.api.nvim_get_current_buf()

    local start_pos = vim.api.nvim_buf_get_mark(bufnr, "<")
    local end_pos = vim.api.nvim_buf_get_mark(bufnr, ">")

    if start_pos[1] == end_pos[1] and start_pos[2] == end_pos[2] then
        return 0, 0, 0, 0
    end

    local start_row = start_pos[1] - 1
    local start_col = start_pos[2]

    local end_row = end_pos[1] - 1
    local end_col = end_pos[2] + 1

    if vim.api.nvim_buf_get_lines(bufnr, start_row, start_row + 1, true)[1] == nil then
        return 0, 0, 0, 0
    end

    local start_line_length = vim.api.nvim_buf_get_lines(bufnr, start_row, start_row + 1, true)[1]:len()
    start_col = math.min(start_col, start_line_length)

    local end_line_length = vim.api.nvim_buf_get_lines(bufnr, end_row, end_row + 1, true)[1]:len()
    end_col = math.min(end_col, end_line_length)

    return start_row, start_col, end_row, end_col
end

function Utils.get_selected_lines()
    local bufnr = vim.api.nvim_get_current_buf()
    local start_row, start_col, end_row, end_col = Utils.get_visual_selection()
    local lines = vim.api.nvim_buf_get_text(bufnr, start_row, start_col, end_row, end_col, {})
    return table.concat(lines, "\n")
end

function Utils.insert_lines(lines)
    local bufnr = vim.api.nvim_get_current_buf()
    local line = vim.api.nvim_win_get_cursor(0)[1]
    vim.api.nvim_buf_set_lines(bufnr, line, line, false, lines)
    vim.api.nvim_win_set_cursor(0, { line + #lines, 0 })
end

function Utils.replace_lines(lines, bufnr, start_row, start_col, end_row, end_col)
    vim.api.nvim_buf_set_text(bufnr, start_row, start_col, end_row, end_col, lines)
end

function Utils.append_lines(lines, bufnr, start_row, start_col, end_row, end_col)
    local current_lines = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)
    local last_line = current_lines[#current_lines]

    -- Append the first line content after the end_col to the last line of the current lines
    current_lines[#current_lines] = last_line:sub(1, end_col)

    -- Insert a new line and then append the new lines starting from the first line
    table.insert(current_lines, "---")
    table.insert(current_lines, "")

    table.insert(current_lines, lines[1])
    for i = 2, #lines do
        table.insert(current_lines, lines[i])
    end

    -- Replace the old lines with the new appended lines
    vim.api.nvim_buf_set_lines(bufnr, start_row, end_row + 1, false, current_lines)

    -- Move the cursor to the beginning of the newly appended content
    vim.api.nvim_win_set_cursor(0, {start_row + #current_lines - #lines - 1 + 1, 0})
end

local function get_code_block(lines2)
    local code_block = {}
    local in_code_block = false
    for _, line in ipairs(lines2) do
        if line:match("^```") then
            in_code_block = not in_code_block
        elseif in_code_block then
            table.insert(code_block, line)
        end
    end
    return code_block
end

local function contains_code_block(lines2)
    for _, line in ipairs(lines2) do
        if line:match("^```") then
            return true
        end
    end
    return false
end

function Utils.trim_to_code_block(lines)
    if contains_code_block(lines) then
        return get_code_block(lines)
    end
    return lines
end

function Utils.parse_lines(response_text)
    if vim.g["codegpt_write_response_to_err_log"] then
        vim.api.nvim_err_write("ChatGPT response: \n" .. response_text .. "\n")
    end

    return vim.fn.split(vim.trim(response_text), "\n")
end


function Utils.fix_indentation(bufnr, start_row, end_row, new_lines)
    local original_lines = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row, true)
    local min_indentation = math.huge
    local original_identation = ""

    -- Find the minimum indentation of any line in original_lines
    for _, line in ipairs(original_lines) do
        local indentation = string.match(line, "^%s*")
        if #indentation < min_indentation then
            min_indentation = #indentation
            original_identation = indentation
        end
    end

    -- Change the existing lines in new_lines by adding the old identation
    for i, line in ipairs(new_lines) do
        new_lines[i] = original_identation .. line
    end
end

function Utils.get_accurate_tokens(content)
    local ok, result = pcall(
        vim.api.nvim_exec2,
        string.format([[
python3 << EOF
import tiktoken
encoder = tiktoken.get_encoding("cl100k_base")
encoded = encoder.encode("""%s""")
print(len(encoded))
EOF
]], content), true)
    if ok and #result > 0 then
        return ok, tonumber(result)
    end
    return ok, 0
end


function Utils.remove_trailing_whitespace(lines)
    for i, line in ipairs(lines) do
        lines[i] = line:gsub("%s+$", "")
    end
    return lines
end


function Utils.read_file_as_base64(file_path)
    if not file_path then return nil end

    -- Expand path if it contains ~
    if file_path:sub(1, 1) == "~" then
        file_path = os.getenv("HOME") .. file_path:sub(2)
    end

    local file = io.open(file_path, "rb")
    if not file then
        print("Error: Could not open image file: " .. file_path)
        return nil
    end

    local content = file:read("*all")
    file:close()

    -- Convert to base64
    local base64_str = vim.fn.system({"base64", "-w", "0"}, content):gsub("\n", "")
    return base64_str
end

function Utils.parse_code_edit_instructions(text)
    local instructions = {}
    local stack = {}
    local lines = vim.fn.split(text, "\n")
    local cur_edit = nil
    local cur_field = nil
    local buffer = {}

    for i, line in ipairs(lines) do
        -- Only trim lines outside of content blocks
        if cur_field ~= "content" then
            line = vim.trim(line)
        end

        -- Start of a code-edit block
        if line == "<code-edit>" then
            table.insert(stack, "<code-edit>")
            cur_edit = {file = nil, object = nil, content = nil}
            cur_field = nil
            buffer = {}
        -- End of code-edit block
        elseif line == "</code-edit>" then
            if cur_field and #buffer > 0 then
                cur_edit[cur_field] = table.concat(buffer, "\n")
            end
            table.insert(instructions, cur_edit)
            table.remove(stack)
            cur_edit = nil
            cur_field = nil
            buffer = {}
        -- Start of a field
        elseif line == "<file>" or line == "<object>" or line == "<content>" then
            if cur_field and #buffer > 0 then
                cur_edit[cur_field] = table.concat(buffer, "\n")
            end
            cur_field = line:match("^<([^>]+)>$")
            buffer = {}
        -- End of a field
        elseif line == "</file>" or line == "</object>" or line == "</content>" then
            -- Save the buffer to the field in cur_edit
            if cur_field and #buffer > 0 then
                cur_edit[cur_field] = table.concat(buffer, "\n")
            end
            cur_field = nil
            buffer = {}
        -- Inside a field
        elseif cur_field then
            table.insert(buffer, line)
        end
    end

    return instructions
end

local function ensure_dir_exists(file_path)
    local dir = file_path:match("(.+)/[^/]+$")
    if dir then
        local ok, err = os.execute('[ -d "'..dir..'" ] || mkdir -p "'..dir..'"')
        if not ok then
            vim.api.nvim_err_writeln("Could not create directory: " .. dir .. (err and (" ("..err..")") or ""))
            return false
        end
    end
    return true
end

local function get_lang_from_filename(filename)
    local ext = filename:match("^.+%.([a-zA-Z0-9_]+)$")
    if not ext then return nil end
    -- Map extension to filetype (as Neovim does)
    local ft = vim.filetype.match({ filename = filename }) or ext
    return parsers.ft_to_lang(ft) or ft
end

local function get_lang_from_filename(filename)
    local ext = filename:match("^.+%.([a-zA-Z0-9_]+)$")
    if not ext then return nil end
    local ft = vim.filetype.match({ filename = filename }) or ext
    return parsers.ft_to_lang(ft) or ft
end

function Utils.apply_code_edit_with_treesitter(edit)
    local object_name = edit.object
    local new_code = edit.content
    local file = edit.file

    print("Object name:", object_name)
    print("File:", file)

    if not object_name or not new_code then
        vim.api.nvim_err_writeln("Missing object or content in code edit block.")
        return
    end

    if not ensure_dir_exists(file) then return end

    -- Touch file if not exists
    local f = io.open(file, "r")
    if not f then
        local wf = io.open(file, "w")
        if wf then wf:close() end
    else
        f:close()
    end

    -- Read lines
    local lines = {}
    local rf = io.open(file, "r")
    if rf then
        for l in rf:lines() do table.insert(lines, l) end
        rf:close()
    end

    local lang = get_lang_from_filename(file)
    if not lang then
        vim.api.nvim_out_write(
            "Could not detect language for file: " .. file .. ". Appending code at end of file.\n"
        )
        local new_lines = vim.split(new_code, "\n")
        for _, l in ipairs(new_lines) do
            table.insert(lines, l)
        end
        local wf = io.open(file, "w")
        if not wf then
            vim.api.nvim_err_writeln("Could not open file for writing: " .. file)
            return
        end
        wf:write(table.concat(lines, "\n"))
        wf:close()
        vim.notify("Code edit applied to file: " .. file)
        return
    end

    local parser = vim.treesitter.get_string_parser(table.concat(lines, "\n"), lang)
    local tree = parser:parse()[1]
    local root = tree:root()

    local function get_object_queries(lang)
        local query_files = {"locals", "highlights"}
        for _, qfile in ipairs(query_files) do
            local ok, query = pcall(vim.treesitter.query.get, lang, qfile)
            if ok and query then
                return query
            end
        end
        return nil
    end

    local function extract_node_name(node, lines)
        local name_fields = {"name", "identifier", "declaration", "value", "field"}
        for _, field in ipairs(name_fields) do
            local name_node = node:field(field)[1]
            if name_node then
                return vim.treesitter.get_node_text(name_node, lines)
            end
        end

        local first_child = node:child(0)
        if first_child then
            local child_type = first_child:type()
            if child_type:find("identifier") or child_type:find("name") then
                return vim.treesitter.get_node_text(first_child, lines)
            end
        end

        return nil
    end

    local function handle_special_cases(lang, root, lines, object_name)
        -- Add language-specific handling here if needed
        return nil
    end

    local function find_object_with_fallback(lang, root, lines, object_name)
        -- Try special cases first
        local special_case = handle_special_cases(lang, root, lines, object_name)
        if special_case then return special_case end

        -- Try query
        local query = get_object_queries(lang)
        if query then
            for id, node in query:iter_captures(root, 0, 0, -1) do
                local name = extract_node_name(node, lines)
                if name == object_name then
                    return node
                end
            end
        end

        -- Then try generic search
        local function search_children(node)
            local name = extract_node_name(node, lines)
            if name == object_name then
                return node
            end

            for child in node:iter_children() do
                local result = search_children(child)
                if result then return result end
            end
            return nil
        end

        return search_children(root)
    end

    local object_node = find_object_with_fallback(lang, root, lines, object_name)

    if not object_node then
        local msg = string.format(
            "Could not find object '%s' in file (treesitter). Possible reasons:\n" ..
            "- The object exists but has a different syntax structure\n" ..
            "- The language parser doesn't recognize this construct\n" ..
            "- The name is used in a different context\n\n" ..
            "Appending as new code at the end of the file.",
            object_name
        )
        vim.api.nvim_out_write(msg)

        local new_lines = vim.split(new_code, "\n")
        for _, l in ipairs(new_lines) do
            table.insert(lines, l)
        end
    else
        local start_row, _, end_row, _ = object_node:range()
        local new_lines = vim.split(new_code, "\n")
        for i = start_row + 1, end_row + 1 do
            lines[i] = nil
        end
        for i, l in ipairs(new_lines) do
            table.insert(lines, start_row + i, l)
        end
    end

    local wf = io.open(file, "w")
    if not wf then
        vim.api.nvim_err_writeln("Could not open file for writing: " .. file)
        return
    end
    wf:write(table.concat(lines, "\n"))
    wf:close()
    vim.notify("Code edit applied to file: " .. file)
end

return Utils
