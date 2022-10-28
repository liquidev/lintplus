-- mod-version:3

-- lint+ - an improved linter for lite
-- copyright (C) lqdev, 2020
-- licensed under the MIT license


--- STATIC CONFIG ---


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


local core = require "core"
local command = require "core.command"
local common = require "core.common"
local config = require "core.config"
local style = require "core.style"
local keymap = require "core.keymap"
local syntax = require "core.syntax"

local Doc = require "core.doc"
local DocView = require "core.docview"
local StatusView = require "core.statusview"

local liteipc = require "plugins.lintplus.liteipc"


local lint = {}
lint.fs = require "plugins.lintplus.fsutil"
lint.ipc = liteipc


lint.index = {}
lint.messages = {}


local LintContext = {}
LintContext.__index = LintContext


function LintContext:create_gutter_rail()
  if not self._doc then return 0 end
  local lp = self._doc.__lintplus
  lp.rail_count = lp.rail_count + 1
  return lp.rail_count
end


function LintContext:gutter_rail_count()
  if not self._doc then return 0 end
  return self._doc.__lintplus.rail_count
end


-- Can be used by other plugins to properly set the context when loading a doc
function lint.init_doc(filename, doc)
  filename = core.project_absolute_path(filename)
  local context = setmetatable({
    _doc = doc or nil,
    _user_context = nil,
  }, LintContext)

  if doc then
    doc.__lintplus_context = {}
    context._user_context = doc.__lintplus_context

    doc.__lintplus = {
      rail_count = 0,
    }
  end

  if not lint.messages[filename] then
    lint.messages[filename] = {
      context = context,
      lines = {},
      rails = {},
    }
  elseif doc then
    lint.messages[filename].context = context
  end
end


-- Returns an appropriate linter for the given doc, or nil if no linter is
-- found.
function lint.get_linter_for_doc(doc)
  if not doc.filename then
    return nil
  end

  local file = core.project_absolute_path(doc.filename)
  for name, linter in pairs(lint.index) do
    if common.match_pattern(file, linter.filename) then
      return linter, name
    end
    if linter.syntax ~= nil then
      local header = doc:get_text(1, 1, doc:position_offset(1, 1, 128))
      local syn = syntax.get(doc.filename, header)
      for i = #linter.syntax, 1, -1 do
        local s = linter.syntax[i]
        if syn.name == s then
          return linter, name
        end
      end
    end
  end
end


-- unused for now, because it was a bit buggy
-- Note: Should be fixed now
function lint.clear_messages(filename)
  filename = core.project_absolute_path(filename)

  if lint.messages[filename] then
    lint.messages[filename].lines = {}
    lint.messages[filename].rails = {}
  end
end


function lint.add_message(filename, line, column, kind, message, rail)
  filename = core.project_absolute_path(filename)
  if not lint.messages[filename] then
    -- This allows us to at least store messages until context is properly
    -- set from the calling plugin.
    lint.init_doc(filename)
  end
  local file_messages = lint.messages[filename]
  local lines, rails = file_messages.lines, file_messages.rails
  lines[line] = lines[line] or {}
  if rail ~= nil then
    rails[rail] = rails[rail] or { lines_taken = {} }
    if not rails[rail].lines_taken[line] then
      rails[rail].lines_taken[line] = true
      table.insert(rails[rail], {
        line = line,
        column = column,
        kind = kind,
      })
    end
  end
  table.insert(lines[line], {
    column = column,
    kind = kind,
    message = message,
    rail = rail,
  })
end


local function process_line(doc, linter, line, context)
  local file = core.project_absolute_path(doc.filename)

  local had_messages = false

  local iterator = linter.procedure.interpreter(file, line, context)
  if iterator == "bail" then return iterator end

  if os.getenv("LINTPLUS_DEBUG_LINES") then
    print("lint+ | "..line)
  end

  for rawfile, lineno, columnno, kind, message, rail in iterator do
    assert(type(rawfile) == "string")
    local absfile = core.project_absolute_path(rawfile)
    if absfile == file then -- TODO: support project-wide errors
      assert(type(lineno) == "number")
      assert(type(columnno) == "number")
      assert(type(kind) == "string")
      assert(type(message) == "string")
      assert(rail == nil or type(rail) == "number")

      lint.add_message(absfile, lineno, columnno, kind, message, rail)
      core.redraw = true
    end
  end

  return had_messages
