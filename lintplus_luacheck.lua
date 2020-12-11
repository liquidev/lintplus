-- luacheck plugin for lint+

--- CONFIG ---

-- config.lint.luacheck_args: string
--   passes the specified arguments to luacheck

--- IMPLEMENTATION ---

local lintplus = require "plugins.lintplus"

lintplus.add("luacheck") {
  filename = "%.lua$",
  procedure = {
    command = lintplus.args_command(
      "luacheck $args --formatter visual_studio $filename",
      "luacheck_args"
    ),
    interpreter = lintplus.interpreter {
      warning = "(.-)%((%d+),(%d+)%) : warning .-: (.+)",
      error = "(.-)%((%d+),(%d+)%) : error .-: (.+)",
    }
  },
}
