-- liteipc - async IPC for lite

local core = require "core"
local fs = require "plugins.lintplus.fsutil"

local liteipc = {}

local Process = {}
Process.__index = Process

-- based on nim stdlib: os.quoteShellWindows, os.quoteShellPosix

local quote_shell
if PLATFORM == "Windows" then
  quote_shell = function (arg)
    local need_quote = #arg == 0 or arg:match("[ \t]") ~= nil
    local result = ""
    local backslash_buffer = {}
    if need_quote then
      result = result .. '"'
    end
    for i = 1, #arg do
      local c = arg:sub(i, i)
      if c == '\\' then
        table.insert(backslash_buffer, c)
      elseif c == '"' then
        local buffer_concat = table.concat(backslash_buffer)
        result = result ..
          buffer_concat .. buffer_concat .. -- wtf?
          '\\"'
        backslash_buffer = {}
      else
        if #backslash_buffer > 0 then
          result = result .. table.concat(backslash_buffer)
          backslash_buffer = {}
        end
        result = result .. c
      end
    end
    if need_quote then
      result = result .. '"'
    end
    return result
  end
else
  quote_shell = function (arg)
    if #arg == 0 then
      return "''"
    end
    local is_safe = arg:match("[^%%%+%-%./_:=@0-9a-zA-Z]") == nil
    if is_safe then
      return arg
    else
      return "'" .. arg:gsub("'", "'\"'\"'") .. "'"
    end
  end
end

local function escape_args(args)
  local result = {}
  for _, arg in ipairs(args) do
    table.insert(result, quote_shell(arg))
  end
  return table.concat(result, ' ')
end

function liteipc.start_process(args, cwd)
  local escaped_command = escape_args(args)
  if os.getenv("LINTPLUS_LITEIPC_DEBUG_SYNC_MODE_ARGS") then
    print(escaped_command)
  end
  local proc = setmetatable({
    popen = process.start(args)
  }, Process)
  return proc
end

function Process.poll(self, callback)
  local line = ""
  local read = nil
  while true do
    read = self.popen:read_stderr(1)
    if read == nil or read == "\n" then
      if line ~= "" then callback(line) end
      break
    else
      line = line .. read
    end
  end
  if not self.popen:running() and read == nil then
    local exit = "exit"
    local retcode = self.popen:returncode()
    if retcode ~= 1 and retcode ~= 0 then
      exit = "signal"
    end
    local errmsg = process.strerror(retcode)
    return exit, retcode, errmsg
  end
  return nil, nil, nil
end

return liteipc
