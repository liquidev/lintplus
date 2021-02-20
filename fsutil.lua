-- file system utilities

local fs = {}

function fs.normalize_path(path)
  if PLATFORM == "Windows" then
    return path:gsub('\\', '/')
  else
    return path
  end
end

function fs.parent_directory(path)
  path = fs.normalize_path(path)
  path = path:match("^(.-)/*$")
  local last_slash_pos = -1
  for i = #path, 1, -1 do
    if path:sub(i, i) == '/' then
      last_slash_pos = i
      break
    end
  end
  if last_slash_pos < 0 then
    return nil
  end
  return path:sub(1, last_slash_pos - 1)
end

return fs
