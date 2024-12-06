local Snipe = {}
local H = {}

Snipe.setup = function(config)
  Snipe.config = H.setup_config(config)

  local SnipeMenu = require("snipe.menu")
  Snipe.global_menu = SnipeMenu:new({
    dictionary = Snipe.config.hints.dictionary,
    position = Snipe.config.ui.position,
    open_win_override = Snipe.config.ui.open_win_override,
    max_height = Snipe.config.ui.max_height,
    align = Snipe.config.ui.text_align == "file-first" and "left" or Snipe.config.ui.text_align,
    map_tags = Snipe.default_map_tags,
    set_window_local_options = Snipe.set_window_local_options,
  })
  Snipe.global_items = {}
end

H.default_config = {
  ui = {
    max_height = -1, -- -1 means dynamic height
    -- Where to place the ui window
    -- Can be any of "topleft", "bottomleft", "topright", "bottomright", "center", "cursor" (sets under the current cursor pos)
    position = "topleft",
    -- Override options passed to `nvim_open_win`
    -- Be careful with this as snipe will not validate
    -- anything you override here. See `:h nvim_open_win`
    -- for config options
    open_win_override = {
      -- title = "My Window Title",
      border = "single", -- use "rounded" for rounded border
    },

    -- Preselect the currently open buffer
    preselect_current = false,

    -- Set a function to preselect the currently open buffer
    -- E.g, `preselect = require("snipe").preselect_by_classifier("#")` to
    -- preselect alternate buffer (see :h ls and look at the "Indicators")
    preselect = nil, -- function (bs: Buffer[] [see lua/snipe/buffer.lua]) -> int (index)

    -- Changes how the items are aligned: e.g. "<tag> foo    " vs "<tag>    foo"
    -- Can be "left", "right" or "file-first"
    -- NOTE: "file-first" buts the file name first and then the directory name
    text_align = "left",
  },
  hints = {
    -- Charaters to use for hints (NOTE: make sure they don't collide with the navigation keymaps)
    dictionary = "sadflewcmpghio",
  },
  navigate = {
    -- When the list is too long it is split into pages
    -- `[next|prev]_page` options allow you to navigate
    -- this list
    next_page = "J",
    prev_page = "K",

    -- You can also just use normal navigation to go to the item you want
    -- this option just sets the keybind for selecting the item under the
    -- cursor
    under_cursor = "<cr>",

    -- In case you changed your mind, provide a keybind that lets you
    -- cancel the snipe and close the window.
    cancel_snipe = "<esc>",

    -- Close the buffer under the cursor
    -- Remove "j" and "k" from your dictionary to navigate easier to delete
    -- NOTE: Make sure you don't use the character below on your dictionary
    close_buffer = "D",

    -- Open buffer in vertical split
    open_vsplit = "V",

    -- Open buffer in split, based on `vim.opt.splitbelow`
    open_split = "H",

    -- Change tag manually
    change_tag = "C",
  },
  -- The default sort used for the buffers
  -- Can be any of "last", (sort buffers by last accessed) "default" (sort buffers by its number)
  sort = "default",
}

H.setup_config = function(config)
  config = config or {}
  vim.validate({ config = { config, "table", true } })
  config = vim.tbl_deep_extend("force", vim.deepcopy(H.default_config), config)

  local validation_set = {
    ["ui.max_width"] = { config.ui.max_width, "number", true },
    ["ui.position"] = { config.ui.position, "string", true },
    ["ui.open_win_override"] = { config.ui.open_win_override, "table", true },
    ["ui.preselect_current"] = { config.ui.preselect_current, "boolean", true },
    ["ui.preselect"] = { config.ui.preselect, "function", true },
    ["ui.text_align"] = { config.ui.text_align, "string", true },
    ["hints.dictionary"] = { config.hints.dictionary, "string", true },
    ["navigate.next_page"] = { config.navigate.next_page, "string", true },
    ["navigate.prev_page"] = { config.navigate.prev_page, "string", true },
    ["navigate.under_cursor"] = { config.navigate.under_cursor, "string", true },
    ["navigate.cancel_snipe"] = { config.navigate.cancel_snipe, "string", true },
    ["navigate.close_buffer"] = { config.navigate.close_buffer, "string", true },
    ["navigate.open_vsplit"] = { config.navigate.open_vsplit, "string", true },
    ["navigate.open_split"] = { config.navigate.open_split, "string", true },
    ["navigate.change_tag"] = { config.navigate.change_tag, "string", true },
    ["sort"] = { config.sort, "string", true },
  }

  vim.validate(validation_set)

  -- Make sure they are not using preselect_current and preselect
  if config.ui.preselect ~= nil and config.ui.preselect_current then
    vim.notify("(snipe) Conflicting options: ui.preselect_current is set true while ui.preselect is not nil")
  end

  -- Validate hint characters and setup tables
  if #config.hints.dictionary < 2 then
    vim.notify("(snipe) Dictionary must have at least 2 items", vim.log.levels.ERROR)
    return config
  end

  return config
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

function Snipe.default_keymaps(m)
  local nav_next = function()
    m:goto_next_page()
    m:reopen()
  end

  local nav_prev = function()
    m:goto_prev_page()
    m:reopen()
  end

  vim.keymap.set("n", Snipe.config.navigate.next_page, nav_next, { nowait = true, buffer = m.buf })
  vim.keymap.set("n", Snipe.config.navigate.prev_page, nav_prev, { nowait = true, buffer = m.buf })
  vim.keymap.set("n", Snipe.config.navigate.close_buffer, function()
    local hovered = m:hovered()
    local bufnr = m.items[hovered].id
    -- I have to hack switch back to main window, otherwise currently background focused
    -- window cannot be deleted when focused on a floating window
    m.opened_from_wid = m:open_over()
    vim.api.nvim_set_current_win(m.opened_from_wid)
    vim.api.nvim_buf_delete(bufnr, { force = true })
    vim.api.nvim_set_current_win(m.win)
    table.remove(m.items, hovered)
    m:reopen()
  end, { nowait = true, buffer = m.buf })

  vim.keymap.set("n", Snipe.config.navigate.open_vsplit, function()
    local bufnr = m.items[m:hovered()].id
    m:close() -- make sure to call first !
    vim.api.nvim_open_win(bufnr, true, { vertical = true, win = 0 })
  end, { nowait = true, buffer = m.buf })

  vim.keymap.set("n", Snipe.config.navigate.open_split, function()
    local split_direction = vim.opt.splitbelow:get() and "below" or "above"
    local bufnr = m.items[m:hovered()].id
    m:close() -- make sure to call first !
    vim.api.nvim_open_win(bufnr, true, { split = split_direction, win = 0 })
  end, { nowait = true, buffer = m.buf })

  vim.keymap.set("n", Snipe.config.navigate.cancel_snipe, function()
    m:close()
  end, { nowait = true, buffer = m.buf })
  vim.keymap.set("n", Snipe.config.navigate.under_cursor, function()
    local hovered = m:hovered()
    m:close()
    vim.api.nvim_set_current_buf(m.items[hovered].id)
  end, { nowait = true, buffer = m.buf })

  vim.keymap.set("n", Snipe.config.navigate.change_tag, function()
    local item_id = m:hovered()
    vim.ui.input({ prompt = "Enter custom tag: " }, function(input)
      table.insert(Snipe.index_to_tag, { index = item_id, tag = input })
      m:reopen()
    end)
  end, { nowait = true, buffer = m.buf })
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
  local cmd = Snipe.config.sort == "last" and "ls t" or "ls"
  Snipe.global_items = require("snipe.buffer").get_buffers(cmd)
  if Snipe.config.ui.text_align == "file-first" then
    Snipe.global_items = Snipe.file_first_format(Snipe.global_items)
  end
  Snipe.global_menu:add_new_buffer_callback(Snipe.default_keymaps)

  if Snipe.config.ui.preselect then
    local i = Snipe.config.ui.preselect(Snipe.global_items)
    Snipe.global_menu:open(Snipe.global_items, Snipe.default_select, Snipe.default_fmt, i)
  elseif Snipe.config.ui.preselect_current then
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
  Snipe.ui_select_menu.config.open_win_override.title = Snipe.config.ui.open_win_override.title
end

return Snipe
