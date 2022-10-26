-- shellcheck plugin for lint+

--- INSTALLATION ---
-- In order to use this linter, please ensure you have the shellcheck binary
-- in your path. For installation notes please see
-- https://github.com/koalaman/shellcheck#user-content-installing

--- CONFIG ---

-- config.lint.shellcheck_args: table[string]
--   passes the given arguments to shellcheck.

--- IMPLEMENTATION ---

local lintplus = require "plugins.lintplus"

lintplus.add("shellcheck") {
  filename = "%.sh$",
  syntax = {
    "Shell script",
    "shellscript",
    "bashscript",
    "Bash script",
    "Bash",
    "bash",
  },
  procedure = {
    command = lintplus.args_command(
      { "shellcheck",
        "--format=gcc",
        lintplus.args,
        lintplus.filename
      },
      "shellcheck_args"
    ),
    interpreter = lintplus.interpreter {
      info = "(.*):(%d+):(%d+): note: (.+)",
      error = "(.*):(%d+):(%d+): error: (.+)",
      warning = "(.*):(%d+):(%d+): warning: (.+)",
    }
  },
}
