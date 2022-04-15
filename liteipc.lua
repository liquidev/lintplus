-- liteipc - async IPC for lite

local liteipc = {}

local Process = {}
Process.__index = Process

function liteipc.start_process(args, cwd)
  local proc = setmetatable({
    popen = process.start(args, {cwd = cwd}),
    read_from = ""
  }, Process)
  return proc
end

function Process.poll(self, callback)
  local line = ""
  local read = nil

  while self.read_from == "" and self.popen:returncode() == nil do
    local stderr = self.popen:read_stderr(1)
    local stdout = self.popen:read_stdout(1)
    local out = nil
    if stderr ~= nil and stderr ~= "" then
      out = stderr
      self.read_from = "stderr"
    elseif stdout ~= nil and stdout ~= "" then
      out = stdout
      self.read_from = "stdout"
    end
    if out ~= nil then
      if out ~= "\n" then
        line = line .. out
      end
      break
    end
  end

  while true do
    if self.read_from == "stderr" then
      read = self.popen:read_stderr(1)
    else
      read = self.popen:read_stdout(1)
    end
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
