local unset = -1

local Config = require("snipe.config")
local Highlights = require("snipe.highlights")

---@class snipe.Menu
local Menu = {
  config = {},
  dict = {},
  items = {},
  display_items = {},
  buf = unset,
  win = unset,
  page = 1,
  opened_from_wid = -1, -- the window that the window was opened in

  tag_followed = nil, -- callback
  fmt = nil, -- callback
  new_buffer_callbacks = {}, -- callbacks for when snipe recreates its buffer

  -- Data for "persist_tags" feature
  tag_map = {}, -- bufnr -> tag
  tag_refs = {}, -- tag -> ref_count

  old_tags = {},
  augroup = vim.api.nvim_create_augroup("SnipeMenu", {}),
}

Menu.__index = Menu

local Slice = require("snipe.slice")

-- Table for helper stuff
local H = {}

-- This config will only really apply if not
-- being called through the high level interface (which pushes global config values down)
H.default_config = {
  dictionary = Config.hints.dictionary,
  position = Config.ui.position,
  persist_tags_key = nil,
  open_win_override = Config.ui.open_win_override,
  default_keymaps = {
    -- if enabled, the default keymaps will be set automatically
    auto_setup = false,
    cancel = Config.navigate.cancel_snipe,
    under_cursor = Config.navigate.under_cursor,
    next_page = Config.navigate.next_page,
    prev_page = Config.navigate.prev_page,
  },
  leader = Config.navigate.leader,
  prefix_key = Config.hints.prefix_key,
  -- unset means no maximum
  max_height = Config.ui.max_height,
  align = Config.ui.text_align == "right" and "right" or "left", -- one of "right" and "left"
  map_tags = nil, -- Apply map operation on generated tags
  set_window_local_options = function(wid)
    vim.wo[wid].foldenable = false
    vim.wo[wid].wrap = false
    vim.wo[wid].cursorline = true
  end,
}

---@class snipe.MenuKeymapCallbacks
---@field close? fun(m)
---@field nav_next? fun(m)
---@field nav_prev? fun(m)
---@field under_cursor? fun(m: snipe.Menu, index: number)

---@param callbacks ?snipe.MenuKeymapCallbacks
function Menu:default_keymaps(callbacks)
  local keymaps = self.config.default_keymaps

  local default_callbacks = {
    close = function()
      self:close()
    end,
    nav_next = function()
      self:goto_next_page()
      self:reopen()
    end,
    nav_prev = function()
      self:goto_prev_page()
      self:reopen()
    end,
    under_cursor = function()
      local hovered = self:hovered()
      self.tag_followed(self, hovered, false)
    end,
  }

  callbacks = vim.tbl_extend("force", default_callbacks, callbacks or {})

  local function set_keymap(key, cb, mode)
    mode = mode or "n"
    vim.keymap.set(mode, key, cb, { nowait = true, buffer = self.buf })
  end

  set_keymap(keymaps.next_page, callbacks.nav_next)
  set_keymap(keymaps.prev_page, callbacks.nav_prev)

  local under_cursor_keys = type(keymaps.under_cursor) == "string" and { keymaps.under_cursor } or keymaps.under_cursor
  for _, key in ipairs(under_cursor_keys or {}) do
    set_keymap(key, callbacks.under_cursor)
  end

  local cancel_keys = type(keymaps.cancel) == "string" and { keymaps.cancel } or keymaps.cancel
  for _, key in ipairs(cancel_keys or {}) do
    set_keymap(key, callbacks.close)
  end
end

--- @param config ?table
function Menu:new(config)
  local o = setmetatable({}, self)
  o.__index = self
  o.config = vim.tbl_deep_extend("keep", config or {}, H.default_config)
  o.dict, o.tag_refs = H.generate_dict_structs(o.config.dictionary)

  if o.config.default_keymaps.auto_setup then
    o:add_new_buffer_callback(function()
      o:default_keymaps()
    end)
  end
  return o
end

