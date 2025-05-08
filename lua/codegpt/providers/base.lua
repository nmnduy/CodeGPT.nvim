local Api = require("codegpt.api")
local Utils = require("codegpt.utils")

-- Attempt to require the db module
local Db_ok, Db = pcall(require, "codegpt.db")
if not Db_ok then
    -- Db will be nil, checks later will handle this
end

local BaseProvider = {}

-- Module-level variable to store context for the upcoming API call
local current_api_call_log_context = {}

-- Function to be called by commands.lua before initiating an API call chain
function BaseProvider.set_current_api_call_log_context(context)
    -- context should be a table like { command_name = "...", provider_name = "..." }
    current_api_call_log_context = context or {}
end

function BaseProvider.handle_response_structure(json_response, cb, provider_name_for_error)
    local choices = json_response and json_response.choices
    if choices and #choices > 0 then
        local first_choice = choices[1]
        local message_content = ""
        if first_choice.message and first_choice.message.content then
            message_content = first_choice.message.content
        elseif first_choice.text then
            message_content = first_choice.text
        else
            local err_src = provider_name_for_error or "API"
            Api.set_status("error", err_src .. "_response_error: Unexpected response structure")
            vim.notify(err_src .. ": Unexpected response structure: " .. vim.inspect(first_choice), vim.log.levels.ERROR)
            if cb then cb(nil) end
            return
        end

        local lines = vim.split(message_content, "\n", { plain = true, trimempty = false })
        Api.set_status("success")
        if cb then cb(lines) end
    elseif json_response and json_response.error then
        local err_src = provider_name_for_error or "API"
        local err_msg = err_src .. "_api_error: " .. (json_response.error.message or vim.inspect(json_response.error))
        Api.set_status("error", err_msg)
        vim.notify(err_msg, vim.log.levels.ERROR)
        if cb then cb(nil) end
    else
        local err_src = provider_name_for_error or "API"
        local err_msg = err_src .. "_response_error: No choices found or unexpected JSON structure"
        Api.set_status("error", err_msg)
        vim.notify(err_msg .. ": " .. vim.inspect(json_response), vim.log.levels.ERROR)
        if cb then cb(nil) end
    end
end

-- make_api_call no longer needs provider_name and command_name as direct arguments
function BaseProvider.make_api_call(url, payload, make_headers_fn, handle_response_fn, cb)
    -- Capture the current context for this specific call and its closures.
    -- This ensures that if another command quickly follows, its context won't interfere with this one.
    local captured_log_context = current_api_call_log_context
    local provider_name_for_status = captured_log_context.provider_name or "unknown_provider"
    local command_name_for_log = captured_log_context.command_name or "unknown_command" -- For logging

    Api.set_status("loading", "Waiting for " .. provider_name_for_status .. "...")

    local headers_table, err = pcall(make_headers_fn)
    if not headers_table then
        Api.set_status("error", "Failed to create headers: " .. (err or "unknown error"))
        vim.notify("CodeGPT: Failed to create headers: " .. (err or "unknown error"), vim.log.levels.ERROR)
        if cb then cb(nil) end
        return
    end

    local headers_curl_args = {}
    for key, value in pairs(headers_table) do
        table.insert(headers_curl_args, "-H")
        table.insert(headers_curl_args, string.format("%s: %s", key, value))
    end

    local cmd_array = {
        "curl",
        "-sS",
        "-X",
        "POST",
        url,
    }
    vim.list_extend(cmd_array, headers_curl_args)
    table.insert(cmd_array, "-d")
    table.insert(cmd_array, vim.fn.json_encode(payload))

    local stdout_chunks = {}
    local stderr_chunks = {}

    vim.fn.jobstart(cmd_array, {
        on_stdout = function(_, data, _)
            if data then
                for _, line in ipairs(data) do
                    table.insert(stdout_chunks, line)
                end
            end
        end,
        on_stderr = function(_, data, _)
            if data then
                for _, line in ipairs(data) do
                    if line ~= "" then
                        table.insert(stderr_chunks, line)
                    end
                end
            end
        end,
        on_exit = function(_, exit_code, _)
            local full_stdout_response = table.concat(stdout_chunks, "\n")
            local full_stderr_response = table.concat(stderr_chunks, "\n")

            -- Use the captured_log_context for provider and command names
            local provider_name_from_context = captured_log_context.provider_name or "unknown_provider"
            local command_name_from_context = captured_log_context.command_name or "unknown_command"

            if exit_code == 0 then
                if vim.g.codegpt_save_output == true then
                    if Db_ok and Db and Db.save_api_log then
                        local log_data = {
                            timestamp = os.time(),
                            provider = provider_name_from_context, -- Use from captured context
                            command = command_name_from_context,  -- Use from captured context
                            url = url,
                            request = payload, -- 'payload' is captured by this closure
                            response = full_stdout_response,
                        }
                        local save_ok, save_err = pcall(Db.save_api_log, log_data)
                        if not save_ok then
                            vim.notify("CodeGPT: Failed to save API call to DB: " .. (save_err or "unknown error"), vim.log.levels.ERROR)
                        end
                    elseif not (Db_ok and Db and Db.save_api_log) then
                        vim.notify("CodeGPT: DB logging enabled but 'codegpt.db' or 'save_api_log' is not available.", vim.log.levels.WARN)
                    end
                end

                local ok, json_response = pcall(vim.fn.json_decode, full_stdout_response)
                if not ok then
                    local err_msg = provider_name_from_context .. " JSON decode error: " .. tostring(json_response)
                    Api.set_status("error", err_msg)
                    vim.notify("CodeGPT: " .. err_msg .. "\nRaw Response:\n" .. full_stdout_response, vim.log.levels.ERROR)
                    if cb then cb(nil) end
                    return
                end
                -- Pass provider_name_from_context to handle_response_structure for consistent error reporting
                handle_response_fn(json_response, cb, provider_name_from_context)
            else
                local err_msg = string.format("%s API call failed (exit %d). stderr: %s", provider_name_from_context, exit_code, full_stderr_response)
                Api.set_status("error", err_msg)
                vim.notify("CodeGPT: " .. err_msg, vim.log.levels.ERROR)
                if cb then cb(nil) end
            end
        end,
        pty = false,
        clear_env = false,
    })
end

return BaseProvider
