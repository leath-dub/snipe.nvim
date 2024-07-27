# Snipe.nvim

Efficient targetted menu built for fast buffer navigation

[demo](https://imgur.com/a/Mh5AccG)

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
  setup = function()
    local snipe = require("snipe")
    snipe.setup()
    vim.keymap.set("n", "gb", snipe.toggle_buffer_menu())
  end
}
```

For `packadd` (builtin package manager), clone the repo into `$HOME/.config/nvim/pack/snipe/opt/snipe.nvim` and add this to your configuration:

```lua
vim.cmd.packadd "snipe.nvim"
local snipe = require("snipe")
snipe.setup()
vim.keymap.set("n", "gb", snipe.toggle_buffer_menu())
```

## Options

You can pass in a table of options to the `setup` function, here are the default options:

```lua
Snipe.config = {
  ui = {
    max_width = -1, -- -1 means dynamic width
  },
  hints = {
    -- Charaters to use for hints (NOTE: make sure they don't collide with the navigation keymaps)
    dictionary = "sadfjklewcmpgh",
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
    under_cursor = "<cr>"
  },
}
```

## Producers

A producer is just a function that returns two lists (tables), the first is a `user/meta-data` table, this is will
later be passed into a callback allowing you to give context to the selections (e.g. for buffer producer the `meta-data`
is the list of buffer-id's). The second table is the list of actual strings you want to list as selections.

Below is an example of a file producer:

```lua
local function file_menu()
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

  return snipe.toggle_menu(file_producer, function (meta, _) vim.cmd.edit(meta[2]) end)
end

vim.keymap.set("n", "<leader>f", file_menu())
```

This lets you navigate files in the current directory with `<leader>f`
