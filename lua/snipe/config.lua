---@class snipe.Config: snipe.DefaultConfig
local M = {}

---@class snipe.DefaultConfig
M.defaults = {
  ui = {
    ---@type integer
    max_height = -1, -- -1 means dynamic height
    -- Where to place the ui window
    -- Can be any of "topleft", "bottomleft", "topright", "bottomright", "center", "cursor" (sets under the current cursor pos)
    ---@type "topleft"|"bottomleft"|"topright"|"bottomright"|"center"|"cursor"
    position = "topleft",
    -- Override options passed to `nvim_open_win`
    -- Be careful with this as snipe will not validate
    -- anything you override here. See `:h nvim_open_win`
    -- for config options
    ---@type vim.api.keyset.win_config
    open_win_override = {
      -- title = "My Window Title",
      border = "single", -- use "rounded" for rounded border
    },

    -- Preselect the currently open buffer
    ---@type boolean
    preselect_current = false,

    -- Set a function to preselect the currently open buffer
    -- E.g, `preselect = require("snipe").preselect_by_classifier("#")` to
    -- preselect alternate buffer (see :h ls and look at the "Indicators")
    ---@type nil|fun(buffers: snipe.Buffer[]): number
    preselect = nil, -- function (bs: Buffer[] [see lua/snipe/buffer.lua]) -> int (index)

    -- Changes how the items are aligned: e.g. "<tag> foo    " vs "<tag>    foo"
    -- Can be "left", "right" or "file-first"
    -- NOTE: "file-first" puts the file name first and then the directory name
    ---@type "left"|"right"|"file-first"
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

    -- Whether to remember mappings from bufnr -> tag
    persist_tags = true,
  },
  hints = {
    -- Charaters to use for hints (NOTE: make sure they don't collide with the navigation keymaps)
    ---@type string
    dictionary = "sadflewcmpghio",
    -- Character used to disambiguate tags when 'persist_tags' option is set
    prefix_key = ".",
  },
  navigate = {
    -- Specifies the "leader" key
    -- This allows you to select a buffer but defer the action.
    -- NOTE: this does not override your actual leader key!
    leader = ",",

    -- Leader map defines keys that follow a selection prefixed by the
    -- leader key. For example (with tag "a"):
    -- ,ad -> run leader_map["d"](m, i)
    -- NOTE: the leader_map cannot specify multi character bindings.
    leader_map = {
      ["d"] = function (m, i) require("snipe").close_buf(m, i) end,
      ["v"] = function (m, i) require("snipe").open_vsplit(m, i) end,
      ["h"] = function (m, i) require("snipe").open_split(m, i) end,
    },

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

    -- Change tag manually (note only works if `persist_tags` is not enabled)
    -- change_tag = "C",
  },
  -- The default sort used for the buffers
  -- Can be any of:
  --  "last" - sort buffers by last accessed
  --  "default" - sort buffers by its number
  --  fun(bs:snipe.Buffer[]):snipe.Buffer[] - custom sort function, should accept a list of snipe.Buffer[] as an argument and return sorted list of snipe.Buffer[]
  ---@type "last"|"default"|fun(buffers:snipe.Buffer[]):snipe.Buffer[]
  sort = "default",
}

M.options = vim.deepcopy(M.defaults)

M.validate = function(config)
  local validation_set = {
    ["config"] = { config, "table", true },

    ["ui"] = { config.ui, "table", true },
    ["ui.max_width"] = { config.ui.max_width, "number", true },
    ["ui.position"] = { config.ui.position, "string", true },
    ["ui.open_win_override"] = { config.ui.open_win_override, "table", true },
    ["ui.preselect_current"] = { config.ui.preselect_current, "boolean", true },
    ["ui.preselect"] = { config.ui.preselect, "function", true },
    ["ui.text_align"] = { config.ui.text_align, "string", true },

    ["hints"] = { config.hints, "table", true },
    ["hints.dictionary"] = { config.hints.dictionary, "string", true },
    ["hints.prefix_key"] = { config.hints.dictionary, "string", true },

    ["navigate"] = { config.navigate, "table", true },
    ["navigate.leader"] = { config.navigate.leader, "string", true },
    ["navigate.leader_map"] = { config.navigate.leader_map, "table", true },
    ["navigate.next_page"] = { config.navigate.next_page, "string", true },
    ["navigate.prev_page"] = { config.navigate.prev_page, "string", true },
    ["navigate.under_cursor"] = { config.navigate.under_cursor, "string", true },
    ["navigate.cancel_snipe"] = { config.navigate.cancel_snipe, { "string", "table" }, true },
    ["navigate.close_buffer"] = { config.navigate.close_buffer, "string", true },
    ["navigate.open_vsplit"] = { config.navigate.open_vsplit, "string", true },
    ["navigate.open_split"] = { config.navigate.open_split, "string", true },

    ["sort"] = { config.sort, { "string", "function" }, true },
  }

  if vim.fn.has("nvim-0.11") == 1 then
    for name, value_validator_optional in pairs(validation_set) do
      vim.validate(name, unpack(value_validator_optional))
    end
  else
    vim.validate(validation_set)
  end

  if config.ui.persist_tags and config.navigate.change_tag ~= nil then
    vim.notify("(snipe) Conflicting options: ui.persist_tags is set true while navigate.change_tag is not nil", vim.log.levels.WARNING)
  end

  local leader_binds = vim.tbl_keys(config.navigate.leader_map)
  for _, lb in ipairs(leader_binds) do
    if #lb > 1 then
      vim.notify("(snipe) invalid leader_map binding '" .. lb .. "': leader_map bindings can only be single characters", vim.log.levels.ERROR)
    end
  end

  if #config.hints.dictionary == 0 then
    vim.notify("(snipe) Cannot have an empty dictionary", vim.log.levels.ERROR)
  end

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
