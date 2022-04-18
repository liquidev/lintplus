-- Nim plugin for lint+

--- CONFIG ---

-- config.lint.use_nimc: bool
--   switches the linting backend from `nim check` to `nim c`. this can
--   eliminate certain kinds of errors but is less safe due to `nim c` allowing
--   staticExec
-- config.lint.nim_args: string
--   passes the specified arguments to the lint command.
--   extra arguments may also be passed via a nim.cfg or config.nims.

--- IMPLEMENTATION ---

local lintplus = require "plugins.lintplus"

local nullfile
if PLATFORM == "Windows" then
  nullfile = "NUL"
elseif PLATFORM == "Linux" then
  nullfile = "/dev/null"
end

local cmd = {
  "nim",
  "--listFullPaths",
  "--stdout",
  lintplus.args,
}
if nullfile == nil or not lintplus.config.use_nimc then
  table.insert(cmd, "check")
else
  table.insert(cmd, "-o:" .. nullfile)
  table.insert(cmd, "c")
end
table.insert(cmd, lintplus.filename)

lintplus.add("nim") {
  filename = "%.nim$",
  procedure = {
    command = lintplus.args_command(cmd, "nim_args"),
    interpreter = lintplus.interpreter {
      hint = "(.-)%((%d+), (%d+)%) Hint: (.+)",
      warning = "(.-)%((%d+), (%d+)%) Warning: (.+)",
      error = "(.-)%((%d+), (%d+)%) Error: (.+)",
      strip = "%s%[%w+%]$",
    },
  },
}
