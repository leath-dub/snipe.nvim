local M = {}

local Buffer = {
  id = 0,
  name = "",
  classifiers = "     ", -- see :help ls for more info
}

Buffer.__index = Buffer

M.Buffer = Buffer

-- Converts single line from ":buffers" output
function Buffer:from_line(s)
  local o = setmetatable({}, Buffer)

  o.id = tonumber(vim.split(s, " ", { trimempty = true })[1])
  o.classifiers = s:sub(4, 8)

  local ss = s:find('"')
  local se = #s - s:reverse():find('"')

  o.name = s:sub(ss + 1, se)

  return o
end

function M.get_buffers(cmd)
  cmd = cmd or "ls"
  local bufs_out = vim.api.nvim_exec2(cmd, { output = true }).output
  local bufs = vim.split(bufs_out, "\n", { trimempty = true })
  return vim.tbl_map(function(l)
    return Buffer:from_line(l)
  end, bufs)
end

return M
