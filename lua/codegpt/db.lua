local M = {}

local function get_db_path()
  return vim.fn.stdpath("data") .. "/codegpt.db"
end

local function with_retry(callback, max_retries, delay_ms)
  max_retries = max_retries or 3
  delay_ms = delay_ms or 100

  local retries = 0
  while true do
    local ok, result = pcall(callback)
    if ok then
      return result
    end

    -- Check if error is SQLITE_BUSY (database is locked)
    if not (result:match("database is locked") or result:match("SQLITE_BUSY")) then
      error(result)
    end

    retries = retries + 1
    if retries >= max_retries then
      error("Max retries ("..max_retries..") reached: "..result)
    end

    -- Exponential backoff
    local wait_time = delay_ms * (2 ^ (retries - 1))
    vim.wait(wait_time)
  end
end

function M.init_db()
  return with_retry(function()
    local db_path = get_db_path()
    local db = vim.uv.sqlite3_open(db_path)

    local create_table = [[
      CREATE TABLE IF NOT EXISTS api_responses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
        model TEXT,
        request TEXT,
        response TEXT,
        status INTEGER,
        command TEXT
      )
    ]]

    db:exec(create_table)
    db:close()
  end)
end

function M.save_response(model, request, response, status, command)
  return with_retry(function()
    local db_path = get_db_path()
    local db = vim.uv.sqlite3_open(db_path)

    local stmt = db:prepare([[
      INSERT INTO api_responses (model, request, response, status, command)
      VALUES (?, ?, ?, ?, ?)
    ]])

    stmt:bind_values(model, request, response, status, command)
    stmt:step()
    stmt:finalize()
    db:close()
  end)
end

return M
