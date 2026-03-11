-- C++ cppcheck linter for lint+

local lintplus = require "plugins.lintplus"
local core = require "core"

lintplus.add("cppcheck") {
	filename = "%.cpp$",
	procedure = {
		command = lintplus.args_command(
			{
			"cppcheck",
			"--enable=all",
			"--inline-suppr",
			"--std=c++20",
			"--check-level=normal",
			"--suppress=missingIncludeSystem",
			"--quiet",
			lintplus.args,
			lintplus.filename
			},
		"cppcheck_args"
		),
		interpreter = function (filename, line, context)
			local line_processed = false
			return function ()
				if line_processed then return nil end
				local file, line_num, column_num, severity, message, code = line:match(
					"^(.-):(%d+):(%d+): (%w+): (.+) %[(.-)%]"
				)
				if line_num then
					line_processed = true
					local kind
					if severity == "error" then
						kind = "error"
					elseif severity == "warning" then
						kind = "warning"
					else
						kind = "hint"
					end
					return file, tonumber(line_num), tonumber(column_num), kind, message .. " [" .. code .. "]"
				end
			end
		end
	}
}
