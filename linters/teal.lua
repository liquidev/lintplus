-- teal plugin for lint+

--- CONFIG ---

-- config.lint.teal_args: table[string]
--   passes the specified arguments to teal

--- IMPLEMENTATION ---

local core = require "core"
local lintplus = require "plugins.lintplus"

local line_processed = false
local severity = "error"

local function interpreter(filename, line, context)
      return function ()
        if line_processed then
          line_processed = false
          return nil
        end
        local num, type = line:match("^(%d+)%s+([a-rt-z]+)s?:$") -- treat `s` differently
        if num then
          severity = type
          return nil
        end
        local line_num, column, message = line:match("^/[^:]+:(%d+):(%d+):%s*(.+)$")
        if line_num then
          line_processed = true
          return filename, tonumber(line_num), tonumber(column), severity, message
        end
        return nil
      end
end

lintplus.add("teal") {
  filename = "%.tl$",
  procedure = {
    command = lintplus.args_command(
      { "tl",
        lintplus.args,
        "check",
        lintplus.filename },
      "teal_args"
    ),
    interpreter = interpreter
  },
}
