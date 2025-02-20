local M = {}

M.highlight_groups = {
  hint = {
    name = "SnipeHint",
    definition = { link = "Boolean" },
  },
  text = {
    name = "SnipeText",
    definition = {},
  },
  filename = {
    name = "SnipeFilename",
    definition = { link = "SnipeText" },
  },
  dirname = {
    name = "SnipeDirname",
    definition = { link = "Comment" },
  },
}

M.highlight_ns = vim.api.nvim_create_namespace("snipe")

M.create_default_hl = function()
  for _, hl_group in pairs(M.highlight_groups) do
    vim.api.nvim_set_hl(M.highlight_ns, hl_group.name, hl_group.definition)
  end
end

return M
