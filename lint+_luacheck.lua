-- luacheck plugin for lint+

--- CONFIG ---

-- config.lint.luacheck_args: string
--   passes the specified arguments to luacheck

--- IMPLEMENTATION ---

local lintplus = require "plugins.lint+"

lintplus.add("luacheck") {
  filename = "%.lua$",
  procedure = {
    command = lintplus.command(
      "luacheck --formatter visual_studio " ..
      (lintplus.config.luacheck_args or "") ..
      " $filename"
    ),
    interpreter = lintplus.interpreter {
      warning = "(.-)%((%d+),(%d+)%) : warning .-: (.+)",
      error = "(.-)%((%d+),(%d+)%) : error .-: (.+)",
    }
  },
}
