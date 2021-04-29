-- lite-xl 1.16

-- linter compatibility module for lint+
-- this module simply defines a linter.add_language function for compatibility
-- with the existing linter module.
-- note that linter modules are not capable of using all of lint+'s
-- functionality: namely, they cannot use the four available levels of severity.
-- all messages will have the warning severity level.

local lintplus = require "plugins.lintplus"

local linter = {}
local name_counter = 0

function linter.add_language(t)
  lintplus.add("compat.linter"..name_counter) {
    filename = t.file_patterns,
    procedure = {
      command = lintplus.command(
        t.command
          :gsub("%$FILENAME", "$filename")
          :gsub("%$ARGS", table.concat(t.args, ' '))
      ),

      -- can't use the lintplus interpreter simply because it doesn't work
      -- exactly as linter does
      interpreter = function (filename, line)
        local yielded_message = false
        return function ()
          if yielded_message then return nil end
          local ln, column, message = line:match(t.warning_pattern)
          if ln then
            -- we return the original filename to show all warnings
            -- because... say it with me... that's how linter works!!
            yielded_message = true
            return filename, tonumber(ln), tonumber(column), "warning", message
          end
        end
      end,
    },
  }
  name_counter = name_counter + 1
end


return linter
