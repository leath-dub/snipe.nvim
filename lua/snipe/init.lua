local Snipe = {}
local Buffer = require("snipe.buffer")
local Config = require("snipe.config")
local Highlights = require("snipe.highlights")

Snipe.setup = function(config)
  Config.setup(config)
  --- @deprecated Snipe.config is deprecated, use require('snipe.config') instead
  Snipe.config = Config

  local SnipeMenu = require("snipe.menu")
  Snipe.global_menu = SnipeMenu:new({
    map_tags = Snipe.default_map_tags,
    set_window_local_options = Snipe.set_window_local_options,
  })
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

---create "format" function based on Config.ui options
---@param buffers snipe.Buffer[]
---@return function
function Snipe.create_buffer_formatter(buffers)
  if Config.ui.buffer_format ~= nil then -- custom buffer_format takes precedence
    return Snipe.default_fmt(Config.ui.buffer_format)
  elseif Config.ui.text_align == "file-first" then -- pre-format basename if text_align is "file-first"
    local max_name_length = #buffers[1].basename
    for _, buf in ipairs(buffers) do
      if #buf.basename > max_name_length then
        max_name_length = #buf.basename
      end
    end
    return Snipe.default_fmt({
      "icon",
      function(buffer)
        return buffer.basename .. string.rep(" ", max_name_length - #buffer.basename)
      end,
      "directory",
    })
  else -- return full name if text_align is "left"|"right", actual alignment will be done by `Menu`
    return Snipe.default_fmt({
      function(buffer)
        return buffer.name
      end,
    })
  end
end

---create format function for `Menu`
---@param line_format (string|function)[]
---@return fun(buf: snipe.Buffer): string, {first: integer, last: integer, hlgroup: string}[] - format function
function Snipe.default_fmt(line_format)
  return function(item)
    ---@type { first: integer, last: integer, hlgroup: string}[]
    local highlights = {}
    local result = ""
    local hl_start_index = 1

    for _, format in ipairs(line_format) do
      if format == "filename" then
        result = result .. item.basename .. " "
        table.insert(highlights, {
          first = hl_start_index,
          last = hl_start_index + #item.basename + 1,
          hlgroup = Highlights.highlight_groups.filename.name,
        })
        hl_start_index = hl_start_index + #item.basename + 1
      elseif format == "directory" then
        result = result .. item.dirname .. " "
        table.insert(highlights, {
          first = hl_start_index,
          last = hl_start_index + #item.dirname + 1,
          hlgroup = Highlights.highlight_groups.dirname.name,
        })
        hl_start_index = hl_start_index + #item.dirname + 1
      elseif format == "icon" then
        -- try mini.icons
        if _G.MiniIcons then
          local icon, hl = MiniIcons.get("file", item.basename)
          result = result .. icon .. " "
          table.insert(highlights, {
            first = hl_start_index,
            last = hl_start_index + #icon + 1,
            hlgroup = hl,
          })
          hl_start_index = hl_start_index + #icon + 1
        end
        -- TODO: try nvim-web-devicons
        --
        -- ignore "icon" altogether if no supported icon provider found
      else
        local text, hl = nil, nil
        if type(format) == "string" then
          text = format
        elseif type(format) == "function" then
          text, hl = format(item)
        else
          -- invalid format passed, ignore
        end
        if text then
          result = result .. text .. " "
          table.insert(highlights, {
            first = hl_start_index,
            last = hl_start_index + #text + 1,
            hlgroup = hl or Highlights.highlight_groups.text.name,
          })
          hl_start_index = hl_start_index + #text + 1
        end
      end
    end
    return result, highlights
  end
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
  ---@type snipe.Buffer[]
  local buffers = Buffer.get_buffers(cmd)
  local format_buffer = Snipe.create_buffer_formatter(buffers)
  Snipe.global_menu:add_new_buffer_callback(Snipe.default_keymaps)

  if Config.ui.preselect then
    local i = Config.ui.preselect(buffers)
    Snipe.global_menu:open(buffers, Snipe.default_select, format_buffer, i)
  elseif Config.ui.preselect_current then
    local opened = false
    for i, b in ipairs(buffers) do
      if b.classifiers:sub(2, 2) == "%" then
        Snipe.global_menu:open(buffers, Snipe.default_select, format_buffer, i)
        opened = true
      end
    end
    if not opened then
      Snipe.global_menu:open(buffers, Snipe.default_select, format_buffer)
    end
  else
    Snipe.global_menu:open(buffers, Snipe.default_select, format_buffer)
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
