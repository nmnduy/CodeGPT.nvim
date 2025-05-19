local CommandsList = require("codegpt.commands_list")
local Providers = require("codegpt.providers")
local Api = require("codegpt.api")
local CodeEdit = require("codegpt.code_edit.main")

local Commands = {}

function Commands.run_cmd(command, command_args, text_selection)
  local cmd_opts = CommandsList.get_cmd_opts(command)
  if cmd_opts == nil then
    vim.notify("Command not found: " .. command, vim.log.levels.ERROR, {
      title = "CodeGPT",
    })
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local start_row, start_col, end_row, end_col = Utils.get_visual_selection()

  if cmd_opts.callback_type == 'code_agent' then
    local prompt_addition = CodeEdit.get_prompt()
    cmd_opts.user_message_template = prompt_addition .. cmd_opts.user_message_template

    local request = Providers.get_provider().make_request(command, cmd_opts, command_args, text_selection)
    Providers.get_provider().make_call(request, function(lines)
      -- lines: XML string from code agent
      CodeEdit.parse_and_apply_actions(lines)
    end)
    return
  end

  local new_callback = function(lines)
    cmd_opts.callback(lines, bufnr, start_row, start_col, end_row, end_col)
  end

  local request = Providers.get_provider().make_request(command, cmd_opts, command_args, text_selection)
  Providers.get_provider().make_call(request, new_callback)
end

function Commands.get_status(...)
	return Api.get_status(...)
end

return Commands
