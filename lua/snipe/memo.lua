local M = {}

function M.make(fn, karg)
  local memo = {}
  return function (...)
    local key = select(1, ...)
    local view = memo
    for i = 2, karg do
      if view[key] == nil then
        view[key] = {}
      end
      view = view[key]
      key = select(i, ...)
    end
    if view[key] ~= nil then
      return view[key]
    end
    view[key] = fn(...)
    return view[key]
  end
end

return M
