local CommandsList = require("codegpt.commands_list")
local Providers = require("codegpt.providers")
local Api = require("codegpt.api")
local Utils = require("codegpt.utils")
local BaseProvider = require("codegpt.providers.base") -- Require BaseProvider to set context

local Commands = {}

function Commands.run_cmd(command_name, command_args, text_selection)
	local cmd_opts = CommandsList.get_cmd_opts(command_name)
	if cmd_opts == nil then
		vim.notify("Command not found: " .. command_name, vim.log.levels.ERROR, {
			title = "CodeGPT",
		})
		return
	end

    -- Determine provider name.
    -- This assumes vim.g.codegpt_api_provider holds the string name (e.g., "openai", "openrouter").
    -- If Providers.get_current_provider_name() exists and is more reliable, use that.
    local provider_name_str = vim.g.codegpt_api_provider
    if not provider_name_str or provider_name_str == "" then
        -- Attempt to get it from Providers module if available and vim.g variable is not set
        if Providers and Providers.get_current_provider_name then
             provider_name_str = Providers.get_current_provider_name()
        else
            provider_name_str = "unknown" -- Fallback
            vim.notify("CodeGPT: vim.g.codegpt_api_provider is not set. Provider name for logging will be 'unknown'.", vim.log.levels.WARN)
        end
    end

    -- Set the logging context in BaseProvider. This creates a new table each time.
    BaseProvider.set_current_api_call_log_context({
        command_name = command_name,
        provider_name = provider_name_str,
    })

    local bufnr = vim.api.nvim_get_current_buf()
    local start_row, start_col, end_row, end_col = Utils.get_visual_selection()
    local new_callback = function(lines)
        cmd_opts.callback(lines, bufnr, start_row, start_col, end_row, end_col)
    end

	local request_payload = Providers.get_provider().make_request(command_name, cmd_opts, command_args, text_selection)
    -- The provider's make_call signature does NOT change.
    Providers.get_provider().make_call(request_payload, new_callback)
end

function Commands.get_status(...)
	return Api.get_status(...)
end

return Commands
