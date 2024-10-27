local unset = -1

local Menu = {
  config = {},
  dict = {},
  dict_index = {},
  items = {},
  display_items = {},
  buf = unset,
  win = unset,
  page = 1,

  tag_followed = nil, -- callback
  fmt = nil, -- callback
  new_buffer_callbacks = {},

  old_tags = {},
}

Menu.__index = Menu

local Slice = require("snipe2.slice")

-- Table for helper stuff
local H = {}

-- This config will only really apply if not
-- being called through the high level interface (which pushes global config values down)
H.default_config = {
  dictionary = "sadflewcmpghio",
  position = "topleft",
  open_win_override = {},

  -- unset means no maximum
  max_height = unset,
}

--- @param config ?table
function Menu:new(config)
  local o = setmetatable({}, self)
  self.config = vim.tbl_extend("keep", config or {}, H.default_config)
  self.dict, self.dict_index = H.generate_dict_structs(self.config.dictionary)
  return o
end

---@generic T
---@generic M
---@param items table<T> list of items to present
---@param tag_followed fun(menu: M, itemi: number): nil the callback when tag is followed by user
---@param fmt ?fun(item: T): (string) takes each item and transforms it before printing
---@param preselect ?number item to preselect
function Menu:open(items, tag_followed, fmt, preselect)
  self.items = items
  self.tag_followed = tag_followed
  self.fmt = fmt

  if #items <= 0 then
    vim.notify("(snipe) empty list of items passed to open method", vim.log.levels.ERROR)
    return
  end

  local num_pages, max_page_size = H.get_page_info(#items, self.config.max_height)

  -- Since the items could have changed, we always want to clamp the page index
  self.page = H.clamp(self.page, 1, num_pages)

  -- Get the offset and number of items to display
  local first_item_index = (self.page - 1) * max_page_size + 1
  local num_items = math.min(#items - first_item_index + 1, max_page_size)

  self.display_items = Slice:new(items, first_item_index, num_items)
  local tags = H.generate_tags(num_items, self.dict, self.dict_index)

  -- The actual list of strings that are displayed
  local widest_line_width = 0
  local display_lines = {}
  for i, item in self.display_items:ipairs() do
    display_lines[i] = string.format("%s %s", tags[i], fmt and fmt(item) or item)
    if #display_lines[i] > widest_line_width then
      widest_line_width = #display_lines[i]
    end
  end

  -- Maintain buffer and window
  self:ensure_buffer()
  if self.win ~= unset and vim.api.nvim_win_is_valid(self.win) then
    self:update_window(num_items, widest_line_width)
  else
    self.win = self:create_window(self.buf, num_items, widest_line_width)
  end

  vim.bo[self.buf].modifiable = true
  vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, display_lines)
  vim.bo[self.buf].modifiable = false

  vim.api.nvim_set_current_win(self.win)

  if preselect ~= nil and preselect <= num_items then
    vim.api.nvim_win_set_cursor(self.win, {preselect, 0})
  end

  local tag_width = H.min_digits(#display_lines, #self.config.dictionary)

  -- Remove old tags from the buffer
  for _, old_tag in ipairs(self.old_tags) do
    vim.api.nvim_buf_del_keymap(self.buf, "n", old_tag)
  end

  -- Clear old highlights
  vim.api.nvim_buf_clear_namespace(self.buf, H.highlight_ns, 0, #tags)

  -- Set the highlights and keymaps for tags
  for i, tag in ipairs(tags) do
    vim.api.nvim_buf_add_highlight(self.buf, H.highlight_ns, "SnipeHint", i - 1, 0, tag_width)
    vim.keymap.set("n", tag, function ()
      tag_followed(self, self.display_items.offset + i - 1)
    end, { nowait = true, buffer = self.buf })
  end
  self.old_tags = tags
end

function Menu:ensure_buffer()
  if self.buf == unset or not vim.api.nvim_buf_is_valid(self.buf) then
    self.buf = H.create_buffer()
    -- Call the new buffer callbacks
    for _, cb in ipairs(self.new_buffer_callbacks) do
      cb(self)
    end
  end
end

function Menu:add_new_buffer_callback(callback)
  table.insert(self.new_buffer_callbacks, callback)
end

function Menu:reopen()
  self:open(self.items, self.tag_followed, self.fmt)
end

function Menu:hovered()
  local pos = vim.api.nvim_win_get_cursor(self.win)
  return self.display_items.offset + pos[1] - 1
end

function Menu:goto_next_page()
  local num_pages, _ = H.get_page_info(#self.items, self.config.max_height)
  self.page = H.clamp(self.page + 1, 1, num_pages)
end

function Menu:goto_prev_page()
  local num_pages, _ = H.get_page_info(#self.items, self.config.max_height)
  self.page = H.clamp(self.page - 1, 1, num_pages)
end

function Menu:close_nosave()
  if self.win ~= unset and vim.api.nvim_win_is_valid(self.win) then
    vim.api.nvim_win_close(self.win, true)
  end

  self.win = unset
end

function Menu:close()
  if self.win ~= unset and vim.api.nvim_win_is_valid(self.win) then
    vim.api.nvim_win_close(self.win, true)
  end

  self.win = unset
end

function Menu:get_window_opts(height, width)
  local row, col = 0, 0
  local anchor = "NW"
  local pos = self.config.position

  local max_height = H.window_get_max_height()

  local current_tabpage = vim.api.nvim_get_current_tabpage()
  local root_win = vim.api.nvim_tabpage_list_wins(current_tabpage)[1]
  local max_width = vim.fn.winwidth(root_win)

  if pos == "topleft" then
    row, col = 0, 0
    anchor = "NW"
  elseif pos == "topright" then
    row, col = 0, max_width
    anchor = "NE"
  elseif pos == "bottomleft" then
    row, col = max_height + 2, 0
    anchor = "SW"
  elseif pos == "bottomright" then
    row, col = max_height + 2, max_width
    anchor = "SE"
  elseif pos == "center" then
    row, col = math.floor((max_height + 2) / 2) - math.floor((height + 2) / 2),
               math.floor(max_width / 2) - math.floor((width + 2) / 2)
  elseif pos == "cursor" then
    -- Taken from telescope source
    local winbar = (function()
      if vim.fn.exists "&winbar" == 1 then
        return vim.wo.winbar == "" and 0 or 1
      end
      return 0
    end)()
    local position = vim.api.nvim_win_get_position(0)
    row, col = vim.fn.winline() + position[1] + winbar, vim.fn.wincol() + position[2]
    anchor = "NW"
  else
    vim.notify("(snipe) unrecognized position", vim.log.levels.WARN)
  end

  return vim.tbl_extend("keep", self.config.open_win_override, {
    title = "Snipe",
    anchor = anchor,
    border = "single",
    style = "minimal",
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    zindex = 99,
  })
end

function Menu:update_window(height, width)
  local cursor_pos = vim.api.nvim_win_get_cursor(self.win)

  vim.api.nvim_win_set_config(self.win, self:get_window_opts(height, width))

  -- clamp the old cursor position to the new window
  cursor_pos[1] = H.clamp(cursor_pos[1], 1, height)
  cursor_pos[2] = H.clamp(cursor_pos[2], 0, width)

  vim.api.nvim_win_set_cursor(self.win, {1, 0}) -- make sure first line is shown
  vim.api.nvim_win_set_cursor(self.win, cursor_pos)
  vim.api.nvim_win_set_hl_ns(self.win, H.highlight_ns)
  vim.wo[self.win].foldenable = false
  vim.wo[self.win].wrap = false
  vim.wo[self.win].cursorline = true
end

function Menu:create_window(bufnr, height, width)
  local win = vim.api.nvim_open_win(bufnr, false, self:get_window_opts(height, width))

  vim.api.nvim_win_set_hl_ns(win, H.highlight_ns)
  vim.wo[win].foldenable = false
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = true

  return win
end

H.get_page_info = function(num_items, max_height)
  local viewport_height = H.window_get_max_height()
  if max_height ~= nil and max_height ~= -1 then
    viewport_height = math.min(max_height, viewport_height)
  end

  local num_pages = math.floor(num_items / viewport_height)
  if num_items % viewport_height ~= 0 then
    num_pages = num_pages + 1
  end

  return num_pages, viewport_height
end

H.create_buffer = function()
  local bufnr = vim.api.nvim_create_buf(false, false)
  vim.bo[bufnr].filetype = "snipe-menu"
  vim.bo[bufnr].buflisted = false
  vim.bo[bufnr].buftype = "nofile" -- ensures no "unsaved changes" popup
  return bufnr
end

-- From https://github.com/echasnovski/mini.nvim
H.window_get_max_height = function()
  local has_tabline = vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1)
  local has_statusline = vim.o.laststatus > 0
  -- Remove 2 from maximum height to account for top and bottom borders
  return vim.o.lines - vim.o.cmdheight - (has_tabline and 1 or 0) - (has_statusline and 1 or 0) - 2
end

H.create_default_hl = function()
  H.highlight_ns = vim.api.nvim_create_namespace("")
  vim.api.nvim_set_hl(H.highlight_ns, "SnipeHint", { link = "CursorLineNr" })
end

H.clamp = function(val, min, max)
  return math.min(math.max(val, min), max)
end

H.min_digits = function(n, base)
  return math.max(1, math.ceil(math.log(n, base)))
end

H.generate_dict_structs = function(dict_str)
  local dict = {}
  local dict_index = {}
  for i = 1, #dict_str do
    local c = dict_str:sub(i, i)
    if dict_index[c] ~= nil then -- duplicate
      vim.notify("(snipe) Dictionary must have unique items: ignoring duplicates", vim.log.levels.WARNING)
    else
      table.insert(dict, c)
      dict_index[c] = i
    end
  end
  return dict, dict_index
end

-- Generating tags is essentially a generalized
-- form of counting where our unique digits is the
-- dictionary of characters with base = #characters
H.generate_tags = function(n, dict, dict_index)
  local max = dict[#dict]

  local function inc_digit(digit)
    return dict[(dict_index[digit] + 1) % (#dict + 1)]
  end

  local function inc(num)
    local last = num[#num]
    if last == max then
      -- "carry the one"
      local i = #num - 1
      while i >= 1 and num[i] == max do
        i = i - 1
      end

      if i == 0 then -- increase number of digits
        table.insert(num, dict[1])
        i = 1
        num[i] = dict[1]
      end

      -- i is what we need to increment and zero everything after it
      num[i] = inc_digit(num[i])
      for s = i + 1, #num do
        num[s] = dict[1]
      end

      return num
    end

    num[#num] = inc_digit(last)
    return num
  end

  -- This is so we can add trailing "0": where "0" is just first item in dictionary
  local max_width = H.min_digits(n, #dict)

  local tags = {}
  local tag = {dict[1]}
  for _ = 1, n do
    local lead = string.rep(dict[1], max_width - #tag)
    table.insert(tags, lead .. table.concat(tag))
    tag = inc(tag)
  end

  return tags
end

H.create_default_hl()

return Menu
