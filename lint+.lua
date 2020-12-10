-- lint+ - an improved linter for lite
-- copyright (C) lqdev, 2020
-- licensed under the MIT license


--- INTRODUCTION ---

-- a few reasons for why this and not the existing linter plugin:
-- · it can only show warnings
-- · it doesn't show error messages after lines, you have to hover over the
--   warning first
-- · it spam-runs the linter command, but Nim (and possibly other languages)
--   compiles relatively slowly
-- · it is not async, so when the lint command takes its sweet time your editor
--   freezes completely
-- · it doesn't display the first or current error message on the status view
-- this linter aims to fix any and all of the above problems.
-- however, there are still some issues with it:
-- · despite its asyncness, it still lags your editor a tiny bit when linting.
--   this cannot be fixed easily due to the fact that io.popen operations are
--   blocking, so if the lint command doesn't output anything for a while the
--   linter thread will stall until it gets some output
-- · due to the fact that it shows the most important message at the end of the
--   line, displaying more than one message per line is really difficult with
--   the limited horizontal real estate, so it can only display one message per
--   line. usually this isn't a problem though
-- · it is unable to display the offending token, simply because linter error
--   messages do not contain that information. it will highlight the line and
--   column, though.

--- CONFIG ---

-- config.lint.kind_pretty_names: {hint: string, warning: string, error: string}
--   defines the pretty names for displaying messages on the status view

--- CREATING LINTERS ---

-- the lint+ API is fairly simple:
--
--   -- the following example is a Nim linter
--   local lintplus = require "plugins.lint+"
--   lintplus.add {
--     filename = "%.nim$",
--     -- the linting procedure is a special table containing info on how to
--     -- run the lint command and interpret its output
--     procedure = {
--       command = lintplus.command "nim --listFullPaths --stdout $filename",
--       interpreter = lintplus.interpreter {
--         -- for this example, we use the general hint/warning/error
--         -- interpreter. this field is a function that gets called for each
--         -- line of the lint command's output
--         hint = "(.-)%((%d+), (%d+)%) Hint: (.+)",
--         warning = hint = "(.-)%((%d+), (%d+)%) Warning: (.+)",
--         error = "(.-)%((%d+), (%d+)%) Error: (.+)",
--         -- we can also add a strip action. this will remove the specified
--         -- pattern from the output
--         strip = "%s%[%w+%]$",
--       }
--     },
--   }


--- STATIC CONFIG ---

-- note that due to the nature of how this linter displays errors,
-- messages with lower priorities get overwritten by messages with higher
-- priorities
local kind_priority = {
  hint = 0,
  warning = 1,
  error = 2,
}

local default_kind_pretty_names = {
  hint = "H",
  warning = "W",
  error = "E",
}


--- IMPLEMENTATION ---


local command = require "core.command"
local config = require "core.config"
local core = require "core"
local style = require "core.style"

local Doc = require "core.doc"
local DocView = require "core.docview"
local StatusView = require "core.statusview"


local lint = {}
lint.index = {}


function lint.get_linter_for_doc(doc)
  if not doc.filename then
    return nil
  end

  local file = system.absolute_path(doc.filename)
  for _, linter in pairs(lint.index) do
    if file:match(linter.filename) then
      return linter
    end
  end
end


local function process_line(doc, linter, line)
  local lp = doc.__lintplus
  local file = system.absolute_path(doc.filename)
  local ok, outfile, lineno, columnno, kind, message =
    linter.procedure.interpreter(line)

  if not ok then return end
  if outfile ~= file then return end

  if lp.messages[lineno] == nil or
     kind_priority[lp.messages[lineno].kind] < kind_priority[kind]
  then
    lp.messages[lineno] = {
      kind = kind,
      column = columnno,
      message = message,
    }
  end
end


function lint.check(doc)
  if doc.filename == nil then
    return
  end

  local linter = lint.get_linter_for_doc(doc)
  if linter == nil then
    core.error("no linter available for the given filetype")
    return
  end

  doc.__lintplus = {
    line_count = #doc.lines
  }
  local lp = doc.__lintplus
  lp.messages = {}

  core.add_thread(function ()
    local file = system.absolute_path(doc.filename)
    local lc = io.popen(linter.procedure.command(file), 'r')
    local line_buffer = {}

    for char in lc:lines(1) do
      if char == '\n' then
        process_line(doc, linter, table.concat(line_buffer))
        line_buffer = {}
        coroutine.yield(0)
      elseif char == '\r' then -- nop
      else
        table.insert(line_buffer, char)
        -- this slows the linting process a bit but should help reduce the
        -- lagginess due to blocking I/O
        if #line_buffer % 32 == 0 then
          coroutine.yield(0)
        end
      end
    end
  end)
end


-- inject hooks to Doc.insert and Doc.remove to shift messages around
local Doc_insert = Doc.insert
function Doc:insert(line, column, text)
  Doc_insert(self, line, column, text)

  if line == math.huge then return end

  local lp = self.__lintplus
  if lp ~= nil and #self.lines > lp.line_count then
    local shift = #self.lines - lp.line_count
    -- this sucks
    for i = #self.lines, line, -1 do
      if lp.messages[i] ~= nil then
        lp.messages[i + shift] = lp.messages[i]
        lp.messages[i] = nil
      end
    end
    lp.line_count = #self.lines
  end
