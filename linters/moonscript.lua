-- MoonScript plugin for lint+

--- CONFIG ---

-- config.lint.moonscript_args: table[string]
--   passes the specified arguments to moonscript

--- IMPLEMENTATION ---

local core = require "core"
local lintplus = require "plugins.lintplus"

local line_processed = false
local fatal = nil

local function interpreter(filename, line, _context)
      return function ()
        if line_processed then
          line_processed = false
          return nil
        end
        if fatal then
          local line_num = line:match("^.*%[(%d+)%] >>") or "1"
          line_processed = true
          fatal = nil
          return filename, tonumber(line_num), 1, "error", "Failed to parse"
        end
        local line_num, message = line:match("^line (%d+): (.+)$")
        fatal = line:match("^Failed to parse:$")
        if fatal then
          return nil
        end
        if line_num then
          line_processed = true
          return filename, tonumber(line_num), 1, "warning", message
        end
        return nil
      end
end

lintplus.add("moonscript") {
  filename = "%.moon$",
  procedure = {
    command = lintplus.args_command(
      { "moonc",
        lintplus.args,
        "--lint",
        lintplus.filename },
      "moonscript_args"
    ),
    interpreter = interpreter
  },
}
