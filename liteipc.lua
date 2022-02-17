-- liteipc - async IPC for lite

local liteipc = {}

local Process = {}
Process.__index = Process

function liteipc.start_process(args, cwd)
  local proc = setmetatable({
    popen = process.start(args, {cwd = cwd})
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
