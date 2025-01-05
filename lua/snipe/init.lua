local Snipe = {}
local Config = require("snipe.config")

Snipe.setup = function(config)
  Config.setup(config)
  --- @deprecated Snipe.config is deprecated, use require('snipe.config') instead
  Snipe.config = Config

  local SnipeMenu = require("snipe.menu")
  Snipe.global_menu = SnipeMenu:new({
    map_tags = Snipe.default_map_tags,
    set_window_local_options = Snipe.set_window_local_options,
  })
  Snipe.global_items = {}
end

function Snipe.set_window_local_options(wid)
  vim.wo[wid].foldenable = false
  vim.wo[wid].wrap = false
  vim.wo[wid].cursorline = true
end

Snipe.index_to_tag = {}

function Snipe.default_map_tags(tags)
  for _, index_and_tag in ipairs(Snipe.index_to_tag) do
    tags[index_and_tag.index] = index_and_tag.tag
  end
  return tags
end

---@param m snipe.Menu
function Snipe.default_keymaps(m)
  m:default_keymaps({
    under_cursor = function()
      local hovered = m:hovered()
      m:close()
      vim.api.nvim_set_current_buf(m.items[hovered].id)
    end,
  })

  local opts = { nowait = true, buffer = m.buf }

  -- Specific keymaps
  vim.keymap.set("n", Config.navigate.close_buffer, function()
    local hovered = m:hovered()
    local bufnr = m.items[hovered].id
    -- I have to hack switch back to main window, otherwise currently background focused
    -- window cannot be deleted when focused on a floating window
    m.opened_from_wid = m:open_over()
    vim.api.nvim_set_current_win(m.opened_from_wid)

    local ok, snacks = pcall(require, "snacks")
    if ok then
      snacks.bufdelete(bufnr)
    else
      vim.api.nvim_buf_delete(bufnr, { force = false })
    end

    vim.api.nvim_set_current_win(m.win)
    table.remove(m.items, hovered)
    m:reopen()
  end, opts)

  vim.keymap.set("n", Config.navigate.open_vsplit, function()
    local bufnr = m.items[m:hovered()].id
    m:close() -- make sure to call first !
    vim.api.nvim_open_win(bufnr, true, { vertical = true, win = 0 })
  end, opts)

  vim.keymap.set("n", Config.navigate.open_split, function()
    local split_direction = vim.opt.splitbelow:get() and "below" or "above"
    local bufnr = m.items[m:hovered()].id
    m:close() -- make sure to call first !
    vim.api.nvim_open_win(bufnr, true, { split = split_direction, win = 0 })
  end, opts)

  vim.keymap.set("n", Config.navigate.change_tag, function()
    local item_id = m:hovered()
    vim.ui.input({ prompt = "Enter custom tag: " }, function(input)
      table.insert(Snipe.index_to_tag, { index = item_id, tag = input })
      m:reopen()
    end)
  end, opts)
end

Snipe.directory_separator = "@"

-- Function is used when "file-first" is set as `ui.text_align`
function Snipe.file_first_format(buffers)
  for i, item in ipairs(buffers) do
    local e = item.name
    local basename = vim.fs.basename(e)
    local dirname = vim.fs.dirname(e)
    buffers[i].meta = { prefix = basename, dir = dirname }
  end

  local max = 0
  for _, e in ipairs(buffers) do
    if #e.meta.prefix > max then
      max = #e.meta.prefix
    end
  end

  for i, e in ipairs(buffers) do
    local padding_len = max - #e.meta.prefix
    local padding = string.rep(" ", padding_len)
    if e.meta.dir ~= nil then
      buffers[i].pre_formatted =
        string.format("%s%s %s %s", e.meta.prefix, padding, Snipe.directory_separator, e.meta.dir)
    else
      buffers[i].pre_formatted = string.format("%s", e.meta.prefix)
    end
  end

  return buffers
end

function Snipe.default_fmt(item)
  if item.pre_formatted ~= nil then
    return item.pre_formatted
  end
  return item.name
end

function Snipe.default_select(m, i)
  Snipe.global_menu:close()
  m.opened_from_wid = m:open_over()
  vim.api.nvim_set_current_win(m.opened_from_wid)
  vim.api.nvim_set_current_buf(m.items[i].id)
end

function Snipe.preselect_by_classifier(classifier)
  return function(bs)
    for i, b in ipairs(bs) do
      -- Check if the classifier is anywhere in the classifier string
      for j = 1, #b.classifiers do
        if b.classifiers:sub(j, j) == classifier then
          return i
        end
      end
    end
    return 1 -- default select the first item if classifier not found
  end
end

function Snipe.open_buffer_menu()
  local cmd = Config.sort == "last" and "ls t" or "ls"
  Snipe.global_items = require("snipe.buffer").get_buffers(cmd)
  if Config.ui.text_align == "file-first" then
    Snipe.global_items = Snipe.file_first_format(Snipe.global_items)
  end
  Snipe.global_menu:add_new_buffer_callback(Snipe.default_keymaps)

  if Config.ui.preselect then
    local i = Config.ui.preselect(Snipe.global_items)
    Snipe.global_menu:open(Snipe.global_items, Snipe.default_select, Snipe.default_fmt, i)
  elseif Config.ui.preselect_current then
    local opened = false
    for i, b in ipairs(Snipe.global_items) do
      if b.classifiers:sub(2, 2) == "%" then
        Snipe.global_menu:open(Snipe.global_items, Snipe.default_select, Snipe.default_fmt, i)
        opened = true
      end
    end
    if not opened then
      Snipe.global_menu:open(Snipe.global_items, Snipe.default_select, Snipe.default_fmt)
    end
  else
    Snipe.global_menu:open(Snipe.global_items, Snipe.default_select, Snipe.default_fmt)
  end
end

Snipe.ui_select_menu = nil

-- Can be set as your `vim.ui.select`
---@param items any[] Arbitrary items
---@param opts table Additional options
---@param on_choice fun(item: any|nil, idx: integer|nil)
function Snipe.ui_select(items, opts, on_choice)
  if Snipe.ui_select_menu == nil then
    vim.notify("Must instanciate `require('snipe').ui_select_menu' before using `ui_select'", vim.log.levels.ERROR)
    return
  end

  if opts.prompt ~= nil then
    Snipe.ui_select_menu.config.open_win_override.title = opts.prompt
  end
  Snipe.ui_select_menu:open(items, function(m, i)
    on_choice(m.items[i], i)
    m:close()
  end, opts.format_item)
  Snipe.ui_select_menu.config.open_win_override.title = Config.ui.open_win_override.title
end

return Snipe
