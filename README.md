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
    max_width = -1, -- -1 means dynamic width
    -- Where to place the ui window
    -- Can be any of "topleft", "bottomleft", "topright", "bottomright", "center", "cursor" (sets under the current cursor pos)
    position = "topleft",
  },
  hints = {
    -- Characters to use for hints (NOTE: make sure they don't collide with the navigation keymaps)
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
    -- NOTE: Make sure you don't use the character below in your dictionary
    close_buffer = "D",
  },
  -- Define the way buffers are sorted by default
  -- Can be any of "default" (sort buffers by their number) or "last" (sort buffers by last accessed)
  sort = "default"
}
```

You can also pass options to `create_buffer_menu_toggler`:

```lua
{
  -- Limit the width of path buffer names
  -- /my/long/path/is/really/annoying will be is/really/annoying (max of 3)
  max_path_width = 3
}
```

## Events

The following `User` events can be hooked into:

* `SnipeCreateBuffer` - event is triggered after tag and default mappings are set. The following code allows you to hook into this:

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "SnipeCreateBuffer",
  callback = function (args)
    -- | Format of `args`:
    --
    -- args = {
    --   data = {
    --     menu = {
    --       close = <function>,
    --       open = <function>,
    --       is_open = <function>,
    --     }
    --     buf = <menu bufnr>,
    --   }
    -- }

    -- Do something with args
  end,
})
```

## Producers

A producer is just a function that returns two lists (tables), the first is a `user/meta-data` table, this is will
later be passed into a callback allowing you to give context to the selections (e.g. for buffer producer the `meta-data`
is the list of buffer-id's). The second table is the list of actual strings you want to list as selections.

Below is an example of a file producer:

```lua
local function file_menu_toggler()
  local function file_producer()
    local uv = (vim.loop or vim.uv)
    local items = {}

    for name, type in vim.fs.dir(uv.cwd()) do
      table.insert(items, { type, name })
    end

    local items_display = vim.tbl_map(function (ent)
      return string.format("%s %s", (ent[1] == "file" and "F" or "D"), ent[2])
    end, items)

    return items, items_display
  end

  return snipe.create_menu_toggler(file_producer, function (meta, _) vim.cmd.edit(meta[2]) end)
end

vim.keymap.set("n", "<leader>f", file_menu_toggler())
```

This lets you navigate files in the current directory with `<leader>f`
