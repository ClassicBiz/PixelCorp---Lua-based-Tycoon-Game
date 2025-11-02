local basalt = require("/API/basalt")

local M = {
  _root = nil,
  _border = nil,
  _overlay = nil,
  _left = nil,      -- categories pane
  _right = nil,     -- article pane
  _title = nil,     -- article title label
  _body = nil,      -- article body scroll container
  _search = nil,    -- optional search input
  _data = nil,
  _catButtons = {}, -- map: catId -> button
  _open = false,
  _current = { catId = nil, articleId = nil },
}

local LEFT_W = 22           -- left pane width (category list + search)
local PADDING = 1           -- inner padding for text
local ACTIVE_BG = colors.lightBlue
local ACTIVE_FG = colors.black
local INACTIVE_BG = colors.white
local INACTIVE_FG = colors.black
local dividerX = 21  -- X position of your divider line
local dividerY = 2   -- starting Y
local dividerH = 14  -- number of rows (adjust as needed)


local SCREEN_W, SCREEN_H = term.getSize()

local function _wipe(frame) if frame and frame.removeChildren then frame:removeChildren() end end

local function _findCat(data, id)
  for _, c in ipairs(data.categories or {}) do if c.id == id then return c end end
end
local function _findArticle(cat, articleId)
  for _, a in ipairs(cat.articles or {}) do if a.id == articleId then return a end end
end

local function _wrapText(text, maxWidth)
  local lines, line = {}, ""
  for word in tostring(text):gmatch("%S+") do
    if #line == 0 then
      line = word
    elseif #line + 1 + #word <= maxWidth then
      line = line .. " " .. word
    else
      table.insert(lines, line)
      line = word
    end
  end
  if #line > 0 then table.insert(lines, line) end
  -- also preserve intentional newlines by splitting first:
  local out = {}
  for _, block in ipairs(lines) do
    for sub in tostring(block):gmatch("[^\r\n]+") do table.insert(out, sub) end
  end
  return out
end

local function _setActive(btn, active)
  if not btn then return end
  if active then
    btn:setBackground(ACTIVE_BG):setForeground(ACTIVE_FG):setText(btn:getText():gsub("^%s*",""))
  else
    btn:setBackground(INACTIVE_BG):setForeground(INACTIVE_FG):setText(btn:getText():gsub("^%p%s*",""))
  end
end

local function _renderArticle(catId, articleId)
  if not (M._data and M._right) then return end
  local cat = _findCat(M._data, catId); if not cat then return end
  local art = _findArticle(cat, articleId) or cat.articles[1]; if not art then return end

  M._current.catId, M._current.articleId = catId, art.id
  if M._title then M._title:setText(art.title or "") end

  _wipe(M._body)

  local bw, _bh = M._body:getSize()
  local contentW = math.max(8, bw - (PADDING)) -- safety minimum
  local y = 1

  local function addWrappedBlock(text)
    for _, line in ipairs(_wrapText(text, contentW)) do
      M._body:addLabel():setText(line):setPosition(PADDING, y)
      y = y + 1
    end
  end

  if art.summary and art.summary ~= "" then
    addWrappedBlock("* " .. art.summary)
    y = y + 1
  end

  if art.body and art.body ~= "" then
    for para in tostring(art.body):gmatch("([^\n]+)") do
      addWrappedBlock(para)
    end
  else
    addWrappedBlock("(No content)")
  end

  -- re-highlight category (if re-rendered from external jump)
  for id, b in pairs(M._catButtons) do _setActive(b, id == catId) end
end

local function _renderCategories(filterText)
  _wipe(M._left)
  M._catButtons = {}

  local y = 1
  local ft = (filterText or ""):lower()

  for _, cat in ipairs(M._data.categories or {}) do
    local show = (ft == "") or ((cat.title or ""):lower():find(ft, 1, true) ~= nil)
    if show then
      local btn = M._left:addButton()
        :setText((cat.title or cat.id))
        :setPosition(2, y)
        :setSize(LEFT_W-3, 1)
        :setBackground(INACTIVE_BG)
        :setForeground(INACTIVE_FG)
        :onClick(function()
          local first = (cat.articles and cat.articles[1] and cat.articles[1].id) or nil
          -- mark active
          for id, b in pairs(M._catButtons) do _setActive(b, id == cat.id) end
          M._current.catId = cat.id
          _renderArticle(cat.id, first)
        end)

      M._catButtons[cat.id] = btn
      -- keep current selection styled
      _setActive(btn, M._current.catId == cat.id)
      y = y + 1
    end
  end
end

local function _buildUI(root)
  local W, H = SCREEN_W, SCREEN_H

  M._border = root:addFrame()
    :setSize(W - 4, H - 4)
    :setPosition(3, 3)
    :setBackground(colors.lightGray)
    :setZIndex(180)
    :hide()

  M._overlay = M._border:addFrame()
    :setSize(W - 6, H - 6)
    :setPosition(2, 2)
    :setBackground(colors.white)
    :setZIndex(181)
    :hide()

  -- Close
  M._border:addButton()
    :setText(" X ")
    :setPosition(45, 1)
    :setSize(3,1)
    :setBackground(colors.red)
    :setForeground(colors.white)
    :onClick(function() M.hide() end)

  -- Left categories (scrollable)
  M._left = M._overlay:addScrollableFrame()
    :setPosition(2, 3)
    :setSize(19, H - 10)
    :setBackground(colors.white)
    :setDirection("vertical")

for i = 0, dividerH - 1 do
    M._overlay:addLabel()
        :setPosition(dividerX, dividerY + i)
        :setText("|")
        :setForeground(colors.black)
end

  -- Optional search bar
  M._search = M._overlay:addInput()
    :setPosition(2, 2)
    :setSize(18, 1)
    :setDefaultText("Search")
    :onChange(function(self)
      local txt = self:getValue()
      _renderCategories(txt)
    end)

  -- Right article panel
  M._title = M._overlay:addLabel()
    :setText("Guide")
    :setPosition(22, 2)
    :setForeground(colors.black)

  M._right = M._overlay:addScrollableFrame()
    :setPosition(23, 3)
    :setSize(W - 10 - 18, H - 10)
    :setBackground(colors.white)
    :setDirection("vertical")

  M._body = M._right -- alias for clarity
end

-- Public API

function M.init(rootFrame)
  M._root = rootFrame
  _buildUI(rootFrame)
  return M
end

function M.setData(data)
  M._data = data or { categories = {} }
  _renderCategories(nil)
  local c = M._data.categories[1]
  if c and c.articles and c.articles[1] then
    M._current.catId = c.id
    _renderArticle(c.id, c.articles[1].id)
    for id, b in pairs(M._catButtons) do _setActive(b, id == c.id) end
  end
  return M
end

function M.show()
  if not (M._overlay and M._border) then return end
  M._border:show(); M._overlay:show()
  M._open = true
end

function M.hide()
  if not (M._overlay and M._border) then return end
  M._overlay:hide(); M._border:hide()
  M._open = false
end

function M.openCategory(catId, articleId)
  -- externally jump to a specific article (e.g., from tutorial)
  _renderArticle(catId, articleId)
  M.show()
end

return M