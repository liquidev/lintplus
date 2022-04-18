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


-- message processing

local function message_spans_multiple_lines(message, line)
  if #message.spans == 0 then return false end
  for _, span in ipairs(message.spans) do
    if span.line_start ~= line then
      return true
    end
  end
  for _, child in ipairs(message.children) do
    local child_spans_multiple_lines = message_spans_multiple_lines(child, line)
    if child_spans_multiple_lines then
      return true
    end
  end
  return false
end

local function process_message(
  context,
  message,
  out_messages,
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
  if span ~= nil then
    local filename = context.workspace_root .. '/' .. span.file_name
    local line, column = span.line_start, span.column_start

    if rail == nil then
      if message_spans_multiple_lines(message, line) then
        rail = context:create_gutter_rail()
      end
    end

    for _, sp in ipairs(message.spans) do
      if sp.label ~= nil and not sp.is_primary then
        local s_filename = context.workspace_root .. '/' .. span.file_name
        local s_line, s_column = sp.line_start, sp.column_start
        table.insert(out_messages,
                     { s_filename, s_line, s_column, "info", sp.label, rail })
      end
    end

    if span.suggested_replacement ~= nil then
      local suggestion = span.suggested_replacement:match("(.-)\r?\n")
      if suggestion ~= nil then
        msg = msg .. " `" .. suggestion .. '`'
      end
    end
    table.insert(out_messages, { filename, line, column, kind, msg, rail })
  end

  for _, child in ipairs(message.children) do
    process_message(context, child, out_messages, rail)
  end
end


local function get_messages(context, event)
  -- filename, line, column, kind, message
  local messages = {}
  process_message(context, event.message, messages)
  return messages
end


-- linter

lintplus.add("rust") {
  filename = "%.rs$",
  procedure = {

    init = function (filename, context)
      local process = lintplus.ipc.start_process({
        "cargo", "locate-project", "--workspace"
      }, lintplus.fs.parent_directory(filename))
      while true do
        local exit, _ = process:poll(function (line)
          local ok, process_result = pcall(json.decode, line)
          if not ok then return end
          context.workspace_root =
            lintplus.fs.parent_directory(process_result.root)
        end)
        if exit ~= nil then break end
      end
    end,

    command = lintplus.command {
      set_cwd = true,
      "cargo", "clippy",
      "--message-format", "json",
      "--color", "never",
      -- "--tests",
    },

    interpreter = function (filename, line, context)
      -- initial checks
      if context.workspace_root == nil then
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
