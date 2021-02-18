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
          backslash_buffer.add(c)
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

  function liteipc.start_process(args)
    local proc = setmetatable({
      popen = io.popen(escape_args(args), 'r'),
    }, Process)
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
  if PLATFORM == "Windows" then
    this_file = this_file:gsub('\\', '/')
  end

  local function parent_directory(path)
    path = path:match("^(.-)/*$")
    local last_slash_pos = -1
    for i = #path, 1, -1 do
      if path:sub(i, i) == '/' then
        last_slash_pos = i
        break
      end
    end
    if last_slash_pos < 0 then
      return nil
    end
    return path:sub(1, last_slash_pos - 1)
  end

  local this_dir = parent_directory(this_file):match("[@=](.*)")
  package.cpath =
    package.cpath .. path_sep .. this_dir .. dir_sep .. sub .. ".so"

  return require "liteipc_native"
end

return liteipc_loader