end


local function compare_message_priorities(a, b)
  return kind_priority[a.kind] > kind_priority[b.kind]
end

local function compare_messages(a, b)
  if a.column == b.column then
    return compare_message_priorities(a, b)
  end
  return a.column > b.column
end

local function compare_rail_messages(a, b)
  return a.line < b.line
end


function lint.check(doc)
  if doc.filename == nil then return end

  local linter, linter_name = lint.get_linter_for_doc(doc)
  if linter == nil then
    core.error("no linter available for the given filetype")
    return
  end

  local filename = core.project_absolute_path(doc.filename)
  local context = setmetatable({
    _doc = doc,
    _user_context = doc.__lintplus_context,
  }, LintContext)

  doc.__lintplus = {
    rail_count = 0,
  }
--   clear_messages(linter)
  lint.messages[filename] = {
    context = context,
    lines = {},
    rails = {},
  }

  local function report_error(msg)
    core.log_quiet(
      "lint+/" .. linter_name .. ": " ..
      doc.filename .. ": " .. msg
    )
  end

  local cmd, cwd = linter.procedure.command(filename), nil
  if cmd.set_cwd then
    cwd = lint.fs.parent_directory(filename)
  end
  local process = liteipc.start_process(cmd, cwd)
  core.add_thread(function ()
    -- poll the process for lines of output
    while true do
      local exit, code, errmsg = process:poll(function (line)
        process_line(doc, linter, line, context)
      end)
      if exit ~= nil then
        -- If linter exited with exit code non 0 or 1 log it
        if exit == "signal" then
          report_error(
            "linter exited with signal " .. code
            .. (errmsg and " : " .. errmsg or "")
          )
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
      core.redraw = true
      coroutine.yield(0)
    end
  end)
end


-- inject initialization routines to documents

local Doc_load, Doc_save, Doc_on_close = Doc.load, Doc.save, Doc.on_close

local function init_linter_for_doc(doc)
  local linter, _ = lint.get_linter_for_doc(doc)
  if linter == nil then return end
  doc.__lintplus_context = {}
  if linter.procedure.init ~= nil then
    linter.procedure.init(
      core.project_absolute_path(doc.filename),
      doc.__lintplus_context
    )
  end
end

function Doc:load(filename)
  local old_filename = self.filename
  Doc_load(self, filename)
  if old_filename ~= filename then
    init_linter_for_doc(self)
  end
end

function Doc:save(filename, abs_filename)
  local old_filename = self.filename
  Doc_save(self, filename, abs_filename)
  if old_filename ~= filename then
    init_linter_for_doc(self)
  end
end

function Doc:on_close()
  Doc_on_close(self)
  if not self.filename then return end
  local filename = core.project_absolute_path(self.filename)
  -- release Doc object for proper garbage collection
  if lint.messages[filename] then
    lint.messages[filename] = nil
  end
end


-- inject hooks to Doc.insert and Doc.remove to shift messages around

local function sort_positions(line1, col1, line2, col2)
  if line1 > line2
  or line1 == line2 and col1 > col2 then
    return line2, col2, line1, col1, true
  end
  return line1, col1, line2, col2, false
end

local Doc_insert = Doc.insert
function Doc:insert(line, column, text)
  Doc_insert(self, line, column, text)

  if self.filename == nil then return end
  if line == math.huge then return end

  local filename = core.project_absolute_path(self.filename)
  local file_messages = lint.messages[filename]
  local lp = self.__lintplus
  if file_messages == nil or lp == nil then return end

  -- shift line messages downwards
  local shift = 0
  for _ in text:gmatch('\n') do
    shift = shift + 1
  end
  if shift == 0 then return end

  local lines = file_messages.lines
  for i = #self.lines, line, -1 do
    if lines[i] ~= nil then
      if not (i == line and lines[i][1].column < column) then
        lines[i + shift] = lines[i]
        lines[i] = nil
      end
    end
  end

  -- shift rails downwards
  local rails = file_messages.rails
  for _, rail in pairs(rails) do
    for _, message in ipairs(rail) do
      if message.line >= line then
        message.line = message.line + shift
      end
    end
  end