---@generic T
---@generic M
---@param items table<T> list of items to present
---@param tag_followed fun(menu: M, itemi: number, leader: boolean): nil the callback when tag is followed by user
---@param fmt ?fun(item: T): (string) takes each item and transforms it before printing
---@param preselect ?number item to preselect
function Menu:open(items, tag_followed, fmt, preselect)
  -- Keep original open root window unless it gets deleted (becomes invalid)
  self.opened_from_wid = self:open_over()

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

  local tags = nil
  if not self.config.persist_tags_key then
    tags = H.generate_tags(num_items, self.dict)
    if self.config.map_tags ~= nil then
      tags = self.config.map_tags(tags)
    end
  end

  -- The actual list of strings that are displayed
  local widest_line_width = 0
  local display_lines = {}
  local lines_highlights = {}

  if self.config.align == "right" then
    local widest = #self.display_items[1]
    for _, item in self.display_items:ipairs() do
      local fmtd = fmt and fmt(item) or item
      if #fmtd > widest then
        widest = #fmtd
      end
    end

    for i, item in self.display_items:ipairs() do
      local line_string = item
      local line_highlights = nil
      if fmt then
        line_string, line_highlights = fmt(item)
      end
      local pad = (" "):rep(widest - #line_string)

      local tag
      if self.config.persist_tags_key then
        tag = H.prefix_tag(self:_get_persistent_tag_for(self.config.persist_tags_key(item)), self.config.prefix_key)
      else
        assert(tags ~= nil)
        tag = tags[i]
      end

      display_lines[i] = string.format("%s %s%s", tag, pad, line_string)
      -- increase highlights first/last by pad size
      if line_highlights ~= nil then
        for _, hl in ipairs(line_highlights) do
          hl.first = hl.first + #pad
          hl.last = hl.last + #pad
        end
        lines_highlights[i] = line_highlights
      end
      if #display_lines[i] > widest_line_width then
        widest_line_width = #display_lines[i]
      end
    end
  else
    for i, item in self.display_items:ipairs() do
      local line_string = item
      local line_highlights = nil
      if fmt then
        line_string, line_highlights = fmt(item)
      end

      local tag
      if self.config.persist_tags_key then
        tag = H.prefix_tag(self:_get_persistent_tag_for(self.config.persist_tags_key(item)), self.config.prefix_key)
      else
        assert(tags ~= nil)
        tag = tags[i]
      end

      display_lines[i] = string.format("%s %s", tag, line_string)
      lines_highlights[i] = line_highlights

      if #display_lines[i] > widest_line_width then
        widest_line_width = #display_lines[i]
      end
    end
  end

  if self.config.open_win_override.title ~= nil then
    widest_line_width = math.max(widest_line_width, #self.config.open_win_override.title)
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
    vim.api.nvim_win_set_cursor(self.win, { preselect, 0 })
  end

  local tag_width = H.min_digits(#display_lines, #self.config.dictionary)

  -- Remove old tags from the buffer
  for _, old_tag in ipairs(self.old_tags) do
    pcall(vim.api.nvim_buf_del_keymap, self.buf, "n", old_tag)
    pcall(vim.api.nvim_buf_del_keymap, self.buf, "n", self.config.leader .. old_tag)
  end

  -- Clear old highlights
  vim.api.nvim_buf_clear_namespace(self.buf, Highlights.highlight_ns, 0, num_items)

  if self.config.persist_tags_key then
    for i, item in self.display_items:ipairs() do
      vim.api.nvim_buf_add_highlight(
        self.buf,
        Highlights.highlight_ns,
        Highlights.highlight_groups.hint.name,
        i - 1,
        0,
        tag_width
      )
      local tag = H.prefix_tag(self.tag_map[self.config.persist_tags_key(item)], self.config.prefix_key)
      vim.keymap.set("n", tag, function()
        tag_followed(self, self.display_items.offset + i - 1, false)
      end, { nowait = true, buffer = self.buf })
      -- Set leader variants
      vim.keymap.set("n", self.config.leader .. tag, function()
        tag_followed(self, self.display_items.offset + i - 1, true)
      end, { nowait = true, buffer = self.buf })
    end
  else
    assert(tags ~= nil)
    -- Set the highlights and keymaps for tags
    for i, tag in ipairs(tags) do
      vim.api.nvim_buf_add_highlight(
        self.buf,
        Highlights.highlight_ns,
        Highlights.highlight_groups.hint.name,
        i - 1,
        0,
        tag_width
      )
      vim.keymap.set("n", tag, function()
        tag_followed(self, self.display_items.offset + i - 1, false)
      end, { nowait = true, buffer = self.buf })
      -- Set leader variants
      vim.keymap.set("n", self.config.leader .. tag, function()
        tag_followed(self, self.display_items.offset + i - 1, true)
      end, { nowait = true, buffer = self.buf })
    end
  end

  -- Set line highlights
  for i, line_hl in ipairs(lines_highlights) do
    if line_hl ~= nil then
      for _, hl in ipairs(line_hl) do
        vim.api.nvim_buf_add_highlight(
          self.buf,
          Highlights.highlight_ns,
          hl.hlgroup,
          i - 1,
          tag_width + hl.first, -- offset by tag_width
          tag_width + hl.last -- offset by tag_width
        )
      end
    end
  end

  if self.config.persist_tags_key then
    self.old_tags = vim.tbl_map(function (t)
      return H.prefix_tag(t, self.config.prefix_key)
    end, vim.tbl_values(self.tag_map))
  else
    assert(tags ~= nil)
    self.old_tags = tags
  end

  vim.api.nvim_create_autocmd("WinLeave", {
    group = self.augroup,
    callback = function()
      self:close()
    end,
    desc = "Close Snipe menu on window leave",
    once = true,
  })
end

function Menu:open_over()
  return vim.fn.win_getid()
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
  local max_width = vim.o.columns

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
    row, col =
      math.floor((max_height + 2) / 2) - math.floor((height + 2) / 2),
      math.floor(max_width / 2) - math.floor((width + 2) / 2)
  elseif pos == "cursor" then
    -- Taken from telescope source
    local winbar = (function()
      if vim.fn.exists("&winbar") == 1 then
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

  local opts = self:get_window_opts(height, width)
  if self.config.position == "cursor" then
    -- Maintain initial window open position
    -- See issue #40
    local pos = vim.api.nvim_win_get_position(self.win)
    opts.row = pos[1]
    opts.col = pos[2]
  end
  vim.api.nvim_win_set_config(self.win, opts)

  -- clamp the old cursor position to the new window
  cursor_pos[1] = H.clamp(cursor_pos[1], 1, height)
  cursor_pos[2] = H.clamp(cursor_pos[2], 0, width)

  vim.api.nvim_win_set_cursor(self.win, { 1, 0 }) -- make sure first line is shown
  vim.api.nvim_win_set_cursor(self.win, cursor_pos)
  vim.api.nvim_win_set_hl_ns(self.win, Highlights.highlight_ns)
  self.config.set_window_local_options(self.win)
end

function Menu:create_window(bufnr, height, width)
  local win = vim.api.nvim_open_win(bufnr, false, self:get_window_opts(height, width))

  vim.api.nvim_win_set_hl_ns(win, Highlights.highlight_ns)
  self.config.set_window_local_options(win)

  return win
end

-- Note: id here is just the unique identifier for an item
function Menu:_get_persistent_tag_for(id)
  local tag = self.tag_map[id]
  if tag == nil then
    -- Find the minimum reference count
    local min
    for _, tn in ipairs(self.dict) do
      local rc = self.tag_refs[tn]
      if not min then
        min = { tn, rc }
      elseif rc < min[2] then
        min = { tn, rc }
      end
    end

    self.tag_refs[min[1]] = self.tag_refs[min[1]] + 1
    tag = {
      ord = min[2],
      name = min[1],
    }
    self.tag_map[id] = tag
  end
  return tag
end

function Menu:generate_persistent_tags(from, to)
    return H.generate_tags_in_range(from, to, self.dict)
end

-- Free tag for unique identifier
function Menu:free_tag(id)
  -- Only necessary if the id is in the tag map
  local tag = self.tag_map[id]
  if tag then
    self.tag_refs[tag.name] = self.tag_refs[tag.name] - 1
    for _, t in pairs(self.tag_map) do
      -- Decrement the order for all references to the tag
      -- this effectively removes a prefix
      if t.name == tag.name then
        t.ord = math.max(0, t.ord - 1)
      end
    end
  end
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

H.clamp = function(val, min, max)
  return math.min(math.max(val, min), max)
end

H.min_digits = function(n, base)
  return math.max(1, math.ceil(math.log(n, base)))
end

H.generate_dict_structs = function(dict_str)
  local dict = {}
  local refs = {}
  for i = 1, #dict_str do
    local char = dict_str:sub(i, i)
    table.insert(dict, char)
    refs[char] = 0
  end
  return dict, refs
end

local function generate_tag_aux(d, base, acc, dict)
  if d == 0 then
    return acc
  end
  return generate_tag_aux(math.floor(d / base), base, dict[d % base + 1] .. acc, dict)
end

local function generate_tag(d, dict)
  local acc = ""
  local base = #dict
  return generate_tag_aux(d, base, acc, dict)
end

local generate_tags_in_range = function(from, to, dict)
  local tags = {}
  local max = 0
  for i = from, to do
    local tag = generate_tag(i, dict);
    if #tag > max then
      max = #tag
    end
    table.insert(tags, tag)
  end
  return {tags, max}
end

local pad_tags = function(tags, to, zerov)
  local padded_tags = {}
  for _, tag in ipairs(tags) do
    table.insert(padded_tags, string.rep(zerov, to - #tag) .. tag)
  end
  return padded_tags
end

H.generate_tags_in_range = function (from, to, dict)
  local ret = generate_tags_in_range(from, to, dict);
  return pad_tags(ret[1], ret[2], dict[1])
end

H.generate_tags = function (n, dict)
  local ret = generate_tags_in_range(0, n, dict);
  return pad_tags(ret[1], ret[2], dict[1])
end

H.prefix_tag = function (t, prefix)
  return prefix:rep(t.ord) .. t.name
end

Highlights.create_default_hl()

return Menu
