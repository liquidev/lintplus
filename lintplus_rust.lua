-- Rust plugin for lint+


--- IMPLEMENTATION ---


local common = require "core.common"
local core = require "core"

local lintplus = require "plugins.lintplus"
local json = require "plugins.lintplus.json"


-- common functions


local function no_op() end


local function parent_directories(filename)

  return function ()
    filename = lintplus.fs.parent_directory(filename)
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


local function process_message(
  context,
  message,
  out_messages,
  package_root,
  rail
)
  local msg = message.message
  local span = message.spans[1]

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

  local nonprimary_spans = 0
  for _, sp in ipairs(message.spans) do
    if not sp.is_primary then
      nonprimary_spans = nonprimary_spans + 1
    end
  end

  -- only assign a rail if there are children or multiple non-primary spans
  if rail == nil and (#message.children > 0 or nonprimary_spans > 0) and
     span ~= nil then
    -- only assign a rail if the children are spread across multiple lines
    local multiline = false
    for _, child in ipairs(message.children) do
      local child_span = child.spans[1]
      if child_span ~= nil and child_span.line_start ~= span.line_start then
        multiline = true
        break
      end
    end
    if multiline or nonprimary_spans > 0 then
      rail = context:gutter_rail()
    end
  end

  if span ~= nil then
    local filename = package_root .. '/' .. span.file_name
    local line, column = span.line_start, span.column_start
    table.insert(out_messages, { filename, line, column, kind, msg, rail })
  end

  for _, sp in ipairs(message.spans) do
    if sp.label ~= nil and not sp.is_primary then
      local filename = package_root .. '/' .. span.file_name
      local line, column = sp.line_start, sp.column_start
      table.insert(out_messages,
                   { filename, line, column, "info", sp.label, rail })
    end
  end

  for _, child in ipairs(message.children) do
    process_message(context, child, out_messages, package_root, rail)
  end
end


local function get_messages(context, event)
  -- filename, line, column, kind, message
  local messages = {}
  local package_root = find_package_root(event.target.src_path)
  process_message(context, event.message, messages, package_root)
  return messages
end


-- linter

lintplus.add("rust") {
  filename = "%.rs$",
  procedure = {
    mode = "project",
    command = lintplus.command {
      set_cwd = true,
      "cargo", "check",
      "--message-format", "json",
      "--color", "never",
    },
    interpreter = function (filename, line, context)
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
        local messages = get_messages(context, event)
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
