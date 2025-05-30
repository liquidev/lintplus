-- luacheck plugin for lint+

--- CONFIG ---

-- config.lint.luacheck_args: table[string]
--   passes the specified arguments to luacheck

--- IMPLEMENTATION ---

local common = require "core.common"
local lintplus = require "plugins.lintplus"

local config_options = { ",--config", ",--no-config," } --, ",--default-config" }
local function contains_config_options(haystack)
  for _, needle in ipairs(config_options) do
    if nil ~= string.find(haystack, needle, 1, true) then
      return true
    end
  end

  return false
end

local function command(filename)
  local def = {
    "luacheck",
    lintplus.args,
    "--formatter",
    "visual_studio",
    lintplus.filename,
  }
  local luacheck_args = lintplus.config.luacheck_args or {}
  local args_string = "," .. table.concat(luacheck_args, ",") .. ","
  if contains_config_options(args_string) then
    -- User has configured luacheck arguments dealing with config.
    return lintplus.args_command(def, "luacheck_args")(filename)
  end

  -- We need to look for config file up the tree.
  local path = common.dirname(filename)
  local config_path
  while path do
    config_path = string.format("%s%s.luacheckrc", path, PATHSEP)
    if system.get_file_info(config_path) then
      table.insert(def, 2, string.format("--config %s", config_path))
      break
    end
    path = common.dirname(path)
  end
  return lintplus.args_command(def, "luacheck_args")(filename)
end

lintplus.add("luacheck") {
  filename = { "%.lua$", "%.rockspec$" },
  procedure = {
    command = command,
    interpreter = lintplus.interpreter {
      warning = "(.-)%((%d+),(%d+)%) : warning .-: (.+)",
      error = "(.-)%((%d+),(%d+)%) : error .-: (.+)",
    }
  },
}
