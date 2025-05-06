local curl = require("plenary.curl")
local Render = require("codegpt.template_render")
local Utils = require("codegpt.utils")
local Api = require("codegpt.api")

OpenRouterProvider = {}

local function generate_messages(command, cmd_opts, command_args, text_selection)
    local system_message = Render.render(command, cmd_opts.system_message_template, command_args, text_selection,
        cmd_opts)
    local user_message = Render.render(command, cmd_opts.user_message_template, command_args, text_selection, cmd_opts)

    -- Check for image paths in command_args
    local image_paths = {}
    if command_args and type(command_args) == "string" then
        -- Extract all image tags from command_args
        for path in command_args:gmatch("<image:%s*(.-)>") do
            table.insert(image_paths, path)
        end
    end
    local has_images = #image_paths > 0

    local messages = {}

    -- Add system message if present
    if system_message ~= nil and system_message ~= "" then
        table.insert(messages, { role = "system", content = system_message })
    end

    -- Handle user message with possible images
    if has_images then
        local content = {}

        -- Add text content if present
        if user_message and user_message ~= "" then
            table.insert(content, { type = "text", text = user_message })
        end

        -- Add all images
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

        -- Only add the message if we have at least one valid content item
        if #content > 0 then
            table.insert(messages, { role = "user", content = content })
        end
    elseif user_message ~= nil and user_message ~= "" then
        -- No images, just regular text message
        table.insert(messages, { role = "user", content = user_message })
    end

    return messages
end

local function check_context_length(max_tokens, messages, model)
    -- Special handling for Google Gemini model messages structure
    if model and model:match("google/gemini") then
        local ok, total_length = Utils.get_accurate_tokens(vim.fn.json_encode(messages))

        if not ok then
            total_length = 0
            -- For Gemini, the content is in a different format with type and text fields
            for _, message in ipairs(messages) do
                for _, content_part in ipairs(message.content) do
                    if content_part.type == "text" then
                        total_length = total_length + string.len(content_part.text)
                    end
                end
                total_length = total_length + string.len(message.role)
            end
        end

        if total_length >= max_tokens then
            error("Total length of messages exceeds max_tokens: " .. total_length .. " > " .. max_tokens)
        end

        return max_tokens - total_length
    end

    -- Standard token counting for other models
    local ok, total_length = Utils.get_accurate_tokens(vim.fn.json_encode(messages))

    if not ok then
        total_length = 0
        for _, message in ipairs(messages) do
            total_length = total_length + string.len(message.content) / 4 -- 1 token is approximately 4 chars
            total_length = total_length + 1 -- role is 1 token
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

local function curl_callback(response, cb)
    local status = response.status
    local body = response.body
    if status ~= 200 then
        body = body:gsub("%s+", " ")
        print("Error: " .. status .. " " .. body)
        return
    end

    if body == nil or body == "" then
        print("Error: No body")
        return
    end

    vim.schedule_wrap(function(msg)
        local json = vim.fn.json_decode(msg)
        OpenRouterProvider.handle_response(json, cb)
    end)(body)

    Api.run_finished_hook()
end

function OpenRouterProvider.make_headers()
    local token = vim.env["OPENROUTER_API_KEY"]
    if not token then
        error(
            "OpenRouter API Key not found, set the env variable 'OPENROUTER_API_KEY'"
        )
    end

    return { Content_Type = "application/json", Authorization = "Bearer " .. token }
end

function OpenRouterProvider.handle_response(json, cb)
    if json == nil then
        print("Response empty")
    elseif json.error then
        print("Error: " .. json.error.message)
    elseif not json.choices or 0 == #json.choices or not json.choices[1].message then
        print("Error: " .. vim.fn.json_encode(json))
    else
        local response_text = json.choices[1].message.content

        if response_text ~= nil then
            if type(response_text) ~= "string" or response_text == "" then
                print("Error: No response text " .. type(response_text))
                print(vim.inspect(response_text))
            else
                local bufnr = vim.api.nvim_get_current_buf()
                if vim.g["codegpt_clear_visual_selection"] then
                    vim.api.nvim_buf_set_mark(bufnr, "<", 0, 0, {})
                    vim.api.nvim_buf_set_mark(bufnr, ">", 0, 0, {})
                end
                cb(Utils.parse_lines(response_text))
            end
        else
            print("Error: No message")
        end
    end
end

function OpenRouterProvider.make_call(payload, cb)
    local payload_str = vim.fn.json_encode(payload)
    local url = "https://openrouter.ai/api/v1/chat/completions"
    local headers = OpenRouterProvider.make_headers()
    Api.run_started_hook()
    curl.post(url, {
        body = payload_str,
        headers = headers,
        callback = function(response)
            curl_callback(response, cb)
        end,
        on_error = function(err)
            print('Error:', err.message)
            Api.run_finished_hook()
        end,
    })
end

return OpenRouterProvider