end

local function update_messages_after_removal(
  doc,
  line1, column1,
  line2, column2
)
  if line1 == line2 then return end
  if line2 == math.huge then return end
  if doc.filename == nil then return end

  local filename = core.project_absolute_path(doc.filename)
  local file_messages = lint.messages[filename]
  local lp = doc.__lintplus
  if file_messages == nil or lp == nil then return end

  local lines = file_messages.lines

  line1, column1, line2, column2 =
    sort_positions(line1, column1, line2, column2)
  local shift = line2 - line1

  -- remove all messages in this range
  for i = line1, line2 do
    lines[i] = nil
  end

  -- shift all line messages up
  for i = line1, #doc.lines do
    if lines[i] ~= nil then
      lines[i - shift] = lines[i]
      lines[i] = nil
    end
  end

  -- remove all rail messages in this range
  local rails = file_messages.rails
  for _, rail in pairs(rails) do
    local remove_indices = {}
    for i, message in ipairs(rail) do
      if message.line >= line1 and message.line < line2 then
        table.insert(remove_indices, i)
      elseif message.line > line1 then
        message.line = message.line - shift
      end
    end
    for i = #remove_indices, 1, -1 do
      table.remove(rail, remove_indices[i])
    end
  end
end

local Doc_remove = Doc.remove
function Doc:remove(line1, column1, line2, column2)
  update_messages_after_removal(self, line1, column1, line2, column2)
  Doc_remove(self, line1, column1, line2, column2)
end


-- inject rendering routines

local renderutil = require "plugins.lintplus.renderutil"

local function rail_width(dv)
  return dv:get_line_height() / 3 -- common.round(style.padding.x / 2)
end

local function rail_spacing(dv)
  return common.round(rail_width(dv) / 4)
end

local DocView_get_gutter_width = DocView.get_gutter_width
function DocView:get_gutter_width()
  local extra_width = 0
  if self.doc.filename ~= nil then
    local file_messages = lint.messages[core.project_absolute_path(self.doc.filename)]
    if file_messages ~= nil then
      local rail_count = file_messages.context:gutter_rail_count()
      extra_width = rail_count * (rail_width(self) + rail_spacing(self))
    end
  end
  local original_width, padding = DocView_get_gutter_width(self)
  return original_width + extra_width, padding
end


local function get_gutter_rail_x(dv, index)
  return
    dv.position.x + dv:get_gutter_width() -
    (rail_width(dv) + rail_spacing(dv)) * index + rail_spacing(dv)
end


local function get_message_group_color(messages)
  if style.lint ~= nil then
    return style.lint[messages[1].kind]
  else
    local default_colors = {
      info = style.syntax["normal"],
      hint = style.syntax["function"],
      warning = style.syntax["number"],
      error = style.syntax["keyword2"]
    }
    return default_colors[messages[1].kind]
  end
end

local function get_underline_y(dv, line)
  local _, y = dv:get_line_screen_position(line)
  local line_height = dv:get_line_height()
  local extra_space = line_height - dv:get_font():get_height()
  return y + line_height - extra_space / 2
end

