-- Rust plugin for lint+


--- IMPLEMENTATION ---


local common = require "core.common"
local core = require "core"

local lintplus = require "plugins.lintplus"
local json = require "plugins.lintplus.json"


-- common functions


local function no_op() end


local function parent_directories(filename)

  if PLATFORM == "Windows" then
    -- jank
    filename = filename:gsub('\\', '/')
  end

  local function parent_directory(path)
    -- trim trailing slashes
    path = path:match("^(.-)/*$")
    -- find last slash
    local last_slash_pos = -1
    for i = #path, 1, -1 do
      if path:sub(i, i) == '/' then
        last_slash_pos = i
        break
      end
    end
    -- return nil if this is the root directory
    if last_slash_pos < 0 then
      return nil
    end
    -- trim everything up until the last slash
    return path:sub(1, last_slash_pos - 1)
  end

  return function ()
    filename = parent_directory(filename)
    return filename
  end

end


local function find_package_root(filename)
  for dir in parent_directories(filename) do
    local cargotoml = dir .. "/Cargo.toml"
    if system.get_file_info(cargotoml) then
      return dir
    end
  end
end


-- message processing


local function process_message(message, out_messages, package_root)
  local msg = message.message
  local kind do
    local l = message.level
    if l == "error" or l == "warning" then
      kind = l
    elseif l == "error: internal compiler error" then
      kind = "error"
    else
      kind = "info"
    end
  end

  local span = message.spans[1]
  if span ~= nil then
    local filename = package_root .. '/' .. span.file_name
    local line, column = span.line_start, span.column_start
    table.insert(out_messages, { filename, line, column, kind, msg })
  end

  for _, child in ipairs(message.children) do
    process_message(child, out_messages, package_root)
  end
end


local function get_messages(event)
  -- filename, line, column, kind, message
  local messages = {}
  local package_root = find_package_root(event.target.src_path)
  process_message(event.message, messages, package_root)
  return messages
end


-- linter

lintplus.add("rust") {
  filename = "%.rs$",
  procedure = {
    mode = "project",
    command = lintplus.command {
      "cargo", "check",
      "--message-format", "json",
      "--color", "never",
    },
    interpreter = function (filename, line)
      -- initial checks
      if line:match("^error: could not find `Cargo%.toml`") then
        core.error(
          "lint+/rust: "..filename.." is not situated in a cargo crate"
        )
        return no_op
      end
      if line:match("^ *Blocking") then
        return "bail"
      end

      local ok, event = pcall(json.decode, line)
      if not ok then return no_op end

      if event.reason == "compiler-message" then
        local messages = get_messages(event)
        local i = 1

        return function ()
          local msg = messages[i]
          if msg ~= nil then
            i = i + 1
            return table.unpack(msg)
          else
            return nil
          end
        end
      else
        return no_op
      end
    end,
  },
}
