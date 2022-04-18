-- Zig plugin for lint+

--- CONFIG ---

-- config.lint.zig_mode: "ast-check" | "build"
--   changes the linting mode. ast-check is a quick'n'dirty check (default),
--   build compiles the tests in a file (but does not run them).
-- config.lint.zig_args: table[string]
--   passes the given table of arguments to zig test. this does not have any
--   effect in "ast-check" mode.

--- IMPLEMENTATION ---

local core = require "core"
local lintplus = require "plugins.lintplus"

local mode = lintplus.config.zig_mode or "ast-check"
if mode ~= "ast-check" and mode ~= "build" then
  core.error("lint+/zig: invalid zig_mode '%s'. "..
             "available modes: 'ast-check', 'build'")
  return
end

local command
if mode == "ast-check" then
  command = lintplus.command {
    "zig",
    "ast-check",
    "--color", "off",
    lintplus.filename
  }
elseif mode == "build" then
  command = lintplus.args_command({
    "zig",
    "test",
    "--color", "off",
    "-fno-emit-bin",
    lintplus.args,
    lintplus.filename
  }, "zig_args")
end


lintplus.add("zig") {
  filename = "%.zig$",
  procedure = {
    command = command,
    interpreter = lintplus.interpreter {
      hint = "(.-):(%d+):(%d+): note: (.+)",
      error = "(.-):(%d+):(%d+): error: (.+)",
      warning = "(.-):(%d+):(%d+): warning: (.+)",
    }
  },
}