local function draw_gutter_rail(dv, index, messages)
  local rail = messages.rails[index]
  if rail == nil or #rail < 2 then return end

  local first_message = rail[1]
  local last_message = rail[#rail]

  local x = get_gutter_rail_x(dv, index)
  local rw = rail_width(dv)
  local start_y = get_underline_y(dv, first_message.line)
  local fin_y = get_underline_y(dv, last_message.line)

  -- connect with lens
  local line_x = x + rw
  for i, message in ipairs(rail) do
    -- connect with lens
    local lx, _ = dv:get_line_screen_position(message.line)
    local ly = get_underline_y(dv, message.line)
    local line_messages = messages.lines[message.line]
    if line_messages ~= nil then
      local column = line_messages[1].column
      local message_left = line_messages[1].message:sub(1, column - 1)
      local line_color = get_message_group_color(line_messages)
      local xoffset = (x + rw) % 2
      local line_w = dv:get_font():get_width(message_left) - line_x + lx
      renderutil.draw_dotted_line(x + rw + xoffset, ly, line_w, 'x', line_color)
      -- draw curve
      ly = ly - rw * (i == 1 and 0 or 1) + (i ~= 1 and 1 or 0)
      renderutil.draw_quarter_circle(x, ly, rw, style.accent, i > 1)
    end
  end

  -- draw vertical part
  local height = fin_y - start_y + 1 - rw * 2
  renderer.draw_rect(x, start_y + rw, 1, height, style.accent)

end

local DocView_draw = DocView.draw
function DocView:draw()
  DocView_draw(self)

  local filename = self.doc.filename
  if filename == nil then return end
  filename = core.project_absolute_path(filename)
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
  local lens_style = config.lint.lens_style or "solid"
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

  local yy = get_underline_y(self, idx)
  local file_messages = lint.messages[core.project_absolute_path(self.doc.filename)]
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
  local text_y = y + self:get_line_text_y_offset()
  for i, msg in ipairs(messages) do
    local text_color = get_or_default(style.lint, msg.kind, underline_color)
    msg_x = renderer.draw_text(font, msg.message, msg_x, text_y, text_color)
    if i < #messages then
      msg_x = renderer.draw_text(font, ",  ", msg_x, text_y, style.syntax.comment)
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


local function get_error_messages(doc, ordered)
  if not doc then return nil end
  local messages = lint.messages[core.project_absolute_path(doc.filename)]
  if not messages then return nil end
  if not ordered then return messages.lines end
  -- sort lines
  local lines = {}
  for line, _ in pairs(messages.lines) do
    table.insert(lines, line)
  end
  table.sort(lines, function(a, b) return a < b end)
  local lines_info = {}
  -- store in array instead of dictionary to keep insertion order
  for _, line in ipairs(lines) do
    table.insert(
      lines_info,
      {line = line, table.unpack(messages.lines[line])}
    )
  end
  return lines_info
end


local function get_current_error(doc)
  local file_messages = get_error_messages(doc)
  local line, message = math.huge, nil
  for ln, messages in pairs(file_messages) do
    local msg = messages[1]
    if msg.kind == "error" and ln < line  then
      line, message = ln, msg
    end
  end
  if message ~= nil then
    return line, message.kind, message.message
  end
  return nil, nil, nil
end


local function goto_prev_message()
  local doc = core.active_view.doc
  local current_line = doc:get_selection()
  local file_messages = get_error_messages(doc, true)
  if file_messages ~= nil then
    local prev = nil
    local found = false
    local last = nil
    for _, line_info in pairs(file_messages) do
      local line = line_info.line
      if current_line <= line  then
        found = true
      end
      if not found then
        prev = line
      end
      last = line
    end
    local line = prev or last
    if line then
      doc:set_selection(line, 1, line, 1)
    end
  end
end


local function goto_next_message()
  local doc = core.active_view.doc
  local current_line = doc:get_selection()
  local file_messages = get_error_messages(doc, true)
  if file_messages ~= nil then
    local first = nil
    local next = nil
    for _, line_info in pairs(file_messages) do
      local line = line_info.line
      if not first then
        first = line
      end
      if line > current_line then
        next = line
        break
      end
    end
    local line = next or first
    if line then
      doc:set_selection(line, 1, line, 1)
    end
  end
end


local function get_status_view_items()
  local doc = core.active_view.doc
  local line1, _, line2, _ = doc:get_selection()
  local file_messages = get_error_messages(doc)
  if file_messages ~= nil then
    if file_messages[line1] ~= nil and line1 == line2 then
      local msg = file_messages[line1][1]
      return {
        kind_pretty_name(msg.kind), ": ",
        style.text, msg.message,
      }
    else
      local line, kind, message = get_current_error(doc)
      if line ~= nil then
        return {
          "line ", tostring(line), " ", kind_pretty_name(kind), ": ",
          style.text, message,
        }
      end
    end
  end
  return {}
end

if StatusView["add_item"] then
  core.status_view:add_item({
    predicate = function()
      local doc = core.active_view.doc
      if
        doc and doc.filename  -- skip new files
        and
        getmetatable(core.active_view) == DocView
        and
        (
          lint.get_linter_for_doc(doc)
          or
          lint.messages[core.project_absolute_path(doc.filename)]
        )
      then
        return true
      end
      return false
    end,
    name = "lint+:message",
    alignment = StatusView.Item.LEFT,
    get_item = get_status_view_items,
    command = function()
      local doc = core.active_view.doc
      local line = get_current_error(doc)
      if line ~= nil then
        doc:set_selection(line, 1, line, 1)
      end
    end,
    position = -1,
    tooltip = "Lint+ error message",
    separator = core.status_view.separator2
  })
else
  local StatusView_get_items = StatusView.get_items
  function StatusView:get_items()
    local left, right = StatusView_get_items(self)
    local doc = core.active_view.doc

    if
      doc and doc.filename  -- skip new files
      and
      getmetatable(core.active_view) == DocView
      and
      (
        lint.get_linter_for_doc(doc)
        or
        lint.messages[core.project_absolute_path(doc.filename)]
      )
    then
      local items = get_status_view_items()
      if #items > 0 then
        table.insert(left, {style.dim, self.separator2, table.unpack(items)})
      end
    end

    return left, right
  end
end


command.add(DocView, {
  ["lint+:check"] = function ()
    lint.check(core.active_view.doc)
  end
})

command.add(DocView, {
  ["lint+:goto-previous-message"] = function ()
    goto_prev_message()
  end
})

command.add(DocView, {
  ["lint+:goto-next-message"] = function ()
    goto_next_message()
  end
})

keymap.add {
  ["alt+up"]    = "lint+:goto-previous-message",
  ["alt+down"]  = "lint+:goto-next-message"
}


--- LINTER PLUGINS ---


function lint.add(name)
  return function (linter)
    lint.index[name] = linter
  end
end


--- SETUP ---


lint.setup = {}

function lint.setup.lint_on_doc_load()

  local doc_load = Doc.load
  function Doc:load(filename)
    doc_load(self, filename)
    if not self.filename then return end
    if lint.get_linter_for_doc(self) ~= nil then
      lint.check(self)
    end
  end

end

function lint.setup.lint_on_doc_save()

  local doc_save = Doc.save
  function Doc:save(filename, abs_filename)
    doc_save(self, filename, abs_filename)
    if lint.get_linter_for_doc(self) ~= nil then
      lint.check(self)
    end
  end

end

function lint.enable_async()
  core.error("lint+: calling enable_async() is not needed anymore")
end


--- LINTER CREATION UTILITIES ---


lint.filename = {}
lint.args = {}


local function map(tab, fn)
  local result = {}
  for k, v in pairs(tab) do
    local mapped, mode = fn(k, v)
    if mode == "append" then
      table_add(result, mapped)
    elseif type(k) == "number" then
      table.insert(result, mapped)
    else
      result[k] = mapped
    end
  end
  return result
end


function lint.command(cmd)
  return function (filename)
    return map(cmd, function (k, v)
      if type(k) == "number" and v == lint.filename then
        return filename
      end
      return v
    end)
  end
end


function lint.args_command(cmd, config_option)
  return function (filename)
    local c = map(cmd, function (k, v)
      if type(k) == "number" and v == lint.args then
        local args = lint.config[config_option] or {}
        return args, "append"
      end
      return v
    end)
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


function lint.load(linter)
  if type(linter) == "table" then
    for _, v in ipairs(linter) do
      require("plugins.lintplus.linters." .. v)
    end
  elseif type(linter) == "string" then
    require("plugins.lintplus.linters." .. linter)
  end
end


if type(config.lint) ~= "table" then
  config.lint = {}
end
lint.config = config.lint


--- END ---

return lint
