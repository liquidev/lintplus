-- lint+ - an improved linter for lite
-- copyright (C) lqdev, 2020
-- licensed under the MIT license


--- STATIC CONFIG ---


-- note that due to the nature of how this linter displays errors,
-- messages with lower priorities get overwritten by messages with higher
-- priorities
local kind_priority = {
  info = -1,
  hint = 0,
  warning = 1,
  error = 2,
}

local default_kind_pretty_names = {
  info = "I",
  hint = "H",
  warning = "W",
  error = "E",
}


--- IMPLEMENTATION ---


local command = require "core.command"
local common = require "core.common"
local config = require "core.config"
local core = require "core"
local style = require "core.style"

local Doc = require "core.doc"
local DocView = require "core.docview"
local StatusView = require "core.statusview"

local liteipc_loader = require "plugins.lintplus.liteipc"
local liteipc = liteipc_loader.sync()


local lint = {}
lint.fs = require "plugins.lintplus.fsutil"


lint.index = {}
lint.messages = {}
lint.running = 0


function lint.get_linter_for_doc(doc)
  if not doc.filename then
    return nil
  end

  local file = system.absolute_path(doc.filename)
  for name, linter in pairs(lint.index) do
    if common.match_pattern(file, linter.filename) then
      return linter, name
    end
  end
end


-- unused for now, because it was a bit buggy
local function clear_messages(linter)
  local clear = {}
  for filename, _ in pairs(lint.messages) do
    if common.match_pattern(filename, linter.filename) then
      table.insert(clear, filename)
    end
  end
  for _, filename in ipairs(clear) do
    lint.messages[filename] = nil
  end
end


local function add_message(filename, line, column, kind, message, rail)
  local file_messages = lint.messages[filename]
  local lines, rails = file_messages.lines, file_messages.rails
  lines[line] = lines[line] or {}
  if rail ~= nil then
    rails[rail] = rails[rail] or {}
    table.insert(rails[rail], {
      line = line,
      column = column,
      kind = kind,
    })
  end
  table.insert(lines[line], {
    column = column,
    kind = kind,
    message = message,
    rail = rail,
  })
end


local function process_line(doc, linter, line, context)
  local file = system.absolute_path(doc.filename)

  local had_messages = false

  local iterator = linter.procedure.interpreter(file, line, context)
  if iterator == "bail" then return iterator end

  for outfile, lineno, columnno, kind, message, rail in iterator do
    if outfile == file then -- TODO: support project-wide errors
      assert(type(outfile) == "string")
      assert(type(lineno) == "number")
      assert(type(columnno) == "number")
      assert(type(kind) == "string")
      assert(type(message) == "string")
      assert(rail == nil or type(rail) == "number")

      add_message(outfile, lineno, columnno, kind, message, rail)
      core.redraw = true
    end
  end

  return had_messages
end


local LintContext = {}
LintContext.__index = LintContext


function LintContext:gutter_rail()
  self._rails = self._rails + 1
  return self._rails
end


function LintContext:gutter_rail_count()
  return self._rails
end


local function compare_message_priorities(a, b)
  return kind_priority[a.kind] > kind_priority[b.kind]
end

local function compare_messages(a, b)
  return a.column > b.column or compare_message_priorities(a, b)
end

local function compare_rail_messages(a, b)
  return a.line < b.line or compare_message_priorities(a, b)
end

function lint.check(doc)
  if doc.filename == nil then
    return
  end

  local linter, linter_name = lint.get_linter_for_doc(doc)
  if linter == nil then
    core.error("no linter available for the given filetype")
    return
  end

  local filename = system.absolute_path(doc.filename)
  local context = setmetatable({
    _rails = 0,
  }, LintContext)

  doc.__lintplus = {
    line_count = #doc.lines,
  }
--   clear_messages(linter)
  lint.messages[filename] = {
    context = context,
    lines = {},
    rails = {},
  }

  local function report_error(msg)
    core.error(
      "lint+/" .. linter_name .. ": " ..
      doc.filename .. ": " .. msg)
  end

  local process = liteipc.start_process(linter.procedure.command(filename))
  core.add_thread(function ()
    lint.running = lint.running + 1
    -- poll the process for lines of output
    while true do
      local exit, code = process:poll(function (line)
        process_line(doc, linter, line, context)
      end)
      if exit ~= nil then
        -- the only OK exit condition is ("exit", _)
        -- the exit code is ignored because the linter is allowed to return an
        -- error
        if exit == "signal" then
          report_error("linter exited with signal " .. code)
        elseif exit == "other" then
          report_error("linter exited with error code " .. code)
        elseif exit == "undetermined" then
          report_error("linter exited with an undetermined error")
        end
        break
      end
      coroutine.yield(0)
    end
    -- after reading some lines, sort messages by priority in all files
    -- and sort rail connections by line number
    for _, file_messages in pairs(lint.messages) do
      for _, messages in pairs(file_messages.lines) do
        table.sort(messages, compare_messages)
      end
      for _, rail in pairs(file_messages.rails) do
        table.sort(rail, compare_rail_messages)
      end
      file_messages.rails_sorted = true
    end
    lint.running = lint.running - 1
  end)
