---@class snipe.Config: snipe.DefaultConfig
local M = {}

---@class snipe.DefaultConfig
M.defaults = {
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
    -- NOTE: "file-first" puts the file name first and then the directory name
    text_align = "left",

    -- Provide custom buffer list format
    -- Available options:
    --  "filename" - basename of the buffer
    --  "directory" - buffer parent directory path
    --  "icon" - icon for buffer filetype from "mini.icons" or "nvim-web-devicons"
    --  string - any string, will be inserted as is
    --  fun(buffer_object): string,string - function that takes snipe.Buffer object as an argument
    --    and returns a string to be inserted and optional highlight group name
    -- buffer_format = { "->", "icon", "filename", "", "directory", function(buf)
    --   if vim.fn.isdirectory(vim.api.nvim_buf_get_name(buf.id)) == 1 then
    --     return " ", "SnipeText"
    --   end
    -- end },
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

    -- In case you changed your mind, provide a keybind that lets yu
    -- cancel the snipe and close the window.
    ---@type string|string[]
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

M.options = vim.deepcopy(M.defaults)

M.validate = function(config)
  vim.validate({ config = { config, "table", true } })

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
    ["navigate.cancel_snipe"] = { config.navigate.cancel_snipe, { "string", "table" }, true },
    ["navigate.close_buffer"] = { config.navigate.close_buffer, "string", true },
    ["navigate.open_vsplit"] = { config.navigate.open_vsplit, "string", true },
    ["navigate.open_split"] = { config.navigate.open_split, "string", true },
    ["navigate.change_tag"] = { config.navigate.change_tag, "string", true },
    ["sort"] = { config.sort, { "string", "function" }, true },
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

  return true
end

M.setup = function(user_config)
  local config = vim.tbl_deep_extend("force", M.options, user_config or {})

  if M.validate(config) then
    M.options = config
  end
end

setmetatable(M, {
  __index = function(_, k)
    return M.options[k]
  end,
})

return M
