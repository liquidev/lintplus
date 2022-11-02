-- v plugin for lint+

--- INSTALLATION ---
-- In order to use this linter, please ensure you have the v binary
-- in your $PATH. For installation notes please see
-- https://github.com/vlang/v/blob/master/doc/docs.md#installing-v-from-source

--- CONFIG ---

-- config.lint.v_mode: "check" | "check-syntax"
--   changes the linting mode. check scans, parses, and checks the files 
--   without compiling the program (default),
--   check-syntax only scan and parse the files, but then stops. 
--   Useful for very quick syntax checks.
-- config.lint.v_args: table[string]
--   passes the given arguments to v.

--- IMPLEMENTATION ---

local core = require "core"
local lintplus = require "plugins.lintplus"

local mode = lintplus.config.v_mode or "check"
if mode ~= "check" and mode ~= "check-syntax" then
  core.error("lint+/v: invalid v_mode '%s'. "..
    "available modes: 'check', 'check-syntax'")
  return
end

local command
if mode == "check" then
  command = lintplus.command {
    "v",
    "-check",
    "-nocolor",
    "-shared",
    "-message-limit", "-1",
    lintplus.args,
    lintplus.filename
  }
elseif mode == "check-syntax" then
  command = lintplus.args_command({
    "v",
    "-check-syntax",
    "-nocolor",
    "-shared",
    "-message-limit", "-1",
    lintplus.args,
    lintplus.filename
  }, "v_args")
end

lintplus.add("v") {
  filename = "%.v$",
  syntax = {
    "V",
    "v",
    "Vlang",
    "vlang",
  },
  procedure = {
    command = command,
    interpreter = lintplus.interpreter {
      error = "(.*):(%d+):(%d+): error: (.+)",
      warning = "(.*):(%d+):(%d+): warning: (.+)",
    },
  },
}