end


-- inject hooks to Doc.insert and Doc.remove to shift messages around

local Doc_insert = Doc.insert
function Doc:insert(line, column, text)
  Doc_insert(self, line, column, text)

  if self.filename == nil then return end
  if line == math.huge then return end

  local filename = system.absolute_path(self.filename)
  local file_messages = lint.messages[filename]
  local lp = self.__lintplus
  if file_messages == nil or lp == nil then return end
  if #self.lines == lp.line_count then return end

  -- shift line messages downwards
  local shift = #self.lines - lp.line_count
  local lines = file_messages.lines
  for i = #self.lines, line, -1 do
    if lines[i] ~= nil then
      lines[i + shift] = lines[i]
      lines[i] = nil
    end
  end

  -- shift rails downwards
  local rails = file_messages.rails
  for _, rail in ipairs(rails) do
    for _, message in ipairs(rail) do
      if message.line >= line then
        message.line = message.line + shift
      end
    end
  end

  -- update line count
  lp.line_count = #self.lines
end


local Doc_remove = Doc.remove
function Doc:remove(line1, column1, line2, column2)
  Doc_remove(self, line1, column1, line2, column2)

  if line1 == line2 then return end
  if line2 == math.huge then return end
  if self.filename == nil then return end

  local filename = system.absolute_path(self.filename)
  local file_messages = lint.messages[filename]
  local lp = self.__lintplus
  if file_messages == nil or lp == nil then return end

  local shift = lp.line_count - #self.lines
  local lines = file_messages.lines

  -- remove all messages in this range
  local min, max = math.min(line1, line2), math.max(line1, line2)
  for i = min, max do
    lines[i] = nil
  end

  -- shift all line messages up
  for i = min, #self.lines do
    if lines[i] ~= nil then
      lines[i - shift] = lines[i]
      lines[i] = nil
    end
  end

  -- remove all rail messages in this range
  local rails = file_messages.rails
  for _, rail in ipairs(rails) do
    local remove_indices = {}
    for i, message in ipairs(rail) do
      if message.line >= min and message.line <= max then
        table.insert(remove_indices, i)
      elseif message.line > min then
        message.line = message.line - shift
      end
    end
    for i = #remove_indices, 1, -1 do
      table.remove(rail, remove_indices[i])
    end
  end

  lp.line_count = #self.lines
end


-- inject rendering routines

local renderutil = require "plugins.lintplus.renderutil"

local function rail_width()
  return common.round(style.padding.x / 2)
end

local function rail_spacing()
  return common.round(rail_width() / 4)
end

local DocView_get_gutter_width = DocView.get_gutter_width
function DocView:get_gutter_width()
  local extra_width = 0
  if self.doc.filename ~= nil then
    local file_messages = lint.messages[system.absolute_path(self.doc.filename)]
    if file_messages ~= nil then
      local rail_count = file_messages.context._rails
      extra_width = rail_count * (rail_width() + rail_spacing())
    end
  end
  return DocView_get_gutter_width(self) + extra_width
end


local function get_gutter_rail_x(dv, index)
  return
    dv.position.x + dv:get_gutter_width() -
    (rail_width() + rail_spacing()) * index + rail_spacing()
end

local function get_message_group_color(messages)
  if style.lint ~= nil then
    return style.lint[messages[1].kind]
  else
    return style.accent
  end
end

