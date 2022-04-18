-- luacheck plugin for lint+

--- CONFIG ---

-- config.lint.luacheck_args: table[string]
--   passes the specified arguments to luacheck

--- IMPLEMENTATION ---

local lintplus = require "plugins.lintplus"

lintplus.add("luacheck") {
  filename = "%.lua$",
  procedure = {
    command = lintplus.args_command(
      { "luacheck",
        lintplus.args,
        "--formatter",
        "visual_studio",
        lintplus.filename },
      "luacheck_args"
    ),
    interpreter = lintplus.interpreter {
      warning = "(.-)%((%d+),(%d+)%) : warning .-: (.+)",
      error = "(.-)%((%d+),(%d+)%) : error .-: (.+)",
    }
  },
}
