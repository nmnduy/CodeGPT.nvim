local Render = require("codegpt.template_render")
-- local Utils = require("codegpt.utils") -- Handled by BaseProvider if needed, or keep if used elsewhere
-- local Api = require("codegpt.api") -- Handled by BaseProvider
local BaseProvider = require("codegpt.providers.base") -- Require the base provider

local OpenAIProvider = {}

-- generate_messages is simpler for OpenAI (no image handling in this version)
local function generate_messages(command, cmd_opts, command_args, text_selection)
    local system_message = Render.render(command, cmd_opts.system_message_template, command_args, text_selection,
        cmd_opts)
    local user_message = Render.render(command, cmd_opts.user_message_template, command_args, text_selection, cmd_opts)

    local messages = {}
    if system_message ~= nil and system_message ~= "" then
        table.insert(messages, { role = "system", content = system_message })
    end
    if user_message ~= nil and user_message ~= "" then
        table.insert(messages, { role = "user", content = user_message })
    end
    return messages
end

-- get_token_count is specific to OpenAI's simpler counting
local function get_token_count(messages)
    local token_count = 0
    for _, message in ipairs(messages) do
        if type(message.content) == "string" then -- Ensure content is a string
            token_count = token_count + #message.content / 4
        end
    end
    return token_count -- This is a very rough estimate, not real tokens.
end

function OpenAIProvider.make_request(command, cmd_opts, command_args, text_selection)
    local messages = generate_messages(command, cmd_opts, command_args, text_selection)
    local estimated_input_tokens = get_token_count(messages) -- This now uses the char_count / 4 estimate

    -- Assuming cmd_opts.max_tokens refers to the model's total context window limit (e.g., 4096, 8192).
    local model_context_limit = cmd_opts.max_tokens

    -- If cmd_opts.max_tokens is defined, perform a client-side check.
    -- The original condition was likely based on context_size being a raw character count.
    -- If context_size (as chars) > model_context_limit (as tokens) * 3 (chars/token estimate),
    -- it meant: estimated_tokens_method_A > model_context_limit.
    -- With estimated_input_tokens = char_count / 4, the equivalent check becomes:
    -- estimated_input_tokens > model_context_limit * (3/4)
    -- This checks if the estimated input tokens exceed 75% of the model's total capacity.
    if model_context_limit and estimated_input_tokens > model_context_limit * 0.75 then
        -- This client-side check is a rough estimate.
        -- It's often better to rely on the API for precise context length errors.
        -- The error message (if uncommented) should reflect that estimated_input_tokens is an token estimate.
        -- error("Estimated input token count (" .. estimated_input_tokens .. ") might exceed ~75% of model's capacity (" .. model_context_limit .. " tokens). Threshold: " .. model_context_limit * 0.75 .. " tokens.")
    end

    local request = {
        temperature = cmd_opts.temperature,
        n = cmd_opts.number_of_choices,
        model = cmd_opts.model,
        messages = messages,
        max_tokens = cmd_opts.max_output_tokens, -- This is the max tokens for the generated *output*.
    }
    request = vim.tbl_extend("force", request, cmd_opts.extra_params or {})
    return request
end

function OpenAIProvider.make_headers()
    local token = vim.g["codegpt_openai_api_key"] or vim.env.OPENAI_API_KEY -- Prefer vim.g, fallback to env
    if not token then
        error(
            "OpenAI API Key not found, set vim.g.codegpt_openai_api_key or env var OPENAI_API_KEY"
        )
        return nil -- Indicate error
    end
    return { Content_Type = "application/json", Authorization = "Bearer " .. token }
end

-- This is the specific handle_response for OpenAI
function OpenAIProvider.handle_response(json, cb)
    BaseProvider.handle_response_structure(json, cb, "OpenAI")
end

function OpenAIProvider.make_call(payload, cb)
    local url = vim.g["codegpt_chat_completions_url"] or "https://api.openai.com/v1/chat/completions" -- Add a default
    BaseProvider.make_api_call(
        url,
        payload,
        OpenAIProvider.make_headers,
        OpenAIProvider.handle_response, -- Pass its own handler
        cb
    )
end

return OpenAIProvider
