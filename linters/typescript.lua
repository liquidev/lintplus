-- Typescript lint plugin for lint+

--- CONFIG ---

--- __Site__: https://github.com/eslint/eslint
--- __Installation__: `npm install -g eslint typescript --save-dev`
--- __Local Config__: [optional] npx eslint --init

--- IMPLEMENTATION ---
local lintplus = require "plugins.lintplus"

lintplus.add("typescript") {
  filename = "%.ts$",
  procedure = {
    
    command = lintplus.command(
      { 
        "eslint",
        "--rule", "{}"
        "--format", "visualstudio",
        lintplus.filename
      }
    ),
    
    interpreter = lintplus.interpreter ({
      warning = "^(.+)%((%d+),(%d+)%)%: warning%s?[^:]*: (.+)$",
      error = "^(.+)%((%d+),(%d+)%)%: error%s?[^:]*: (.+)$"
    }),
  }
}
