-- liteipc - async IPC for lite

local fs = require "plugins.lintplus.fsutil"

local liteipc_loader = {}

-- a fallback to support io.popen in case the user didn't install the
-- async process runtime
function liteipc_loader.sync()

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
    -- this solution with pushd and popd feels fragile af but i don't know of
    -- any better way to make popen behave like i need it to
    if cwd ~= nil then os.execute("pushd "..quote_shell(cwd)) end
    -- we need to redirect stderr to stdout
    local escaped_command = escape_args(args).." 2>&1"
    if os.getenv("LINTPLUS_LITEIPC_DEBUG_SYNC_MODE_ARGS") then
      print(escaped_command)
    end
    local proc = setmetatable({
      popen = io.popen(escaped_command, 'r'),
    }, Process)
    if cwd ~= nil then os.execute("popd") end
    return proc
  end

  function Process.poll(self, callback)
    for line in self.popen:lines() do
      callback(line)
    end

    local ok, exit = self.popen:close()
    local code = ok and 1 or 0
    return exit, code
  end

  return liteipc

end

-- this is a huge hack to get liteipc_native.so loading to work but it should be
-- functional under most circumstances. at least i hope so
function liteipc_loader.async()
  local dir_sep, path_sep, sub = package.config:match("(.-)\n(.-)\n(.-)\n")
  local this_file = debug.getinfo(1, 'S').source

  local this_dir = fs.parent_directory(this_file):match("[@=](.*)")
  package.cpath =
    package.cpath .. path_sep .. this_dir .. dir_sep .. sub .. ".so"

  return require "liteipc_native"
end

return liteipc_loader