end


local Doc_remove = Doc.remove
function Doc:remove(line1, column1, line2, column2)
  Doc_remove(self, line1, column1, line2, column2)

  if line2 == math.huge then return end

  local lp = self.__lintplus
  if line1 ~= line2 and lp ~= nil then
    local shift = lp.line_count - #self.lines
    -- remove all messages in this range
    local min, max = math.min(line1, line2), math.max(line1, line2)
    for i = min, max do
      lp.messages[i] = nil
    end
    -- shift all of them up
    for i = min, #self.lines do
      if lp.messages[i] ~= nil then
        lp.messages[i - shift] = lp.messages[i]
        lp.messages[i] = nil
      end
    end
    lp.line_count = #self.lines
  end
end


local DocView_draw_line_text = DocView.draw_line_text
function DocView:draw_line_text(idx, x, y)
  DocView_draw_line_text(self, idx, x, y)

  local lp = self.doc.__lintplus
  if lp == nil then return end

  local yy = y + self:get_line_text_y_offset() + self:get_line_height() - 1
  local msg = lp.messages[idx]
  if msg == nil then return end

  local font = self:get_font()
  local color = style.syntax["literal"]
  if style.lint ~= nil then
    color = style.lint[msg.kind]
  end
  local colx = font:get_width(self.doc.lines[idx]:sub(1, msg.column - 1))
  local w = font:get_width('w')

  local msgx = font:get_width(self.doc.lines[idx]) + w * 3
  local text = msg.message
  local linew = msgx + font:get_width(text)
  for px = x + colx, x + linew, 2 do
    renderer.draw_rect(px, yy, 1, 1, color)
  end
  renderer.draw_text(font, msg.message, x + msgx, y, color)
end


local function table_add(t, d)
  for _, v in ipairs(d) do
    table.insert(t, v)
  end
end


local function kind_pretty_name(kind)
  return (config.kind_pretty_names or default_kind_pretty_names)[kind]
end


local StatusView_get_items = StatusView.get_items
function StatusView:get_items()
  local left, right = StatusView_get_items(self)

  if getmetatable(core.active_view) == DocView and
     lint.get_linter_for_doc(core.active_view.doc)
  then
    local doc = core.active_view.doc
    local line1, _, line2, _ = doc:get_selection()
    local lp = doc.__lintplus
    if lp then
      if lp.messages[line1] and line1 == line2 then
        local msg = lp.messages[line1]
        table_add(left, {
          style.dim, self.separator2,
          kind_pretty_name(msg.kind), ": ",
          style.text, msg.message,
        })
      else
        local line, message = math.huge, nil
        for ln, msg in pairs(lp.messages) do
          if msg.kind == "error" and ln < line  then
            line, message = ln, msg
          end
        end
        if message ~= nil then
          table_add(left, {
            style.dim, self.separator2,
            "line ", tostring(line), " ", kind_pretty_name(message.kind), ": ",
            style.text, message.message,
          })
        end
      end
    end
  end

  return left, right
end


command.add(DocView, {
  ["lint+:check"] = function ()
    lint.check(core.active_view.doc)
  end
})


--- LINTER PLUGINS ---

function lint.add(name)
  return function (linter)
    lint.index[name] = linter
  end
end


--- SETUP ---

lint.setup = {}

function lint.setup.lint_on_doc_load()

  local Doc_load = Doc.load
  function Doc:load(...)
    Doc_load(self, ...)
    if lint.get_linter_for_doc(self) ~= nil then
      lint.check(self)
    end
  end

end

function lint.setup.lint_on_doc_save()

  local Doc_save = Doc.save
  function Doc:save(...)
    Doc_save(self, ...)
    if lint.get_linter_for_doc(self) ~= nil then
      lint.check(self)
    end
  end

end


--- LINTER CREATION UTILITIES ---

local pattern_magics = {
  ['^'] = true,
  ['$'] = true,
  ['('] = true,
  [')'] = true,
  ['%'] = true,
  ['.'] = true,
  ['['] = true,
  [']'] = true,
  ['*'] = true,
  ['+'] = true,
  ['-'] = true,
  ['?'] = true,
}

local function escape_pattern(patt)
  local result = {}
  for i = 1, #patt do
    local c = patt:sub(i, i)
    local e = c
    if pattern_magics[c] then
      e = '%'..c
    end
    table.insert(result, e)
  end
  return table.concat(result)
end


function lint.command(cmd)
  return function (filename)
    return cmd:gsub('$filename', filename)
  end
end


function lint.interpreter(i)
  local patterns = {
    hint = i.hint,
    warning = i.warning,
    error = i.error,
  }
  local strip_pattern = i.strip

  return function (line)
    for kind, patt in pairs(patterns) do
      assert(
        type(patt) == "string",
        "lint+: interpreter pattern must be a string")
      local ok, _, file, line, column, message = line:find(patt)
      if ok then
        if strip_pattern then
          message = message:gsub(strip_pattern, "")
        end
        return true, file, tonumber(line), tonumber(column), kind, message
      end
    end
    return false
  end
end


if type(config.lint) == "table" then
  lint.config = config.lint
else
  lint.config = {}
end


--- END ---

return lint
