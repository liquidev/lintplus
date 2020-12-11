-- Nim plugin for lint+

--- CONFIG ---

-- config.lint.use_nimc: bool
--   switches the linting backend from `nim check` to `nim c`. this can
--   eliminate certain kinds of errors but is less safe due to `nim c` allowing
--   staticExec

-- extra arguments may be passed via a nim.cfg or config.nims.

--- IMPLEMENTATION ---

local lintplus = require "plugins.lint+"

local nullfile
if PLATFORM == "Windows" then
  nullfile = "NUL"
elseif PLATFORM == "Linux" then
  nullfile = "/dev/null"
end

local cmd = "nim --listFullPaths --stdout "
if nullfile == nil or not lintplus.config.use_nimc then
  cmd = cmd.."check $filename"
else
  cmd = cmd.."--errorMax:0 -o:"..nullfile.." c $filename"
end

lintplus.add("nim") {
  filename = "%.nim$",
  procedure = {
    command = lintplus.command(cmd),
    interpreter = lintplus.interpreter {
      hint = "(.-)%((%d+), (%d+)%) Hint: (.+)",
      warning = "(.-)%((%d+), (%d+)%) Warning: (.+)",
      error = "(.-)%((%d+), (%d+)%) Error: (.+)",
      strip = "%s%[%w+%]$",
    },
  },
}
