-- This file implements a transparent view object for a lua array

local Slice = { array = {}, offset = 0, len = 0 }
Slice.__index = Slice

function Slice:new(array, offset, len)
  local o = setmetatable({}, self)

  assert(offset <= #array, "offset out of bounds of the array")
  assert(len <= #array, "len is larger than the backed array")

  self.array = array
  self.offset = offset
  self.len = len

  return o
end

function Slice:__index(index)
  if type(index) == "string" then
    return rawget(Slice, index)
  end
  assert(type(index) == "number", "index must be a number")
  return self.array[self.offset + index - 1]
end

function Slice:ipairs()
  local index = 0
  return function()
    if index < self.len then
      index = index + 1
      return index, self[index]
    end
  end
end

function Slice:pairs()
  local index = 0
  return function()
    if index < self.len then
      index = index + 1
      return self[index]
    end
  end
end

return Slice
