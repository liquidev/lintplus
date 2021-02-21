-- rendering utilities

local common = require "core.common"

local renderutil = {}

function renderutil.draw_dotted_line(x, y, length, axis, color)
  if axis == 'x' then
    for xx = x, x + length, 2 do
      renderer.draw_rect(xx, y, 1, 1, color)
    end
  elseif axis == 'y' then
    for yy = y, y + length, 2 do
      renderer.draw_rect(x, yy, 1, 1, color)
    end
  end
end

local function plot(x, y, color)
  renderer.draw_rect(x, y, 1, 1, color)
end

function renderutil.draw_quarter_circle(x, y, r, color, flipy)
  -- inefficient for large circles, but it works.
  color = { table.unpack(color) }
  local a = color[4]
  for dx = 0, r - 1 do
    for dy = 0, r - 1 do
      local xx = r - 1 - dx
      local yy = dy
      if not flipy then
        yy = r - 1 - dy
      end
      local t = math.abs(math.sqrt(xx*xx + yy*yy) - r + 1)
      t = common.clamp(1 - t, 0, 1)
      if t > 0 then
        color[4] = a * t
        plot(x + dx, y + dy, color)
      end
    end
  end
end

return renderutil
