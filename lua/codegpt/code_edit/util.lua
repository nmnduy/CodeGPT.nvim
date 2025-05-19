local util = {}

-- Read file into lines
function util.read_lines(file_path)
  local lines = {}
  for line in io.lines(file_path) do
    table.insert(lines, line)
  end
  return lines
end

-- Write lines to file
function util.write_lines(file_path, lines)
  local f = io.open(file_path, "w")
  for _, line in ipairs(lines) do
    f:write(line .. "\n")
  end
  f:close()
end

-- Remove file
function util.remove_file(file_path)
  os.remove(file_path)
end

return util
