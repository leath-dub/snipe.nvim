local Snipe = {}
local H = {}

Snipe.setup = function(config)
  config = H.setup_config(config)
  H.apply_config(config)
  H.create_default_hl()
end

Snipe.config = {
  ui = {
    max_width = -1, -- -1 means dynamic width
    -- Where to place the ui window
    -- Can be any of "topleft", "bottomleft", "topright", "bottomright", "center", "cursor" (sets under the current cursor pos)
    position = "topleft",
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
  },
}

--- Creates a snipe menu
---
--- A producer must return a tuple where the first component is
--- some user data (anything) associated with the second component
--- being the string value of the item to show
---
---@generic T
---@param producer fun(): table<T>, table<string> (function) Function
---@param callback fun(meta: T, index: integer) (function) Function
---@return table { open = fun(), close = fun(), is_open = fun() } : Table of menu functions
Snipe.menu = function(producer, callback)
  local window_unset = -1
  local buffer = H.create_buffer()
  local state = {
    buffer = buffer,
    window = window_unset,
    bindings = {},
    page_index = 1,
  }

  local function is_open()
    return vim.api.nvim_win_is_valid(state.window) or not window_unset
  end

  local function close()
    vim.api.nvim_buf_delete(state.buffer, { force = true })
    state.window = window_unset
  end

  local function open()
    if not vim.api.nvim_win_is_valid(state.window) then
      if vim.api.nvim_buf_is_valid(state.buffer) then
        -- Probably not likely to be possible but just in case don't wan't to leak a buffer
        vim.api.nvim_buf_delete(state.buffer, { force = true })
      end

      -- Create fresh window and buffer
      state.buffer = H.create_buffer()
      state.window = window_unset
    end

    local meta, items = producer()
    local max_height = H.window_get_max_height() - 1

    if #meta == 0 then
      vim.notify("(snipe) No items", vim.log.levels.WARNING)
      return
    end

    if #meta ~= #items then
      vim.notify("(snipe) Meta-data length from producer does not match the number of items", vim.log.levels.ERROR)
      return
    end

    local page_count = math.max(1, math.ceil(#items / max_height))

    state.page_index = state.page_index > page_count
      and page_count -- clamp
      or state.page_index

    local item_count = max_height
    local last_page = state.page_index == page_count
    if last_page then
      item_count = #items % max_height
    end

    local off = (state.page_index - 1) * max_height + 1
    local page_items = vim.list_slice(items, off, off + item_count)

    vim.bo[state.buffer].modifiable = true

    local annotated_page_items = H.annotate_with_tags(page_items)
    local annotated_raw_page_items = vim.tbl_map(function (ent)
      return table.concat(ent, " ")
    end, annotated_page_items)

    vim.api.nvim_buf_set_lines(state.buffer, 0, -1, false, annotated_raw_page_items)

    if state.window == window_unset then
      if Snipe.config.ui.max_width ~= -1 then
        state.window = H.create_window(state.buffer, #page_items, Snipe.config.ui.max_width)
      else
        local max = 1
        for i, s in ipairs(annotated_raw_page_items) do
          max = #s > #annotated_raw_page_items[max] and i or max
        end
        state.window = H.create_window(state.buffer, #page_items, #annotated_raw_page_items[max])
      end
    end

    vim.api.nvim_win_set_height(state.window, #page_items)
    vim.api.nvim_set_current_win(state.window)
    vim.api.nvim_win_set_hl_ns(state.window, H.highlight_ns)

    vim.bo[state.buffer].modifiable = false
    vim.wo[state.window].foldenable = false
    vim.wo[state.window].wrap = false
    vim.wo[state.window].cursorline = true

    vim.api.nvim_exec_autocmds("User", {
      pattern = "SnipeCreateBuffer",
      data = {
        menu = {
          open = open,
          close = close,
          is_open = is_open,
        },
        buf = state.buffer,
      },
    })

    -- TODO investicate vim.fn.getcharstr() a bit more for this
    local max_width = H.min_digits(#page_items, #H.hints.dictionary)

    for i, pair in ipairs(annotated_page_items) do
      vim.api.nvim_buf_add_highlight(state.buffer, H.highlight_ns, "SnipeHint", i - 1, 0, max_width)

      vim.keymap.set("n", pair[1], function ()
        close()
        callback(meta[i], off + i - 1)
      end, { nowait = true, buffer = state.buffer })
    end

    vim.keymap.set("n", Snipe.config.navigate.next_page, function()
      state.page_index = math.min(state.page_index + 1, page_count)
      close() -- close so keymaps get freed
      open()
    end, { nowait = true, buffer = state.buffer })

    vim.keymap.set("n", Snipe.config.navigate.under_cursor, function()
      local pos = vim.api.nvim_win_get_cursor(state.window)
      close()
      callback(meta[pos[1]], off + pos[1] - 1)
    end, { nowait = true, buffer = state.buffer })


    vim.keymap.set("n", Snipe.config.navigate.prev_page, function()
      state.page_index = math.max(state.page_index - 1, 1)
      close() -- close so keymaps get freed
      open()
    end, { nowait = true, buffer = state.buffer })

    vim.keymap.set("n", Snipe.config.navigate.cancel_snipe, function()
      close()
    end, { nowait = true, buffer = state.buffer })
  end

  return {
    open = open,
    close = close,
    is_open = is_open,
  }
end

--- Creates a toggle menu
---
--- Wraps the Snipe.menu such that this function closes
--- the menu when its open and opens the menu when its
--- closed
---
---@generic T
---@param producer fun(): table<T>, table<string> (function) Function
---@param callback fun(meta: T, index: integer) (function) Function
Snipe.create_menu_toggler = function(producer, callback)
  local menu = Snipe.menu(producer, callback)
  return function()
    if menu.is_open() then
      menu.close()
    else
      menu.open()
    end
  end
end

---@deprecated Use `create_toggle_menu` instead
Snipe.toggle_menu = Snipe.create_menu_toggler

Snipe.create_buffer_menu_toggler = function(bopts_)
  local bopts = bopts_ or {}
  return Snipe.create_menu_toggler(function() return Snipe.buffer_producer(bopts) end, function(bufnr, _)
    vim.api.nvim_set_current_buf(bufnr)
  end)
end

---@deprecated Use `create_toggle_buffer_menu` instead
Snipe.toggle_buffer_menu = Snipe.create_buffer_menu_toggler

Snipe.open_buffer_menu = function(bopts_)
	Snipe.create_buffer_menu_toggler(bopts_)()
end

--- Buffer producer lists open buffers
---
---@return table<integer>, table<string>
Snipe.buffer_producer = function(opts_)
  local opts = opts_ or {}

  local bufnrs = vim.tbl_filter(function (b)
    return vim.fn.buflisted(b) == 1
  end, vim.api.nvim_list_bufs())

  local bufnames = vim.tbl_map(function (b)

    local name = vim.fn.bufname(b)
    if #name == 0 then
      return "[No Name]"
    end

    local res = name:gsub(vim.env.HOME, "~", 1)

    if opts.max_path_width ~= nil then
      local rem = name
      res = ""
      for _ = 1, opts.max_path_width do
        if vim.fs.dirname(rem) == rem then
          break
        end
        if res ~= "" then
          res = "/" .. res
        end
        if rem == vim.env.HOME then
          res = "~" .. res
        else
          res = vim.fs.basename(rem) .. res
        end
        rem = vim.fs.dirname(rem)
      end
    end

    return res
  end, bufnrs)

  return bufnrs, bufnames
end

H.hints = {
  dictionary = {},
  dictionary_index = {},
}

H.default_config = vim.deepcopy(Snipe.config)

H.setup_config = function(config)
  vim.validate({ config = { config, "table", true } })
  config = vim.tbl_deep_extend("force", vim.deepcopy(H.default_config), config or {})

  vim.validate({
    ["ui.max_width"] = { config.ui.max_width, "number", true },
    ["ui.position"] = { config.ui.position, "string", true },
    ["hints.dictionary"] = { config.hints.dictionary, "string", true },
    ["navigate.next_page"] = { config.navigate.next_page, "string", true },
    ["navigate.prev_page"] = { config.navigate.prev_page, "string", true },
    ["navigate.under_cursor"] = { config.navigate.under_cursor, "string", true },
  })

  -- Validate hint characters and setup tables
  if #config.hints.dictionary < 2 then
    vim.notify("(snipe) Dictionary must have at least 2 items", vim.log.levels.ERROR)
    return config
  end

  for i = 1, #config.hints.dictionary do
    local c = config.hints.dictionary:sub(i, i)
    if H.hints.dictionary_index[c] ~= nil then -- duplicate
      vim.notify("(snipe) Dictionary must have unique items: ignoring duplicates", vim.log.levels.WARNING)
    else
      table.insert(H.hints.dictionary, c)
      H.hints.dictionary_index[c] = i
    end
  end

  return config
end

H.apply_config = function(config) Snipe.config = config end

H.annotate_with_tags = function(items)
  local tags = H.generate_tags(#items)
  local i = 0

  return vim.tbl_map(function (ent)
    i = i + 1
    return {tags[i], ent}
  end, items)
end

H.min_digits = function(n, base)
  return math.max(1, math.ceil(math.log(n, base)))
end

-- Generating tags is essentially a generalized
-- form of counting where our unique digits is the
-- dictionary of characters with base = #characters
H.generate_tags = function(n)
  local max = H.hints.dictionary[#H.hints.dictionary]

  local function inc_digit(digit)
    return H.hints.dictionary[(H.hints.dictionary_index[digit] + 1) % (#H.hints.dictionary + 1)]
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
        table.insert(num, H.hints.dictionary[1])
        i = 1
        num[i] = H.hints.dictionary[1]
      end

      -- i is what we need to increment and zero everything after it
      num[i] = inc_digit(num[i])
      for s = i + 1, #num do
        num[s] = H.hints.dictionary[1]
      end

      return num
    end

    num[#num] = inc_digit(last)
    return num
  end

  -- This is so we can add trailing "0": where "0" is just first item in dictionary
  local max_width = H.min_digits(n, #H.hints.dictionary)

  local tags = {}
  local tag = {H.hints.dictionary[1]}
  for _ = 1, n do
    local lead = string.rep(H.hints.dictionary[1], max_width - #tag)
    table.insert(tags, lead .. table.concat(tag))
    tag = inc(tag)
  end

  return tags
end

H.create_buffer = function()
  return vim.api.nvim_create_buf(false, false)
end

H.create_window = function(bufnr, height, width)
  local row, col = 0, 0
  local anchor = "NW"
  local pos = Snipe.config.ui.position

  local max_height = H.window_get_max_height()
  local max_width = vim.fn.winwidth(0)

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

  local winnr = vim.api.nvim_open_win(bufnr, false, {
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

  return winnr
end

H.create_default_hl = function()
  H.highlight_ns = vim.api.nvim_create_namespace("")
  vim.api.nvim_set_hl(H.highlight_ns, "SnipeHint", { link = "CursorLineNr" })
end

-- From https://github.com/echasnovski/mini.nvim
H.window_get_max_height = function()
  local has_tabline = vim.o.showtabline == 2 or (vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1)
  local has_statusline = vim.o.laststatus > 0
  -- Remove 2 from maximum height to account for top and bottom borders
  return vim.o.lines - vim.o.cmdheight - (has_tabline and 1 or 0) - (has_statusline and 1 or 0) - 2
end

return Snipe
