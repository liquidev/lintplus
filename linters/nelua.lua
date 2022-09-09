-- Nelua plugin for lint+

--- CONFIG ---

-- config.lint.nelua_mode: "analyze" | "lint"
--   changes the linting mode, "analyze" (default) does a complete checking,
--   while "lint" only checks for syntax errors.

--- IMPLEMENTATION ---

local core = require 'core'
local lintplus = require 'plugins.lintplus'

local mode = lintplus.config.nelua_mode or "analyze"

if mode ~= "analyze" and mode ~= "lint" then
  core.error("lint+/nelua: invalid nelua_mode '%s'. Available modes: 'analyze', 'lint'", mode)
  mode = "lint"
end

local command = lintplus.command {
  'nelua',
  '--no-color',
  '--'..mode,
  lintplus.filename
}

lintplus.add 'nelua' {
  filename = '%.nelua$',
  procedure = {
    command = command,
    interpreter = lintplus.interpreter {
      error = "(.-):(%d+):(%d+):.-error: (.+)"
    },
  },
}

