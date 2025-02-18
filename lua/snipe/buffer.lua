local M = {}

---@class snipe.Buffer
---@field id integer buffer id
---@field name string full name of the buffer, as in ":ls" output
---@field basename string filename of the buffer
---@field dirname string parent directory path
---@field classifiers string see :help ls for more info

---@class snipe.Buffer
local Buffer = {}

Buffer.__index = Buffer

M.Buffer = Buffer

---create snipe.Buffer from ":ls" output string
---@param s string - ":ls" output line, ie. '49 %a + "lua/snipe/buffer.lua"         line 18'
---@return snipe.Buffer
function Buffer:from_line(s)
  local o = setmetatable({}, Buffer)

  o.id = tonumber(vim.split(s, " ", { trimempty = true })[1]) --[[@as integer]]
  o.classifiers = s:sub(4, 8)

  local ss = s:find('"')
  local se = #s - s:reverse():find('"')

  o.name = s:sub(ss + 1, se)
  o.basename = vim.fs.basename(o.name)
  o.dirname = vim.fs.dirname(o.name)

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
