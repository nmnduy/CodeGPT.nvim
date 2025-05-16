local curl = require("plenary.curl")
local Utils = require("codegpt.utils")
local Api = require("codegpt.api")

local BaseProvider = {}

-- This function is almost identical in both, so we make it generic.
-- The specific provider will pass its own handle_response function.
local function base_curl_callback(response, cb, specific_handle_response_fn)
    local status = response.status
    local body = response.body
    if status ~= 200 then
        body = body and body:gsub("%s+", " ") or "Unknown error"
        print("Error: " .. status .. " " .. body)
        Api.run_finished_hook() -- Ensure hook runs on error
        return
    end

    if body == nil or body == "" then
        print("Error: No body")
        Api.run_finished_hook() -- Ensure hook runs on error
        return
    end

    vim.schedule_wrap(function(msg)
        local json = vim.fn.json_decode(msg)
        specific_handle_response_fn(json, cb) -- Call the specific provider's handler
    end)(body)

    Api.run_finished_hook()
end

-- This function is also very similar.
-- The specific provider will pass its own handle_response function.
function BaseProvider.handle_response_structure(json, cb, provider_name)
    if json == nil then
        print(provider_name .. " Error: Response empty")
    elseif json.error then
        print(provider_name .. " Error: " .. (json.error.message or vim.fn.json_encode(json.error)))
    elseif not json.choices or 0 == #json.choices or not json.choices[1].message then
        print(provider_name .. " Error: Invalid response structure " .. vim.fn.json_encode(json))
    else
        local response_text = json.choices[1].message.content

        if response_text ~= nil then
            if type(response_text) ~= "string" or response_text == "" then
                print(provider_name .. " Error: No response text or invalid type " .. type(response_text))
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
            print(provider_name .. " Error: No message content in response")
        end
    end
end


-- Generic make_call function
-- It takes the URL and the make_headers function, and the specific handle_response function from the child provider.
function BaseProvider.make_api_call(url, payload, make_headers_fn, specific_handle_response_fn, cb)
    local payload_str = vim.fn.json_encode(payload)
    local headers = make_headers_fn()
    if not headers then return end -- make_headers_fn might error out

    Api.run_started_hook()
    curl.post(url, {
        body = payload_str,
        headers = headers,
        callback = function(response)
            -- Pass the specific_handle_response_fn to the base_curl_callback
            base_curl_callback(response, cb, specific_handle_response_fn)
        end,
        on_error = function(err)
            print('cURL Error:', err.message)
            Api.run_finished_hook()
        end,
    })
end

return BaseProvider
