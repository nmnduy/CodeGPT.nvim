local Render = require("codegpt.template_render")
local Utils = require("codegpt.utils")
-- local Api = require("codegpt.api") -- Handled by BaseProvider
local BaseProvider = require("codegpt.providers.base") -- Require the base provider

local OpenRouterProvider = {}

-- generate_messages is specific to OpenRouter due to image handling
local function generate_messages(command, cmd_opts, command_args, text_selection)
    local system_message = Render.render(command, cmd_opts.system_message_template, command_args, text_selection,
        cmd_opts)
    local user_message = Render.render(command, cmd_opts.user_message_template, command_args, text_selection, cmd_opts)

    local image_paths = {}
    if command_args and type(command_args) == "string" then
        for path in command_args:gmatch("<image:%s*(.-)>") do
            table.insert(image_paths, path)
        end
    end
    local has_images = #image_paths > 0

    local messages = {}
    if system_message ~= nil and system_message ~= "" then
        table.insert(messages, { role = "system", content = system_message })
    end

    if has_images then
        local content = {}
        if user_message and user_message ~= "" then
            table.insert(content, { type = "text", text = user_message })
        end
        for _, image_path in ipairs(image_paths) do
            local image_data = Utils.read_file_as_base64(image_path)
            if image_data then
                table.insert(content, {
                    type = "image_url",
                    image_url = {
                        url = "data:image/jpeg;base64," .. image_data
                    }
                })
            end
        end
        if #content > 0 then
            table.insert(messages, { role = "user", content = content })
        end
    elseif user_message ~= nil and user_message ~= "" then
        table.insert(messages, { role = "user", content = user_message })
    end

    return messages
end

-- check_context_length is specific to OpenRouter's potential token counting
local function check_context_length(max_tokens, messages, model)
    local ok, total_length = Utils.get_accurate_tokens(vim.fn.json_encode(messages))
    if not ok then
        total_length = 0
        for _, message in ipairs(messages) do
            if type(message.content) == "string" then
                total_length = total_length + string.len(message.content) / 4
            elseif type(message.content) == "table" then -- Handle array of content parts
                for _, part in ipairs(message.content) do
                    if part.type == "text" and part.text then
                         total_length = total_length + string.len(part.text) / 4
                    -- Note: image token counting is complex and model-dependent,
                    -- this approximation doesn't account for images accurately.
                    end
                end
            end
            total_length = total_length + 1
        end
    end

    if total_length >= max_tokens then
        error("Total length of messages exceeds max_tokens: " .. total_length .. " > " .. max_tokens)
    end
    return max_tokens - total_length
end

function OpenRouterProvider.make_request(command, cmd_opts, command_args, text_selection)
    local messages = generate_messages(command, cmd_opts, command_args, text_selection)
    check_context_length(cmd_opts.max_tokens, messages, cmd_opts.model)

    local request = {
        temperature = cmd_opts.temperature,
        n = cmd_opts.number_of_choices,
        model = cmd_opts.model,
        messages = messages,
        max_tokens = cmd_opts.max_output_tokens,
    }
    return request
end

function OpenRouterProvider.make_headers()
    local token = vim.env["OPENROUTER_API_KEY"]
    if not token then
        error(
            "OpenRouter API Key not found, set the env variable 'OPENROUTER_API_KEY'"
        )
        return nil -- Indicate error
    end
    return { Content_Type = "application/json", Authorization = "Bearer " .. token }
end

-- This is the specific handle_response for OpenRouter
function OpenRouterProvider.handle_response(json, cb)
    BaseProvider.handle_response_structure(json, cb, "OpenRouter")
end

function OpenRouterProvider.make_call(payload, cb)
    local url = "https://openrouter.ai/api/v1/chat/completions"
    BaseProvider.make_api_call(
        url,
        payload,
        OpenRouterProvider.make_headers,
        OpenRouterProvider.handle_response, -- Pass its own handler
        cb
    )
end

return OpenRouterProvider
