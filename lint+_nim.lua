-- Nim plugin for lint+

--- CONFIG ---

-- config.lint.use_nimcheck
--   switches the linting backend from `nim c` to `nim check`


--- IMPLEMENTATION ---

local lintplus = require "plugins.lint+"

local nullfile
if PLATFORM == "Windows" then
  nullfile = "NUL"
elseif PLATFORM == "Linux" then
  nullfile = "/dev/null"
end

local cmd = "nim --listFullPaths --stdout "
if nullfile == nil or lintplus.config.use_nimcheck then
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