local function draw_gutter_rail(dv, index, messages)
  local rail = messages.rails[index]
  if #rail < 2 then return end

  local first_message = rail[1]
  local last_message = rail[#rail]

  local x = get_gutter_rail_x(dv, index)
  local rw = rail_width()
  local _, start_y = dv:get_line_screen_position(first_message.line)
  local _, fin_y = dv:get_line_screen_position(last_message.line)
  local lh = dv:get_line_height()
  start_y = start_y + lh + rw - 1
  fin_y = fin_y + lh - rw

  -- connect with lens
  local line_x = x + rw
  for i, message in ipairs(rail) do
    -- connect with lens
    local lx, ly = dv:get_line_screen_position(message.line)
    local line_messages = messages.lines[message.line]
    local column = line_messages[1].column
    local message_left = line_messages[1].message:sub(1, column - 1)
    local line_color = get_message_group_color(line_messages)
    local xoffset = (x + rw) % 2
    ly = ly + lh - 1
    local line_w = dv:get_font():get_width(message_left) - line_x + lx
    renderutil.draw_dotted_line(x + rw + xoffset, ly, line_w, 'x', line_color)
    -- draw curve
    local _, y = dv:get_line_screen_position(message.line)
    y = y + lh - rw + (i == 1 and rw - 1 or 0)
    renderutil.draw_quarter_circle(x, y, rw, style.accent, i > 1)
  end

  -- draw vertical part
  local height = fin_y - start_y + 1
  renderer.draw_rect(x, start_y, 1, height, style.accent)

end

local DocView_draw = DocView.draw
function DocView:draw()
  DocView_draw(self)

  local filename = self.doc.filename
  if filename == nil then return end
  filename = system.absolute_path(filename)
  local messages = lint.messages[filename]
  if messages == nil or not messages.rails_sorted then return end
  local rails = messages.rails

  local pos, size = self.position, self.size
  core.push_clip_rect(pos.x, pos.y, size.x, size.y)
  for i = 1, #rails do
    draw_gutter_rail(self, i, messages)
  end
  core.pop_clip_rect()
end


local lens_underlines = {

  blank = function () end,

  solid = function (x, y, width, color)
    renderer.draw_rect(x, y, width, 1, color)
  end,

  dots = function (x, y, width, color)
    renderutil.draw_dotted_line(x, y, width, 'x', color)
  end,

}

local function draw_lens_underline(x, y, width, color)
  local lens_style = config.lint.lens_style or "dots"
  if type(lens_style) == "string" then
    local fn = lens_underlines[lens_style] or lens_underlines.blank
    fn(x, y, width, color)
  elseif type(lens_style) == "function" then
    lens_style(x, y, width, color)
  end
end

local function get_or_default(t, index, default)
  if t ~= nil and t[index] ~= nil then
    return t[index]
  else
    return default
  end
end

local DocView_draw_line_text = DocView.draw_line_text
function DocView:draw_line_text(idx, x, y)
  DocView_draw_line_text(self, idx, x, y)

  local lp = self.doc.__lintplus
  if lp == nil then return end

  local _, yy = self:get_line_screen_position(idx)
  yy = yy + self:get_line_height() - 1
  local file_messages = lint.messages[system.absolute_path(self.doc.filename)]
  if file_messages == nil then return end
  local messages = file_messages.lines[idx]
  if messages == nil then return end

  local underline_start = messages[1].column

  local font = self:get_font()
  local underline_color = get_message_group_color(messages)
  local line = self.doc.lines[idx]
  local line_left = line:sub(1, underline_start - 1)
  local line_right = line:sub(underline_start, -2)
  local underline_x = font:get_width(line_left)
  local w = font:get_width('w')

  local msg_x = x + w * 3 + underline_x + font:get_width(line_right)
  for i, msg in ipairs(messages) do
    local text_color = get_or_default(style.lint, msg.kind, underline_color)
    msg_x = renderer.draw_text(font, msg.message, msg_x, y, text_color)
    if i < #messages then
      msg_x = renderer.draw_text(font, ",  ", msg_x, y, style.syntax.comment)
    end
  end

  local underline_width = msg_x - x - underline_x
  draw_lens_underline(x + underline_x, yy, underline_width, underline_color)
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
    local file_messages = lint.messages[system.absolute_path(doc.filename)]
    if file_messages ~= nil then
      if file_messages.lines[line1] ~= nil and line1 == line2 then
        local msg = file_messages.lines[line1][1]
        table_add(left, {
          style.dim, self.separator2,
          kind_pretty_name(msg.kind), ": ",
          style.text, msg.message,
        })
      else
        local line, message = math.huge, nil
        for ln, messages in pairs(file_messages.lines) do
          local msg = messages[1]
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

  if lint.running > 0 then
    local r = { "linting…", style.dim, self.separator2, style.text }
    table_add(r, right)
    right = r
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

function lint.enable_async()
  local ok, err = core.try(function ()
    liteipc = liteipc_loader.async()
    core.log_quiet("lint+: using experimental async mode")
  end)
  if not ok then
    core.log_quiet("additional error details: \n%s", err)
    core.error(
      "lint+: could not enable async mode. double-check your installation")
  end
end


--- LINTER CREATION UTILITIES ---


lint.filename = {}
lint.args = {}


function lint.command(cmd)
  return function (filename)
    local c = {}
    for i, arg in ipairs(cmd) do
      if arg == lint.filename then
        c[i] = filename
      else
        c[i] = arg
      end
    end
    return c
  end
end


function lint.args_command(cmd, config_option)
  return function (filename)
    local c = {}
    for _, arg in ipairs(cmd) do
      if arg == lint.args then
        local args = lint.config[config_option] or {}
        for _, a in ipairs(args) do
          table.insert(c, a)
        end
      else
        table.insert(c, arg)
      end
    end
    return lint.command(c)(filename)
  end
end


function lint.interpreter(i)
  local patterns = {
    info = i.info,
    hint = i.hint,
    warning = i.warning,
    error = i.error,
  }
  local strip_pattern = i.strip

  return function (_, line)
    local line_processed = false
    return function ()
      if line_processed then
        return nil
      end
      for kind, patt in pairs(patterns) do
        assert(
          type(patt) == "string",
          "lint+: interpreter pattern must be a string")
        local file, ln, column, message = line:match(patt)
        if file then
          if strip_pattern then
            message = message:gsub(strip_pattern, "")
          end
          line_processed = true
          return file, tonumber(ln), tonumber(column), kind, message
        end
      end
    end
  end
end


if type(config.lint) ~= "table" then
  config.lint = {}
end
lint.config = config.lint


--- END ---

return lint
