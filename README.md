# Snipe.nvim

Efficient targetted menu built for fast buffer navigation

![recording](https://github.com/user-attachments/assets/a0804e7f-5a04-4e5c-9274-e5eab7a36dc7)

## Description

`Snipe.nvim` is selection menu that can accept any list of items
and present a user interface with quick minimal character navigation
hints to select exactly what you want. It is not flashy it is just
fast !

## Motivation

If you ever find yourself in a tangle of buffers scrabbling to find
your way back to where you came from, this plugin can help ! Maybe
you use harpoon, this is great for project files, but what if you
want a fast fallback for when you're in someone else's project. Maybe
you use telescope, but that can feel inconsistent and visually
distracting. This is why I made this, because I wanted a [Vimium-like](https://github.com/philc/vimium)
way of hopping around a large amount of buffers

## Usage

For `lazy.nvim`:

```lua
{
  "leath-dub/snipe.nvim",
  keys = {
    {"gb", function () require("snipe").open_buffer_menu() end, desc = "Open Snipe buffer menu"}
  },
  opts = {}
}
```

For `packadd` (builtin package manager), clone the repo into `$HOME/.config/nvim/pack/snipe/opt/snipe.nvim` and add this to your configuration:

```lua
vim.cmd.packadd "snipe.nvim"
local snipe = require("snipe")
snipe.setup()
vim.keymap.set("n", "gb", snipe.open_buffer_menu)
```

## Options

You can pass in a table of options to the `setup` function, here are the default options:

```lua
Snipe.config = {
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
    preselect_current = true,
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
  },
  -- The default sort used for the buffers
  -- Can be any of "last", (sort buffers by last accessed) "default" (sort buffers by its number)
  sort = "default"
}
```

## `vim.ui.select` wrapper

Snipe nvim can act as your `vim.ui.select` menu, which is what is used for "code actions" in LSP
among other things. You can set this up like so:

```lua
local snipe = require("snipe")
snipe.ui_select_menu = require("snipe.menu"):new { position = "center" }
snipe.ui_select_menu:add_new_buffer_callback(function (m)
  vim.keymap.set("n", "<esc>", function ()
    m:close()
  end, { nowait = true, buffer = m.buf })
end)
vim.ui.select = snipe.ui_select;
```

This makes `vim.ui.select` menus open in the center, with `<esc>` to cancel.

## Development

The older API, as I am sure contributors are aware, was shite! The new API is
based on creating a `Menu` which is just a state object mostly just maintaining
a buffer, a window and what page you are on. There is no longer a concept of
`generator`/`producer` functions, each call to `open` on the window just
accepts a list of items to show. All of the old global config was implemented
much easier using this api. A minimal example of a menu is the following:

```lua
local Menu = require("snipe.menu")
local menu = Menu:new {
  -- Per-menu configuration (does not affect global configuration)
  position = "center"
}

-- The items to snipe is just an array
-- Be careful how you reference the array in closures though
-- if you have the items table created inside a closure
-- as uncommented when setting the open keymap a few lines down,
-- this means that the items array will change every trigger and
-- can be an outdated capture in sub-closures.
local items = { "foo", "bar", "baz" }

vim.keymap.set("n", "gb", function()
  -- local items = { ... }

  -- This method allows you to add `n' callbacks to be
  -- triggered whenever a new buffer is created.
  -- A new buffer is only ever created if it is somehow
  -- externally removed or at normal startup. The reason
  -- For this system is so that you can update any buffer local
  -- keymaps and alike to work for the new buffer.
  menu:add_new_buffer_callback(function(m)
    -- `m` is a reference to the menu, prefer referencing it via this (i.e. not through your menu variable) !

    -- Keymaps like "open in split" etc can be put in here
    print("I dont want any other keymaps X( !")
  end)

  menu:open(items, function (m, i)
    -- Prefer accessing items on the menu itself (m.items not items) !
    print("You selected: " .. m.items[i])
    print("You are hovering over: " .. m.items[m:hovered()])
    -- Close the menu
    m:close()
    -- You can also call `reopen` for things like navigating
    -- between pages when the window can stay open and just
    -- needs to be updated.
  end, function (item)
    -- Format function means you don't just have to pass a list of strings
    -- you get to format each item as you choose.
    return item
  end, 10 -- the item to preselect, if it is out of bounds of the currently shown page
          -- it is ignored
  )
end)
```

### Example ( File browser )

```lua
local uv = vim.uv or vim.loop

local menu = require("snipe.menu"):new()
local items

local function set_keymaps(m)
  vim.keymap.set("n", "<esc>", function()
    m:close()
  end, { nowait = true, buffer = m.buf })
  vim.keymap.set("n", "..", function()
    local dir = vim.fs.dirname(m.items[1].name)
    if uv.fs_realpath(dir) ~= "/" then
      dir = ".." .. (dir == "." and "" or "/" .. dir)
    end
    new_dir(vim.fn.resolve(dir))
    m.items = items
    m:reopen()
  end, { nowait = true, buffer = m.buf })
end
menu:add_new_buffer_callback(set_keymaps)

local function new_dir(dir_name)
  local dir = uv.fs_opendir(dir_name)
  items = {}
  while true do
    local ent = dir:readdir()
    if not ent then
      break
    end

    if dir_name ~= uv.cwd() then
      ent[1].name = dir_name .. "/" .. ent[1].name
    end

    table.insert(items, ent[1])
  end
  dir:closedir()
end

vim.keymap.set("n", "cd", function()
  new_dir(uv.cwd())

  menu:open(items, function(m, i)
    if m.items[i].type == "directory" then
      new_dir(m.items[i].name)
      m.items = items
      m:reopen()
    else
      m:close()
      vim.cmd.edit(m.items[i].name)
    end
  end, function (item)
    if item.type == "directory" then
      return item.name .. "/"
    end
    return item.name
  end)
end)
```

### Example (Modal Buffer menu)

The following code has a single menu that has different actions on the selected
item depending on what keybind you open it with (`<leader>o` or `<leader>d`):

```lua
local menu = require("snipe.menu"):new()
local items

-- Other default mappings can be set here too
local function set_keymaps(m)
  vim.keymap.set("n", "<esc>", function()
    m:close()
  end, { nowait = true, buffer = m.buf })
end
menu:add_new_buffer_callback(set_keymaps)

vim.keymap.set("n", "<leader>o", function()
  items = require("snipe.buffer").get_buffers()
  menu.config.open_win_override.title = "Snipe [Open]"
  menu:open(items, function(m, i)
    m:close()
    vim.api.nvim_set_current_buf(m.items[i].id)
  end, function (item) return item.name end)
end)

vim.keymap.set("n", "<leader>d", function()
  items = require("snipe.buffer").get_buffers()
  menu.config.open_win_override.title = "Snipe [Delete]"
  menu:open(items, function(m, i)
    local bufnr = m.items[i].id
    -- I have to hack switch back to main window, otherwise currently background focused
    -- window cannot be deleted when focused on a floating window
    local current_tabpage = vim.api.nvim_get_current_tabpage()
    local root_win = vim.api.nvim_tabpage_list_wins(current_tabpage)[1]
    vim.api.nvim_set_current_win(root_win)
    vim.api.nvim_buf_delete(bufnr, { force = true })
    vim.api.nvim_set_current_win(m.win)
    table.remove(m.items, i)
    m:reopen()
  end, function (item) return item.name end)
end)
```
