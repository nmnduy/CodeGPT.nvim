local Popup = require("nui.popup")
local Split = require("nui.split")
local event = require("nui.utils.autocmd").event

local Ui = {}

local popup
local split

local function setup_ui_element(lines, filetype, bufnr, start_row, start_col, end_row, end_col, ui_elem)
    -- mount/open the component
    ui_elem:mount()

    -- unmount component when cursor leaves buffer
    ui_elem:on(event.BufLeave, function()
        ui_elem:unmount()
    end)

    -- unmount component when key 'q'
    ui_elem:map("n", vim.g["codegpt_ui_commands"].quit, function()
        ui_elem:unmount()
    end, { noremap = true, silent = true })

    -- set content
    vim.api.nvim_buf_set_option(ui_elem.bufnr, "filetype", filetype)
    vim.api.nvim_buf_set_lines(ui_elem.bufnr, 0, 1, false, lines)

    -- replace lines when ctrl-o pressed
    ui_elem:map("n", vim.g["codegpt_ui_commands"].use_as_output, function()
        vim.api.nvim_buf_set_text(bufnr, start_row, start_col, end_row, end_col, lines)
        ui_elem:unmount()
    end)

    -- selecting all the content when ctrl-i is pressed
    -- so the user can proceed with another API request
    ui_elem:map("n", vim.g["codegpt_ui_commands"].use_as_input, function()
        vim.api.nvim_feedkeys("ggVG:Chat ", "n", false)
    end, { noremap = false })

    -- mapping custom commands
    for _, command in ipairs(vim.g.codegpt_ui_custom_commands) do
        ui_elem:map(command[1], command[2], command[3], command[4])
    end
end

local function create_horizontal()
    if not split then
        split = Split({
            relative = "editor",
            position = "bottom",
            size = vim.g["codegpt_horizontal_popup_size"],
        })
    end

    return split
end

local function create_vertical()
    if not split then
        split = Split({
            relative = "editor",
            position = "right",
            size = vim.g["codegpt_vertical_popup_size"],
        })
    end

    return split
end

local function create_popup()
    if not popup then
        local window_options = vim.g["codegpt_popup_window_options"]
        if window_options == nil then
            window_options = {}
        end

        -- check the old wrap config variable and use it if it's not set
        if window_options["wrap"] == nil then
            window_options["wrap"] = vim.g["codegpt_wrap_popup_text"]
        end

        popup = Popup({
            enter = true,
            focusable = true,
            border = vim.g["codegpt_popup_border"],
            position = "50%",
            size = {
                width = "80%",
                height = "60%",
            },
            win_options = window_options,
        })
    end

    popup:update_layout(vim.g["codegpt_popup_options"])

    return popup
end

function Ui.popup(lines, filetype, bufnr, start_row, start_col, end_row, end_col)
    local popup_type = vim.g["codegpt_popup_type"]
    local ui_elem = nil
    if popup_type == "horizontal" then
        ui_elem = create_horizontal()
    elseif popup_type == "vertical" then
        ui_elem = create_vertical()
    else
        ui_elem = create_popup()
    end
    setup_ui_element(lines, filetype, bufnr, start_row, start_col, end_row, end_col, ui_elem)
end

local function native_popup(lines, filetype, bufnr, sr, sc, er, ec)
  -- create a scratch buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "filetype", filetype)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

  -- compute float size & position (80%×60% centered by default)
  local cw = vim.o.columns
  local ch = vim.o.lines
  local w  = math.floor(cw * 0.80)
  local h  = math.floor(ch * 0.60)
  local row = math.floor((ch - h) / 2 - 1)
  local col = math.floor((cw - w) / 2)

  -- open the window
  local win = vim.api.nvim_open_win(buf, true, {
    relative   = "editor",
    row        = row,
    col        = col,
    width      = w,
    height     = h,
    style      = "minimal",
    border     = vim.g.codegpt_popup_border or "single",
    noautocmd  = true,
  })

  -- wrap text?
  if vim.g.codegpt_wrap_popup_text ~= nil then
    vim.api.nvim_win_set_option(win, "wrap", vim.g.codegpt_wrap_popup_text)
  end

  -- close on BufLeave
  vim.api.nvim_create_autocmd("BufLeave", {
    buffer = buf,
    once   = true,
    callback = function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end,
  })

  -- mappings in the popup buffer
  local opts = { buffer = buf, silent = true }

  -- quit with 'q'
  vim.keymap.set("n", vim.g.codegpt_ui_commands.quit, function()
    vim.api.nvim_win_close(win, true)
  end, vim.tbl_extend("force", opts, { noremap = true }))

  -- replace lines in original buffer with popup output (ctrl-o by default)
  vim.keymap.set("n", vim.g.codegpt_ui_commands.use_as_output, function()
    vim.api.nvim_buf_set_text(bufnr, sr, sc, er, ec, lines)
    vim.api.nvim_win_close(win, true)
  end, vim.tbl_extend("force", opts, { noremap = true }))

  -- select all & prefill :Chat (ctrl-i by default)
  vim.keymap.set("n", vim.g.codegpt_ui_commands.use_as_input, function()
    vim.api.nvim_feedkeys("ggVG:Chat ", "n", false)
  end, opts)

  -- custom user mappings
  for _, cmd in ipairs(vim.g.codegpt_ui_custom_commands or {}) do
    -- cmd = {mode, lhs, rhs, map_opts}
    vim.keymap.set(cmd[1], cmd[2], cmd[3], vim.tbl_extend("force", { buffer = buf }, cmd[4] or {}))
  end

  return buf, win
end

return Ui
