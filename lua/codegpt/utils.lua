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
    table.insert(current_lines, "")
    table.insert(current_lines, "---")
    table.insert(current_lines, "")

    table.insert(current_lines, lines[1])
    for i = 2, #lines do
        table.insert(current_lines, lines[i])
    end

    -- Replace the old lines with the new appended lines
    vim.api.nvim_buf_set_lines(bufnr, start_row, end_row + 1, false, current_lines)

    -- Find a window showing the buffer, or use the current window and set its buffer
    -- This works even when the cursor is not on the buffer waiting for response
    local winid = nil
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_get_buf(win) == bufnr then
            winid = win
            break
        end
    end
    if not winid then
        vim.api.nvim_set_current_buf(bufnr)
        winid = vim.api.nvim_get_current_win()
    end

    vim.api.nvim_win_set_cursor(winid, {start_row + #current_lines - #lines - 2 + 1, 0})
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

return Utils
